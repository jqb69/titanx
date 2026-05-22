#!/bin/bash
# scripts/install-webui.sh
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
WEB_DIR="${PROJECT_DIR}/web"
DOCKER_DIR="${PROJECT_DIR}/docker"

log() { echo "[$(date '+%H:%M:%S')] [WEB-UI] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ====================== FUNCTIONS ======================

check_web_source() {
    log "Checking web/ directory..."
    if [[ ! -f "${PROJECT_DIR}/web/app.py" ]]; then
        error "web/app.py not found in repository!"
    fi
    log "✓ web/app.py found"
}

copy_web_files() {
    log "Copying Web UI files..."
    mkdir -p "$WEB_DIR"
    cp -a "${PROJECT_DIR}/web/." "$WEB_DIR/" 2>/dev/null || true
    log "✓ Web files copied"
}

create_requirements_and_dockerfile() {
    log "Creating requirements and Dockerfile..."
    cat > "$WEB_DIR/requirements.txt" << EOF
streamlit
requests
EOF

    cat > "$WEB_DIR/Dockerfile" << EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
EOF
}

add_caddy_and_compose() {
    log "Adding Web UI + Caddy to docker-compose.yml..."

    local compose_file="$DOCKER_DIR/docker-compose.yml"

    # Check if web service already exists
    if grep -qE "^  web:" "$compose_file" 2>/dev/null; then
        log "✓ Web service already present, skipping"
        return 0
    fi

    # Append services safely
    cat >> "$compose_file" << EOF

  web:
    build: ${PROJECT_DIR}/web
    container_name: titanx-web
    restart: unless-stopped
    networks:
      - titanx-net
    depends_on:
      - hermes

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${DOCKER_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
    networks:
      - titanx-net
    depends_on:
      web:
        condition: service_healthy
EOF

    # Add volumes section only if it doesn't exist
    if ! grep -q "^volumes:" "$compose_file" 2>/dev/null; then
        echo "" >> "$compose_file"
        cat >> "$compose_file" << 'EOF'
volumes:
  caddy_data:
EOF
    fi

    # Create Caddyfile
    cat > "$DOCKER_DIR/Caddyfile" << 'EOF'
:80, :443 {
    reverse_proxy web:8501
    tls internal
}
EOF

    log "✓ Caddy + Web UI added successfully"
}



build_and_start() {
    log "Building and starting Web UI + Caddy..."
    cd "$WEB_DIR"
    docker build -t titanx-web:latest .

    cd "$DOCKER_DIR"
    docker compose up -d --build web caddy
    log "✅ Web UI + Caddy started!"
    log "Access: http://YOUR_IP or https://YOUR_IP (self-signed)"
}

# ====================== MAIN ======================
main() {
    log "=== Installing Web UI with Caddy ==="

    check_web_source
    copy_web_files
    create_requirements_and_dockerfile
    add_caddy_and_compose
    build_and_start

    log "✅ Web UI installation completed"
}

main "$@"
