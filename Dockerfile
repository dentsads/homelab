FROM python:3.12-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Base Dependencies
# xorriso: for ISO creation
# jq: for JSON parsing in scripts
# openssh-client: for Ansible connections
# argon2: for Vaultwarden admin token hashing
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
    openssl \
    argon2 \
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

# 4. Install Bitwarden CLI (for Vaultwarden secret injection)
ARG BW_CLI_VERSION=2025.2.0
RUN wget -q "https://github.com/bitwarden/clients/releases/download/cli-v${BW_CLI_VERSION}/bw-linux-${BW_CLI_VERSION}.zip" -O /tmp/bw.zip \
    && unzip -o /tmp/bw.zip -d /usr/local/bin \
    && rm /tmp/bw.zip \
    && bw --version

# 5. Install Ansible & Libs (Via PIP into Python 3.12)
# 'passlib' is required for the Ansible 'password_hash' filter used in your templates
RUN pip install --no-cache-dir --upgrade \
    ansible \
    proxmoxer \
    requests \
    passlib

# 6. Setup Environment
WORKDIR /app

# 7. Default Command
CMD ["/bin/bash"]