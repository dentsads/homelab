FROM python:3.12-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Base Dependencies
# xorriso: for ISO creation
# jq: for JSON parsing in scripts
# openssh-client: for Ansible connections
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    git \
    unzip \
    gnupg \
    gettext-base \
    lsb-release \
    xorriso \
    jq \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Proxmox Auto Install Assistant (via Apt)
# We use the 'bookworm' suite to match the Debian 12 base image.
RUN wget -qO- https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg > /usr/share/keyrings/proxmox-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/proxmox.list && \
    apt-get update && \
    apt-get install -y proxmox-auto-install-assistant && \
    rm -rf /var/lib/apt/lists/*

# 3. Install Terraform (via Hashicorp Repo)
RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && \
    apt-get update && \
    apt-get install -y terraform && \
    rm -rf /var/lib/apt/lists/*

# 4. Install Ansible & Libs (Via PIP into Python 3.12)
# 'passlib' is required for the Ansible 'password_hash' filter used in your templates
RUN pip install --no-cache-dir --upgrade \
    ansible \
    proxmoxer \
    requests \
    passlib

# 5. Setup Environment
WORKDIR /app

# 5. Default Command
CMD ["/bin/bash"]