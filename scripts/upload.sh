#!/bin/bash
# scripts/upload.sh - Prepares droplet environment
TARGET_DIR=$1

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || { echo "Failed to access $TARGET_DIR"; exit 1; }

# Set permissions for all uploaded shell scripts
chmod +x *.sh

echo "--- Scripts ready in $TARGET_DIR ---"
ls -F *.sh
