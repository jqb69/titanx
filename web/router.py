"""Chat vs agentic routing (temp: local chat, cloud agent)."""
from __future__ import annotations

from typing import Optional

import requests

import config

# One pool for all Ollama side-calls (classify + compress)
_SESSION = requests.Session()
_ADAPTER = requests.adapters.HTTPAdapter(
    pool_connections=4, pool_maxsize=4, max_retries=0
)
_SESSION.mount("http://", _ADAPTER)
_SESSION.mount("https://", _ADAPTER)


def is_agentic_keywords(text: str) -> bool:
    t = (text or "").lower()
    if not t:
        return False
    return any(h in t for h in getattr(config, "AGENTIC_HINTS", ()))


def is_agentic_llm(text: str) -> Optional[bool]:
    if not getattr(config, "AGENTIC_USE_LLM", False):
        return None
    base = (getattr(config, "OLLAMA_BASE_URL", "") or "").rstrip("/")
    model = getattr(config, "OLLAMA_MODEL", "qwen2.5:7b")
    if not base:
        return None
    prompt = (
        "Classify the user message. Reply with exactly one word: "
        "AGENT if it needs tools, web, terminal, files, deploy, or live data; "
        "CHAT if it is only conversation or explanation.\n\n"
        f"User: {(text or '')[:500]}"
    )
    try:
        r = _SESSION.post(
            f"{base}/api/chat",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
            },
            timeout=(2, 8),  # was (3, 30) — fail fast
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

    connect_t = float(getattr(config, "OLLAMA_COMPRESS_CONNECT", 2))
    read_t = float(getattr(config, "OLLAMA_COMPRESS_READ", 8))
    system = (
        "Rewrite as a concise agent brief. Keep goal, constraints, URLs/paths. "
        "Max 15 lines. No preamble."
    )
    try:
        r = _SESSION.post(  # module session — do NOT new Session() per call
            f"{base}/api/chat",
            json={
                "model": model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": text[:2000]},
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
        return text[:max_chars]


def messages_for_agent(messages: list) -> list:
    out = []
    last_user_idx = None
    for m in messages or []:
        out.append(dict(m))
        if m.get("role") == "user":
            last_user_idx = len(out) - 1
    if last_user_idx is not None:
        raw = out[last_user_idx].get("content") or ""
        out[last_user_idx]["content"] = compress_for_agent(raw)
    return out
