#!/bin/bash
# scripts/bootstrap-to-ajax.sh
# Clean transfer from root bootstrap to /home/ajax/titanx
set -euo pipefail

BOOTSTRAP="/root/titanx-bootstrap"
TARGET="/home/ajax/titanx"

log() { echo "[BOOTSTRAP $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

setup_ssh_key_access() {
    log "Setting up SSH key access for ajax user..."

    local ROOT_SSH_DIR="/root/.ssh"
    local AJAX_SSH_DIR="/home/ajax/.ssh"

    mkdir -p "$ROOT_SSH_DIR" "$AJAX_SSH_DIR"
    chmod 700 "$ROOT_SSH_DIR" "$AJAX_SSH_DIR"

    # Generate key only if missing
    if [[ ! -f "$ROOT_SSH_DIR/id_ed25519" ]]; then
        log "Generating new ed25519 keypair..."
        ssh-keygen -t ed25519 -f "$ROOT_SSH_DIR/id_ed25519" -N "" -q
        log "✓ New SSH key generated"
    else
        log "✓ Existing SSH key found"
    fi

    # Copy key to ajax
    cp -f "$ROOT_SSH_DIR/id_ed25519" "$AJAX_SSH_DIR/id_ed25519"
    cp -f "$ROOT_SSH_DIR/id_ed25519.pub" "$AJAX_SSH_DIR/id_ed25519.pub" 2>/dev/null || true

    # === SAFE AUTHORIZED_KEYS (NO DUPLICATES) ===
    if [[ -f "$AJAX_SSH_DIR/id_ed25519.pub" ]]; then
        local pubkey
        pubkey=$(cat "$AJAX_SSH_DIR/id_ed25519.pub")

        # Check if key already exists before appending
        if ! grep -qF "$pubkey" "$AJAX_SSH_DIR/authorized_keys" 2>/dev/null; then
            echo "$pubkey" >> "$AJAX_SSH_DIR/authorized_keys"
            log "✓ Added public key to authorized_keys"
        else
            log "✓ Public key already present in authorized_keys"
        fi
    fi

    # Fix permissions
    chown -R ajax:ajax "$AJAX_SSH_DIR"
    chmod 600 "$AJAX_SSH_DIR/id_ed25519" 2>/dev/null || true
    chmod 644 "$AJAX_SSH_DIR/id_ed25519.pub" 2>/dev/null || true
    chmod 600 "$AJAX_SSH_DIR/authorized_keys" 2>/dev/null || true

    log "✅ SSH key access configured for ajax user"
}

# ====================== MAIN ======================
log "Starting transfer to ajax project directory..."

# Ensure ajax user exists
if ! id "ajax" &>/dev/null; then
    log "ajax user not found, creating..."
    bash "$BOOTSTRAP/create-ajax-user.sh"
fi

# Copy all scripts to final location
mkdir -p "$TARGET"
cp -r "$BOOTSTRAP"/* "$TARGET/" 2>/dev/null || true

# Fix ownership and permissions safely
chown -R ajax:ajax "$TARGET"

# Safe chmod for all .sh files
find "$TARGET" -type f -name "*.sh" -exec chmod +x {} + || true

# Setup SSH key for ajax (idempotent)
setup_ssh_key_access

log "✅ All scripts successfully moved to /home/ajax/titanx"
