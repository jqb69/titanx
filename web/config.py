# web/config.py
import os
HERMES_URL = os.getenv("HERMES_URL", "http://titanx-hermes:8642").rstrip("/")
HERMES_API_KEY = os.getenv("HERMES_API_KEY", "")
# Redis with dynamic password from secrets (recommended for your setup)
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "defaultpass")
REDIS_URL = f"redis://:{REDIS_PASSWORD}@redis:6379/0"
# === MODEL CONFIG - Optimized for Cheapskate ===
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free")  # Smart free model router
# Reasoning settings
REASONING_ENABLED = os.getenv("REASONING_ENABLED", "true").lower() == "true"
REASONING_EFFORT = os.getenv("REASONING_EFFORT", "medium")
# Fallback endpoints
ENDPOINTS = [
    "/v1/chat/completions",
    "/chat/completions",
    "/",
    "/api/chat",
    "/v1/chat",
    "/message"
]
CUSTOM_CSS = """
<style>
 .stApp { background-color: #0a0a0a; color: #ffffff; }
 .stChatMessage { border-radius: 12px; padding: 14px; margin-bottom: 10px; }
 h1 { color: #ffffff; text-align: center; font-weight: 300; }
 .file-box { background-color: #1a1a1a; padding: 10px; border-radius: 8px; border: 1px dashed #333; margin-bottom: 10px; }
 .error-box { color: #ff6b6b; }
</style>
"""
