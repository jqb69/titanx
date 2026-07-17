# web/config.py — Updated with file vault settings
# Changes: 4 new FILE_ variables. All existing settings preserved exactly.

import os

# === CORE ENDPOINTS ===
HERMES_URL = os.getenv("HERMES_URL", "http://titanx-hermes:8642").rstrip("/")
AVANGARDE_URL = os.getenv("AVANGARDE_URL", "http://avangarde:8080").rstrip("/")
HERMES_API_KEY = os.getenv("HERMES_API_KEY", "")
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/workspace/uploaded")


# Ensure dirs exist + permissions
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.chmod(UPLOAD_DIR, 0o777)  # or more restrictive with umask + grou
# === REDIS ===
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "defaultpass")
REDIS_URL = f"redis://:{REDIS_PASSWORD}@redis:6379/0"

# === MODEL CONFIG ===
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free")
REASONING_ENABLED = os.getenv("REASONING_ENABLED", "true").lower() == "true"
REASONING_EFFORT = os.getenv("REASONING_EFFORT", "medium")

#Queue names
HERMES_QUEUE = "hermes:jobs"
AVANGARDE_QUEUE = "avangarde:jobs"
RESULTS_QUEUE = "hermes:results"

# Fallback endpoints (retained for endpoint-probing resilience)
ENDPOINTS = [
    "/v1/chat/completions",
    "/chat/completions",
    "/",
    "/api/chat",
    "/v1/chat",
    "/message"
]

# === FILE VAULT (REDIS-OPTIMIZED) ===
FILE_STORAGE_DIR = os.getenv("FILE_STORAGE_DIR", "/workspace/mikie_files")
MAX_FILE_SIZE_MB = int(os.getenv("MAX_FILE_SIZE_MB", "50"))
# web/config.py — Updated with file vault settings
# Changes: 9 new FILE_ variables. All existing settings preserved exactly.

import os

# === CORE ENDPOINTS ===
HERMES_URL = os.getenv("HERMES_URL", "http://titanx-hermes:8642").rstrip("/")
AVANGARDE_URL = os.getenv("AVANGARDE_URL", "http://avangarde:8080").rstrip("/")
HERMES_API_KEY = os.getenv("HERMES_API_KEY", "")
UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/workspace/uploaded")

SECRET_KEY = os.getenv("SECRET_KEY", "")
if not SECRET_KEY:
    import secrets
    SECRET_KEY = secrets.token_hex(32)
    # Optionally save it back to hermes.env on first run (optional)

# Ensure dirs exist + permissions
os.makedirs(UPLOAD_DIR, exist_ok=True)
os.chmod(UPLOAD_DIR, 0o777)  # or more restrictive with umask + grou
# === REDIS ===
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "defaultpass")
REDIS_URL = f"redis://:{REDIS_PASSWORD}@redis:6379/0"

# === MODEL CONFIG ===
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free")
REASONING_ENABLED = os.getenv("REASONING_ENABLED", "true").lower() == "true"
REASONING_EFFORT = os.getenv("REASONING_EFFORT", "medium")

#Queue names
HERMES_QUEUE = "hermes:jobs"
AVANGARDE_QUEUE = "avangarde:jobs"
RESULTS_QUEUE = "hermes:results"

# === TWILIO (for Phone OTP) ===
TWILIO_SID = os.getenv("TWILIO_SID", "")
TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_PHONE = os.getenv("TWILIO_PHONE", "")
# === Google ClientID (for google login) ===
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")

# Fallback endpoints (retained for endpoint-probing resilience)
ENDPOINTS = [
    "/v1/chat/completions",
    "/chat/completions",
    "/",
    "/api/chat",
    "/v1/chat",
    "/message"
]

# === FILE VAULT (REDIS-OPTIMIZED) ===
FILE_STORAGE_DIR = os.getenv("FILE_STORAGE_DIR", "/workspace/mikie_files")
MAX_FILE_SIZE_MB = int(os.getenv("MAX_FILE_SIZE_MB", "50"))

# Redis Keys (Memory-efficient)
REDIS_FILE_INDEX = "mikie:files:index"           # SET of UIDs
REDIS_FILE_META_PREFIX = "mikie:files:meta:"     # HASH per file
REDIS_FILE_TEXT_PREFIX = "mikie:files:text:"     # STRING cache (1 week)
# Comma-separated list, or None to allow all types (UI controls gating)
_ALLOWED_RAW = os.getenv("ALLOWED_FILE_EXTENSIONS", "")
ALLOWED_FILE_EXTENSIONS = None if not _ALLOWED_RAW else {e.strip().lower() for e in _ALLOWED_RAW.split(",")}

CUSTOM_CSS = """
<style>
 .stApp { background-color: #0a0a0a; color: #ffffff; }
 .stChatMessage { border-radius: 12px; padding: 14px; margin-bottom: 10px; }
 h1 { color: #ffffff; text-align: center; font-weight: 300; }
 .file-box { background-color: #1a1a1a; padding: 10px; border-radius: 8px; border: 1px dashed #333; margin-bottom: 10px; }
 .error-box { color: #ff6b6b; }
</style>
"""
# Redis Keys (Memory-efficient)
REDIS_FILE_INDEX = "mikie:files:index"           # SET of UIDs
REDIS_FILE_META_PREFIX = "mikie:files:meta:"     # HASH per file
REDIS_FILE_TEXT_PREFIX = "mikie:files:text:"     # STRING cache (1 week)
# Comma-separated list, or None to allow all types (UI controls gating)
_ALLOWED_RAW = os.getenv("ALLOWED_FILE_EXTENSIONS", "")
ALLOWED_FILE_EXTENSIONS = None if not _ALLOWED_RAW else {e.strip().lower() for e in _ALLOWED_RAW.split(",")}

CUSTOM_CSS = """
<style>
 .stApp { background-color: #0a0a0a; color: #ffffff; }
 .stChatMessage { border-radius: 12px; padding: 14px; margin-bottom: 10px; }
 h1 { color: #ffffff; text-align: center; font-weight: 300; }
 .file-box { background-color: #1a1a1a; padding: 10px; border-radius: 8px; border: 1px dashed #333; margin-bottom: 10px; }
 .error-box { color: #ff6b6b; }
</style>
"""
