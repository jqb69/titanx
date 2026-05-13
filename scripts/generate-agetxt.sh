#!/bin/bash
# scripts/generate-agetxt.sh
set -euo pipefail

# === CONFIGURATION ===
USER="ajax"
PROJECT_DIR="/home/$USER/titanx"
SECRETS_TXT="${PROJECT_DIR}/secrets.txt"

log() { echo "[GENERATE-SECRETS] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

generate_file() {
    log "Verifying individual secret streams..."

    # 1. INDIVIDUAL VALIDATION (Fail fast if GitHub didn't send them)
    [[ -z "${OPENROUTER_KEY:-}" ]] && error "OPENROUTER_API_KEY is missing from stream!"
    [[ -z "${G_USER:-}" ]] && error "GIT_USER is missing from stream!"
    [[ -z "${G_TOKEN:-}" ]] && error "GIT_TOKEN is missing from stream!"
    [[ -z "${P_PRIVATE_KEY:-}" ]] && error "PROJECT_PRIVATE_KEY is missing from stream!"

    # 2. INDIVIDUAL STREAMING TO SECRETS.TXT
    # We map them to the exact names the app/Hermes expects
    log "Writing mapped variables to secrets.txt..."
    
    cat <<EOF > "$SECRETS_TXT"
OPENROUTER_API_KEY=$OPENROUTER_KEY
GIT_USER=$G_USER
GITHUB_TOKEN=$G_TOKEN
PROJECT_PRIVATE_KEY=$P_PRIVATE_KEY
EOF

    # 3. FINAL INTEGRITY CHECK
    # Check if the file actually contains the lines we just wrote
    for var in "OPENROUTER_API_KEY" "GIT_USER" "GITHUB_TOKEN" "PROJECT_PRIVATE_KEY"; do
        if ! grep -q "^$var=" "$SECRETS_TXT"; then
            error "Failed to write $var to secrets.txt!"
        fi
    done

    # 4. SET PERMISSIONS
    chmod 600 "$SECRETS_TXT"
    chown "$USER":"$USER" "$SECRETS_TXT"
    
    log "✓ All variables streamed and verified individually."
}

generate_file
