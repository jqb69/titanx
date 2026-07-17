#!/bin/bash
# scripts/create-secrets.sh
set -euo pipefail

# === CONFIGURATION ===
USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
SECRETS_TXT="${PROJECT_DIR}/secrets.txt"
HERMES_DATA="${PROJECT_DIR}/.hermes"
SECRETS_AGE="${HERMES_DATA}/secrets.age"

log() { echo "[$(date '+%H:%M:%S')] [CREATE-SECRETS] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

create_secrets() {
  log "Starting secrets encryption process..."

  # 1. Path Verification (Absolute Pathing)
  log "Checking for secrets.txt at $SECRETS_TXT..."
  if [[ ! -f "$SECRETS_TXT" ]]; then
    error "secrets.txt not found at $SECRETS_TXT"
  fi

  # 2. Append Redis Password + API server secret
  REDIS_PASS=$(openssl rand -hex 32)
  echo "REDIS_PASSWORD=$REDIS_PASS" >> "$SECRETS_TXT"
  echo "API_SERVER_ENABLED=true" >> "$SECRETS_TXT"
  echo "API_SERVER_HOST=0.0.0.0" >> "$SECRETS_TXT"
  echo "API_SERVER_PORT=8642" >> "$SECRETS_TXT"
  echo "SECRET_KEY=$(openssl rand -hex 32)" >> "$SECRETS_TXT"
  log "✓ Redis, API configs, and SECRET_KEY appended"

  # 3. Prepare .hermes directory
  mkdir -p "$HERMES_DATA"
  chown "$USER":"$USER" "$HERMES_DATA"

  # 4. Encrypt using ajax user's SSH key
  # CRITICAL: Variables $SECRETS_AGE and $SECRETS_TXT are evaluated by the host shell
  # before passing the full absolute paths into the su command string.
  log "Encrypting secrets.txt → secrets.age"
  su - "$USER" -c "age -r \"\$(cat ~/.ssh/id_ed25519.pub)\" -o \"$SECRETS_AGE\" \"$SECRETS_TXT\""

  # 5. Scorched Earth Policy
  if [[ -f "$SECRETS_AGE" ]]; then
    log "✅ Encryption successful"
    # Shred ensures the plain-text cannot be recovered from the NVMe storage
    shred -u "$SECRETS_TXT" 2>/dev/null || rm -f "$SECRETS_TXT"
    log "✓ Plaintext secrets.txt destroyed"
  else
    error "Encryption failed! secrets.age was not created"
  fi

  log "✅ create-secrets.sh completed successfully"
}



# Execute main function
create_secrets
