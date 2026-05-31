#!/bin/bash
# scripts/install-webui.sh
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
WEB_DIR="${PROJECT_DIR}/web"
DOCKER_DIR="${PROJECT_DIR}/docker"

log() { echo "[$(date '+%H:%M:%S')] [WEB-UI] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

check_web_source() {
    log "Checking web/ directory..."
    if [[ ! -f "${PROJECT_DIR}/web/app.py" ]]; then
        error "web/app.py not found!"
    fi
    log "✓ web/app.py found"
}

create_requirements_and_dockerfile() {
    log "Creating requirements and Dockerfile..."
    cat > "$WEB_DIR/requirements.txt" << 'EOF'
streamlit
requests
EOF

    cat > "$WEB_DIR/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
ENV STREAMLIT_BROWSER_GATHER_USAGE_STATS=false
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health')" || exit 1
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
EOF
}

add_caddy_override() {
    log "Creating docker-compose.override.yml..."

    cat > "$DOCKER_DIR/docker-compose.override.yml" << EOF
services:
  web:
    build: ${PROJECT_DIR}/web
    container_name: titanx-web
    restart: unless-stopped
    networks:
      - titanx-net
    depends_on:
      - titanx-hermes
    environment:
      - HERMES_URL=http://titanx-hermes:8642

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
      - web

volumes:
  caddy_data:
EOF

    cat > "$DOCKER_DIR/Caddyfile" << 'EOF'
:80, :443 {
    reverse_proxy web:8501
    tls internal
}
EOF

    log "✅ override file created"
}

build_and_start() {
    log "Building and starting Web UI + Caddy..."
    cd "$DOCKER_DIR"
    docker compose -f docker-compose.yml -f docker-compose.override.yml up -d --build web caddy
    log "✅ Web UI + Caddy started"
}

main() {
    log "=== Installing Web UI with Caddy ==="

    check_web_source
    create_requirements_and_dockerfile
    add_caddy_override
    build_and_start

    log "✅ Web UI installation completed"
}

main "$@"
