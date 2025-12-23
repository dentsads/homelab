#!/bin/bash
set -e

# 1. Load Environment and Tools
source .env

# 2. Run Validator
./validate.sh

# 2. Parse Config
HOST_IP=$(jq -r .host.ip config.json)
TF_USER=$(jq -r .proxmox.tf_user config.json)
VM_IP=$(jq -r .vm.ip config.json)
ISO_FILENAME="custom-installer.iso"

# Read SSH Key
SSH_KEY_CONTENT=$(cat ${SSH_PUB_KEY_PATH})

# --- FUNCTION: BUILD ISO ---
build_iso() {
    echo "💿 Building Custom ISO..."
    
    if ! command -v proxmox-auto-install-assistant &> /dev/null; then
        echo "❌ proxmox-auto-install-assistant missing."
        exit 1
    fi

    # Generate Hashed Password
    PASS_HASH=$(python3 -c "import crypt; print(crypt.crypt('${HOST_ROOT_PASSWORD}', crypt.mksalt(crypt.METHOD_SHA512)))")
    
    # Export Vars for Template
    export HOST_FQDN="$(jq -r .host.hostname config.json).$(jq -r .host.domain config.json)"
    export HOST_PASS_HASH="$PASS_HASH"
    export SSH_KEY="$SSH_KEY_CONTENT"
    export HOST_IP="$HOST_IP"
    export HOST_GATEWAY="$(jq -r .host.gateway config.json)"
    export HOST_CIDR="$(jq -r .host.cidr_bit config.json)"
    export HOST_DNS="$(jq -r .host.dns config.json)"
    export HOST_DISK="$(jq -r .host.disk config.json)"
    export HOST_IFACE="$(jq -r .host.interface config.json)"

    envsubst < 00-iso/answer.template.toml > 00-iso/answer.toml

    ORIG_ISO="proxmox-ve_$(jq -r .proxmox.iso_version config.json).iso"
    if [ ! -f "$ORIG_ISO" ]; then
        echo "❌ Please download $ORIG_ISO to this folder first."
        exit 1
    fi
    
    proxmox-auto-install-assistant prepare-iso "$ORIG_ISO" \
        --fetch-from iso \
        --answer-file 00-iso/answer.toml \
        --output "$ISO_FILENAME"

    echo "✅ ISO Created: $ISO_FILENAME"
    rm 00-iso/answer.toml
}

# --- FUNCTION: FLASH USB ---
flash_usb() {
    if [ ! -f "$ISO_FILENAME" ]; then
        echo "❌ $ISO_FILENAME not found. Run './deploy.sh iso' first."
        exit 1
    fi

    echo "💾 Preparing to flash USB. Please unplug other external drives to be safe."
    echo "-----------------------------------------------------------------------"
    
    OS="$(uname -s)"
    if [ "$OS" == "Linux" ]; then
        echo "Listing removable devices (Linux):"
        lsblk -o NAME,MODEL,SIZE,TRAN,TYPE | grep "usb" || true
        lsblk -o NAME,MODEL,SIZE,TRAN,TYPE | grep "disk" 
    elif [ "$OS" == "Darwin" ]; then
        echo "Listing external devices (MacOS):"
        diskutil list external
    fi
    echo "-----------------------------------------------------------------------"
    
    echo -n "🔴 ENTER DEVICE PATH (e.g. /dev/sdb or /dev/disk2): "
    read TARGET_DRIVE

    if [ -z "$TARGET_DRIVE" ]; then
        echo "❌ No device specified. Aborting."
        exit 1
    fi

    echo "⚠️  WARNING: ALL DATA ON $TARGET_DRIVE WILL BE ERASED FOREVER."
    echo -n "Type 'CONFIRM' to proceed with flashing: "
    read CONFIRM
    if [ "$CONFIRM" != "CONFIRM" ]; then
        echo "❌ Aborting."
        exit 1
    fi

    echo "🔥 Flashing $ISO_FILENAME to $TARGET_DRIVE using dd..."
    
    # Run DD with sudo
    if [ "$OS" == "Darwin" ]; then
        # On Mac, unmount first and use rdisk for speed if possible
        diskutil unmountDisk $TARGET_DRIVE || true
        # Attempt to convert /dev/diskN to /dev/rdiskN for speed
        RAW_DISK="${TARGET_DRIVE/disk/rdisk}"
        dd if="$ISO_FILENAME" of="$RAW_DISK" bs=4m
    else
        # Linux
        umount "$TARGET_DRIVE"* 2>/dev/null || true
        dd if="$ISO_FILENAME" of="$TARGET_DRIVE" bs=4M status=progress oflag=sync
    fi
    
    echo ""
    echo "✅ Flashing complete. You can now boot the Beelink from this USB."
}

# --- FUNCTION: CONFIGURE HOST ---
configure_host() {
    echo "⚙️  Configuring Proxmox Host at $HOST_IP..."
    echo "[proxmox]" > inventory.ini
    echo "$HOST_IP ansible_user=root ansible_ssh_private_key_file=${SSH_PUB_KEY_PATH%.pub} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> inventory.ini
    
    ansible-playbook -i inventory.ini 01-host-config/setup_host.yml \
        --extra-vars "terraform_user=$TF_USER terraform_password=$TF_USER_PASSWORD"
    rm inventory.ini
}

# --- FUNCTION: PROVISION INFRA ---
provision_infra() {
    echo "🏗️  Provisioning Infrastructure via Terraform..."
    cd 02-infrastructure
    
    export TF_VAR_pm_api_url="https://${HOST_IP}:8006/api2/json"
    export TF_VAR_pm_user="${TF_USER}@pve"
    export TF_VAR_pm_password="${TF_USER_PASSWORD}"
    export TF_VAR_ssh_key="${SSH_KEY_CONTENT}"
    export TF_VAR_vm_id=$(jq -r .vm.id ../config.json)
    export TF_VAR_vm_name=$(jq -r .vm.name ../config.json)
    export TF_VAR_vm_ip=$(jq -r .vm.ip ../config.json)
    export TF_VAR_vm_gateway=$(jq -r .host.gateway ../config.json)

    terraform init
    terraform apply -auto-approve
    cd ..
}

# --- FUNCTION: DEPLOY SERVICES ---
deploy_services() {
    echo "🚀 Deploying Docker Services to VM ($VM_IP)..."
    sleep 30
    echo "[docker_nodes]" > inventory.ini
    echo "$VM_IP ansible_user=debian ansible_ssh_private_key_file=${SSH_PUB_KEY_PATH%.pub} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> inventory.ini

    ansible-playbook -i inventory.ini 03-services/install_docker.yml
    rm inventory.ini
}

# --- MENU ---
case "$1" in
    iso)
        build_iso
        ;;
    flash)
        flash_usb
        ;;
    host)
        configure_host
        ;;
    infra)
        provision_infra
        ;;
    services)
        deploy_services
        ;;
    all)
        configure_host
        provision_infra
        deploy_services
        ;;
    *)
        echo "Usage: $0 {iso|flash|host|infra|services|all}"
        echo "  1. ./deploy.sh iso    -> Build ISO"
        echo "  2. ./deploy.sh flash  -> Burn ISO to USB (dd)"
        echo "  3. [Boot Machine]"
        echo "  4. ./deploy.sh all    -> Configure Host, VM, and Docker"
        ;;
esac