packer {
  required_plugins {
    # see https://github.com/hashicorp/packer-plugin-proxmox
    proxmox = {
      version = "1.2.2"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "source_template" {
  type    = string
  default = "template-windows-11-24h2-uefi"
}

variable "proxmox_node" {
  type    = string
  default = env("PROXMOX_NODE")
}

source "proxmox-clone" "windows" {
  clone_vm                 = var.source_template
  template_name            = "template-windows-sysprep-playground"
  template_description     = "See https://github.com/rgl/windows-sysprep-playground"
  tags                     = "template-windows-sysprep-playground;template"
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node
  full_clone               = false
  cpu_type                 = "host"
  cores                    = 2
  memory                   = 4 * 1024
  scsi_controller          = "virtio-scsi-single"
  task_timeout             = "10m"
  os                       = "win11"
  communicator             = "ssh"
  ssh_username             = "vagrant"
  ssh_password             = "vagrant"
  ssh_timeout              = "60m"
}

build {
  sources = [
    "source.proxmox-clone.windows",
  ]

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-chocolatey.ps1"
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-handle.ps1"
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-notepadplusplus.ps1"
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-block-internet-access.ps1"
  }

  provisioner "file" {
    source      = "provision-sysprep-oobe.ps1"
    destination = "C:/Windows/System32/Sysprep/provision-sysprep-oobe.ps1"
  }

  #
  # do the first round of sysprep.
  #

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep.ps1"
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep-oobe-wait.ps1"
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep-status.ps1"
  }

  #
  # do the second round of sysprep.
  #

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep.ps1"
  }

  provisioner "windows-restart" {
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep-oobe-wait.ps1"
  }

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep-status.ps1"
  }

  #
  # leave the machine template generalized.
  #

  provisioner "powershell" {
    use_pwsh = true
    script   = "provision-sysprep.ps1"
  }
}
