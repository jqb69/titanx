#!/bin/bash
# create-ajax-user.sh
# Script 1: Create ajax user + SSH Key
set -euo pipefail

USER="ajax"
PROJECT_DIR="/home/$USER/titanx"
HERMES_DATA="${PROJECT_DIR}/.hermes"

log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Run as root"

log "Creating ajax user..."
if ! id "$USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$USER"
    usermod -aG sudo "$USER"
fi

mkdir -p "$HERMES_DATA" "$PROJECT_DIR/workspace" "/home/$USER/.ssh"
chown -R "$USER":"$USER" "$PROJECT_DIR" "/home/$USER/.ssh"
chmod 700 "/home/$USER/.ssh"

if [[ ! -f "/home/$USER/.ssh/id_ed25519" ]]; then
    su - "$USER" -c "ssh-keygen -t ed25519 -C 'ajax@titanx' -f ~/.ssh/id_ed25519 -N ''"
    log "SSH key generated"
fi

cp "/home/$USER/.ssh/id_ed25519.pub" "/home/$USER/.ssh/authorized_keys"
chmod 600 "/home/$USER/.ssh/authorized_keys"

log "✅ ajax user + SSH key ready"
