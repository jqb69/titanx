#!/bin/bash
# install-titanx-docker.sh
# ================================================
# TitanX Docker Installer - 
# Run as ROOT after create-ajax-user.sh and create-secrets.sh
# ================================================

set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"
DOCKER_DIR="${PROJECT_DIR}/docker"
SECRETS_AGE="${HERMES_DATA}/secrets.age"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

check_root() {
    [[ $EUID -eq 0 ]] || error "This script must be run as root"
}

check_prerequisites() {
    log "Checking prerequisites..."
    [[ -f "$SECRETS_AGE" ]] || error "secrets.age not found! Run create-secrets.sh first."
    log "✓ secrets.age found"
}

check_and_install_age() {
    log "Checking for 'age' tool..."
    if command -v age >/dev/null 2>&1; then
        log "✓ age is already installed"
        return 0
    fi

    log "age not found. Installing..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y age && return $?
    fi

    # Fallback: Manual install from GitHub
    log "Installing age from GitHub..."
    TMP=$(mktemp -d) || return 1
    trap 'rm -rf "$TMP"' RETURN

    VERSION="v1.1.1"
    URL="https://github.com/FiloSottile/age/releases/download/${VERSION}/age-${VERSION}-linux-amd64.tar.gz"

    curl -fsSL "$URL" -o "$TMP/age.tar.gz" || wget -qO "$TMP/age.tar.gz" "$URL" || error "Failed to download age"

    tar -xzf "$TMP/age.tar.gz" -C "$TMP" || error "Failed to extract age"

    BIN=$(find "$TMP" -type f -name age -perm /111 | head -n1)
    sudo install -m 0755 "$BIN" /usr/local/bin/age || error "Failed to install age"

    log "✓ age installed successfully"
}

install_docker() {
    log "Installing Docker and dependencies..."
    
    # Update and upgrade core packages
    apt-get update -qq && apt-get upgrade -y -qq
    
    # Install prerequisites
    apt-get install -y -qq curl ufw fail2ban

    # Official Docker convenience script
    curl -fsSL https://get.docker.com | sh

    # Install Compose plugin
    apt-get install -y -qq docker-compose-plugin

    # Add user to docker group
    usermod -aG docker "$USER"
    
    log "✓ Docker and Compose plugin installed successfully"
}

setup_ufw() {
    log "Configuring UFW firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 8642/tcp
    ufw --force enable
    log "✓ UFW configured"
}

cleanup_existing_hermes() {
    log "🔍 Querying system for redundant or conflicting Hermes containers..."
    
    # Get all container names matching 'hermes'
    local conflicting_containers
    conflicting_containers=$(docker ps -a --format '{{.Names}}' | grep 'hermes' || true)

    if [[ -n "$conflicting_containers" ]]; then
        log "⚠️ Found redundant containers: ${conflicting_containers}"
        log "Scorching old containers to clear paths..."
        
        # Force remove any matching container to free up names, networks, and ports
        echo "$conflicting_containers" | while read -r container; do
            if [[ -n "$container" ]]; then
                docker rm -f "$container" >/dev/null 2>&1 || true
                log "✓ Removed old container: $container"
            fi
        done
    else
        log "✓ No redundant Hermes containers found. Workspace clean."
    fi
}

cleanup_existing_hermes() {
    log "🔍 Querying engine for redundant or standalone Hermes containers..."
    local redundant_containers
    redundant_containers=$(docker ps -a --format '{{.Names}}' | grep 'hermes' || true)

    if [[ -n "$redundant_containers" ]]; then
        log "⚠️ Found conflicting instances: ${redundant_containers}. Wiping workspace..."
        echo "$redundant_containers" | while read -r container; do
            if [[ -n "$container" ]]; then
                docker rm -f "$container" >/dev/null 2>&1 || true
                log "✓ Erased container: $container"
            fi
        done
    else
        log "✓ Workspace clean. No standalone containers discovered."
    fi
}

configure_and_launch() {
    # 1. Prepare Environment Directory Framework
    log "Configuring Docker environment spaces for user: $USER_NAME..."
    mkdir -p "$DOCKER_DIR"
    mkdir -p "$HERMES_DATA"

    # 2. Relocate and Secure Runtime Container Entrypoint
    if [[ -f "${PROJECT_DIR}/entrypoint.sh" ]]; then
        log "Moving entrypoint.sh → $HERMES_DATA..."
        mv "${PROJECT_DIR}/entrypoint.sh" "${HERMES_DATA}/entrypoint.sh"
        chmod +x "${HERMES_DATA}/entrypoint.sh"
        chown "$USER_NAME":"$USER_NAME" "${HERMES_DATA}/entrypoint.sh"
    else
        error "Entrypoint script is missing from ${PROJECT_DIR}!"
    fi

    # 3. Decrypt and Extract Orchestration Passwords Resiliently
    log "Extracting Redis credentials securely..."
    local raw_secrets
    raw_secrets=$(su - "$USER_NAME" -c "age -d -i ~/.ssh/id_ed25519 \"$SECRETS_AGE\"" 2>/dev/null || true)
    
    if [[ -z "$raw_secrets" ]]; then
        error "Decryption failed or secrets payload empty at $SECRETS_AGE"
    fi

    local redis_pass
    redis_pass=$(echo "$raw_secrets" | grep "^REDIS_PASSWORD=" | cut -d'=' -f2 || true)
    
    if [[ -z "$redis_pass" ]]; then 
        error "REDIS_PASSWORD tag not defined inside target secrets cluster."
    fi

    # 4. Generate Clean docker-compose.yml (No obsolete version markers)
    log "Generating docker-compose.yml configuration asset..."
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
      - ${HERMES_DATA}:/home/ajax/titanx/.hermes
      - ${PROJECT_DIR}/workspace:/home/ajax/workspace
      - /home/${USER_NAME}/.ssh/id_ed25519:/home/ajax/.ssh/id_ed25519:ro
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - WORKSPACE_DIR=/home/ajax/workspace
    ports:
      - "127.0.0.1:8642:8642"
    depends_on:
      - redis
    entrypoint: ["/bin/bash", "/home/ajax/titanx/.hermes/entrypoint.sh"]
    networks:
      - titanx-net

volumes:
  redis_data:

networks:
  titanx-net:
    driver: bridge
EOF

    # Fix ownership of generated composition folders
    chown -R "$USER_NAME":"$USER_NAME" "$PROJECT_DIR"
    log "✓ Docker configuration asset generated successfully."

    # 5. Clear Out Competing Name allocations
    cleanup_existing_hermes

    # 6. Spin Up Runtime Application Stack
    log "Starting fresh Hermes + Redis runtime container stack..."
    cd "$DOCKER_DIR"
    docker compose up -d

    log "✓ Subsystem containers online."
    log "========================================"
    log "✅ TITANX DOCKER INSTALLATION COMPLETE!"
    log "========================================"
}

start_services() {
    log "Starting Hermes + Redis..."
    cd "$DOCKER_DIR"
    docker compose up -d
    log "✓ Services started"
}

show_final() {
    echo ""
    echo "========================================"
    echo "✅ TITANX DOCKER INSTALLATION COMPLETE!"
    echo "========================================"
    echo "Download SSH key:"
    echo "scp ajax@YOUR_DROPLET_IP:/home/ajax/.ssh/id_ed25519 ~/.ssh/titanx_ajax"
    echo ""
    echo "Check status: cd ${DOCKER_DIR} && docker compose logs -f"
    echo "========================================"
}

# ====================== MAIN ======================
main() {
    check_root
    check_prerequisites
    check_and_install_age
    install_docker
    setup_ufw
    configure_and_launch
    start_services
    show_final
}

main "$@"
