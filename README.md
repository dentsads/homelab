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
You do not need to install Terraform, Ansible, or Python manually. The entire environment runs inside a container.

*   **Docker Engine** (Installed and running)

### Secrets
You must have an SSH Key pair generated on your host machine:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
```

### Repository Structure

```
homelab-automation/
├── .env                    # Secrets (GitIgnored - You must create this)
├── config.json             # Central Config (IPs, Hostnames, Resources)
├── run-docker.sh           # ENTRYPOINT: Run this wrapper script
├── Dockerfile              # Defines the build environment
├── deploy.sh               # Internal orchestration (runs inside container)
├── 00-iso/                 # Layer 0: Custom ISO generation
├── 01-host-config/         # Layer 1: Proxmox Host Setup (Ansible)
├── 02-infrastructure/      # Layer 2: VM Creation (Terraform)
└── 03-services/            # Layer 3: Docker Setup (Ansible)
```

## 🚀 Usage Guide

The deploy.sh script handles the entire lifecycle.

### Phase 1: Create the Installer

1. Build the ISO:
This spins up the builder container and bakes your network config/SSH keys into a custom installer.

```bash
./run-docker.sh iso
```

Output: `custom-installer.iso`

2. Flash to USB:
⚠️ WARNING: This uses `dd`. Be absolutely sure you select the correct USB drive. The script will ask for confirmation.

```bash
./run-docker.sh flash
```

### Phase 2: Bare Metal Install

1. Insert the USB stick into the Beelink.
2. Boot the machine.
3. Do nothing. The installer will automatically select the disk defined in `config.json`, wipe it, install Proxmox, configure the static IP, and reboot.
4. Remove the USB stick when the machine reboots.

### Phase 3: Bootstrap Infrastructure

Once the Proxmox host is reachable (ping the IP set in `config.json`), run:

```bash
./run-docker.sh all
```

This single command performs the following "Inception" steps:

1. Configure Host:
  * Connects to Proxmox via SSH (using the key injected by the ISO).
  * Removes Enterprise repos, updates packages.
  * Creates a `terraform-prov` user and API permissions.
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
* `./run-docker.sh iso`	Generates the automated installation ISO.
* `./run-docker.sh flash`	Burns the ISO to a USB drive.
* `./run-docker.sh host`	Runs Ansible to configure the Proxmox bare metal host.
* `./run-docker.sh infra`	Runs Terraform to create/update VMs.
* `./run-docker.sh services`	Runs Ansible to install Docker and deploy containers.

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

## 🔑 Handling SSH Keys with Passphrases

If your SSH private key is protected by a passphrase, Ansible inside the container will fail with `Permission denied (publickey)` because it cannot interactively ask you to type the password.

To solve this, this pipeline uses **SSH Agent Forwarding**. You unlock the key once on your host machine, and the container uses the unlocked connection.

**Before running the deployment, perform these steps on your host:**

1.  **Start the SSH Agent** (if not running):
    ```bash
    eval "$(ssh-agent -s)"
    ```

2.  **Add your Private Key:**
    Enter your passphrase when prompted.
    ```bash
    ssh-add ~/.ssh/id_ed25519
    ```

3.  **Verify:**
    Ensure your key is listed.
    ```bash
    ssh-add -l
    ```

The `run-docker.sh` script automatically detects your running agent and mounts the socket into the container.

## 💾 Backup & Restore Guide

This repository includes an automated workflow to snapshot Docker Named Volumes and restore them. This ensures that even if you wipe the entire MiniPC, you can recover your application state (databases, configs, histories) in minutes.

---

### 🏗 How it Works

The backup system targets **Docker Named Volumes** (located at `/var/lib/docker/volumes/`). It does **not** backup bind mounts (host paths), so ensure your `docker-compose.yml` files use named volumes for persistent data.

#### The Backup Flow
1.  **Stop:** The stack containers are stopped to ensure data consistency (no database writes during backup).
2.  **Archive:** Each volume associated with the stack is compressed into a `.tar.gz` file.
3.  **Download:** The archives are downloaded to your local controller machine (inside the `backups/` folder).
4.  **Restart:** The stack containers are started again.

### The Restore Flow
1.  **Upload:** Backup archives are uploaded to the remote VM.
2.  **Create:** The Docker volume is created (if missing).
3.  **Extract:** Data is unarchived directly into the volume data directory.

---

### 🛠 Commands

All commands are run via the `run-docker.sh` wrapper.

#### 1. Backing Up a Stack

To backup a stack (e.g., `core`):

```bash
./run-docker.sh services backup core
```

Result:
You will find the files on your laptop at:
./backups/core/core.tar.gz

#### 1. Restoring a Stack

To restore data to the stack:

```bash
./run-docker.sh services restore core
```

## 🚨 Disaster Recovery Scenario (Total Wipe)

If your server dies or you intentionally wipe the machine, follow this exact sequence to restore operations.

#### 1. Rebuild Infrastructure

Run the main automation pipeline to provision the hardware, VM, and empty containers. 

```bash
# This configures Host -> Creates VM -> Installs Docker -> Starts Empty Stacks
./run-docker.sh all
```

At this point, your services (e.g., Portainer) are running, but they are fresh installations with no data.

#### 2. Stop the "Empty" Stacks

You cannot restore data while the specific stack is running. Stop the specific stack you want to restore (e.g., core).

```bash
./run-docker.sh services delete core
```

(Note: 'delete' here stops containers and removes the service definition, but keeps the volumes. We are about to overwrite those volumes.)

#### 3. Restore Data

Inject your local backups into the VM.

```bash
./run-docker.sh services restore core
```

#### 4. Restart Service

Now start the stack again. It will attach to the restored volumes.

```bash
./run-docker.sh services deploy core
```

#### Verification:
Log in to your service (e.g., Portainer UI). Your previous admin account, settings, and environments should be present.

### ⚠️ Important Notes

#### 1. Bind Mounts:
If you use bind mounts (e.g., - `/opt/data:/data`) in your Compose files, this tool will NOT backup that data. Recommendation: Use Named Volumes for everything in this setup.

Bad (Bind Mount):
```yaml
volumes:
  - ./config:/config
```

Good (Named Volume):

```yaml
volumes:
  - config_data:/config

volumes:
  config_data:
```

#### 2. Git Ignore:
The `backups/` folder is ignored by Git (`.gitignore`) to prevent committing large binaries or sensitive database dumps to your version control. Ensure you have a separate backup strategy for your laptop (e.g., Time Machine, Backblaze) to protect these `.tar.gz` files.
