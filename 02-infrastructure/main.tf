resource "proxmox_vm_qemu" "docker_node" {
  name        = var.vm_name
  vmid        = var.vm_id
  target_node = "pve-beelink" # Hardcoded to match config.json hostname
  clone       = "debian-cloud-template"     # Matches template created by Ansible
  full_clone  = true

  agent = 1
  agent_timeout = 180

  cpu {
    cores = 4
  }
  
  memory  = 4096
  scsihw  = "virtio-scsi-pci"
  
  disk {
    slot    = "scsi0"
    size    = "20G"
    type    = "disk"
    storage = "local-lvm"
    discard = true
  }
  
  disk {
    slot    = "ide2"  
    type    = "cloudinit"
    storage = "local-lvm"    
  }

  boot = "order=scsi0"

  network {
    id = 0
    model = "virtio"
    bridge = "vmbr0"
  }

  os_type = "cloud-init"
  ciuser  = "debian"
  sshkeys = <<EOF
  ${trimspace(var.ssh_key)}
EOF
  
  # Inject Network Config
  ipconfig0 = "ip=${var.vm_ip}/24,gw=${var.vm_gateway}"
}