#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# === INTERNAL CONTAINER CONFIGURATION ===
# Centralized hoisting for internal container paths [cite: 347, 354, 357]
USER_NAME="ajax"
PROJECT_DIR="/home/${USER_NAME}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
SECRETS_AGE="${HERMES_DATA}/secrets.age"
KEY_PATH="/home/${USER_NAME}/.ssh/id_ed25519"

# Variables allowed to be exported to the environment [cite: 280, 306]
ALLOWED=("REDIS_PASSWORD" "OPENROUTER_API_KEY" "GITHUB_TOKEN" "GIT_USER" "PROJECT_PRIVATE_KEY")

log() { echo "[ENTRYPOINT] $*"; }

# --- MODULAR DECRYPTION FUNCTION ---
load_runtime_secrets() {
    if [[ -f "$SECRETS_AGE" ]]; then
        log "Decrypting secrets from $SECRETS_AGE..."
        
        if [[ ! -f "$KEY_PATH" ]]; then
            echo "[ERROR] Decryption key missing at $KEY_PATH" >&2
            exit 1
        fi

        # Process substitution avoids subshell variable loss [cite: 296, 307, 331]
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Ignore comments and blank lines [cite: 280, 303]
            [[ "$line" =~ ^#.* ]] || [[ -z "$line" ]] && continue
            
            if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local val="${BASH_REMATCH[2]}"
                
                for target in "${ALLOWED[@]}"; do
                    if [[ "$key" == "$target" ]]; then
                        export "$key"="$val"
                        log "Exported $key"
                    fi
                done
            fi
        done < <(age -d -i "$KEY_PATH" "$SECRETS_AGE" 2>/dev/null)
    else
        log "WARNING: $SECRETS_AGE not found. Proceeding with defaults."
    fi
}

# --- MAIN EXECUTION ---
load_runtime_secrets
log "Launching Hermes Gateway..."
exec /usr/local/bin/hermes gateway run
