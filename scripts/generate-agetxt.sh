#!/bin/bash
# scripts/generate-agetxt.sh
set -euo pipefail

# === CONFIGURATION ===
USER="ajax"
PROJECT_DIR="/home/$USER/titanx"
SECRETS_TXT="${PROJECT_DIR}/secrets.txt"

log() { echo "[GENERATE-SECRETS $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

generate_file() {
    log "Verifying individual secret streams..."

    # 1. Strict validation
    [[ -z "${OPENROUTER_KEY:-}" ]] && error "OPENROUTER_KEY missing"
    [[ -z "${OPENROUTER_MODEL:-}" ]] && error "OPENROUTER_MODEL missing"
    [[ -z "${G_USER:-}" ]] && error "G_USER missing"
    [[ -z "${G_TOKEN:-}" ]] && error "G_TOKEN missing"
    [[ -z "${P_PRIVATE_KEY:-}" ]] && error "P_PRIVATE_KEY missing"

    # 2. Write secrets.txt with proper mapping
    log "Writing mapped variables to secrets.txt..."
    cat <<EOF > "$SECRETS_TXT"
OPENROUTER_API_KEY=$OPENROUTER_KEY
OPENROUTER_MODEL=$OPENROUTER_MODEL
GIT_USER=$G_USER
GIT_TOKEN=$G_TOKEN
PROJECT_PRIVATE_KEY=$P_PRIVATE_KEY
EOF

    # 3. Integrity check
    for var in "OPENROUTER_API_KEY" "OPENROUTER_MODEL" "GIT_USER" "GIT_TOKEN" "PROJECT_PRIVATE_KEY"; do
        if ! grep -q "^${var}=" "$SECRETS_TXT"; then
            error "Failed to write $var to secrets.txt!"
        fi
    done

    # 4. Permissions
    chmod 600 "$SECRETS_TXT"
    chown "$USER":"$USER" "$SECRETS_TXT"
    
    log "✅ secrets.txt generated and verified successfully"
}

# Execute
generate_file
