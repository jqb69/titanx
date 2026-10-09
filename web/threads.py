# web/threads.py — titled conversation threads (Redis)
from __future__ import annotations

import json
import time
import uuid
from typing import Any, Dict, List, Optional

import redis

import config

_r: Optional[redis.Redis] = None


def _redis() -> redis.Redis:
    global _r
    if _r is None:
        _r = redis.from_url(config.REDIS_URL, decode_responses=True)
    return _r


def _uid() -> str:
    return uuid.uuid4().hex[:12]


def _title_from_text(text: str, limit: int = 48) -> str:
    t = (text or "").strip().replace("\n", " ")
    if not t:
        return "New chat"
    return (t[:limit] + "…") if len(t) > limit else t


def create_thread(username: str, title: str = "New chat", topic_id: str = "") -> str:
    r = _redis()
    tid = _uid()
    now = str(time.time())
    r.hset(
        f"thread:{tid}",
        mapping={
            "id": tid,
            "user": username.lower(),
            "title": title or "New chat",
            "topic_id": topic_id or "",
            "created_at": now,
            "updated_at": now,
        },
    )
    r.sadd(f"user:{username.lower()}:threads", tid)
    r.set(f"thread:{tid}:messages", "[]")
    return tid


def list_threads(username: str, topic_id: Optional[str] = None) -> List[Dict[str, str]]:
    """topic_id=None → all; topic_id="" → untagged only; else filter by topic."""
    r = _redis()
    ids = list(r.smembers(f"user:{username.lower()}:threads") or [])
    out: List[Dict[str, str]] = []
    for tid in ids:
        meta = r.hgetall(f"thread:{tid}") or {}
        if not meta or meta.get("user") != username.lower():
            continue
        tid_topic = meta.get("topic_id") or ""
        if topic_id is not None:
            if topic_id == "" and tid_topic:
                continue
            if topic_id and tid_topic != topic_id:
                continue
        out.append(
            {
                "id": tid,
                "title": meta.get("title") or "New chat",
                "topic_id": tid_topic,
                "updated_at": meta.get("updated_at") or "0",
            }
        )
    out.sort(key=lambda x: float(x["updated_at"]), reverse=True)
    return out


def get_thread(tid: str) -> Optional[Dict[str, str]]:
    meta = _redis().hgetall(f"thread:{tid}")
    return meta or None


def rename_thread(tid: str, title: str) -> None:
    r = _redis()
    r.hset(f"thread:{tid}", mapping={"title": title[:80], "updated_at": str(time.time())})


def set_thread_topic(tid: str, topic_id: str) -> None:
    """topic_id="" removes from topic (standalone)."""
    r = _redis()
    r.hset(f"thread:{tid}", mapping={"topic_id": topic_id or "", "updated_at": str(time.time())})


def delete_thread(tid: str, username: str) -> None:
    r = _redis()
    r.srem(f"user:{username.lower()}:threads", tid)
    r.delete(f"thread:{tid}", f"thread:{tid}:messages")


def load_messages(tid: str) -> List[Dict[str, str]]:
    raw = _redis().get(f"thread:{tid}:messages") or "[]"
    try:
        data = json.loads(raw)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_messages(tid: str, messages: List[Dict[str, Any]]) -> None:
    r = _redis()
    r.set(f"thread:{tid}:messages", json.dumps(messages, ensure_ascii=False))
    r.hset(f"thread:{tid}", "updated_at", str(time.time()))



def suggest_title(user_text: str, assistant_text: str = "") -> str:
    """Prefer Ollama; fall back to truncate."""
    try:
        import ollama as ollama_mod
        nice = ollama_mod.suggest_title(user_text, assistant_text)
        if nice:
            return nice
    except Exception:
        pass
    return _title_from_text(user_text)


def append_message(tid: str, role: str, content: str) -> List[Dict[str, str]]:
    msgs = load_messages(tid)
    msgs.append({"role": role, "content": content})
    meta = get_thread(tid) or {}
    title = (meta.get("title") or "").strip()

    # First user message → quick placeholder title
    if role == "user" and title in ("", "New chat", "Previous chat"):
        rename_thread(tid, _title_from_text(content))

    # After assistant response → polish title with Ollama once and lock
    if role == "assistant" and meta.get("title_locked") != "1":
        current = (title or "").strip()
        if current in ("", "New chat", "Previous chat") or len(current) >= 40:
            user_text = next(
                (m["content"] for m in reversed(msgs) if m.get("role") == "user"),
                "",
            )
            nice = suggest_title(user_text, content)  # → ollama.suggest_title + fallback
            rename_thread(tid, nice)
            _redis().hset(f"thread:{tid}", "title_locked", "1")

    save_messages(tid, msgs)
    return msgs
