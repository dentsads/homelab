#!/bin/bash
set -e

IMAGE_NAME="homelab-builder"

# 1. Build the image if it doesn't exist
if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    echo "🐳 Building Docker image (this takes a few minutes the first time)..."
    docker build -t $IMAGE_NAME .
fi

# 2. Configure SSH Agent Forwarding
# This checks if your host has an agent running and mounts the socket
SSH_AGENT_ARGS=""
if [ -n "$SSH_AUTH_SOCK" ]; then
    echo "🔑 Forwarding SSH Agent to container..."
    SSH_AGENT_ARGS="-v $SSH_AUTH_SOCK:/run/ssh-agent -e SSH_AUTH_SOCK=/run/ssh-agent"
else
    echo "⚠️  WARNING: SSH Agent not found on host."
    echo "   You will likely be prompted for passwords or fail authentication."
fi

echo "🐳 Entering Container Environment..."
echo "   (Your local repo is mounted at /app)"

# 3. Resolve VM IP for Vaultwarden DNS (bw CLI needs to connect to internal Vaultwarden)
VM_IP=$(jq -r .vm.ip config.json 2>/dev/null || echo "")
HOST_ENTRY=""
if [ -n "$VM_IP" ]; then
    HOST_ENTRY="--add-host vw.${VM_IP}.nip.io:${VM_IP}"
fi

docker run --rm -it \
    --privileged \
    --net host \
    -v /dev:/dev \
    -v "$(pwd)":/app \
    -v "$HOME/.ssh":/root/.ssh \
    $SSH_AGENT_ARGS \
    $HOST_ENTRY \
    $IMAGE_NAME \
    ./deploy.sh "$@"