# web/ollama.py
"""Ollama droplet connectivity probes."""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

import requests
import config


def _base_url(override: Optional[str] = None) -> str:
    return (override or getattr(config, "OLLAMA_BASE_URL", "") or "").rstrip("/")


def _wanted_model() -> str:
    return getattr(config, "OLLAMA_MODEL", "qwen2.5:7b") or "qwen2.5:7b"


def _model_present(models: List[str], want: str) -> bool:
    if not want:
        return False
    if want in models:
        return True
    # tag-flexible: "qwen2.5:7b" matches "qwen2.5:7b-instruct" etc.
    prefix = want.split(":")[0]
    return any(n == want or n.startswith(prefix + ":") or n.startswith(want) for n in models)


def check_health(base_url: Optional[str] = None, timeout: float = 5.0) -> Dict[str, Any]:
    """
    Probe Ollama /api/tags.
    Returns dict:
      ok, url, models, has_model, model, error, latency_ms
    """
    base = _base_url(base_url)
    want = _wanted_model()
    result: Dict[str, Any] = {
        "ok": False,
        "url": base,
        "models": [],
        "has_model": False,
        "model": want,
        "error": None,
        "latency_ms": None,
    }
    if not base:
        result["error"] = "OLLAMA_BASE_URL not set"
        return result

    url = f"{base}/api/tags"
    try:
        import time
        t0 = time.monotonic()
        r = requests.get(url, timeout=timeout)
        result["latency_ms"] = int((time.monotonic() - t0) * 1000)

        if r.status_code != 200:
            body = (r.text or "")[:160]
            result["error"] = f"HTTP {r.status_code}: {body}"
            return result

        try:
            data = r.json() if r.content else {}
        except json.JSONDecodeError:
            result["error"] = "Invalid JSON from /api/tags"
            return result

        models = [
            (m.get("name") or m.get("model") or "")
            for m in (data.get("models") or [])
            if isinstance(m, dict)
        ]
        models = [n for n in models if n]
        result["models"] = models
        result["ok"] = True
        result["has_model"] = _model_present(models, want)

        if not models:
            result["error"] = "Ollama up but no models loaded"
        elif not result["has_model"]:
            shown = ", ".join(models[:5]) or "(none)"
            result["error"] = f"Model '{want}' missing (have: {shown})"
        return result

    except requests.exceptions.ConnectionError:
        result["error"] = f"Unreachable: {base}"
        return result
    except requests.exceptions.Timeout:
        result["error"] = f"Timeout ({timeout}s): {base}"
        return result
    except requests.exceptions.RequestException as e:
        result["error"] = f"Request error: {e}"
        return result
    except Exception as e:
        result["error"] = f"Unexpected: {e}"
        return result


def status_line(base_url: Optional[str] = None) -> str:
    """One-line status for sidebar / logs."""
    s = check_health(base_url)
    if not s["url"]:
        return "🟠 Ollama: not configured (OLLAMA_BASE_URL empty)"
    extra = f" ({s['latency_ms']}ms)" if s.get("latency_ms") is not None else ""
    if s["ok"] and s["has_model"]:
        return f"🟢 Ollama: online{extra} — {s['url']} — {s['model']}"
    if s["ok"]:
        return f"🟡 Ollama: online{extra} — {s['error']}"
    return f"🔴 Ollama: {s['error']}"


def is_ready(base_url: Optional[str] = None) -> bool:
    """True only when reachable and target model is present."""
    s = check_health(base_url)
    return bool(s["ok"] and s["has_model"])
