#!/bin/bash
# mother-script.sh
# ================================================
# MOTHER SCRIPT  Full TitanX Installation (v2.1)
# Includes Swap + Age Check + Clear Flow
# ================================================
set -euo pipefail

USER_NAME="ajax"
PROJECT_HOME="/home/${USER_NAME}/titanx"
DATA_PATH="${PROJECT_HOME}/data"

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
    # DigitalOcean Auto-Mount point (Ext4) [cite: 227, 230, 238]
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
    chown -R "${USER_NAME}:${USER_NAME}" "$DATA_PATH"
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
        error "Docker daemon is not responding!" [cite: 81]
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
        # Using --tail instead of -f to prevent hanging the CI/CD pipeline 
        docker compose logs --tail=20 hermes 
    else
        error "Docker directory $DOCKER_PATH not found."
    fi
}


# ====================== MAIN ======================

log "=== TitanX Mother Installer Starting ==="

check_root() {
    [[ $EUID -eq 0 ]] || error "Mother script must be run as ROOT"
}

check_root
create_swap
setup_storage_mount
install_age_early

log "Running installation scripts in order..."

./create-ajax-user.sh     || error "create-ajax-user.sh failed"
./create-secrets.sh       || error "create-secrets.sh failed"
./install-titanx-docker.sh || error "install-titanx-docker.sh failed"

log "========================================"
log "✅ TITANX DEPLOYED ON NVMe STORAGE SUCCESSFULLY!"
log "========================================"

# Verification and Logs 
verify_docker_final
print_app_logs


log "========================================"
log "✅ FULL TITANX INSTALLATION COMPLETED SUCCESSFULLY!"
log "========================================"
log "Next Steps:"
log "1. Download your SSH private key:"
log "   scp ajax@YOUR_DROPLET_IP:/home/ajax/.ssh/id_ed25519 ~/.ssh/titanx_ajax"
log "   chmod 600 ~/.ssh/titanx_ajax"
log ""
log "2. Check services:"
log "   cd /home/ajax/titanx/docker && docker compose logs -f"
log ""
log "3. Test Hermes:"
log "   docker exec -it titanx-hermes hermes chat"
log "========================================"
