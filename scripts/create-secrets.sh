#!/bin/bash
# create-secrets.sh
# Script 2: secrets.txt → Encrypt → Scorched Earth Delete
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
SECRETS_TXT="secrets.txt"
SECRETS_AGE="${HERMES_DATA}/secrets.age"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

[[ -f "$SECRETS_TXT" ]] || error "secrets.txt not found in current directory!"

# Add random Redis password
REDIS_PASS=$(openssl rand -hex 32)
echo "REDIS_PASSWORD=$REDIS_PASS" >> "$SECRETS_TXT"

mkdir -p "$HERMES_DATA"
chown "$USER":"$USER" "$HERMES_DATA"

log "Encrypting secrets.txt..."
su - "$USER" -c "age -r \$(cat ~/.ssh/id_ed25519.pub) -o $SECRETS_AGE $(realpath $SECRETS_TXT)"

if [[ -f "$SECRETS_AGE" ]]; then
    log "✅ Encryption successful → Scorched Earth policy"
    rm -f *.txt
    log "All .txt files deleted. No plaintext remains."
else
    error "Encryption failed!"
fi
