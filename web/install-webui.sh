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
    log "Checking web/ directory in repository..."
    if [[ ! -f "${PROJECT_DIR}/web/app.py" ]]; then
        error "web/app.py not found in repository! Please add it first."
    fi
    log "✓ web/app.py found"
}

copy_web_files() {
    log "Copying Web UI files..."
    mkdir -p "$WEB_DIR"
    cp -r "${PROJECT_DIR}/web/"* "$WEB_DIR/" 2>/dev/null || true
    log "✓ Web files copied"
}

create_requirements_and_dockerfile() {
    log "Creating requirements.txt and Dockerfile..."
    
    cat > "$WEB_DIR/requirements.txt" << EOF
streamlit
requests
EOF

    cat > "$WEB_DIR/Dockerfile" << EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
EOF
}

add_caddy_and_compose() {
    log "Adding Web UI + Caddy (HTTPS) to docker-compose.yml..."

    # Avoid duplicate entries
    if grep -q "container_name: titanx-web" "$DOCKER_DIR/docker-compose.yml" 2>/dev/null; then
        log "✓ Web + Caddy services already exist"
        return 0
    fi

    cat >> "$DOCKER_DIR/docker-compose.yml" << EOF

  web:
    build: ${PROJECT_DIR}/web
    container_name: titanx-web
    restart: unless-stopped
    networks:
      - titanx-net

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${DOCKER_DIR}/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    networks:
      - titanx-net
    depends_on:
      - web

volumes:
  caddy_data:
EOF

    # Caddyfile with automatic HTTPS
    cat > "$DOCKER_DIR/Caddyfile" << EOF
:80, :443 {
    reverse_proxy web:8501
    tls {
        on_demand
    }
}
EOF

    log "✓ Caddy configured for automatic HTTPS"
}

build_and_start() {
    log "Building Web UI image..."
    cd "$WEB_DIR"
    docker build -t titanx-web:latest .

    log "Starting Web UI + Caddy..."
    cd "$DOCKER_DIR"
    docker compose up -d --build web caddy

    log "✅ Web UI + HTTPS started!"
    log "Access at: https://YOUR_DROPLET_IP"
}

# ====================== MAIN ======================
main() {
    log "=== Installing Web UI with Caddy HTTPS ==="

    check_web_source
    copy_web_files
    create_requirements_and_dockerfile
    add_caddy_and_compose
    build_and_start

    log "✅ Web UI installation completed successfully"
}

main "$@"
