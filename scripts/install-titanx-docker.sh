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
check_root() { [[ $EUID -eq 0 ]] || error "Must run as root"; }

wait_for_apt_lock() {
    log "[PRE-FLIGHT] Waiting for apt locks..."
    local timeout=120 waited=0
    while [[ $waited -lt $timeout ]]; do
        if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
           ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1 && \
           ! pgrep -x apt-get >/dev/null 2>&1 && \
           ! pgrep -x dpkg >/dev/null 2>&1; then
            log "[PRE-FLIGHT] ✓ Apt clear"
            return 0
        fi
        log "[PRE-FLIGHT] ⚠️ Lock held, waiting 8s..."
        sleep 8
        waited=$((waited + 8))
    done
    error "Timeout waiting for apt locks"
}

check_prerequisites() {
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
    log "[SECURITY] Configuring UFW Firewall..."
    ufw allow 22/tcp comment 'Allow SSH'
    ufw allow 8642/tcp comment 'Hermes Main'
    ufw allow 8643/tcp comment 'Hermes Avangarde'
    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
    log "✓ UFW configured"
}

configure_and_launch() {
    log "Preparing Docker configuration with host-side decryption..."

    mkdir -p "$DOCKER_DIR" "$HERMES_DATA" "${PROJECT_DIR}/workspace"
    chown -R "$USER":"$USER" "$PROJECT_DIR"
    chown -R 1000:1000 "${PROJECT_DIR}/workspace" "$HERMES_DATA"
    chmod -R 750 "${PROJECT_DIR}/workspace" "$HERMES_DATA"
    chmod 700 "$HERMES_DATA"

    # Host-side decryption
    local env_file="${DOCKER_DIR}/hermes.env"
    log "Decrypting secrets on host..."
    if ! su - "$USER" -c "age -d -i ~/.ssh/id_ed25519 \"$SECRETS_AGE\"" > "$env_file"; then
        error "Failed to decrypt secrets.age"
    fi
    chmod 600 "$env_file"
    log "✓ Secrets decrypted and secured"

    # Extract required values safely
    local redis_pass
    local openrouter_model
    redis_pass=$(grep "^REDIS_PASSWORD=" "$env_file" | cut -d'=' -f2 || true)
    openrouter_model=$(grep "^OPENROUTER_MODEL=" "$env_file" | cut -d'=' -f2 || echo "openrouter/free")
    
    [[ -z "$redis_pass" ]] && error "Failed to extract REDIS_PASSWORD"

    # Generate config.yaml automatically so the agent doesn't prompt
    log "Generating hermes config.yaml..."
    cat > "${HERMES_DATA}/config.yaml" << EOF
model: ${openrouter_model}
provider: openrouter
EOF
    chown 1000:1000 "${HERMES_DATA}/config.yaml"
    chmod 644 "${HERMES_DATA}/config.yaml"

    # Minimal entrypoint
    if [[ ! -f "${HERMES_DATA}/entrypoint.sh" ]]; then
        cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF2'
#!/bin/bash
set -euo pipefail
echo "[ENTRYPOINT] Launching Hermes..."
# The agent will now pick up the config.yaml automatically
exec hermes gateway run
EOF2
    fi
    chmod +x "${HERMES_DATA}/entrypoint.sh"
    chown 1000:1000 "${HERMES_DATA}/entrypoint.sh"

    # ... (Keep your existing docker-compose.yml generation block) ...
    # Ensure your compose file volumes mount $HERMES_DATA to /opt/data
    

    # docker-compose
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
    env_file:
      - hermes.env
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${PROJECT_DIR}/workspace:/workspace
      - /home/${USER}/.ssh/id_ed25519:/opt/ssh/id_ed25519:ro
    environment:
      - WORKSPACE_DIR=/workspace
    ports:
      - "127.0.0.1:8642:8642"
    depends_on:
      - redis
    entrypoint: ["/bin/bash", "/opt/data/entrypoint.sh"]
    networks:
      - titanx-net

  hermes-avangarde:
    image: nousresearch/hermes-agent:latest
    container_name: hermes-avangarde
    restart: unless-stopped
    user: "1000:1000"
    env_file:
      - hermes.env
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${PROJECT_DIR}/workspace/avangarde:/workspace
      - /home/${USER}/.ssh/id_ed25519:/opt/ssh/id_ed25519:ro
    environment:
      - WORKSPACE_DIR=/workspace
    ports:
      - "127.0.0.1:8643:8642"
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

    log "Starting services..."
    cd "$DOCKER_DIR"
    docker compose up -d --force-recreate
    log "✅ Services started successfully with auto-configured config.yaml"
    
}

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
