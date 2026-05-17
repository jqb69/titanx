#!/bin/bash
# install-titanx-docker.sh
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
DOCKER_DIR="${PROJECT_DIR}/docker"
SECRETS_AGE="${HERMES_DATA}/secrets.age"

log() { echo "[$(date '+%H:%M:%S')] [DOCKER-INSTALL] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================
check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

wait_for_apt_lock() {
    log "[PRE-FLIGHT] Waiting for apt/dpkg locks..."
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

check_prerequisites() {
    log "Checking prerequisites..."
    [[ -f "$SECRETS_AGE" ]] || error "secrets.age not found!"
    log "✓ secrets.age found"
}

cleanup_stale_docker() {
    log "Cleaning stale containers..."
    docker rm -f $(docker ps -a --format '{{.Names}}' | grep -E 'hermes|redis' || true) 2>/dev/null || true
    docker network rm titanx-net 2>/dev/null || true
    log "✓ Stale resources cleaned"
}

check_and_install_age() {
    log "Checking for age..."
    if command -v age >/dev/null 2>&1; then
        log "✓ age already installed"
        return 0
    fi
    log "Installing age..."
    apt-get update -qq && apt-get install -y age
    log "✓ age installed"
}

install_docker() {
    log "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq curl ufw fail2ban

    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com | sh
    fi

    apt-get install -y -qq docker-compose-plugin
    usermod -aG docker "$USER"

    log "✓ Docker installed successfully"
}

setup_ufw() {
    log "Configuring UFW..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 8642/tcp
    ufw --force enable
    log "✓ UFW configured"
}

cconfigure_and_launch() {
    log "Preparing Docker configuration and entrypoint..."

    mkdir -p "$DOCKER_DIR" "$HERMES_DATA"
    chown -R "$USER":"$USER" "$PROJECT_DIR"

    # === ENTRYPOINT HANDLING (Forced Overwrite to Prevent Stale Cache) ===
    if [[ -f "${PROJECT_DIR}/entrypoint.sh" ]]; then
        log "Moving uploaded entrypoint.sh to persistent volume..."
        mv "${PROJECT_DIR}/entrypoint.sh" "${HERMES_DATA}/entrypoint.sh"
    else
        log "Generating fresh, container-native entrypoint.sh..."
        # Force-writes every deployment to clear out old host-style paths completely
        cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF2'
#!/bin/bash
set -euo pipefail

# absolute volume paths mapped inside the container virtual environment
SECRETS_AGE="/opt/data/secrets.age"
KEY_PATH="/opt/ssh/id_ed25519"

if [[ -f "$SECRETS_AGE" && -f "$KEY_PATH" ]]; then
    echo "[ENTRYPOINT] Decrypting secrets directly into container RAM..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            export "$key"="$val"
            echo "[ENTRYPOINT] Exported: $key"
        fi
    done < <(age -d -i "$KEY_PATH" "$SECRETS_AGE")
else
    echo "[ENTRYPOINT] WARNING: Target assets missing at $SECRETS_AGE or $KEY_PATH."
fi

echo "[ENTRYPOINT] Activating internal image Python virtual environment..."
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    source "/opt/hermes/.venv/bin/activate"
fi

echo "[ENTRYPOINT] Launching Containerized Hermes Gateway Process..."
exec hermes gateway run
EOF2
    fi

    chmod +x "${HERMES_DATA}/entrypoint.sh"
    chown "$USER":"$USER" "${HERMES_DATA}/entrypoint.sh"

    # Extract Redis password for compose
    local redis_pass
    redis_pass=$(su - "$USER" -c "age -d -i ~/.ssh/id_ed25519 \"$SECRETS_AGE\"" 2>/dev/null | grep "^REDIS_PASSWORD=" | cut -d'=' -f2 || true)
    [[ -z "$redis_pass" ]] && error "Failed to extract REDIS_PASSWORD"

    # Generate docker-compose.yml (Removed obsolete version flag)
    cat > "$DOCKER_DIR/docker-compose.yml" << EOF
services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --requirepass ${redis_pass} --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - titanx-net

  hermes:
    image: nousresearch/hermes-agent:latest
    container_name: hermes
    restart: unless-stopped
    user: "1000:1000"
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${PROJECT_DIR}/workspace:/workspace
      - /home/${USER}/.ssh/id_ed25519:/opt/ssh/id_ed25519:ro
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - WORKSPACE_DIR=/workspace
    ports:
      - "127.0.0.1:8642:8642"
    depends_on:
      - redis
    entrypoint: ["/bin/bash", "/opt/data/entrypoint.sh"]
    networks:
      - titanx-net

volumes:
  redis_data:

networks:
  titanx-net:
    driver: bridge
EOF

    cleanup_stale_docker

    log "Starting Hermes + Redis..."
    cd "$DOCKER_DIR"
    docker compose up -d --force-recreate
    log "✅ Services started successfully"
}

# ====================== MAIN ======================
main() {
    check_root
    wait_for_apt_lock
    check_prerequisites
    check_and_install_age
    install_docker
    setup_ufw
    configure_and_launch
}

main "$@"
