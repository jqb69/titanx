#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# Activate the isolated Python virtual environment embedded inside the base image
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    echo "[ENTRYPOINT] Activating image virtual environment..."
    source "/opt/hermes/.venv/bin/activate"
fi
echo "[ENTRYPOINT] Launching Hermes Gateway on 0.0.0.0:8642..."

# CRITICAL: Force Hermes to listen on all interfaces
exec hermes gateway run --host 0.0.0.0 --port 8642
