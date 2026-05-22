#!/bin/bash
# scripts/upload.sh — Idempotent upload matching deploy.yaml layout
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
SOURCE_DIR="/root/titanx-bootstrap"

log() { echo "[$(date '+%H:%M:%S')] [UPLOAD] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

verify_source() {
    [[ -d "$SOURCE_DIR" ]] || error "Source $SOURCE_DIR not found"
    log "✓ Source verified"
}

purge_stale() {
    log "Purging stale artifacts..."

    # Root-level: upload.sh, generate-agetxt.sh, mother-script.sh, etc.
    find "$PROJECT_DIR" -maxdepth 1 -type f -name "*.sh" -delete 2>/dev/null || true
    
    # Compose overrides
    rm -f "$PROJECT_DIR/docker-compose.override.yml" "$PROJECT_DIR/docker-compose.override.yaml" 2>/dev/null || true

    # Wipe subdirectories completely (no overlay garbage)
    rm -rf "$PROJECT_DIR/scripts" "$PROJECT_DIR/web"
    mkdir -p "$PROJECT_DIR/scripts" "$PROJECT_DIR/web"

    log "✓ Stale artifacts purged"
}

copy_fresh() {
    log "Copying fresh files..."

    # scripts/ directory (deploy-app.sh, install-webui.sh, healthcheck.sh, etc.)
    if [[ -d "$SOURCE_DIR/scripts" ]]; then
        cp -a "$SOURCE_DIR/scripts/." "$PROJECT_DIR/scripts/"
        log "✓ scripts/ uploaded ($(ls -1 "$PROJECT_DIR/scripts" | wc -l) files)"
    fi

    # web/ directory (Streamlit app.py, etc.)
    if [[ -d "$SOURCE_DIR/web" ]]; then
        cp -a "$SOURCE_DIR/web/." "$PROJECT_DIR/web/"
        log "✓ web/ uploaded ($(ls -1 "$PROJECT_DIR/web" | wc -l) files)"
    fi

    # Root-level scripts that deploy.yaml expects at /home/ajax/titanx/
    # These come from the source root if they exist there
    for script in upload.sh generate-agetxt.sh; do
        if [[ -f "$SOURCE_DIR/$script" ]]; then
            cp "$SOURCE_DIR/$script" "$PROJECT_DIR/"
            log "✓ Root script uploaded: $script"
        elif [[ -f "$SOURCE_DIR/scripts/$script" ]]; then
            cp "$SOURCE_DIR/scripts/$script" "$PROJECT_DIR/"
            log "✓ Root script uploaded from scripts/: $script"
        fi
    done
}

set_permissions() {
    chown -R "$USER:$USER" "$PROJECT_DIR"
    find "$PROJECT_DIR" -type f -name "*.sh" -exec chmod +x {} \;
    log "✓ Permissions set"
}

main() {
    log "=== Idempotent Upload Starting ==="
    verify_source
    purge_stale
    copy_fresh
    set_permissions
    
    # Verify what we have
    log "=== Deployed structure ==="
    find "$PROJECT_DIR" -maxdepth 2 -type f | sort | while read -r f; do
        log "  → $f"
    done
    
    log "✅ Upload completed"
}

main "$@"
