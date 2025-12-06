resource "proxmox_vm_qemu" "docker_node" {
  name        = var.vm_name
  vmid        = var.vm_id
  target_node = "pve-beelink" # Hardcoded to match config.json hostname
  clone       = "VM 9000"     # Matches template created by Ansible
  full_clone  = true

  cores   = 4
  memory  = 4096
  scsihw  = "virtio-scsi-pci"
  
  disk {
    slot = 0
    size = "20G"
    type = "scsi"
    storage = "local-lvm"
  }
  
  network {
    model = "virtio"
    bridge = "vmbr0"
  }

  os_type = "cloud-init"
  ciuser  = "debian"
  sshkeys = var.ssh_key
  
  # Inject Network Config
  ipconfig0 = "ip=${var.vm_ip}/24,gw=${var.vm_gateway}"
}