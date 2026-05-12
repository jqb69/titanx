#!/bin/bash
# scripts/check_ssh_key.sh
# Local pre-upload validation for raw key strings

RAW_KEaY="$1"

error_exit() {
    echo "CRITICAL ERROR: $1"
    exit 1
}

validate_raw_key() {
    # Strip all white space and newlines from the key 
    CLEAN_KEY=$(echo "$RAW_KEY" | tr -d '[:space:]')
    KEY_LENGTH=${#CLEAN_KEY}

    echo "Validating raw SSH Key string..."

    # RSA-4096 keys in base64/hex are significantly long (typically > 2500 chars) [cite: 276, 280]
    if [ "$KEY_LENGTH" -lt 2500 ]; then
        error_exit "Key length ($KEY_LENGTH) is too short for a standard RSA-4096 key string."
    fi

    # Ensure it doesn't already contain PEM headers (to avoid double-wrapping)
    if [[ "$RAW_KEY" =~ "BEGIN" ]]; then
        error_exit "Key already contains PEM headers. Please provide ONLY the raw key string."
    fi

    echo "✓ Raw SSH Key string validated (Length: $KEY_LENGTH)."
}

if [ -z "$RAW_KEY" ]; then
    error_exit "DIGITAL_OCEAN_SSH_KEY secret is empty."
fi

validate_raw_key
