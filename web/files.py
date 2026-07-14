# web/files.py — 4GB Droplet Optimized File Vault
import os
import hashlib
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, asdict
from pathlib import Path

import config
from redis import Redis

r = Redis.from_url(config.REDIS_URL, decode_responses=True)

_FILE_STORAGE_DIR = getattr(config, "UPLOAD_DIR", "/workspace/uploaded")
_MAX_BYTES = getattr(config, "MAX_FILE_SIZE_MB", 20) * 1024 * 1024   # lowered default
_MAX_CONTEXT_CHARS = 100_000   # ~25k tokens safe limit


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
# At module top (after other imports)
try:
    import pytesseract
    from PIL import Image
    import fitz  # pymupdf
    OCR_AVAILABLE = True
except ImportError:
    OCR_AVAILABLE = False
    pytesseract = None
    print("⚠️ OCR modules (pytesseract + pymupdf) not available — scanned PDFs limited")

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
        uid=uid,
        name=filename,
        ext=ext,
        size_bytes=len(content),
        mime_hint="text/plain" if ext in {".txt",".md",".py",".json",".csv",".sh"} else "application/octet-stream",
        uploaded_at=datetime.utcnow().isoformat(),
        storage_path=path
    )

    r.hset(f"{config.REDIS_FILE_META_PREFIX}{uid}", mapping=meta.to_dict())
    r.sadd(config.REDIS_FILE_INDEX, uid)

    return meta, None


def list_stored_files() -> List[FileMeta]:
    uids = r.smembers(config.REDIS_FILE_INDEX)
    files = []
    for uid in uids:
        raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
        if raw:
            meta = FileMeta.from_dict(raw)
            if not meta.deleted and os.path.exists(meta.storage_path):
                files.append(meta)
    return sorted(files, key=lambda x: x.uploaded_at, reverse=True)


def total_storage_used() -> int:
    uids = r.smembers(config.REDIS_FILE_INDEX)
    total = 0
    for uid in uids:
        size_str = r.hget(f"{config.REDIS_FILE_META_PREFIX}{uid}", "size_bytes")
        if size_str:
            total += int(size_str)
    return total


def get_file_meta(uid: str) -> Optional[FileMeta]:
    raw = r.hgetall(f"{config.REDIS_FILE_META_PREFIX}{uid}")
    if raw:
        meta = FileMeta.from_dict(raw)
        if not meta.deleted and os.path.exists(meta.storage_path):
            return meta
    return None


def extract_text_for_llm(meta: FileMeta) -> Tuple[Optional[str], Optional[str]]:
    cache_key = f"{config.REDIS_FILE_TEXT_PREFIX}{meta.uid}"
    cached = r.get(cache_key)
    if cached:
        return cached, None

    text, err = _extract_text(meta)
    if text:
        r.setex(cache_key, 604800, text)  # 7 days cache
    return text, err


def _extract_text(meta: FileMeta) -> Tuple[Optional[str], Optional[str]]:
    if not os.path.exists(meta.storage_path):
        return None, "File missing"

    try:
        # Text files — lazy read
        text_extensions = {
            ".txt", ".md", ".py", ".json", ".csv", ".sh", ".yml", ".yaml",
            ".js", ".ts", ".html", ".css", ".xml", ".sql", ".log"
        }
        if meta.ext in text_extensions:
            with open(meta.storage_path, "rb") as f:
                return f.read().decode("utf-8", errors="ignore"), None
        if meta.ext == ".pdf":
            text = _extract_pdf_text(meta.storage_path)
            return text, None

        if meta.ext == ".docx":
            try:
                import docx
                doc = docx.Document(meta.storage_path)
                paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
                return "\n\n".join(paragraphs), None
            except Exception as e:
                return None, f"DOCX error: {e}"

        return f"[Binary file: {meta.name}]", None
    except Exception as e:
        return None, str(e)


def _extract_pdf_text(path: str) -> str:
    """Multi-engine PDF extraction: text layer → pdfplumber → OCR. 4GB-safe."""
    filename = Path(path).name

    # 1. PyPDF2
    try:
        import PyPDF2
        reader = PyPDF2.PdfReader(path)
        text = "\n\n".join(p.extract_text() or "" for p in reader.pages)
        if text.strip():
            return text.strip()
    except Exception:
        pass

    # 2. pdfplumber
    try:
        import pdfplumber
        with pdfplumber.open(path) as pdf:
            text = "\n\n".join((pg.extract_text() or "") for pg in pdf.pages)
        if text.strip():
            return text.strip()
    except Exception:
        pass

    # 3. OCR Fallback
    if not OCR_AVAILABLE:
        return f"[PDF: {filename} — scanned/image PDF, OCR not available]"

    try:
        out = []
        total_chars = 0
        with fitz.open(path) as doc:
            for page in doc:
                pix = page.get_pixmap(dpi=150, colorspace=fitz.csGRAY)
                with Image.open(io.BytesIO(pix.tobytes("png"))) as img:
                    t = pytesseract.image_to_string(img, lang="eng", config='--psm 6')
                
                out.append(t.strip())
                total_chars += len(t)
                
                del pix  # ← Moved BEFORE break (Miki fix)
                
                if total_chars > _MAX_CONTEXT_CHARS:
                    break

        ocr_text = "\n\n".join(out).strip()
        if ocr_text:
            return ocr_text
    except Exception as e:
        if out:
            return "\n\n".join(out).strip()
        return f"[PDF OCR failed on {filename}: {e}]"

    return f"[PDF: {filename} — no extractable text (scanned/image-based PDF)]"

def delete_file(uid: str, hard_delete: bool = True) -> bool:
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


def build_context_from_attached(uids: List[str]) -> Tuple[str, List[Dict]]:
    """Memory-safe context building with truncation"""
    parts = []
    records = []
    total_chars = 0

    for uid in uids:
        meta = get_file_meta(uid)
        if not meta:
            continue

        text, _ = extract_text_for_llm(meta)
        header = f"=== FILE: {meta.name} ({meta.size_bytes} bytes) ==="
        entry = f"{header}\n{text or '[Binary file]'}"

        if total_chars + len(entry) > _MAX_CONTEXT_CHARS:
            parts.append("[Additional files truncated due to context limit]")
            break

        parts.append(entry)
        total_chars += len(entry)
        records.append({"uid": uid, "name": meta.name, "ext": meta.ext, "size": meta.size_bytes})

    return "\n\n".join(parts), records


def format_message_with_files(user_prompt: str, file_context: str) -> str:
    if not file_context or not file_context.strip():
        return user_prompt
    return f"--- LOCAL WORKSPACE FILE ATTACHED ---\n{file_context}\n\nUser Message: {user_prompt}"
