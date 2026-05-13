#!/bin/bash
# create-secrets.sh
# Script 2: secrets.txt → Encrypt → Scorched Earth Delete
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
SECRETS_TXT="secrets.txt"
SECRETS_AGE="${HERMES_DATA}/secrets.age"
PUBKEY_PATH="/home/${USER}/.ssh/id_ed25519.pub"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }



# --- MODULAR ENCRYPTION FUNCTION ---
generate_and_encrypt() {
    log "Merging manual secrets with auto-generated Redis password..."

    # 1. Verification
    [[ ! -f "$SECRETS_TXT" ]] && error "Manual secrets.txt not found!"
    [[ ! -f "$PUBKEY_PATH" ]] && error "Recipient public key missing at $PUBKEY_PATH"

    # 2. Append the random Redis password to the uploaded secrets.txt
    local redis_pass
    redis_pass=$(openssl rand -hex 32)
    echo "REDIS_PASSWORD=${redis_pass}" >> "$SECRETS_TXT"
    log "✓ Appended REDIS_PASSWORD to secrets.txt"

    # 3. Encrypt the merged file using ajax user's public key
    log "Encrypting merged secrets into $SECRETS_AGE..."
    if su - "$USER" -c "age -r \"\$(cat $PUBKEY_PATH)\" -o \"$SECRETS_AGE\" \"$SECRETS_TXT\""; then
        log "✓ Secrets encrypted successfully."
        
        # 4. Shred the raw file immediately
        log "Shredding plain-text secrets file..."
        shred -u "$SECRETS_TXT"
    else
        error "Encryption failed!"
    fi
}

# --- MAIN EXECUTION ---
generate_and_encrypt
