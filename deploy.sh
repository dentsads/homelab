#!/bin/bash
set -e

# 1. Load Environment and Tools
source .env

# 2. Run Validator
./validate.sh

# 2. Parse Config
HOST_IP=$(jq -r .host.ip config.json)
HOST_MAC=$(jq -r .host.mac config.json)
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
        --extra-vars "terraform_user=$TF_USER terraform_password=$TF_USER_PASSWORD host_mac=$HOST_MAC"
    rm inventory.ini
}

# --- FUNCTION: PROVISION INFRA ---
provision_infra() {
        ACTION=$1
    
    echo "🏗️  Infrastructure Management (Action: ${ACTION:-apply})..."
    cd 02-infrastructure

    # Debug: Check if key is loaded
    if [ -z "$SSH_KEY_CONTENT" ]; then
        echo "❌ Error: SSH Public Key content is empty!"
        echo "   Checked path: $SSH_PUB_KEY_PATH"
        exit 1
    fi
    
    export TF_VAR_pm_api_url="https://${HOST_IP}:8006/api2/json"
    export TF_VAR_pm_user="${TF_USER}@pve"
    export TF_VAR_pm_password="${TF_USER_PASSWORD}"
    export TF_VAR_ssh_key="${SSH_KEY_CONTENT}"
    export TF_VAR_vm_id=$(jq -r .vm.id ../config.json)
    export TF_VAR_vm_name=$(jq -r .vm.name ../config.json)
    export TF_VAR_vm_ip=$(jq -r .vm.ip ../config.json)
    export TF_VAR_vm_gateway=$(jq -r .host.gateway ../config.json)

    # Initialize Provider
    terraform init

    # Toggle Action
    if [ "$ACTION" == "destroy" ]; then
        echo "💥 DESTROYING VM Infrastructure..."
        terraform destroy -auto-approve
    else
        echo "🚀 Applying VM Infrastructure..."
        terraform apply -auto-approve
    fi

    cd ..
}

# --- FUNCTION: DEPLOY SERVICES ---
deploy_services() {
    SUB_CMD=$1
    TARGET_STACK=$2
    
    echo "🚀 Service Management (Command: ${SUB_CMD:-usage})..."
    
    # --- COMMON: SETUP SSH KEYS ---
    HOST_IP=$(jq -r .vm.ip config.json)
    PUB_KEY_PATH=$(eval echo "$SSH_PUB_KEY_PATH")
    PRIV_KEY_PATH="${PUB_KEY_PATH%.pub}"
    SAFE_KEY_DIR="$HOME/.ssh-safe"
    SAFE_KEY_PATH="$SAFE_KEY_DIR/id_deployment_key"

    mkdir -p "$SAFE_KEY_DIR"
    cp "$PRIV_KEY_PATH" "$SAFE_KEY_PATH"
    chmod 600 "$SAFE_KEY_PATH"

    echo "[docker_nodes]" > inventory.ini
    echo "$HOST_IP ansible_user=debian ansible_ssh_private_key_file=$SAFE_KEY_PATH ansible_ssh_common_args='-o StrictHostKeyChecking=no'" >> inventory.ini
    # ------------------------------

    if [ "$SUB_CMD" == "install" ]; then
        echo "🔧 Installing Docker Engine..."
        ansible-playbook -i inventory.ini 03-services/setup_docker.yml
        
    elif [ "$SUB_CMD" == "deploy" ]; then
        
        if [ "$TARGET_STACK" == "all" ] || [ -z "$TARGET_STACK" ]; then
            echo "📦 Deploying ALL stacks defined in 03-services/stacks/..."
            for stack_dir in 03-services/stacks/*; do
                if [ -d "$stack_dir" ]; then
                    STACK_NAME=$(basename "$stack_dir")
                    echo "   ➡️  Processing stack: $STACK_NAME"
                    ansible-playbook -i inventory.ini 03-services/deploy_stack.yml \
                        --extra-vars "stack_name=$STACK_NAME"
                fi
            done
            echo "✅ All stacks deployed."
        else
            if [ ! -d "03-services/stacks/$TARGET_STACK" ]; then
                 echo "❌ Error: Stack '$TARGET_STACK' not found locally."
                 rm inventory.ini; rm -rf "$SAFE_KEY_DIR"; exit 1
            fi
            echo "📦 Deploying Single Stack: $TARGET_STACK ..."
            ansible-playbook -i inventory.ini 03-services/deploy_stack.yml \
                --extra-vars "stack_name=$TARGET_STACK"
        fi

    elif [ "$SUB_CMD" == "delete" ]; then

        if [ "$TARGET_STACK" == "all" ] || [ -z "$TARGET_STACK" ]; then
            echo "🔥 Deleting ALL stacks found in local 03-services/stacks/..."
            for stack_dir in 03-services/stacks/*; do
                if [ -d "$stack_dir" ]; then
                    STACK_NAME=$(basename "$stack_dir")
                    echo "   ➡️  Removing stack: $STACK_NAME"
                    ansible-playbook -i inventory.ini 03-services/remove_stack.yml \
                        --extra-vars "stack_name=$STACK_NAME"
                fi
            done
            echo "✅ All matched stacks removed."
        else
            echo "🔥 Removing Single Stack: $TARGET_STACK ..."
            # Note: We do NOT check if the local folder exists, allowing you 
            # to delete stacks on the server even if you deleted the local folder.
            ansible-playbook -i inventory.ini 03-services/remove_stack.yml \
                --extra-vars "stack_name=$TARGET_STACK"
        fi

    else
        echo "❌ Unknown service command."
        echo "Usage:"
        echo "  ./run-docker.sh services install             (Installs Docker)"
        echo "  ./run-docker.sh services deploy <name|all>   (Starts stacks)"
        echo "  ./run-docker.sh services delete <name|all>   (Stops & Removes stacks)"
    fi

    rm inventory.ini
    rm -rf "$SAFE_KEY_DIR"
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
        # Pass the second arg (e.g., "destroy") to the function
        provision_infra "$2"
        ;;
    services)
        deploy_services "$2" "$3"
        ;;
    all)
        configure_host
        provision_infra
        deploy_services install
        deploy_services deploy all
        ;;
    *)
        echo "Usage: $0 {iso|flash|host|infra [destroy]|services {install|deploy <stack>|deploy all}|all}"
        ;;
esac