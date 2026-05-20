#!/bin/bash
# scripts/check_ssh_key.sh
set -euo pipefail

validate_raw_key() {
    local RAW_KEY="$1"

    # Clean only empty lines — DO NOT use xargs (destroys multiline keys)
    RAW_KEY=$(echo "$RAW_KEY" | sed '/^$/d')

    if [[ -z "$RAW_KEY" ]]; then
        echo "❌ DIGITAL_OCEAN_SSH_KEY secret is empty!"
        exit 1
    fi

    echo "Raw key length: ${#RAW_KEY} characters"

    # Auto-fix headers if missing
    if [[ "$RAW_KEY" == *"-----BEGIN"* ]]; then
        echo "✅ Key already has headers"
        FIXED_KEY="$RAW_KEY"
    else
        echo "🔧 Adding OPENSSH headers (ed25519)..."
        FIXED_KEY=$(cat <<EOF
-----BEGIN OPENSSH PRIVATE KEY-----
$RAW_KEY
-----END OPENSSH PRIVATE KEY-----
EOF
)
    fi

    # Export fixed key for subsequent steps
    cat <<HEREDOC >> "$GITHUB_ENV"
VALID_SSH_KEY<<HEREDOC
$FIXED_KEY
HEREDOC
HEREDOC

    echo "✅ SSH Key validated and fixed successfully"
}

validate_raw_key "$1"
