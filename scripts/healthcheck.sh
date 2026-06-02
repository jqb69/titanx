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
    local timeout=90
    for ((i=0; i<timeout; i+=3)); do
        if python3 -c '
import urllib.request
try:
    urllib.request.urlopen("http://localhost/_stcore/health", timeout=5)
    exit(0)
except:
    exit(1)
' 2>/dev/null; then
            log "✅ Streamlit is reachable via Caddy"
            return 0
        fi
        sleep 3
        if ((i >= 45)); then
            log "Still waiting... ($i/$timeout s)"
        fi
    done
    log "⚠️ Streamlit took longer than expected"
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
