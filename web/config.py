# web/config.py
import os

HERMES_URL = os.getenv("HERMES_URL", "http://titanx-hermes:8642").rstrip("/")
HERMES_API_KEY = os.getenv("HERMES_API_KEY", "")

# STRICT SPEC: /v1/chat/completions remains at index 0 of fallback list
ENDPOINTS = [
    "/v1/chat/completions",
    "/",
    "/chat",
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
</style>
"""
