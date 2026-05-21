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
    if ! docker compose -f "$DOCKER_DIR/docker-compose.yml" ps --format "{{.Name}}" | grep -q "hermes"; then
        error "Hermes container is not running"
    fi
    log "✓ Hermes container is running"
}

check_streamlit() {
    log "Waiting for Streamlit Web UI (port $WEB_PORT)..."
    local timeout=180 waited=0 interval=5

    while ! curl -sf "http://localhost:${WEB_PORT}/_stcore/health" > /dev/null 2>&1; do
        sleep "$interval"
        waited=$((waited + interval))
        if [ "$waited" -ge "$timeout" ]; then
            log "❌ Streamlit failed to start in time"
            docker compose -f "$DOCKER_DIR/docker-compose.yml" logs web --tail=30
            error "Streamlit health check timeout"
        fi
    done
    log "✅ Streamlit is healthy"
}

check_caddy() {
    log "Checking Caddy (HTTP)..."
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
