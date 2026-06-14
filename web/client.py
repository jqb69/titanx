import requests
import json
import streamlit as st
from typing import List, Dict, Tuple
import config
import state
import re
import worker  # Must contain enqueue_job()

def check_hermes_health() -> bool:
    try:
        headers = {"Authorization": f"Bearer {config.HERMES_API_KEY}"} if getattr(config, "HERMES_API_KEY", None) else {}
        r = requests.get(f"{config.HERMES_URL}/health", headers=headers, timeout=4)
        return r.status_code == 200
    except Exception:
        return False

def format_messages(raw_messages: List[Dict]) -> List[Dict]:
    """Clean messages for OpenAI-compatible API."""
    formatted: List[Dict] = []
    for msg in raw_messages:
        role = msg.get("role")
        if role not in ["user", "assistant", "system"]:
            continue
        content = msg.get("content", "")
        if "--- LOCAL WORKSPACE FILE ATTACHED ---" in content:
            content = content.split("User Message:")[-1].strip() if "User Message:" in content else content
        formatted.append({"role": role, "content": content})
    return formatted

def extract_thinking_and_answer(full_text: str) -> Tuple[str, str]:
    """Parse <think> blocks like Grok."""
    think_match = re.search(r'<think>(.*?)</think>', full_text, re.DOTALL | re.IGNORECASE)
    if think_match:
        thinking = think_match.group(1).strip()
        answer = re.sub(r'<think>.*?</think>', '', full_text, flags=re.DOTALL | re.IGNORECASE).strip()
        return thinking, answer
    return "", full_text

def post_to_hermes(endpoint: str, headers: dict, messages: List[Dict], placeholder) -> str:
    """Direct streaming call to Hermes."""
    full_response = ""
    url = f"{config.HERMES_URL}{endpoint}"

    try:
        payload = {
            "model": config.OPENROUTER_MODEL,
            "messages": format_messages(messages),
            "stream": True,
        }
        if getattr(config, 'REASONING_ENABLED', True):
            payload["reasoning"] = {"enabled": True, "effort": getattr(config, 'REASONING_EFFORT', "medium")}

        with requests.post(url, json=payload, headers=headers, stream=True, timeout=(5, 120)) as r:
            if r.status_code != 200:
                try:
                    err = r.json()
                except Exception:
                    err = r.text[:200]
                return f"❌ HTTP {r.status_code}: {err}"

            for raw in r.iter_lines(decode_unicode=True):
                if state.is_stopped():
                    full_response += "\n\n🛑 *Generation cancelled by user.*"
                    break

                if not raw:
                    continue

                line = raw.strip()
                if line in ("[DONE]", "data: [DONE]"):
                    break

                # Safe SSE parsing
                if line.startswith("data:"):
                    chunk = line[5:].strip()          # Safer than split
                else:
                    chunk = line

                if not chunk:
                    continue

                try:
                    data = json.loads(chunk)
                    choice0 = (data.get("choices") or [{}])[0]
                    content = (choice0.get("delta", {}) or {}).get("content", "") or choice0.get("text", "")
                    if content:
                        full_response += content
                        try:
                            placeholder.markdown(full_response + "▌")
                        except Exception:
                            pass
                except json.JSONDecodeError:
                    continue
                except Exception:
                    continue

    except requests.exceptions.ConnectionError:
        return "❌ Hermes is unreachable. Try again later."
    except requests.exceptions.Timeout:
        return "⏱️ Request timed out."
    except Exception as e:
        return f"❌ Error: {e}"

    return full_response

def run_routing_pipeline(messages: List[Dict], placeholder) -> str:
    """Try direct endpoints first, fallback to worker queue."""
    headers = {"Authorization": f"Bearer {config.HERMES_API_KEY}"} if getattr(config, "HERMES_API_KEY", None) else {}
    errors: List[str] = []

    for endpoint in getattr(config, "ENDPOINTS", []):
        if state.is_stopped():
            break
        resp = post_to_hermes(endpoint, headers, messages, placeholder)
        if resp and not str(resp).startswith("❌"):
            return resp
        errors.append(resp or "Unknown error")

    # Fallback: Enqueue via worker
    payload = {
        "model": config.OPENROUTER_MODEL,
        "messages": format_messages(messages),
        "task_type": "chat",
        "stream": False
    }

    try:
        enqueue_res = worker.enqueue_job(payload)
    except Exception as e:
        enqueue_res = {"queued": False, "error": str(e)}

    if isinstance(enqueue_res, dict) and enqueue_res.get("queued"):
        job_id = enqueue_res.get("job_id", "unknown")
        try:
            placeholder.markdown(f"**Queued for background processing**\nJob ID: `{job_id}`")
        except Exception:
            pass
        return f"✅ Task queued successfully (ID: {job_id}). Background worker is processing it."

    # Final error
    combined = "\n".join([f"* {err}" for err in errors if err])
    enqueue_err = f"\n* Enqueue failed: {enqueue_res.get('error', 'Unknown')}" if isinstance(enqueue_res, dict) and enqueue_res.get("error") else ""
    
    return f"### ⚠️ Hermes Unavailable\n{combined}{enqueue_err}"