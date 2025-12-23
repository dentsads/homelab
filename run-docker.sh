#!/bin/bash
set -e

IMAGE_NAME="homelab-builder"

# 1. Build the image if it doesn't exist
if [[ "$(docker images -q $IMAGE_NAME 2> /dev/null)" == "" ]]; then
    echo "🐳 Building Docker image (this takes a few minutes the first time)..."
    docker build -t $IMAGE_NAME .
fi

# 2. Run the container
# --privileged: Required to access /dev/sdX for flashing
# -v /dev:/dev: Passes block devices to container
# -v $(pwd):/app: Mounts current repo
# -v ~/.ssh:/root/.ssh: Mounts SSH keys (read-only recommended, but RW needed if adding to known_hosts)
# --net host: Useful to access local network easily (optional but recommended for homelabs)

echo "🐳 Entering Container Environment..."
echo "   (Your local repo is mounted at /app)"

docker run --rm -it \
    --privileged \
    --net host \
    -v /dev:/dev \
    -v "$(pwd)":/app \
    -v "$HOME/.ssh":/root/.ssh \
    $IMAGE_NAME \
    ./deploy.sh "$@"