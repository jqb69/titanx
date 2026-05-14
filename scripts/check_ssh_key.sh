#!/bin/bash
# scripts/check-ssh-key.sh
set -euo pipefail

validate_raw_key() {
    local RAW_KEY="$1"

    # Clean input
    RAW_KEY=$(echo "$RAW_KEY" | sed '/^$/d' | xargs)

    if [[ -z "$RAW_KEY" ]]; then
        echo "❌ DIGITAL_OCEAN_SSH_KEY secret is empty!"
        exit 1
    fi

    echo "Raw key length: ${#RAW_KEY} characters"

    # Auto-fix headers
    if [[ "$RAW_KEY" == *"-----BEGIN"* ]]; then
        echo "✅ Key already contains headers"
        FIXED_KEY="$RAW_KEY"
    else
        echo "🔧 Adding OPENSSH headers (recommended for ed25519)..."
        FIXED_KEY=$(cat <<EOF
-----BEGIN OPENSSH PRIVATE KEY-----
$RAW_KEY
-----END OPENSSH PRIVATE KEY-----
EOF
)
    fi

    # Export to GitHub Actions environment
    cat <<EOF >> "$GITHUB_ENV"
VALID_SSH_KEY<<HEREDOC
$FIXED_KEY
HEREDOC
EOF

    echo "✅ SSH Key successfully validated and exported as VALID_SSH_KEY"
}

validate_raw_key "$1"
