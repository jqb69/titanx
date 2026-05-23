#!/bin/bash
# scripts/bootstrap-to-ajax.sh
# Clean transfer from root bootstrap to /home/ajax/titanx
set -euo pipefail

BOOTSTRAP="/root/titanx-bootstrap"
TARGET="/home/ajax/titanx"

log() { echo "[BOOTSTRAP $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

setup_ssh_key_access() {
    log "Setting up new SSH key access for ajax user..."

    local AJAX_SSH_DIR="/home/ajax/.ssh"
    local ROOT_SSH_DIR="/root/.ssh"

    mkdir -p "$AJAX_SSH_DIR"
    chmod 700 "$AJAX_SSH_DIR"

    # Copy private key (critical for ssh-action as ajax)
    if [[ -f "$ROOT_SSH_DIR/id_ed25519" ]]; then
        cp -f "$ROOT_SSH_DIR/id_ed25519" "$AJAX_SSH_DIR/id_ed25519"
        cp -f "$ROOT_SSH_DIR/id_ed25519.pub" "$AJAX_SSH_DIR/id_ed25519.pub" 2>/dev/null || true
        log "✓ Copied SSH private key to ajax user"
    else
        log "⚠️ No id_ed25519 found in root - skipping copy"
    fi

    # Setup authorized_keys
    if [[ -f "$ROOT_SSH_DIR/authorized_keys" ]]; then
        cp -f "$ROOT_SSH_DIR/authorized_keys" "$AJAX_SSH_DIR/authorized_keys" 2>/dev/null || true
    fi

    # Ensure public key is in authorized_keys
    if [[ -f "$AJAX_SSH_DIR/id_ed25519.pub" ]]; then
        if ! grep -q -f "$AJAX_SSH_DIR/id_ed25519.pub" "$AJAX_SSH_DIR/authorized_keys" 2>/dev/null; then
            cat "$AJAX_SSH_DIR/id_ed25519.pub" >> "$AJAX_SSH_DIR/authorized_keys"
            log "✓ Added public key to authorized_keys"
        else
            log "✓ Public key already in authorized_keys"
        fi
    fi

    # Fix permissions (very important)
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
