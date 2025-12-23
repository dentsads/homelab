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
```

### Repository Structure

```
homelab-automation/
├── .env                    # Secrets (GitIgnored - You must create this)
├── config.json             # Central Config (IPs, Hostnames, Resources)
├── deploy.sh               # Main orchestration script
├── bootstrap.sh            # Dependency installer
├── 00-iso/                 # Layer 0: Custom ISO generation
├── 01-host-config/         # Layer 1: Proxmox Host Setup (Ansible)
├── 02-infrastructure/      # Layer 2: VM Creation (Terraform)
└── 03-services/            # Layer 3: Docker Setup (Ansible)
```

## 🚀 Usage Guide

The deploy.sh script handles the entire lifecycle.

### Phase 1: Create the Installer

1. Build the ISO:
This bakes your network config and SSH keys into a custom installer.

```bash
./deploy.sh iso
```

Output: `custom-installer.iso`

2. Flash to USB:
⚠️ WARNING: This uses `dd`. Be absolutely sure you select the correct USB drive.

```bash
./deploy.sh flash
```

### Phase 2: Bare Metal Install

Insert the USB stick into the Beelink.

Boot the machine.

Do nothing. The installer will automatically select the disk defined in config.json, wipe it, install Proxmox, configure the static IP, and reboot.

Remove the USB stick when the machine reboots.

### Phase 3: Bootstrap Infrastructure

Once the Proxmox host is reachable (ping the IP set in config.json), run:

```bash
./deploy.sh all
```

This single command performs the following "Inception" steps:

1. Configure Host:
  * Connects to Proxmox via SSH (using the key injected by the ISO).
  * Removes Enterprise repos, updates packages.
  * Creates a terraform-prov user and API permissions.
  * Downloads a Debian Cloud Image and converts it to a Proxmox Template.

2. Provision Infra:

  * Runs Terraform to clone the template.
  * Resizes disks and injects Cloud-Init data (IPs, Users).

3. Deploy Services:

  * Waits for the VM to boot.
  * Installs Docker & Docker Compose.
  * Deploys the containers defined in 03-services/files/docker-compose.yml.

## 🛠 Individual Commands

If you need to run specific parts of the pipeline separately:

### Command	Description
* `./deploy.sh iso`	Generates the automated installation ISO.
* `./deploy.sh flash`	Burns the ISO to a USB drive.
* `./deploy.sh host`	Runs Ansible to configure the Proxmox bare metal host.
* `./deploy.sh infra`	Runs Terraform to create/update VMs.
* `./deploy.sh services`	Runs Ansible to install Docker and deploy containers.

## Wake-On-LAN

In order to be able to use wake on lan you need to install the `ẁakeonlan` cli 

```bash
apt update

apt install -y wakeonlan
```

afterwards you can wake up the server if you know the mac address

```bash
# e.g. sudo wakeonlan 78:55:36:02:6c:54
sudo wakeonlan <mac-address>
```