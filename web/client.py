import requests
import json
import time
#import streamlit as st
from typing import List, Dict, Tuple
import config
import state
import re
import worker
import ollama as ollama_mod


def check_ollama_health(base_url: str = None) -> dict:
    return ollama_mod.check_health(base_url=base_url)


def ollama_status_line(base_url: str = None) -> str:
    return ollama_mod.status_line(base_url=base_url)


def check_hermes_health(url: str = None) -> bool:
    """Check health of a Hermes instance."""
    url = url or config.HERMES_URL
    try:
        headers = {}
        if getattr(config, "HERMES_API_KEY", None):
            headers = {"Authorization": f"Bearer {config.HERMES_API_KEY}"}

        r = requests.get(f"{url}/health", headers=headers, timeout=4)
        return r.status_code == 200
    except Exception:
        return False


def format_messages(raw_messages: List[Dict]) -> List[Dict]:
    formatted = []
    for msg in raw_messages:
        role = msg.get("role")
        if role not in ["user", "assistant", "system"]:
            continue
        content = msg.get("content", "")
        # DO NOT strip file content — let the AI see it
        # if "--- LOCAL WORKSPACE FILE ATTACHED ---" in content:
        #     content = content.split("User Message:")[-1].strip()
        formatted.append({"role": role, "content": content})
    return formatted

def post_to_ollama(messages: List[Dict], placeholder) -> str:
    """
    Format messages, then stream via ollama.post_chat.
    Returns str on success, None on failure (same as post_chat).
    """
    return ollama_mod.post_chat(
        messages=format_messages(messages),
        placeholder=placeholder,
        base_url=getattr(config, "OLLAMA_BASE_URL", None) or None,
        model=config.resolve_model() if hasattr(config, "resolve_model") else None,
        timeout=(5, 180),
    )


def extract_thinking_and_answer(full_text: str) -> Tuple[str, str]:
    think_match = re.search(r'<think>(.*?)</think>', full_text, re.DOTALL | re.IGNORECASE)
    if think_match:
        thinking = think_match.group(1).strip()
        answer = re.sub(r'<think>.*?</think>', '', full_text, flags=re.DOTALL | re.IGNORECASE).strip()
        return thinking, answer
    return "", full_text


def post_to_hermes(url: str, headers: dict, messages: List[Dict], placeholder) -> str:
    """Stream from one Hermes instance with full endpoint flexibility."""
    full_response = ""
    endpoints = getattr(config, "ENDPOINTS", ["/v1/chat/completions"])

    for endpoint in endpoints:
        full_url = f"{url.rstrip('/')}{endpoint}"
        try:
            payload = {
                "model": config.resolve_model(),
                "messages": format_messages(messages),
                "stream": True,
            }
            if getattr(config, 'REASONING_ENABLED', True):
                payload["reasoning"] = {"enabled": True, "effort": getattr(config, 'REASONING_EFFORT', "medium")}

            with requests.post(full_url, json=payload, headers=headers, stream=True, timeout=(5, 120)) as r:
                if r.status_code != 200:
                    continue  # Try next endpoint

                for raw in r.iter_lines(decode_unicode=True):
                    if state.is_stopped():
                        full_response += "\n\n🛑 *Generation cancelled by user.*"
                        break

                    if not raw or raw.strip() in ("[DONE]", "data: [DONE]"):
                        continue

                    chunk = raw[len("data:"):].strip() if raw.startswith("data:") else raw.strip()
                    if not chunk:
                        continue

                    try:
                        data = json.loads(chunk)
                        choice0 = (data.get("choices") or [{}])[0]
                        content = choice0.get("delta", {}).get("content", "") or choice0.get("text", "")
                        if content:
                            full_response += content
                            placeholder.markdown(full_response + "▌")
                    except Exception:
                        continue
                return full_response  # Success on this endpoint
        except requests.exceptions.ConnectionError:
            continue
        except Exception:
            continue

    return None  # All endpoints failed on this instance


def run_routing_pipeline(messages: List[Dict], placeholder) -> str:
    """Multi-instance + endpoint probing + reasoning preserved."""
    headers = {"Authorization": f"Bearer {config.HERMES_API_KEY}"} if getattr(config, "HERMES_API_KEY", None) else {}
    try:
        placeholder.markdown(f"*{ollama_status_line()}*")
    except Exception:
        pass
    # 1. Try Main Hermes (with full endpoint probing)
    result = post_to_hermes(config.HERMES_URL, headers, messages, placeholder)
    if result and not str(result).startswith("❌"):
        return result

    # 2. Try Avangarde (safe access)
    avangarde_url = getattr(config, "AVANGARDE_URL", None)
    if avangarde_url:
        placeholder.markdown("⚠️ Main Hermes unreachable → Switching to Avangarde...")
        result = post_to_hermes(avangarde_url, headers, messages, placeholder)
        if result and not str(result).startswith("❌"):
            return result
          
     # 3. Direct Ollama (timeout / unreachable harness fallback)
    placeholder.markdown("⚠️ Hermes path failed → direct Ollama…")
    result = post_to_ollama(messages, placeholder)
    if result and not str(result).startswith("❌"):
        return result
    

    # 3. Final fallback: Enqueue
    payload = {
        "task_id": f"job_{int(time.time())}",
        "messages": format_messages(messages),   # Pre-format!
        "model": config.resolve_model(),
        "task_type": "chat",
        "stream": False
    }

    try:
        enqueue_res = worker.enqueue_job(payload)
    except Exception as e:
        enqueue_res = {"queued": False, "error": str(e)}

    if isinstance(enqueue_res, dict) and enqueue_res.get("queued"):
        job_id = enqueue_res.get("job_id", "unknown")
        placeholder.markdown(f"**Queued for background processing**\nJob ID: `{job_id}`")
        return f"✅ Task queued (ID: {job_id}). Background worker is processing it."

     return "❌ Hermes, Avangarde, and Ollama all failed."
