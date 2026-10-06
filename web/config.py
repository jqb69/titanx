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
    "/"
]

# === FILE VAULT (REDIS-OPTIMIZED) ===
FILE_STORAGE_DIR = os.getenv("FILE_STORAGE_DIR", "/workspace/mikie_files")
MAX_FILE_SIZE_MB = int(os.getenv("MAX_FILE_SIZE_MB", "50"))
# web/config.py — Updated with file vault settings
# Changes: 9 new FILE_ variables. All existing settings preserved exactly.


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
# Email (Resend)
RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
EMAIL_FROM = os.getenv("EMAIL_FROM", "MIKIE <onboarding@resend.dev>")

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

# === LLM ROUTING ===
OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "").rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:7b")
LLM_PRIMARY = os.getenv("LLM_PRIMARY", "ollama").lower()
LLM_FALLBACK = os.getenv("LLM_FALLBACK", "openrouter").lower()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "openrouter/free")

# Comma-separated; override via env AGENTIC_HINTS
_AGENTIC_RAW = os.getenv(
    "AGENTIC_HINTS",
    "weather,forecast,run ,install,ssh,droplet,browse,search web,encode,decode,copy,"
    "carry out,execute,screenshot,open url,create file,delete file,docker,encrypt,decrypt,study,"
    "deploy,terminal,shell,curl ,wget ,git clone,pip install,assess,report,translate,"
    "code,coding,refactor,patch,fix,bug,error,stack,traceback,"
    "titanx,mikie,avangarde,hermes,ollama,openrouter,organize,"
    "review,compile,build,debug,trace,task,implement,deploy,repo,github,commit,pr,merge",
)
AGENTIC_HINTS = tuple(
    h.strip().lower() for h in _AGENTIC_RAW.split(",") if h.strip()
)
AGENTIC_SHOW_BRIEF = os.getenv("AGENTIC_SHOW_BRIEF", "true").lower() == "true"

AGENTIC_ALWAYS_COMPRESS = os.getenv("AGENTIC_ALWAYS_COMPRESS", "false").lower() == "true"
# optional max brief size
OLLAMA_CHAT_TIMEOUT = (4, 90)          # was implicit (5, 180)

AGENTIC_USE_LLM = False
AGENTIC_BRIEF_CHARS = 1200
OLLAMA_COMPRESS_CONNECT = float(os.getenv("OLLAMA_COMPRESS_CONNECT", "2"))
OLLAMA_COMPRESS_READ = float(os.getenv("OLLAMA_COMPRESS_READ", "8"))
AGENTIC_BRIEF_CHARS = int(os.getenv("AGENTIC_BRIEF_CHARS", "1200"))

# Optional: use tiny Ollama classify pass (slower, smarter)
AGENTIC_USE_LLM = os.getenv("AGENTIC_USE_LLM", "false").lower() == "true"

CUSTOM_CSS = """
<style>
 .stApp { background-color: #0a0a0a; color: #ffffff; }
 .stChatMessage {
   border-radius: 12px;
   padding: 14px;
   margin-bottom: 10px;
 }
 h1 { color: #ffffff; text-align: center; font-weight: 300; }
 .file-box {
   background-color: #1a1a1a;
   padding: 10px;
   border-radius: 8px;
   border: 1px dashed #333;
   margin-bottom: 10px;
 }
 .error-box { color: #ff6b6b; }
</style>
"""


def ollama_model() -> str:
    return OLLAMA_MODEL or "qwen2.5:7b"

def openrouter_model() -> str:
    return OPENROUTER_MODEL or "openrouter/free"

def resolve_model(for_backend: str = "auto") -> str:
    """
    for_backend: "ollama" | "openrouter" | "auto"
    auto = ollama if LLM_PRIMARY==ollama else openrouter
    """
    if for_backend == "ollama":
        return ollama_model()
    if for_backend == "openrouter":
        return openrouter_model()
    if LLM_PRIMARY == "ollama":
        return ollama_model()
    return openrouter_model()
