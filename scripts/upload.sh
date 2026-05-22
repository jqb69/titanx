#!/bin/bash
# scripts/upload.sh — Idempotent upload with stale script purge
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
SOURCE_DIR="/root/titanx-bootstrap"  # Where SCP drops files

log() { echo "[$(date '+%H:%M:%S')] [UPLOAD] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

verify_source() {
    log "Verifying bootstrap source..."
    if [[ ! -d "$SOURCE_DIR" ]]; then
        error "Source directory $SOURCE_DIR not found. Did SCP succeed?"
    fi
    log "✓ Source found: $SOURCE_DIR"
}

purge_old_scripts() {
    log "Purging stale .sh scripts in $PROJECT_DIR..."
    
    # Safety: only delete .sh files, never touch data/, .hermes/, docker/, web/, workspace/
    # Also preserve secrets.age and any .txt files
    find "$PROJECT_DIR" -maxdepth 1 -type f -name "*.sh" -delete 2>/dev/null || true
    
    # Also clean the scripts/ subdirectory if it exists
    if [[ -d "$PROJECT_DIR/scripts" ]]; then
        find "$PROJECT_DIR/scripts" -maxdepth 1 -type f -name "*.sh" -delete 2>/dev/null || true
    fi
    
    log "✓ Old scripts purged"
}

upload_new_files() {
    log "Uploading new files from $SOURCE_DIR..."
    
    # Ensure target exists
    mkdir -p "$PROJECT_DIR"
    chown "$USER:$USER" "$PROJECT_DIR"
    
    # Copy scripts/ directory (new refactored deploy-app.sh, etc.)
    if [[ -d "$SOURCE_DIR/scripts" ]]; then
        mkdir -p "$PROJECT_DIR/scripts"
        cp -a "$SOURCE_DIR/scripts/." "$PROJECT_DIR/scripts/" 2>/dev/null || true
        chown -R "$USER:$USER" "$PROJECT_DIR/scripts"
        log "✓ scripts/ uploaded"
    fi
    
    # Copy web/ directory (Streamlit app)
    if [[ -d "$SOURCE_DIR/web" ]]; then
        mkdir -p "$PROJECT_DIR/web"
        cp -a "$SOURCE_DIR/web/." "$PROJECT_DIR/web/" 2>/dev/null || true
        chown -R "$USER:$USER" "$PROJECT_DIR/web"
        log "✓ web/ uploaded"
    fi
    
    # Copy any loose .sh files at root (legacy compatibility during transition)
    for f in "$SOURCE_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        cp "$f" "$PROJECT_DIR/"
        chown "$USER:$USER" "$PROJECT_DIR/$(basename "$f")"
        chmod +x "$PROJECT_DIR/$(basename "$f")"
    done
    log "✓ Root .sh files uploaded"
}

verify_permissions() {
    log "Setting permissions..."
    chown -R "$USER:$USER" "$PROJECT_DIR"
    find "$PROJECT_DIR" -maxdepth 2 -type f -name "*.sh" -exec chmod +x {} \;
    log "✓ Permissions set"
}

# ====================== MAIN ======================
main() {
    log "=== Idempotent Upload Starting ==="
    
    verify_source
    purge_old_scripts
    upload_new_files
    verify_permissions
    
    # Final safety: list what we have
    log "=== Deployed scripts ==="
    find "$PROJECT_DIR" -maxdepth 2 -type f -name "*.sh" | while read -r f; do
        log "  → $f"
    done
    
    log "✅ Upload completed — no stale scripts remain"
}

main "$@"
