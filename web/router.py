"""Chat vs agentic routing (temp: local chat, cloud agent)."""
# web/router.py
from __future__ import annotations

from typing import Optional
import config

def is_agentic_keywords(text: str) -> bool:
    t = (text or "").lower()
    if not t:
        return False
    return any(h in t for h in getattr(config, "AGENTIC_HINTS", ()))


def is_agentic_llm(text: str) -> Optional[bool]:
    """
    Optional Ollama one-shot classifier.
    Returns True/False, or None if classify failed (caller falls back to keywords).
    """
    if not getattr(config, "AGENTIC_USE_LLM", False):
        return None
    try:
        import ollama as ollama_mod
        prompt = (
            "Classify the user message. Reply with exactly one word: "
            "AGENT if it needs tools, web, terminal, files, deploy, or live data; "
            "CHAT if it is only conversation or explanation.\n\n"
            f"User: {text[:500]}"
        )
        # minimal non-stream call via existing health base
        import requests
        base = (getattr(config, "OLLAMA_BASE_URL", "") or "").rstrip("/")
        model = getattr(config, "OLLAMA_MODEL", "qwen2.5:7b")
        if not base:
            return None
        r = requests.post(
            f"{base}/api/chat",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
            },
            timeout=(3, 30),
        )
        if r.status_code != 200:
            return None
        content = (
            (r.json().get("message") or {}).get("content") or ""
        ).strip().upper()
        if content.startswith("AGENT"):
            return True
        if content.startswith("CHAT"):
            return False
        return None
    except Exception:
        return None


def is_agentic(text: str) -> bool:
    judged = is_agentic_llm(text)
    if judged is not None:
        return judged
    return is_agentic_keywords(text)


def last_user_text(messages: list) -> str:
    for m in reversed(messages or []):
        if m.get("role") == "user":
            return m.get("content") or ""
    return ""


def compress_for_agent(text: str, max_chars: int = None) -> str:
    text = (text or "").strip()
    max_chars = max_chars or int(getattr(config, "AGENTIC_BRIEF_CHARS", 1200))
    if not text:
        return text
    if len(text) <= max_chars and not getattr(config, "AGENTIC_ALWAYS_COMPRESS", False):
        return text

    base = (getattr(config, "OLLAMA_BASE_URL", "") or "").rstrip("/")
    model = getattr(config, "OLLAMA_MODEL", "qwen2.5:7b")
    if not base:
        return text[:max_chars]

    # Tight timeouts: fail fast → agents get the raw/truncated prompt
    connect_t = float(getattr(config, "OLLAMA_COMPRESS_CONNECT", 2))
    read_t = float(getattr(config, "OLLAMA_COMPRESS_READ", 8))

    system = (
        "Rewrite as a concise agent brief. Keep goal, constraints, URLs/paths. "
        "Max 15 lines. No preamble."
    )
    try:
        import requests
        r = requests.post(
            f"{base}/api/chat",
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": text[:4000]},
                ],
                "stream": False,
            },
            timeout=(connect_t, read_t),
        )
        if r.status_code != 200:
            return text[:max_chars]
        brief = ((r.json().get("message") or {}).get("content") or "").strip()
        return brief if brief else text[:max_chars]
    except Exception:
        # timeout / connection → immediate fallback, no wait
        return text[:max_chars]


def messages_for_agent(messages: list) -> list:
    """Copy messages; replace last user turn with compressed brief."""
    out = []
    last_user_idx = None
    for i, m in enumerate(messages or []):
        out.append(dict(m))
        if m.get("role") == "user":
            last_user_idx = len(out) - 1
    if last_user_idx is not None:
        raw = out[last_user_idx].get("content") or ""
        out[last_user_idx]["content"] = compress_for_agent(raw)
    return out
