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
redis
EOF

    cat > "$WEB_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
ENV STREAMLIT_BROWSER_GATHER_USAGE_STATS=false
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health', timeout=5)" || exit 1
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
DOCKERFILE

}


add_caddy_override() {
    log "Creating docker-compose.override.yml with web + worker + Caddy..."

    local api_key=""
    local redis_pass=""

    if [[ -f "$DOCKER_DIR/hermes.env" ]]; then
        api_key=$(grep "^API_KEY=" "$DOCKER_DIR/hermes.env" | cut -d'=' -f2- || true)
        redis_pass=$(grep "^REDIS_PASSWORD=" "$DOCKER_DIR/hermes.env" | cut -d'=' -f2- || true)
    fi

    if [[ -z "$api_key" ]]; then
        api_key=$(openssl rand -hex 32)
        echo "API_KEY=$api_key" >> "$DOCKER_DIR/hermes.env"
        log "✓ Generated new API_KEY"
    else
        log "✓ Loaded API_KEY from hermes.env"
    fi

    if [[ -z "$redis_pass" ]]; then
        log "⚠️ REDIS_PASSWORD not found in hermes.env"
    else
        log "✓ Loaded REDIS_PASSWORD"
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
    env_file:
      - hermes.env   
    environment:
      - HERMES_URL=http://titanx-hermes:8642
      - HERMES_API_KEY=${api_key}     # Still pass as HERMES_API_KEY to client.py
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
    healthcheck:
      test: ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8501/_stcore/health', timeout=5)\" 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  worker:
    image: titanx-web:latest
    restart: unless-stopped
    working_dir: /app
    command: ["python", "-u", "worker.py"]
    depends_on:
      - redis
      - hermes
      - hermes-avangarde
    env_file:
      - hermes.env
    environment:
      - REDIS_URL=redis://:${redis_pass}@redis:6379/0
      - HERMES_URL=http://titanx-hermes:8642
      - AVANGARDE_URL=http://hermes-avangarde:8642
      - HERMES_API_KEY=${api_key}
    volumes:
      - ${PROJECT_DIR}/web:/app
    networks:
      - titanx-net

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

    log "✅ Override created using API_KEY from hermes.env"
}

build_and_start() {
    log "Building titanx-web image and starting stack..."

    # Build the web image (contains app.py + worker.py)
    cd "${WEB_DIR}" || error "web directory not found"
    docker build -t titanx-web:latest . || error "Failed to build titanx-web image"

    cd "$DOCKER_DIR"

    # Start services with worker scaling, forcing recreation for fresh state
    docker compose up -d --build --force-recreate --scale worker=3 web worker caddy

    log "✅ TitanX Stack started successfully with 3 worker replicas"
    log "Web UI → http://YOUR_SERVER_IP (via Caddy)"
    log "Workers → 3 replicas active"
}

main() {
    log "=== Installing Web UI with Worker + Caddy ==="

    check_web_source
    create_requirements_and_dockerfile
    add_caddy_override
    build_and_start

    log "✅ Web UI installation completed"
}

main "$@"
