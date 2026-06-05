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
    docker rm -f $(docker ps -a --format '{{.Names}}' | grep -E 'hermes|redis|web|caddy|titanx-web' || true) 2>/dev/null || true
    docker network rm titanx-net 2>/dev/null || true
    log "✓ Stale resources cleaned"
}

write_docker_compose() {
    local redis_pass="$1"
    local api_key="$2"

    log "Generating modular docker-compose.yml..."
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
      - API_SERVER_KEY=${api_key}
      - WORKSPACE_DIR=/workspace
      - HOST=0.0.0.0          
      - PORT=8642
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
      - API_SERVER_KEY=${api_key}
      - WORKSPACE_DIR=/workspace
      - HOST=0.0.0.0          
      - PORT=8642
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
    chmod 644 "$DOCKER_DIR/docker-compose.yml"
    log "✓ File docker-compose.yml generated successfully"
}

configure_and_launch() {
    log "Preparing Docker configuration and workspaces for MIKIE..."

    # 1. Path Definitions
    local workspace_main="${PROJECT_DIR}/workspace"
    local workspace_avangarde="${workspace_main}/avangarde"
    local env_file="${DOCKER_DIR}/hermes.env"

    # 2. Create ALL directory structures FIRST (Natively as ajax)
    log "Initializing directory structures..."
    mkdir -p "$DOCKER_DIR" "$HERMES_DATA" "$workspace_main" "$workspace_avangarde"

    # 3. Permissions: Secure .hermes data (completely private to host ajax only)
    chmod 700 "$HERMES_DATA"

    # 4. Shared Workspace Access via SGID Group Inheritance (NO chown, NO sudo)
    log "Enforcing SGID permission mapping..."
    chmod 2770 "$workspace_main" "$workspace_avangarde"
    find "$workspace_main" -type d -exec chmod 2770 {} + 2>/dev/null || true

    # 5. Repair any existing files inside workspace to be group-writable
    log "Repairing file permission bits..."
    find "$workspace_main" -type f ! -perm /g+w -exec chmod g+w {} + 2>/dev/null || true

    # 6. ATOMIC HOST-SIDE DECRYPTION & VALIDATION (Sandbox via Temp File)
    log "Decrypting secrets natively as $USER..."
    local temp_env
    temp_env=$(mktemp) || error "Failed to create temp file"
    trap "rm -f '$temp_env'" RETURN
    
    if ! age -d -i ~/.ssh/id_ed25519 "$SECRETS_AGE" > "$temp_env" 2>/dev/null; then
        error "Failed to decrypt secrets.age"
    fi
    
    # Extract and validate critical variables safely before touching production
    local redis_pass openrouter_model
    redis_pass=$(grep "^REDIS_PASSWORD=" "$temp_env" | cut -d'=' -f2- | tr -d ' ')
    openrouter_model=$(grep "^OPENROUTER_MODEL=" "$temp_env" | cut -d'=' -f2- || echo "openrouter/free")
    
    [[ -z "$redis_pass" ]] && error "REDIS_PASSWORD not found in secrets"
    
    # Safe atomic shift to production context
    mv "$temp_env" "$env_file"
    chmod 600 "$env_file"
    log "✓ Secrets decrypted and verified"

    # 7. Clean, Deterministic API_KEY Assignment
    local API_KEY="${API_SERVER_KEY:-}"
    if [[ -z "$API_KEY" ]]; then
        API_KEY=$(openssl rand -hex 32)
        export API_SERVER_KEY="$API_KEY"
        log "✓ Generated new API_SERVER_KEY"
    else
        log "✓ Reusing in-memory API_SERVER_KEY"
    fi

    # Append key to file ONLY if it is completely absent to stop bloat loops
    if ! grep -q "^API_KEY=" "$env_file"; then
        echo "API_KEY=$API_KEY" >> "$env_file"
        log "✓ Appended API_SERVER_KEY to hermes.env"
    fi

    # 8. Idempotent Config Generation
    log "Validating configurations..."
    if [[ ! -f "${HERMES_DATA}/config.yaml" ]]; then
        cat > "${HERMES_DATA}/config.yaml" << EOF
model: ${openrouter_model}
provider: openrouter
EOF
        chmod 644 "${HERMES_DATA}/config.yaml"
        log "✓ Generated config.yaml"
    fi

    # 9. Idempotent Custom Entrypoint Validation
    if [[ ! -f "${HERMES_DATA}/entrypoint.sh" ]]; then
        log "Creating entrypoint.sh..."
        cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF2'
#!/bin/bash
set -euo pipefail
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    source "/opt/hermes/.venv/bin/activate"
fi
echo "[ENTRYPOINT] Launching Hermes Gateway on 0.0.0.0:8642..."
exec hermes gateway run --host 0.0.0.0 --port 8642
EOF2
        chmod +x "${HERMES_DATA}/entrypoint.sh"
        log "✓ Generated entrypoint.sh"
    fi

    # 10. Invoke Correctly-Scoped Functions
    write_docker_compose "$redis_pass" "$API_KEY"
    cleanup_stale_docker

    # 11. Modular Backend Launch Context
    log "Booting decoupled infrastructure engine stack..."
    cd "$DOCKER_DIR"
    
    docker compose up -d --force-recreate redis hermes hermes-avangarde
    log "✅ Backend core engine infrastructure live."
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
