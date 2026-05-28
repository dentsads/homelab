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

            # Deploy vaultwarden first with bootstrap secrets
            generate_vaultwarden_secrets
            for stack_dir in 03-services/stacks/*; do
                if [ -d "$stack_dir" ] && [ "$(basename "$stack_dir")" == "vaultwarden" ]; then
                    echo "   ➡️  Processing stack: vaultwarden"
                    SECRETS_FILE="/tmp/secrets/vaultwarden.env"
                    ansible-playbook -i inventory.ini 03-services/deploy_stack.yml \
                        --extra-vars "stack_name=vaultwarden secrets_env_file=$SECRETS_FILE"
                fi
            done

            # Login and fetch secrets for remaining stacks
            bw_login_and_unlock
            for stack_dir in 03-services/stacks/*; do
                if [ -d "$stack_dir" ]; then
                    STACK_NAME=$(basename "$stack_dir")
                    if [ "$STACK_NAME" == "vaultwarden" ]; then
                        continue
                    fi
                    
                    SECRETS_FILE=""
                    if [ "$STACK_NAME" == "proxy" ]; then
                        mkdir -p /tmp/secrets
                        cat > /tmp/secrets/proxy.env << EOF
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
EOF
                    else
                        fetch_stack_secrets "$STACK_NAME"
                    fi
                    SECRETS_FILE="/tmp/secrets/$STACK_NAME.env"
                    set -a; source "$SECRETS_FILE"; set +a
                    
                    echo "   ➡️  Processing stack: $STACK_NAME"
                    ansible-playbook -i inventory.ini 03-services/deploy_stack.yml \
                        --extra-vars "stack_name=$STACK_NAME${SECRETS_FILE:+ secrets_env_file=$SECRETS_FILE}"
                fi
            done
            echo "✅ All stacks deployed."
            rm -rf /tmp/secrets
        else
            if [ ! -d "03-services/stacks/$TARGET_STACK" ]; then
                 echo "❌ Error: Stack '$TARGET_STACK' not found locally."
                 rm inventory.ini; rm -rf "$SAFE_KEY_DIR"; exit 1
            fi

            # Handle secrets: vaultwarden uses bootstrap, proxy generates from .env, others fetch
            if [ "$TARGET_STACK" == "vaultwarden" ]; then
                generate_vaultwarden_secrets
            elif [ "$TARGET_STACK" == "proxy" ]; then
                mkdir -p /tmp/secrets
                cat > /tmp/secrets/proxy.env << EOF
CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
EOF
            elif [ ! -f "/tmp/secrets/$TARGET_STACK.env" ]; then
                bw_login_and_unlock
                fetch_stack_secrets "$TARGET_STACK"
            fi

            SECRETS_FILE=""
            if [ -f "/tmp/secrets/$TARGET_STACK.env" ]; then
                if [ "$TARGET_STACK" != "vaultwarden" ]; then
                    set -a; source "/tmp/secrets/$TARGET_STACK.env"; set +a
                fi
                SECRETS_FILE="/tmp/secrets/$TARGET_STACK.env"
            fi
            echo "📦 Deploying Single Stack: $TARGET_STACK ..."
            ansible-playbook -i inventory.ini 03-services/deploy_stack.yml \
                --extra-vars "stack_name=$TARGET_STACK${SECRETS_FILE:+ secrets_env_file=$SECRETS_FILE}"
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

    elif [ "$SUB_CMD" == "backup" ]; then
        if [ -z "$TARGET_STACK" ]; then echo "❌ Specify stack name."; exit 1; fi
        
        echo "💾 Backing up volumes for stack: $TARGET_STACK ..."
        ansible-playbook -i inventory.ini 03-services/backup_stack.yml \
            --extra-vars "stack_name=$TARGET_STACK"

    elif [ "$SUB_CMD" == "restore" ]; then
        if [ -z "$TARGET_STACK" ]; then echo "❌ Specify stack name."; exit 1; fi

        echo "♻️  Restoring volumes for stack: $TARGET_STACK ..."
        ansible-playbook -i inventory.ini 03-services/restore_stack.yml \
            --extra-vars "stack_name=$TARGET_STACK"
            
    else
        echo "❌ Unknown command."
        echo "Usage:"
        echo "  ./run-docker.sh services install             (Installs Docker)"
        echo "  ./run-docker.sh services deploy <name|all>   (Starts stacks)"
        echo "  ./run-docker.sh services delete <name|all>   (Stops & Removes stacks)"
        echo "  ./run-docker.sh services backup <name>       (Backs up stack volumes)"
        echo "  ./run-docker.sh services restore <name>      (Restores stack volumes)"
    fi

    rm inventory.ini
    rm -rf "$SAFE_KEY_DIR"
}

# --- FUNCTION: BW AUTH ---
bw_login_and_unlock() {
    if [ -n "$BW_SESSION" ]; then
        echo "✅ Already logged into Vaultwarden"
        return 0
    fi
    echo "🔐 Logging into Vaultwarden..."    
    bw config server "${VAULTWARDEN_URL}"
    bw logout > /dev/null 2>&1 || true
    export BW_CLIENTID="$VAULTWARDEN_BW_CLIENTID"
    export BW_CLIENTSECRET="$VAULTWARDEN_BW_CLIENTSECRET"
    if ! bw login --apikey; then
        echo "❌ Vaultwarden login failed. Check VAULTWARDEN_BW_CLIENTID/SECRET in .env"
        exit 1
    fi
    export BW_SESSION=$(echo "$VAULTWARDEN_BW_PASSWORD" | bw unlock --raw)
    bw sync
    echo "✅ Vaultwarden session established"
}

# --- FUNCTION: FETCH SECRETS ---
fetch_stack_secrets() {
    local stack_name=$1
    mkdir -p /tmp/secrets
    local output_file="/tmp/secrets/${stack_name}.env"

    rm -f "$output_file"
    if ! bw get item "$stack_name" > /dev/null 2>&1; then
        echo "❌ Vaultwarden item '$stack_name' not found in vault."
        echo "   Create a Login item named '$stack_name' in the Deployment collection"
        echo "   with Custom Fields matching the env vars for that stack."
        exit 1
    fi

    bw get item "$stack_name" | jq -r '.fields[] | "\(.name)=\(.value)"' | sed 's/\$/$$/g' > "$output_file"
    echo "✅ Fetched secrets for '$stack_name' ($(wc -l < "$output_file") vars)"
}

# --- FUNCTION: GENERATE VAULTWARDEN BOOTSTRAP SECRETS ---
generate_vaultwarden_secrets() {
    mkdir -p /tmp/secrets
    local salt=$(openssl rand -base64 32)
    local hash=$(printf '%s' "$VAULTWARDEN_ADMIN_TOKEN" | argon2 "$salt" -e -id -k 65540 -t 3 -p 4)
    printf "VAULTWARDEN_ADMIN_TOKEN=%s\n" "$hash" | sed 's/\$/$$/g' > /tmp/secrets/vaultwarden.env
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

        # Phase 1: Deploy vaultwarden with bootstrap ADMIN_TOKEN
        echo "📦 Deploying vaultwarden (bootstrap phase)..."
        generate_vaultwarden_secrets
        deploy_services deploy vaultwarden

        # Phase 2: Login to Vaultwarden
        bw_login_and_unlock

        # Phase 3: Deploy remaining stacks with fetched secrets
        echo "📦 Deploying remaining stacks..."
        for stack_dir in 03-services/stacks/*; do
            if [ -d "$stack_dir" ]; then
                STACK_NAME=$(basename "$stack_dir")
                if [ "$STACK_NAME" != "vaultwarden" ]; then
                    fetch_stack_secrets "$STACK_NAME"
                    deploy_services deploy "$STACK_NAME"
                fi
            fi
        done
        echo "✅ All stacks deployed."
        rm -rf /tmp/secrets
        ;;
    *)
        echo "Usage: $0 {iso|flash|host|infra [destroy]|services {install|deploy <stack>|deploy all}|all}"
        ;;
esac