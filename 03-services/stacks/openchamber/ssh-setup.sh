#!/bin/bash
set -e

if [ -n "$GITHUB_SSH_PRIVATE_KEY_B64" ]; then
    mkdir -p /home/openchamber/.ssh && chmod 700 /home/openchamber/.ssh
    echo "$GITHUB_SSH_PRIVATE_KEY_B64" | base64 -d > /home/openchamber/.ssh/id_ed25519
    chmod 600 /home/openchamber/.ssh/id_ed25519
    chown -R openchamber:openchamber /home/openchamber/.ssh
    ssh-keyscan github.com >> /home/openchamber/.ssh/known_hosts 2>/dev/null
fi

if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    getent group "$DOCKER_GID" >/dev/null || groupadd -g "$DOCKER_GID" dockersock
    usermod -aG "$(getent group "$DOCKER_GID" | cut -d: -f1)" openchamber
fi

exec su openchamber -c "sh /home/openchamber/openchamber-entrypoint.sh"
