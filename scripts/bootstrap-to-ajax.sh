#!/bin/bash
# scripts/bootstrap-to-ajax.sh
# Clean transfer from root bootstrap to /home/ajax/titanx
set -euo pipefail

BOOTSTRAP="/root/titanx-bootstrap"
TARGET="/home/ajax/titanx"

log() { echo "[BOOTSTRAP $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

log "Starting transfer to ajax project directory..."

# Ensure ajax user exists
if ! id "ajax" &>/dev/null; then
    log "ajax user not found, creating..."
    bash "$BOOTSTRAP/create-ajax-user.sh"
fi

# Copy all scripts to final location
mkdir -p "$TARGET"
cp -r "$BOOTSTRAP"/* "$TARGET/" 2>/dev/null || true

# Fix ownership and permissions
chown -R ajax:ajax "$TARGET"
chmod +x "$TARGET"/*.sh

log "✅ All scripts successfully moved to /home/ajax/titanx"
