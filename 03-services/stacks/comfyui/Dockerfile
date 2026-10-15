# syntax=docker/dockerfile:1

# CPU-only ComfyUI. All heavy inference is offloaded to Modal GPUs by the
# comfyui-modal custom node, so no CUDA runtime is needed here.
FROM python:3.11-slim

# Pinned versions (bump deliberately).
ARG COMFYUI_TAG=v0.41.1
ARG COMFYUI_MANAGER_COMMIT=45ef35b08184798687433c76b9514a18a9ca7f42
ARG COMFYUI_MODAL_COMMIT=8aca1984adb35e2bcf0505138fc41093a815957b

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      git \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxext6 \
      libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# CPU-only PyTorch first, so ComfyUI's requirements.txt does not pull CUDA wheels.
RUN pip install torch torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cpu

# ComfyUI (pinned).
RUN git clone --depth 1 --branch "${COMFYUI_TAG}" \
      https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI
WORKDIR /app/ComfyUI
RUN pip install -r requirements.txt

# Custom nodes are baked here as seeds and copied into the persistent
# custom_nodes volume by entrypoint.sh on first run.
RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager.git /opt/seeds/custom_nodes/ComfyUI-Manager \
 && cd /opt/seeds/custom_nodes/ComfyUI-Manager \
 && git checkout "${COMFYUI_MANAGER_COMMIT}" \
 && pip install -r requirements.txt \
 && rm -rf .git

RUN git clone https://github.com/JunnnnyWon/comfyui-modal.git /opt/seeds/custom_nodes/comfyui-modal \
 && cd /opt/seeds/custom_nodes/comfyui-modal \
 && git checkout "${COMFYUI_MODAL_COMMIT}" \
 && rm -rf .git

# Modal SDK: used by comfyui-modal to deploy the remote app and call the GPUs.
RUN pip install modal

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/entrypoint.sh"]
