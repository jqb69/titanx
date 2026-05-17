#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# === INTERNAL CONTAINER CONFIGURATION ===
# FIXED: Replaced invalid host paths with absolute container volume mounts
USER_NAME="ajax"
PROJECT_DIR="/home/${USER_NAME}/titanx"
SECRETS_AGE="/opt/data/secrets.age"
KEY_PATH="/opt/ssh/id_ed25519"

# Security whitelist for runtime environment extraction
ALLOWED=("REDIS_PASSWORD" "OPENROUTER_API_KEY" "GITHUB_TOKEN" "GIT_USER" "PROJECT_PRIVATE_KEY")

log() { echo "[ENTRYPOINT] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

load_runtime_secrets() {
    if [[ -f "$SECRETS_AGE" ]]; then
        log "Decrypting secrets from $SECRETS_AGE directly into RAM..."
        
        if [[ ! -f "$KEY_PATH" ]]; then
            error "Decryption identity key missing inside container at $KEY_PATH"
        fi

        # Process substitution prevents variable loss from piping into a subshell
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Disregard comment blocks and empty lines
            [[ "$line" =~ ^#.* ]] && continue
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"

                for target in "${ALLOWED[@]}"; do
                    if [[ "$key" == "$target" ]]; then
                        export "$key"="$val"
                        log "✓ Successfully exported $key to RAM"
                    fi
                done
            fi
        done < <(age -d -i "$KEY_PATH" "$SECRETS_AGE" 2>/dev/null)
    else
        log "WARNING: $SECRETS_AGE not found inside container. Using system defaults."
    fi
}

# --- EXECUTION ---
load_runtime_secrets

# FIXED: Source the image's internal Python virtual environment before executing 
# so the standard container shell can discover the 'hermes' binary path.
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    log "Activating internal image Python virtual environment..."
    source "/opt/hermes/.venv/bin/activate"
fi

log "Launching Containerized Hermes Gateway..."
exec hermes gateway run
