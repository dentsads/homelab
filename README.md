# Zero-Touch Homelab Automation (Proxmox + Debian + Docker)

DISCLAIMER: The following has been written by a LLM ;-)

This repository contains a fully automated **Infrastructure as Code (IaC)** pipeline to provision a bare-metal MiniPC into a production-ready Docker Swarm node. 

It solves the "Inception Problem" of bootstrapping the hypervisor itself, followed by the VM infrastructure, and finally the application layer.

## 🏗 Architecture

The automation is split into 4 reproducible layers:

*   **Layer 0: Bare Metal Boot** (Proxmox Auto-Install + Custom ISO)
*   **Layer 1: Host Configuration** (Ansible)
*   **Layer 2: VM Provisioning** (Terraform + Cloud-Init)
*   **Layer 3: Service Deployment** (Ansible + Docker Compose)

## 📋 Prerequisites

### Hardware
*   **Target Machine:** x86_64 MiniPC (Beelink Mini S13 at the time of writing this guide) with a blank or wipeable NVMe/SSD.
*   **Storage Media:** A USB Flash Drive.
*   **Controller Machine:** A laptop/desktop running Linux, macOS, or WSL (Windows Subsystem for Linux).

### Software (Controller)
You do not need to install tools manually. The included `bootstrap.sh` script will check for and install:
*   `ansible`
*   `terraform`
*   `jq`
*   `proxmox-auto-install-assistant` (Requires Rust/Cargo if not found)
*   `xorriso` (for ISO building)

### Secrets
You must have an SSH Key pair generated:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519