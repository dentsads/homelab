#!/bin/bash
set -e

check_and_install() {
    TOOL=$1
    INSTALL_CMD=$2
    
    if ! command -v $TOOL &> /dev/null; then
        echo "⚠️  $TOOL not found. Installing..."
        eval $INSTALL_CMD
        echo "✅ $TOOL installed."
    else
        echo "✅ $TOOL is present."
    fi
}

OS="$(uname -s)"
echo "🔎 Checking dependencies for $OS..."

# 1. Standard Utilities
check_and_install "dd" "echo '❌ dd is missing. This is a critical system tool. Reinstall coreutils.'"

if [ "$OS" == "Linux" ]; then
    # Debian/Ubuntu assumption
    sudo apt update -qq
    check_and_install "jq" "sudo apt install -y jq"
    check_and_install "ansible" "sudo apt install -y ansible"
    check_and_install "xorriso" "sudo apt install -y xorriso" 
    check_and_install "lsblk" "sudo apt install -y util-linux" # Needed to list USBs
    check_and_install "proxmox-auto-install-assistant" "sudo apt install proxmox-auto-install-assistant"
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        echo "Installing Terraform..."
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    else
        echo "✅ Terraform is present."
    fi

elif [ "$OS" == "Darwin" ]; then
    # MacOS
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew required but not found. Please install Homebrew first."
        exit 1
    fi
    check_and_install "jq" "brew install jq"
    check_and_install "ansible" "brew install ansible"
    check_and_install "terraform" "brew install terraform"
    check_and_install "xorriso" "brew install xorriso"
    # diskutil is standard on mac, no install needed
fi

# Check for Proxmox ISO Tool (Rust)
if ! command -v proxmox-auto-install-assistant &> /dev/null; then
    echo "⚠️  proxmox-auto-install-assistant not found."
    echo "   Please install 'cargo' (Rust) and run:"
    echo "   cargo install proxmox-auto-install-assistant"
fi

echo "🎉 All dependencies checked."