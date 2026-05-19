#!/bin/bash
set -e

if [ -n "$GITHUB_SSH_PRIVATE_KEY_B64" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    echo "$GITHUB_SSH_PRIVATE_KEY_B64" | base64 -d > /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519
    ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null
fi

if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    getent group "$DOCKER_GID" >/dev/null || addgroup -g "$DOCKER_GID" docker
    addgroup root "$(getent group "$DOCKER_GID" | cut -d: -f1)"
fi

exec opencode "$@"
