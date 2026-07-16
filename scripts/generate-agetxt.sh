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

    local required_vars=(
        "OPENROUTER_API_KEY" "OPENROUTER_MODEL"
        "GIT_USER" "GIT_TOKEN"
        "PROJECT_PRIVATE_KEY"
        "TWILIO_SID" "TWILIO_AUTH_TOKEN" "TWILIO_PHONE"
        "GOOGLE_CLIENT_ID"
    )

    [[ -z "${OPENROUTER_KEY:-}" ]] && error "OPENROUTER_KEY missing"
    [[ -z "${OPENROUTER_MODEL:-}" ]] && error "OPENROUTER_MODEL missing"
    [[ -z "${G_USER:-}" ]] && error "G_USER missing"
    [[ -z "${G_TOKEN:-}" ]] && error "G_TOKEN missing"
    [[ -z "${P_PRIVATE_KEY:-}" ]] && error "P_PRIVATE_KEY missing"
    [[ -z "${TWILIO_SID:-}" ]] && error "TWILIO_SID missing"
    [[ -z "${TWILIO_AUTH_TOKEN:-}" ]] && error "TWILIO_AUTH_TOKEN missing"
    [[ -z "${TWILIO_PHONE:-}" ]] && error "TWILIO_PHONE missing"
    [[ -z "${GOOGLE_CLIENT_ID:-}" ]] && error "GOOGLE_CLIENT_ID missing"

    # 2) Write secrets.txt with proper mapping
    log "Writing mapped variables to secrets.txt..."
    cat <<EOF > "$SECRETS_TXT"
OPENROUTER_API_KEY=${OPENROUTER_KEY}
OPENROUTER_MODEL=${OPENROUTER_MODEL}
GIT_USER=${G_USER}
GIT_TOKEN=${G_TOKEN}
PROJECT_PRIVATE_KEY=${P_PRIVATE_KEY}
TWILIO_SID=${TWILIO_SID}
TWILIO_AUTH_TOKEN=${TWILIO_AUTH_TOKEN}
TWILIO_PHONE=${TWILIO_PHONE}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
EOF

    # 3) Integrity check
    for v in "${required_vars[@]}"; do
        grep -q "^${v}=" "$SECRETS_TXT" || error "Failed to write $v to secrets.txt!"
    done

    # 4) Permissions
    chmod 600 "$SECRETS_TXT"
    chown "$USER":"$USER" "$SECRETS_TXT"

    log "✅ secrets.txt generated and verified successfully"
}


# Execute
generate_file
