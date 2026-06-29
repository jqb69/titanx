# web/files.py — Redis-first file vault (compatible with file_ui.py)
import os
import hashlib
import base64
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

import config
from redis import Redis

r = Redis.from_url(config.REDIS_URL, decode_responses=True)

_FILE_STORAGE_DIR = getattr(config, "FILE_STORAGE_DIR", "/workspace/mikie_files")
_MAX_BYTES = getattr(config, "MAX_FILE_SIZE_MB", 50) * 1024 * 1024


@dataclass
class FileMeta:
    uid: str
    name: str
    ext: str
    size_bytes: int
    mime_hint: str
    uploaded_at: str
    storage_path: str
    deleted: bool = False

    def to_dict(self) -> Dict:
        d = asdict(self)
        d['deleted'] = str(d['deleted']).lower()
        d['size_bytes'] = str(d['size_bytes'])
        return d

    @staticmethod
    def from_dict(d: Dict) -> "FileMeta":
        d = dict(d)
        d['size_bytes'] = int(d.get('size_bytes', 0))
        d['deleted'] = str(d.get('deleted', 'false')).lower() == 'true'
        return FileMeta(**d)


def _ensure_dirs():
    os.makedirs(_FILE_STORAGE_DIR, exist_ok=True)


def _compute_uid(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()[:32]


def store_uploaded_file(filename: str, content: bytes) -> Tuple[Optional[FileMeta], Optional[str]]:
    _ensure_dirs()
    if len(content) > _MAX_BYTES:
        return None, f"File exceeds {config.MAX_FILE_SIZE_MB}MB"

    ext = Path(filename).suffix.lower()
    uid = _compute_uid(content)
    path = os.path.join(_FILE_STORAGE_DIR, f"{uid}{ext}")

    if r.sismember(config.REDIS_FILE_INDEX, uid):
        raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
        if raw and os.path.exists(raw.get("storage_path", "")):
            meta = FileMeta.from_dict(raw)
            meta.name = filename
            meta.deleted = False
            r.hset(f"{config.REDIS_FILE_META_PREFIX}{uid}", mapping=meta.to_dict())
            return meta, None

    try:
        with open(path, "wb") as f:
            f.write(content)
    except Exception as e:
        return None, f"Write error: {e}"

    meta = FileMeta(
        uid=uid, name=filename, ext=ext, size_bytes=len(content),
        mime_hint="text/plain" if ext in {".txt",".md",".py",".json",".csv",".sh"} else "application/octet-stream",
        uploaded_at=datetime.utcnow().isoformat(),
        storage_path=path
    )

    r.hset(f"{config.REDIS_FILE_META_PREFIX}{uid}", mapping=meta.to_dict())
    r.sadd(config.REDIS_FILE_INDEX, uid)

    return meta, None


def list_stored_files(include_deleted: bool = False) -> List[FileMeta]:
    uids = r.smembers(config.REDIS_FILE_INDEX)
    files = []
    for uid in uids:
        raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
        if raw:
            meta = FileMeta.from_dict(raw)
            if include_deleted or not meta.deleted:
                if os.path.exists(meta.storage_path):
                    files.append(meta)
    return sorted(files, key=lambda x: x.uploaded_at, reverse=True)


def total_storage_used() -> int:
    """Used by file_ui.py"""
    uids = r.smembers(config.REDIS_FILE_INDEX)
    total = 0
    for uid in uids:
        raw = r.hget(f"{config.REDIS_FILE_META_PREFIX}{uid}", "size_bytes")
        if raw:
            total += int(raw)
    return total


def get_file_meta(uid: str) -> Optional[FileMeta]:
    raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
    if raw:
        meta = FileMeta.from_dict(raw)
        if not meta.deleted and os.path.exists(meta.storage_path):
            return meta
    return None


def extract_text_for_llm(meta: FileMeta) -> Tuple[Optional[str], Optional[str]]:
    """Used by file_ui.py for preview"""
    cache_key = f"{config.REDIS_FILE_TEXT_PREFIX}{meta.uid}"
    cached = r.get(cache_key)
    if cached:
        return cached, None

    text, err = _extract_text(meta)
    if text:
        r.setex(cache_key, 604800, text)  # 7 days
    return text, err


def _extract_text(meta: FileMeta) -> Tuple[Optional[str], Optional[str]]:
    if not os.path.exists(meta.storage_path):
        return None, "File missing"

    try:
        with open(meta.storage_path, "rb") as f:
            raw = f.read()

        if meta.ext in {".txt",".md",".py",".json",".csv",".sh",".yml",".yaml"}:
            return raw.decode("utf-8", errors="ignore"), None

        if meta.ext == ".pdf":
            try:
                import PyPDF2
                reader = PyPDF2.PdfReader(meta.storage_path)
                return "\n\n".join(p.extract_text() or "" for p in reader.pages), None
            except Exception as e:
                return None, f"PDF error: {e}"

        if meta.ext == ".docx":
            try:
                import docx
                doc = docx.Document(meta.storage_path)
                return "\n\n".join(p.text for p in doc.paragraphs if p.text.strip()), None
            except Exception as e:
                return None, f"DOCX error: {e}"

        return f"[Binary file: {meta.name}]", None
    except Exception as e:
        return None, str(e)


def delete_file(uid: str, hard_delete: bool = True) -> bool:
    """Hard delete by default to save disk space."""
    raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
    if not raw:
        return False

    if hard_delete:
        meta = FileMeta.from_dict(raw)
        if os.path.exists(meta.storage_path):
            try:
                os.remove(meta.storage_path)
            except Exception:
                pass

    r.delete(f"{config.REDIS_FILE_META_PREFIX}{uid}")
    r.delete(f"{config.REDIS_FILE_TEXT_PREFIX}{uid}")
    r.srem(config.REDIS_FILE_INDEX, uid)
    return True
