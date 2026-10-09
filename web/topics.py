# web/topics.py — Grok-style projects / topics
from __future__ import annotations

import time
import uuid
from typing import Dict, List, Optional

import redis
import threads
import config

_r: Optional[redis.Redis] = None


def _redis() -> redis.Redis:
    global _r
    if _r is None:
        _r = redis.from_url(config.REDIS_URL, decode_responses=True)
    return _r


def create_topic(username: str, title: str) -> str:
    r = _redis()
    tid = uuid.uuid4().hex[:10]
    r.hset(
        f"topic:{tid}",
        mapping={
            "id": tid,
            "user": username.lower(),
            "title": (title or "Topic")[:60],
            "created_at": str(time.time()),
        },
    )
    r.sadd(f"user:{username.lower()}:topics", tid)
    return tid


def list_topics(username: str) -> List[Dict[str, str]]:
    r = _redis()
    ids = list(r.smembers(f"user:{username.lower()}:topics") or [])
    out = []
    for tid in ids:
        meta = r.hgetall(f"topic:{tid}") or {}
        if meta.get("user") == username.lower():
            out.append({"id": tid, "title": meta.get("title") or "Topic"})
    out.sort(key=lambda x: (x.get("title") or "Topic").lower())
    return out

def rename_topic(topic_id: str, title: str) -> None:
    r = _redis()
    if not r.exists(f"topic:{topic_id}"):
        return
    r.hset(f"topic:{topic_id}", "title", (title or "Topic")[:60])


def delete_topic(topic_id: str, username: str) -> None:
    
    r = _redis()
    meta = r.hgetall(f"topic:{topic_id}") or {}
    if meta.get("user") != username.lower():
        return  # don't delete someone else's topic
    for th in threads.list_threads(username, topic_id=topic_id):
        threads.set_thread_topic(th["id"], "")
    r.srem(f"user:{username.lower()}:topics", topic_id)
    r.delete(f"topic:{topic_id}")
