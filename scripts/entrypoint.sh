#!/bin/bash
# scripts/entrypoint.sh
set -euo pipefail

# Activate the isolated Python virtual environment embedded inside the base image
if [[ -f "/opt/hermes/.venv/bin/activate" ]]; then
    echo "[ENTRYPOINT] Activating image virtual environment..."
    source "/opt/hermes/.venv/bin/activate"
fi

echo "[ENTRYPOINT] Launching Containerized Hermes Gateway Process. (entrpoint.sh)"
exec hermes gateway run
