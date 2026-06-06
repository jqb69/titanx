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
# ====================== HELPER FUNCTIONS (place BEFORE configure_and_launch_hermes) ======================

upsert_env_entry() {
    local key="$1"
    local val="$2"
    local esc_val
    esc_val=$(printf '%s' "$val" | sed 's/[&]/\\&/g')
   
    if grep -q "^${key}=" "$env_file"; then
        sed -i "s|^${key}=.*|${key}=${esc_val}|" "$env_file"
    else
        printf '%s=%s\n' "$key" "$val" >> "$env_file"
    fi
}

write_docker_compose() {
    local redis_pass="${1:?redis_pass missing}"
    local api_key="${2:?api_key missing}"
    local openrouter_model="${3:-openrouter/free}"

    local RUNNER_UID=1000
    local RUNNER_GID=1000

    log "🛠️ Writing docker-compose.yml with proper variable substitution..."

    # Make sure key variables are available for expansion
    #local HERMES_DATA="${HERMES_DATA:-/home/ajax/titanx/.hermes}"
    local WORKSPACE_MAIN="${WORKSPACE_MAIN:-/home/ajax/titanx/workspace}"

    cat > "${DOCKER_DIR}/docker-compose.yml" << EOF
version: '3.9'

networks:
  titanx-net:
    name: titanx-net
    driver: bridge

services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass "${redis_pass}" --appendonly yes
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - titanx-net

  hermes:
    image: nousresearch/hermes-agent:latest
    container_name: titanx-hermes
    restart: unless-stopped
    user: "${RUNNER_UID}:${RUNNER_GID}"
    working_dir: /workspace
    env_file:
      - hermes.env
    ports:
      - "127.0.0.1:8642:8642"
    depends_on:
      - redis
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${WORKSPACE_MAIN}:/workspace
      - /home/${USER}/.ssh:/opt/ssh:ro
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - API_SERVER_KEY=${api_key}
      - OPENROUTER_MODEL=${openrouter_model}
      - WORKSPACE_DIR=/workspace
      - HOST=0.0.0.0
      - PORT=8642
    entrypoint: ["/bin/bash", "/opt/data/entrypoint.sh"]
    networks:
      - titanx-net

  hermes-avangarde:
    image: nousresearch/hermes-agent:latest
    container_name: hermes-avangarde
    restart: unless-stopped
    user: "${RUNNER_UID}:${RUNNER_GID}"
    working_dir: /workspace
    env_file:
      - hermes.env
    depends_on:
      - redis
      - hermes
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${WORKSPACE_MAIN}/avangarde:/workspace
      - /home/${USER}/.ssh:/opt/ssh:ro
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - API_SERVER_KEY=${api_key}
      - OPENROUTER_MODEL=${openrouter_model}
      - WORKSPACE_DIR=/workspace
      - HOST=0.0.0.0
      - PORT=8642
    entrypoint: ["/bin/bash", "/opt/data/entrypoint.sh"]
    networks:
      - titanx-net

volumes:
  redis_data:
EOF

    chmod 644 "${DOCKER_DIR}/docker-compose.yml"
    chown "${RUNNER_UID}:${RUNNER_GID}" "${DOCKER_DIR}/docker-compose.yml"

    log "✓ docker-compose.yml written successfully"
}


# ====================== MAIN CONFIGURATION ======================
configure_and_launch() {
    # ----------------------------------------------------------------------
    # 0️⃣ Global Safety
    # ----------------------------------------------------------------------
    #set -euo pipefail
    log "🔐 Starting hardened TitanX Docker deployment…"

    # ----------------------------------------------------------------------
    # 1️⃣ Runtime Context
    # ----------------------------------------------------------------------
    local RUNNER_UID="${RUNNER_UID:-$(id -u $USER)}"
    local RUNNER_GID="${RUNNER_GID:-$(id -g $USER)}"
    local workspace_main="${PROJECT_DIR}/workspace"
    local workspace_avangarde="${workspace_main}/avangarde"
    local env_file="${DOCKER_DIR}/hermes.env"
    local git_log="${PROJECT_DIR}/git_operation.log"
    local age_key="${AGE_ID:-/home/$USER/.ssh/id_ed25519}"

    # ----------------------------------------------------------------------
    # 2️⃣ Dependency Assertions
    # ----------------------------------------------------------------------
    command -v age >/dev/null || error "Missing required binary: age"
    command -v openssl >/dev/null || error "Missing required binary: openssl"
    command -v docker >/dev/null || error "Missing required binary: docker"
    docker compose version >/dev/null || error "Missing required plugin: docker compose"
    [[ -f "$age_key" ]] || error "Age identity key not found at $age_key"
    [[ -f "$SECRETS_AGE" ]] || error "Encrypted secrets envelope not found at $SECRETS_AGE"

    # ----------------------------------------------------------------------
    # 3️⃣ Directory & Permissions
    # ----------------------------------------------------------------------
    log "📁 Creating required directories…"
    mkdir -p "$DOCKER_DIR" "$HERMES_DATA" "$workspace_main" "$workspace_avangarde"

    log "🔒 Applying strict ownership and mode"
    chown -R "${RUNNER_UID}:${RUNNER_GID}" "$HERMES_DATA" "$workspace_main" "$workspace_avangarde"
    chmod 700 "$HERMES_DATA"
    chmod 2770 "$workspace_main" "$workspace_avangarde"

    if ! find "$workspace_main" -type d -exec chmod 2770 {} + 2>/dev/null; then
        log "⚠️ Recursive chmod on $workspace_main failed – proceeding"
    fi

    # ----------------------------------------------------------------------
    # 4️⃣ Git Sync (Atomic)
    # ----------------------------------------------------------------------
    if [[ -d "${PROJECT_DIR}/.git" ]]; then
        log "🔄 Synchronizing repository state…"
        pushd "$PROJECT_DIR" >/dev/null
        local default_branch
        default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}') || default_branch="main"
        git fetch origin "$default_branch" >>"$git_log" 2>&1 || log "⚠️ git fetch failed – using local state"
        git reset --hard "origin/${default_branch}" >>"$git_log" 2>&1 || log "⚠️ git reset failed – assuming dirty working tree"
        popd >/dev/null
    fi

    # ----------------------------------------------------------------------
    # 5️⃣ Pull Existing API Key
    # ----------------------------------------------------------------------
    local current_api_key=""
    if [[ -f "$env_file" ]]; then
        current_api_key=$(grep '^API_KEY=' "$env_file" | head -n1 | cut -d= -f2- | tr -d '"') || current_api_key=""
    fi

    # ----------------------------------------------------------------------
    # 6️⃣ Decrypt Secrets (Safe In-Memory)
    # ----------------------------------------------------------------------
    local temp_env
    temp_env=$(mktemp -p "$DOCKER_DIR" env.XXXXXX) || error "Failed to create temporary file"
    trap 'rm -f "$temp_env"' EXIT

    log "🔓 Decrypting secrets…"
    if ! age -d -i "$age_key" "$SECRETS_AGE" >"$temp_env" 2>/dev/null; then
        error "Decryption of $SECRETS_AGE failed"
    fi

    local redis_pass="" openrouter_model=""
    while IFS='=' read -r key val || [[ -n $key ]]; do
        key=$(printf '%s' "$key" | tr -d '[:space:]')
        [[ -z "$key" || "$key" == \#* ]] && continue
        val=$(printf '%s' "$val" | sed -e 's/^"//' -e 's/"$//')
        case "$key" in
            REDIS_PASSWORD) redis_pass="$val" ;;
            OPENROUTER_MODEL) openrouter_model="$val" ;;
        esac
    done <"$temp_env"

    [[ -n "$redis_pass" ]] || error "Decrypted REDIS_PASSWORD is empty"

    if [[ -z "$openrouter_model" ]]; then
        openrouter_model="google/gemini-2.5-flash:free"
        log "⚠️ OPENROUTER_MODEL missing – using default openrouter free tier target"
    fi

    rm -f "$temp_env"
    trap - EXIT

    # ----------------------------------------------------------------------
    # 7️⃣ API_KEY — Strict Evaluation
    # ----------------------------------------------------------------------
    local API_KEY="${API_SERVER_KEY:-$current_api_key}"
    if [[ -z "$API_KEY" ]]; then
        log "Neither memory execution contexts nor configuration files contain active tokens. Generating fresh context..."
        API_KEY=$(openssl rand -hex 32)
        export API_SERVER_KEY="$API_KEY"
        log "✓ Generated new dynamic API_KEY asset context"
    else
        log "✓ Reusing active API_KEY context securely via prioritized priority chain"
        if [[ "$API_KEY" == "$current_api_key" ]]; then
            export API_SERVER_KEY="$API_KEY"
        fi
    fi

    # ----------------------------------------------------------------------
    # 8️⃣ hermes.env Upsert
    # ----------------------------------------------------------------------
    [[ -f "$env_file" ]] || touch "$env_file"
    chmod 600 "$env_file"

    log "📝 Updating entries within hermes.env..."
    upsert_env_entry "REDIS_PASSWORD" "$redis_pass"
    upsert_env_entry "OPENROUTER_MODEL" "$openrouter_model"
    upsert_env_entry "API_KEY" "$API_KEY"
    chown "${RUNNER_UID}:${RUNNER_GID}" "$env_file"

    # ----------------------------------------------------------------------
    # 9️⃣ Render Compose + Entrypoint + Launch (3 parameters now)
    # ----------------------------------------------------------------------
    write_docker_compose "$redis_pass" "$openrouter_model" "$API_KEY"

    cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e
if [[ -f /opt/data/secrets.age ]]; then
    echo "Loading secrets into RAM..."
    eval "$(age -d -i /opt/ssh/id_ed25519 /opt/data/secrets.age | sed 's/^/export /')"
fi
exec /usr/local/bin/hermes gateway run --host 0.0.0.0 --port 8642
EOF

    chmod +x "${HERMES_DATA}/entrypoint.sh"
    chown "${RUNNER_UID}:${RUNNER_GID}" "${HERMES_DATA}/entrypoint.sh"

    log "🧹 Removing stale infrastructure containers..."
   
    cd "$DOCKER_DIR" || error "Cannot cd to $DOCKER_DIR"

    # Safe cleanup - only targets containers defined in current compose file
    docker compose -f docker-compose.yml down --remove-orphans --volumes 2>/dev/null || true

    # Optional: Extra safety (remove any old hermes containers by name)
    cleanup_stale_docker

    log "✓ Stale containers cleaned"

    log "🚀 Launching TitanX stack via isolated manifest rules"
    pushd "$DOCKER_DIR" >/dev/null
    local attempts=0 max_attempts=5

    until docker compose -f docker-compose.yml up -d --force-recreate redis hermes hermes-avangarde; do
        ((attempts++))
        if (( attempts >= max_attempts )); then
            error "Fatal: Infrastructure orchestration failed to deploy background services after $attempts loops."
        fi
        log "⏳ Rescheduling execution deployment sequence in 3s ($attempts/$max_attempts)..."
        sleep 3
    done
    popd >/dev/null

    log "✅ Deployment complete – all prioritized services are up"
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
