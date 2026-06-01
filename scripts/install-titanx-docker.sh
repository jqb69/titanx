#!/bin/bash
# scripts/install-titanx-docker.sh
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
DOCKER_DIR="${PROJECT_DIR}/docker"
SECRETS_AGE="${HERMES_DATA}/secrets.age"

log() { echo "[$(date '+%H:%M:%S')] [DOCKER-INSTALL] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== ROOT FUNCTIONS ======================

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
    log "Configuring UFW firewall..."
    ufw allow 22/tcp comment 'SSH Access' || true
    ufw allow 8642/tcp comment 'Hermes Gateway' || true
    ufw allow 8643/tcp comment 'Hermes Avangarde' || true
    ufw default deny incoming
    ufw default allow outgoing

    if ufw status | grep -q "Status: active"; then
        ufw reload
        log "✓ UFW reloaded with rules"
    else
        ufw --force enable
        log "✓ UFW enabled with secure defaults"
    fi
}

# ====================== AJAX FUNCTIONS ======================

cleanup_stale_docker() {
    log "Cleaning stale containers..."
    docker rm -f $(docker ps -a --format '{{.Names}}' | grep -E 'hermes|redis' || true) 2>/dev/null || true
    docker network rm titanx-net 2>/dev/null || true
    log "✓ Stale resources cleaned"
}

configure_and_launch() {
    log "Preparing Docker configuration..."
    
    # Running as ajax, so files are naturally owned by ajax. No chown needed.
    mkdir -p "$DOCKER_DIR" "$HERMES_DATA" "${PROJECT_DIR}/workspace" "${PROJECT_DIR}/workspace/avangarde"
    chmod -R 770 "${PROJECT_DIR}/workspace"
    chmod 700 "$HERMES_DATA"

    # === HOST-SIDE DECRYPTION (Native Ajax Context) ===
    local env_file="${DOCKER_DIR}/hermes.env"
    log "Decrypting secrets natively as $USER..."

    if ! age -d -i ~/.ssh/id_ed25519 "$SECRETS_AGE" > "$env_file" 2>/dev/null; then
        error "Failed to decrypt secrets.age"
    fi
    chmod 600 "$env_file"
    log "✓ Secrets decrypted and locked down"

    # Extract required values safely
    local redis_pass
    local openrouter_model
    redis_pass=$(grep "^REDIS_PASSWORD=" "$env_file" | cut -d'=' -f2 || true)
    openrouter_model=$(grep "^OPENROUTER_MODEL=" "$env_file" | cut -d'=' -f2 || echo "openrouter/free")
    local API_KEY
    [[ -z "$redis_pass" ]] && error "Failed to extract REDIS_PASSWORD"
    # Generate API_SERVER_KEY if missing
    if ! grep -q "API_SERVER_KEY=" "$env_file" 2>/dev/null; then
        API_KEY=$(openssl rand -hex 32)
        echo "API_KEY=$API_KEY" >> "$env_file"
        log "✓ Generated API_SERVER_KEY for Hermes"
    fi
    # === AUTO-GENERATE CONFIG.YAML ===
    log "Generating hermes config.yaml..."
    cat > "${HERMES_DATA}/config.yaml" << EOF
model: ${openrouter_model}
provider: openrouter
EOF
    chmod 644 "${HERMES_DATA}/config.yaml"

    # === AUTO-GENERATE ENTRYPOINT.SH ===
    if [[ ! -f "${HERMES_DATA}/entrypoint.sh" ]]; then
        log "Creating minimal entrypoint.sh..."
        cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF2'
#!/bin/bash

set -euo pipefail

# Activate the isolated Python virtual environment embedded inside the base image
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    echo "[ENTRYPOINT] Activating image virtual environment..."
    source "/opt/hermes/.venv/bin/activate"
fi
echo "[ENTRYPOINT] Launching Hermes Gateway on 0.0.0.0:8642..."

# CRITICAL: Force Hermes to listen on all interfaces
exec hermes gateway run --host 0.0.0.0 --port 8642
EOF2
    fi
    chmod +x "${HERMES_DATA}/entrypoint.sh"

    # === GENERATE docker-compose.yml ===
    log "Generating docker-compose.yml..."
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
    container_name: titanx-hermes
    restart: unless-stopped
    user: "1000:1000"
    env_file:
      - hermes.env
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${PROJECT_DIR}/workspace:/workspace
      - /home/${USER}/.ssh/id_ed25519:/opt/ssh/id_ed25519:ro
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - API_SERVER_KEY=${API_KEY}
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
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - API_SERVER_KEY=${API_KEY}
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
    log "Starting Hermes + Redis..."
    cd "$DOCKER_DIR"
    docker compose -f docker-compose.yml up -d --build --force-recreate redis hermes hermes-avangarde
    log "✅ Services started successfully"
}

# ====================== MAIN ROUTER ======================

MODE=${1:-}

if [[ "$MODE" == "--root" ]]; then
    log "=== Executing Root Infrastructure Phase ==="
    check_root
    wait_for_apt_lock
    check_prerequisites
    check_and_install_age
    install_docker
    setup_ufw
    log "✅ Root Phase Complete."

elif [[ "$MODE" == "--ajax" ]]; then
    log "=== Executing Ajax Application Phase ==="
    if [[ $EUID -eq 0 ]]; then
        error "The --ajax phase must NOT be run as root."
    fi
    configure_and_launch
    log "✅ Ajax Phase Complete."
    
else
    error "Usage: $0 [--root | --ajax]"
fi
