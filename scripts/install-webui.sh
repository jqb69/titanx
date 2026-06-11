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

    cat > "$WEB_DIR/Dockerfile" <<'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
ENV STREAMLIT_BROWSER_GATHER_USAGE_STATS=false
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request, ssl; ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE; (lambda: urllib.request.urlopen('https://caddy/_stcore/health', timeout=5))() or exit(0)" 2>/dev/null || exit 1
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
DOCKERFILE

}

add_caddy_override() {
    log "Creating docker-compose.override.yml (API_KEY sync + clean merge)..."

    # Read the actual key name used in hermes.env
    local api_key=""
    if [[ -f "$DOCKER_DIR/hermes.env" ]]; then
        api_key=$(grep "^API_KEY=" "$DOCKER_DIR/hermes.env" | cut -d'=' -f2- || true)
    fi

    if [[ -z "$api_key" ]]; then
        api_key=$(openssl rand -hex 32)
        echo "API_KEY=$api_key" >> "$DOCKER_DIR/hermes.env"
        log "✓ Generated new API_KEY and appended to hermes.env"
    else
        log "✓ Loaded existing API_KEY from hermes.env"
    fi

    cat > "$DOCKER_DIR/docker-compose.override.yml" << EOF
services:
  web:
    build: ${PROJECT_DIR}/web
    container_name: titanx-web
    restart: unless-stopped
    networks:
      - titanx-net
    depends_on:
      - hermes
    environment:
      - HERMES_URL=http://titanx-hermes:8642
      - HERMES_API_KEY=${api_key}
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health', timeout=5)\" 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 90s

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
      - caddy_config:/config
    networks:
      - titanx-net
    depends_on:
      web:
        condition: service_healthy

volumes:
  caddy_data:
  caddy_config:
EOF

    cat > "$DOCKER_DIR/Caddyfile" << 'EOF'
{
    auto_https off
    admin off
}

:80 {
    reverse_proxy web:8501
}

:443 {
    tls internal {
        on_demand
    }
    reverse_proxy web:8501
}
EOF

    log "✅ Override created with synced HERMES_API_KEY and on-demand HTTPS"
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
