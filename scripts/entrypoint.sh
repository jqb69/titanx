#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# === INTERNAL CONTAINER CONFIGURATION ===
# These internal paths align with the docker-compose volume mappings
USER_NAME="ajax"
PROJECT_DIR="/home/${USER_NAME}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
SECRETS_AGE="${HERMES_DATA}/secrets.age"
KEY_PATH="/home/${USER_NAME}/.ssh/id_ed25519"

# Security whitelist for runtime environment extraction
ALLOWED=("REDIS_PASSWORD" "OPENROUTER_API_KEY" "GITHUB_TOKEN" "GIT_USER" "PROJECT_PRIVATE_KEY")

log() { echo "[ENTRYPOINT] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

load_runtime_secrets() {
    if [[ -f "$SECRETS_AGE" ]]; then
        log "Decrypting secrets from $SECRETS_AGE directly into RAM..."
        
        if [[ ! -f "$KEY_PATH" ]]; then
            error "Decryption identity key missing at $KEY_PATH"
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
        log "WARNING: $SECRETS_AGE not found. Using system defaults."
    fi
}

# --- EXECUTION ---
load_runtime_secrets

log "Launching Containerized Hermes Gateway..."
# UN-FUCKED PATH: Let the container shell resolve 'hermes' automatically from its internal $PATH
exec hermes gateway run
