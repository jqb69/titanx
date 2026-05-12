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
    log "Installing Docker..."
    apt update && apt upgrade -y
    apt install -y curl ufw fail2ban

    curl -fsSL https://get.docker.com | sh
    apt install -y docker-compose-plugin
    usermod -aG docker "$USER"
    log "✓ Docker installed"
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

create_docker_files() {
    log "Creating Docker configuration..."

    mkdir -p "$DOCKER_DIR"
    chown -R "$USER":"$USER" "$PROJECT_DIR"

    # Extract Redis password
    REDIS_PASS=$(su - "$USER" -c "age -d -i ~/.ssh/id_ed25519 $SECRETS_AGE" | grep REDIS_PASSWORD | cut -d'=' -f2)

    cat > "$DOCKER_DIR/docker-compose.yml" << EOF
version: "3.9"
services:
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASS} --appendonly yes
    volumes:
      - redis_data:/data

  hermes:
    image: nousresearch/hermes-agent:latest
    restart: unless-stopped
    volumes:
      - ${HERMES_DATA}:/opt/data
      - ${PROJECT_DIR}/workspace:/workspace
      - /home/${USER}/.ssh:/root/.ssh:ro
    environment:
      - REDIS_URL=redis://:${REDIS_PASS}@redis:6379/0
      - MEMORY_BACKEND=redis
      - TERMINAL_BACKEND=docker
      - WORKSPACE_DIR=/workspace
    ports:
      - "127.0.0.1:8642:8642"
    depends_on:
      - redis
    entrypoint: ["/bin/bash", "/opt/data/entrypoint.sh"]

volumes:
  redis_data:
EOF

    # In-memory decryption entrypoint
    cat > "${HERMES_DATA}/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e
if [[ -f /opt/data/secrets.age ]]; then
    echo "Loading secrets directly into RAM (no disk leak)..."
    eval "$(age -d -i /root/.ssh/id_ed25519 /opt/data/secrets.age | sed 's/^/export /')"
fi
exec /usr/local/bin/hermes gateway run
EOF

    chmod +x "${HERMES_DATA}/entrypoint.sh"
    chown "$USER":"$USER" "${HERMES_DATA}/entrypoint.sh"
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
    create_docker_files
    start_services
    show_final
}

main "$@"
