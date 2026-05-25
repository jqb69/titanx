#!/bin/bash
# scripts/healthcheck.sh
set -euo pipefail

# ====================== CONFIG ======================
PROJECT_DIR="${PROJECT_DIR:-/home/ajax/titanx}"
DOCKER_DIR="${DOCKER_DIR:-${PROJECT_DIR}/docker}"
WEB_PORT="${WEB_PORT:-8501}"
HERMES_PORT="${HERMES_PORT:-8642}"

log() { echo "[HEALTHCHECK $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

check_docker_services() {
    log "Checking Docker services..."
    # Natively change to the directory so Docker automatically merges the base and override files
    cd "$DOCKER_DIR" || error "Failed to navigate to $DOCKER_DIR"
    
    # Check the actual service definitions rather than string matching the raw container name
    if ! docker compose ps --format "{{.Service}}" | grep -q "hermes"; then
        error "Hermes container is not running"
    fi
    log "✓ Hermes container is running"
}

check_streamlit() {
    log "Waiting for Streamlit Web UI (max 90 seconds)..."

    local timeout=90 waited=0 interval=3

    while ! curl -sf http://localhost:8501/_stcore/health > /dev/null 2>&1; do
        sleep "$interval"
        waited=$((waited + interval))
        if [ "$waited" -ge "$timeout" ]; then
            log "❌ Streamlit timeout - showing recent logs"
            docker compose logs web --tail=20
            error "Streamlit failed to start in time"
        fi
        log "Still waiting... ($waited/$timeout s)"
    done
    log "✅ Streamlit is healthy and responding"
}

check_caddy() {
    log "Checking Caddy (HTTP)..."
    # Caddy exposes public ports to the host, so host curl works perfectly here
    if curl -sf http://localhost > /dev/null 2>&1; then
        log "✅ Caddy HTTP is responding"
    else
        log "⚠️ Caddy HTTP not responding (may be using HTTPS only)"
    fi
}

print_summary() {
    log "========================================"
    log "✅ ALL HEALTH CHECKS PASSED"
    log "   Web UI     : http://YOUR_IP:$WEB_PORT"
    log "   Hermes     : http://localhost:$HERMES_PORT"
    log "========================================"
}

# ====================== MAIN ======================
main() {
    log "=== TitanX Health Check Starting ==="

    check_docker_services
    check_streamlit
    check_caddy
    print_summary

    log "Health check completed successfully"
}

main "$@"
