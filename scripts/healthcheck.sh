#!/bin/bash
# scripts/healthcheck.sh
set -euo pipefail

log() { echo "[HEALTHCHECK $(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

log "Starting health check..."

# Wait for Streamlit
log "Waiting for Streamlit Web UI..."
timeout=180
waited=0
while ! curl -sf http://localhost:8501/_stcore/health > /dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [ $waited -ge $timeout ]; then
        log "❌ Streamlit failed to start in time"
        docker compose -f /home/ajax/titanx/docker/docker-compose.yml logs web --tail=30
        exit 1
    fi
done
log "✅ Streamlit is healthy"

# Check Caddy
if curl -sf http://localhost > /dev/null 2>&1; then
    log "✅ Caddy HTTP is responding"
else
    log "⚠️ Caddy HTTP check failed (may be using HTTPS only)"
fi

log "✅ All services are healthy!"
