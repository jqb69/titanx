#!/bin/bash
# scripts/install-web-ui.sh
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/${USER}/titanx"
WEB_DIR="${PROJECT_DIR}/web"
DOCKER_DIR="${PROJECT_DIR}/docker"

log() { echo "[$(date '+%H:%M:%S')] [WEB-UI] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

main() {
    log "=== Installing Web UI ==="

    mkdir -p "$WEB_DIR"

    # Copy app.py from repo (no generation)
    if [[ -f "${PROJECT_DIR}/web/app.py" ]]; then
        cp "${PROJECT_DIR}/web/app.py" "$WEB_DIR/app.py"
        log "✓ Copied app.py"
    else
        error "web/app.py not found in repository!"
    fi

    # requirements
    cat > "$WEB_DIR/requirements.txt" << EOF
streamlit
requests
EOF

    # Dockerfile
    cat > "$WEB_DIR/Dockerfile" << EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0", "--theme.base=dark"]
EOF

    log "Building Web UI image..."
    cd "$WEB_DIR"
    docker build -t titanx-web:latest .

    log "Adding Web UI to docker-compose..."
    cd "$DOCKER_DIR"
    # (Add to compose if not already present - simple append)

    docker compose up -d --build web

    log "✅ Web UI installed and started on port 8501"
}

main "$@"
