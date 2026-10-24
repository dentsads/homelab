#!/bin/bash
set -e

COMFYUI_DIR=/app/ComfyUI
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"

# Seed the baked custom nodes into the persistent custom_nodes volume on first run.
# Subsequent starts keep anything installed at runtime (e.g. via ComfyUI-Manager).
mkdir -p "$CUSTOM_NODES_DIR"
for seed in /opt/seeds/custom_nodes/*; do
    [ -d "$seed" ] || continue
    name="$(basename "$seed")"
    if [ ! -d "$CUSTOM_NODES_DIR/$name" ]; then
        echo "[comfyui] Seeding custom node: $name"
        cp -a "$seed" "$CUSTOM_NODES_DIR/$name"
    fi
done

# Materialize ~/.modal.toml from the environment so the comfyui-modal sidebar
# reports "connected" and `modal deploy` can authenticate.
if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
    printf '[default]\ntoken_id = "%s"\ntoken_secret = "%s"\n' \
        "$MODAL_TOKEN_ID" "$MODAL_TOKEN_SECRET" > /root/.modal.toml
    chmod 600 /root/.modal.toml
else
    echo "[comfyui] WARNING: MODAL_TOKEN_ID/MODAL_TOKEN_SECRET not set - Modal GPU routing will not work."
fi

# Optional Hugging Face token for gated model downloads (the plugin reads this file).
if [ -n "$HF_TOKEN" ] && [ -d "$CUSTOM_NODES_DIR/comfyui-modal" ]; then
    printf '%s' "$HF_TOKEN" > "$CUSTOM_NODES_DIR/comfyui-modal/.hf_token"
fi

cd "$COMFYUI_DIR"
exec python main.py --listen 0.0.0.0 --port 8188 --cpu --disable-auto-launch --enable-assets
