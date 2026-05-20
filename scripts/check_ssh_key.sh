#!/bin/bash
# scripts/check_ssh_key.sh
set -euo pipefail

validate_raw_key() {
    local RAW_KEY="${1:-}"

    # Clean only empty lines, preserve all newlines and formatting
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

    # Safe multiline export to GITHUB_ENV (Kimi's recommended way)
    {
        echo "VALID_SSH_KEY<<GHA_SSH_EOF"
        echo "$FIXED_KEY"
        echo "GHA_SSH_EOF"
    } >> "$GITHUB_ENV"

    echo "✅ SSH Key validated and fixed successfully"
}

validate_raw_key "$1"
