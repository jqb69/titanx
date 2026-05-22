#!/bin/bash
# scripts/upload.sh — Atomic clean upload
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
SOURCE_DIR="/root/titanx-bootstrap"

log() { echo "[$(date '+%H:%M:%S')] [UPLOAD] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

verify_source() {
    [[ -d "$SOURCE_DIR" ]] || error "Source $SOURCE_DIR not found"
    log "✓ Source verified"
}

purge_ghosts() {
    log "Purging stale artifacts..."

    # Kill all .sh at project root (old install-webui.sh, mother-script.sh ghosts)
    find "$PROJECT_DIR" -maxdepth 1 -type f -name "*.sh" -delete 2>/dev/null || true

    # Kill old override file
    rm -f "$PROJECT_DIR"/docker-compose.override.yml 2>/dev/null || true

    # Wipe subdirectories completely — no overlay garbage survives
    rm -rf "$PROJECT_DIR/scripts" "$PROJECT_DIR/web"
    mkdir -p "$PROJECT_DIR/scripts" "$PROJECT_DIR/web"

    log "✓ Ghosts purged"
}

copy_fresh() {
    log "Copying fresh files..."

    # Subdirectories
    cp -a "$SOURCE_DIR/scripts/." "$PROJECT_DIR/scripts/"
    cp -a "$SOURCE_DIR/web/." "$PROJECT_DIR/web/"

    # ALL root-level .sh files from bootstrap
    for script in "$SOURCE_DIR"/*.sh; do
        [[ -f "$script" ]] || continue
        cp "$script" "$PROJECT_DIR/"
        log "✓ Root script uploaded: $(basename "$script")"
    done

    log "✓ Fresh files copied"
}

set_permissions() {
    chown -R "$USER:$USER" "$PROJECT_DIR/scripts" "$PROJECT_DIR/web"

    # Root .sh files
    find "$PROJECT_DIR" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \;

    # Scripts dir
    chmod +x "$PROJECT_DIR/scripts"/*.sh 2>/dev/null || true

    log "✓ Permissions set"
}

# ====================== MAIN ======================

main() {
    log "=== Atomic Upload Starting ==="

    verify_source
    purge_ghosts
    copy_fresh
    set_permissions

    log "✅ Upload completed — no ghosts remain"
}

main "$@"
