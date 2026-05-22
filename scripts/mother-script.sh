#!/bin/bash
# mother-script.sh
# ================================================
# MOTHER SCRIPT Full TitanX Installation (v2.1)
# ================================================
set -euo pipefail

# === PATHS ===
USER="ajax"
PROJECT_HOME="/home/${USER}/titanx"
DATA_PATH="${PROJECT_HOME}/data"
DOCKER_PATH="${PROJECT_HOME}/docker"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================
create_swap() {
    log "Creating 2GB Swap (critical for 2GB RAM Droplet)..."
    if [[ ! -f /swapfile ]]; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log "✓ 2GB Swap created and activated"
    else
        log "✓ Swap already exists"
    fi
}

setup_storage_mount() {
    log "Linking NVMe volume to project data directory..."
    VOLUME_DIR=$(ls -d /mnt/volume_* 2>/dev/null | head -n 1)
    
    if [ -z "$VOLUME_DIR" ]; then
        log "WARNING: NVMe volume not found. Using local disk."
        mkdir -p "$DATA_PATH"
    else
        log "✓ Volume found at $VOLUME_DIR. Linking to $DATA_PATH"
        mkdir -p "$(dirname "$DATA_PATH")"
        if [ ! -L "$DATA_PATH" ] && [ ! -d "$DATA_PATH" ]; then
            ln -s "$VOLUME_DIR" "$DATA_PATH"
        fi
    fi
    # FIXED: Using $USER instead of the non-existent $USER_NAME
    chown -R "${USER}:${USER}" "$DATA_PATH"
}

wait_for_apt_lock() {
    log "[PRE-FLIGHT] Waiting for apt/dpkg locks to clear..."
    local timeout=120 waited=0
    while [[ $waited -lt $timeout ]]; do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && \
           ! pgrep -x apt-get >/dev/null 2>&1 && \
           ! pgrep -x dpkg >/dev/null 2>&1; then
            log "[PRE-FLIGHT] ✓ Apt is clear"
            return 0
        fi
        log "[PRE-FLIGHT] ⚠️ Lock held, waiting 8s..."
        sleep 8
        waited=$((waited + 8))
    done
    error "Timeout waiting for apt locks"
}

install_age_early() {
    log "Ensuring 'age' is installed..."
    if ! command -v age >/dev/null 2>&1; then
        log "Installing age..."
        apt-get update -qq && apt-get install -y age
        log "✓ age installed"
    else
        log "✓ age already installed"
    fi
}

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
    log "========================================"
    log "✅ FULL TITANX INSTALLATION COMPLETED SUCCESSFULLY!"
    log "========================================"
    log "Next Steps:"
    log "1. Download your SSH private key:"
    log "   scp ${USER}@YOUR_DROPLET_IP:/home/${USER}/.ssh/id_ed25519 ~/.ssh/titanx_${USER}"
    log "   chmod 600 ~/.ssh/titanx_${USER}"
    log ""
    log "2. Check services:"
    log "   cd ${DOCKER_PATH} && docker compose logs -f"
    log ""
    log "3. Test Hermes Gateway:"
    log "   docker exec -it hermes /opt/hermes/.venv/bin/hermes chat"
    log ""
    log "4. Test Hermes Avangarde:"
    log "   docker exec -it hermes-avangarde /opt/hermes/.venv/bin/hermes chat"
    log "========================================"
    log "Next Steps:"
    log "   Hermes Main     → http://localhost:8642"
    log "   Web UI (HTTPS)  → https://YOUR_IP"
    log "   SSH Key: scp ${USER}@YOUR_IP:/home/${USER}/.ssh/id_ed25519 ~/.ssh/titanx_${USER}"
    log "========================================"
    log "========================================"

}

# ====================== MAIN ======================
log "=== TitanX Mother Installer Starting ==="

check_root() {
    [[ $EUID -eq 0 ]] || error "Mother script must be run as ROOT"
}

check_root
wait_for_apt_lock
create_swap
setup_storage_mount
install_age_early

log "Running installation scripts in order..."
./create-ajax-user.sh     || error "create-ajax-user.sh failed"
./create-secrets.sh       || error "create-secrets.sh failed"
#./install-titanx-docker.sh || error "install-titanx-docker.sh failed"
#./install-webui.sh       || error "install-web-ui.sh failed"   # ← Added

log "========================================"
log "✅ TITANX ROOT INFRASTRUCTURE DEPLOYED SUCCESSFULLY!"
log "========================================"
