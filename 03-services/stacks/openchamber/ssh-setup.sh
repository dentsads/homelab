#!/bin/bash
set -e

if [ -n "$GITHUB_SSH_PRIVATE_KEY_B64" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$GITHUB_SSH_PRIVATE_KEY_B64" | base64 -d > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
fi

exec sh /home/openchamber/openchamber-entrypoint.sh
