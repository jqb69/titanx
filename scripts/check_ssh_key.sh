#!/bin/bash
# scripts/check-ssh-key.sh
set -euo pipefail

validate_raw_key() {
    local RAW_KEY="$1"
    
    # Remove any leading/trailing whitespace
    RAW_KEY=$(echo "$RAW_KEY" | xargs)

    if [[ -z "$RAW_KEY" ]]; then
        echo "Error: SSH Key is empty."
        exit 1
    fi

    # Check if the header already exists
    if [[ "$RAW_KEY" == *"-----BEGIN"* ]]; then
        echo "Header detected. Using key as-is."
        FIXED_KEY="$RAW_KEY"
    else
        echo "No header detected. Adding RSA headers..."
        # Wrap the raw blob with standard RSA headers
        FIXED_KEY=$(cat <<EOF
-----BEGIN RSA PRIVATE KEY-----
$RAW_KEY
-----END RSA PRIVATE KEY-----
EOF
)
    fi

    # Basic integrity check: ensure it has at least some bulk
    if [[ ${#FIXED_KEY} -lt 100 ]]; then
        echo "Error: Key content is too short to be valid."
        exit 1
    fi

    # Push the FIXED_KEY to the GitHub Environment so actions can use it
    echo "VALID_SSH_KEY<<EOF" >> "$GITHUB_ENV"
    echo "$FIXED_KEY" >> "$GITHUB_ENV"
    echo "EOF" >> "$GITHUB_ENV"
    
    echo "✅ Key validated and headers applied."
}

# Execute the function using the secret passed as the first argument
validate_raw_key "$1"
