#!/bin/bash
# scripts/healthcheck.sh
set -euo pipefail

PROJECT_DIR="/home/ajax/titanx"
DOCKER_DIR="${PROJECT_DIR}/docker"

log() { echo "[HEALTHCHECK $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

check_docker_services() {
    log "Checking Docker services..."
    cd "$DOCKER_DIR"
    docker compose ps
    if ! docker compose ps --format "{{.Name}}" | grep -q "hermes"; then
        error "Hermes container is not running"
    fi
    log "✓ Hermes is running"
}

check_streamlit() {
    log "Waiting for Streamlit via Caddy (max 90s)..."
    local timeout=90 waited=0 interval=5

    while ! curl -sf http://localhost/_stcore/health > /dev/null 2>&1; do
        sleep "$interval"
        waited=$((waited + interval))
        if [ "$waited" -ge "$timeout" ]; then
            log "❌ Streamlit timeout - showing logs"
            docker compose logs web --tail=30
            docker compose logs caddy --tail=20
            error "Streamlit / Caddy failed"
        fi
        log "Still waiting... ($waited/$timeout s)"
    done
    log "✅ Streamlit is reachable via Caddy"
}

print_final_summary() {
    echo "========================================"
    echo "✅ FULL TITANX DEPLOYMENT SUCCESSFUL!"
    echo "========================================"
    echo "Access URLs:"
    echo "   Web UI (Chat) → https://YOUR_DROPLET_IP   ← Preferred (HTTPS)"
    echo "   Alternative   → http://YOUR_DROPLET_IP"
    echo "   Hermes API    → http://localhost:8642"
    echo ""
    echo "Next Steps:"
    echo "1. Open browser → https://YOUR_DROPLET_IP"
    echo "2. Type messages in the chat box"
    echo "3. Hermes will respond through the Web UI"
    echo ""
    echo "Recent Logs:"
    docker compose logs web --tail=10
    docker compose logs caddy --tail=10
    echo "========================================"
}

main() {
    log "=== TitanX Health Check Starting ==="

    check_docker_services
    check_streamlit
    print_final_summary

    log "Health check completed successfully"
}

main "$@"
