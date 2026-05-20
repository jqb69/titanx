#!/bin/bash
# scripts/upload.sh
set -euo pipefail

TARGET_DIR=${1:-"/home/ajax/titanx"}

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || { echo "Failed to access $TARGET_DIR"; exit 1; }

log() { echo "[UPLOAD $(date '+%H:%M:%S')] $*"; }

log "Preparing directories and permissions..."

# Create required directories
mkdir -p "$TARGET_DIR/docker" "$TARGET_DIR/web" "$TARGET_DIR/.hermes" "$TARGET_DIR/workspace"

# Make scripts executable
chmod +x *.sh 2>/dev/null || true

# Copy web/ from bootstrap if available
if [[ -d "/root/titanx-bootstrap/web" ]]; then
    cp -a /root/titanx-bootstrap/web/. "$TARGET_DIR/web/" 2>/dev/null || true
    log "✓ Web UI files copied"
fi

# Secure permissions
chown -R ajax:ajax "$TARGET_DIR"
chmod -R 755 "$TARGET_DIR"
chmod 700 "$TARGET_DIR/.hermes" 2>/dev/null || true

log "✅ Upload completed"
echo "=================================================="
ls -la
