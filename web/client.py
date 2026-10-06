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
import router
_SESSION = requests.Session()

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

        r = _SESSION.get(f"{url}/health", headers=headers, timeout=4)
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
        model=config.resolve_model("ollama") if hasattr(config, "resolve_model") else None,
        timeout=getattr(config, "OLLAMA_CHAT_TIMEOUT", (4, 90)),
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
                "model": config.resolve_model("openrouter"),
                "messages": messages,
                "stream": True,
            }
            if getattr(config, 'REASONING_ENABLED', True):
                payload["reasoning"] = {"enabled": True, "effort": getattr(config, 'REASONING_EFFORT', "medium")}

            with _SESSION.post(full_url, json=payload, headers=headers, stream=True, timeout=(5, 60)) as r:
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
    headers = (
        {"Authorization": f"Bearer {config.HERMES_API_KEY}"}
        if getattr(config, "HERMES_API_KEY", None)
        else {}
    )
    formatted = format_messages(messages)
    user_text = router.last_user_text(messages)
    agentic = router.is_agentic(user_text)
    formatted = config.with_system(formatted, config.SYSTEM_AGENT)
    agent_msgs = formatted  # default for queue
    
    # --- CHAT: local Ollama first ---
    if not agentic:
        try:
            placeholder.markdown(f"*Chat → {ollama_status_line()}*")
        except Exception:
            pass
        messages = config.with_system(messages, config.SYSTEM_CHAT)
        result = post_to_ollama(messages, placeholder)
        if result and not str(result).startswith("❌"):
            return result

        placeholder.markdown("⚠️ Local chat failed → Hermes (OpenRouter)…")
        result = post_to_hermes(config.HERMES_URL, headers, formatted, placeholder)
        if result and not str(result).startswith("❌"):
            return result

        av = getattr(config, "AVANGARDE_URL", None)
        if av:
            result = post_to_hermes(av, headers, formatted, placeholder)
            if result and not str(result).startswith("❌"):
                return result

    # --- AGENTIC: compress → Hermes → Avangarde ---
    else:
        placeholder.markdown("*Agentic → Ollama compressing brief…*")
        try:
            agent_msgs = router.messages_for_agent(formatted)
        except Exception:
            agent_msgs = formatted
        #placeholder.markdown(agent_msgs)
        brief = ""
        for m in reversed(agent_msgs):
            if m.get("role") == "user":
                brief = m.get("content") or ""
                break
              
        if getattr(config, "AGENTIC_SHOW_BRIEF", True) and brief:
            safe = brief.replace("```", "'''")
            placeholder.markdown(f"*Agent brief (Ollama → Hermes):*\n\n*{safe}*")

        placeholder.markdown("*Brief ready → Hermes (OpenRouter)…*")
        result = post_to_hermes(config.HERMES_URL, headers, agent_msgs, placeholder)
        if result and not str(result).startswith("❌"):
            return result

        av = getattr(config, "AVANGARDE_URL", None)
        if av:
            placeholder.markdown("⚠️ Hermes failed → Avangarde…")
            result = post_to_hermes(av, headers, agent_msgs, placeholder)
            if result and not str(result).startswith("❌"):
                return result

    # --- Queue last ---
    payload = {
        "task_id": f"job_{int(time.time())}",
        "messages": agent_msgs,
        "model": config.resolve_model("openrouter"),
        "task_type": "agent" if agentic else "chat",
        "stream": True,
    }
    try:
        enqueue_res = worker.enqueue_job(payload)
    except Exception as e:
        enqueue_res = {"queued": False, "error": str(e)}

    if isinstance(enqueue_res, dict) and enqueue_res.get("queued"):
        job_id = enqueue_res.get("job_id", "unknown")
        placeholder.markdown(f"**Queued** — Job ID: `{job_id}`")
        return f"✅ Task queued (ID: {job_id}). Background worker is processing it."

    return "❌ Hermes, Avangarde, and Ollama all failed."
