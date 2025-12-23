#!/bin/bash
set -e

# Define the required tools
REQUIRED_TOOLS=(
    "terraform"
    "ansible-playbook"
    "jq"
    "proxmox-auto-install-assistant"
    "xorriso"
    "dd"
)

echo "🔍 Verifying environment dependencies..."

MISSING_TOOLS=0

for TOOL in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$TOOL" &> /dev/null; then
        echo "❌ Missing: $TOOL"
        MISSING_TOOLS=1
    else
        # Optional: Print version for debugging
        # echo "✅ Found: $TOOL"
        :
    fi
done

if [ $MISSING_TOOLS -eq 1 ]; then
    echo "----------------------------------------------------------------"
    echo "⛔ CRITICAL MISSING DEPENDENCIES"
    echo "----------------------------------------------------------------"
    echo "It looks like you are trying to run './deploy.sh' directly on your"
    echo "outdated host machine, or the Docker build failed."
    echo ""
    echo "👉 Please use the Docker wrapper instead:"
    echo "   ./run-docker.sh <command>"
    echo "----------------------------------------------------------------"
    exit 1
fi

echo "✅ Environment is healthy. Proceeding..."