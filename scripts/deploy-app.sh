#!/bin/bash
# scripts/deploy-app.sh
# Runs as ajax user - ONLY install-titanx-docker + install-webui
set -euo pipefail

PROJECT_DIR="/home/ajax/titanx"
DOCKER_PATH="${PROJECT_DIR}/docker"
USER="ajax"

log() { echo "[$(date '+%H:%M:%S')] [APP-DEPLOY] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

verify_docker_final() {
    log "Verifying Docker Installation..."
    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not responding!"
    fi
    if ! docker ps --format '{{.Names}}' | grep -q "hermes"; then
        error "Hermes Docker container is NOT running!"
    fi
    log "✓ Docker and Hermes container verified."
}

print_app_logs() {
    log "--- FINAL APPLICATION LOGS (Tail) ---"
    if [ -d "$DOCKER_PATH" ]; then
        cd "$DOCKER_PATH"
        docker compose logs --tail=30 hermes || true
    else
        log "WARNING: Docker directory not found at $DOCKER_PATH"
    fi

    # ====================== YOUR REQUESTED OUTPUT ======================
    echo "========================================"
    log "✅ FULL TITANX INSTALLATION COMPLETED SUCCESSFULLY!"
    echo "========================================"

    echo "Next Steps:"
    echo "1. Download your SSH private key:"
    echo "   scp ${USER}@YOUR_DROPLET_IP:/home/${USER}/.ssh/id_ed25519 ~/.ssh/titanx_${USER}"
    echo "   chmod 600 ~/.ssh/titanx_${USER}"
    echo ""
    echo "2. Check services:"
    echo "   cd ${DOCKER_PATH} && docker compose logs -f"
    echo ""
    echo "3. Test Hermes Gateway:"
    echo "   docker exec -it hermes /opt/hermes/.venv/bin/hermes chat"
    echo ""
    echo "4. Test Hermes Avangarde:"
    echo "   docker exec -it hermes-avangarde /opt/hermes/.venv/bin/hermes chat"
    echo "========================================"

    echo " Hermes Main → http://localhost:8642"
    echo " Web UI (HTTPS) → https://YOUR_IP"
    echo " SSH Key: scp ${USER}@YOUR_IP:/home/${USER}/.ssh/id_ed25519 ~/.ssh/titanx_${USER}"
    echo "========================================"
}

run_app_deployment() {
    log "=== Starting Application Deployment Phase (as ajax) ==="

    cd "$PROJECT_DIR" || error "Cannot cd to $PROJECT_DIR"

    ./install-titanx-docker.sh --ajax || error "Docker app launch failed"
    ./install-webui.sh        || log "Web UI installation skipped (optional)"

    log "✅ Application deployment phase completed"
}

# ====================== MAIN ======================
main() {
    run_app_deployment
    verify_docker_final
    print_app_logs

    log "========================================"
    log "✅ FULL TITANX DEPLOYMENT FINISHED"
    log "========================================"
}

main "$@"
