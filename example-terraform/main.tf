# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.10.2"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.5"
    }
    # see https://registry.terraform.io/providers/bpg/proxmox
    # see https://github.com/bpg/terraform-provider-proxmox
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.68.1"
    }
  }
}

provider "proxmox" {
  ssh {
    node {
      name    = var.proxmox_pve_node_name
      address = var.proxmox_pve_node_address
    }
  }
}

variable "proxmox_pve_node_name" {
  type    = string
  default = "pve"
}

variable "proxmox_pve_node_address" {
  type = string
}

variable "prefix" {
  type    = string
  default = "example-windows-sysprep-playground"
}

variable "username" {
  type    = string
  default = "vagrant"
}

variable "password" {
  type      = string
  sensitive = true
  # NB the password will be reset by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

# see https://registry.terraform.io/providers/bpg/proxmox/0.68.1/docs/data-sources/virtual_environment_vms
data "proxmox_virtual_environment_vms" "windows_templates" {
  tags = ["template-windows-sysprep-playground", "template"]
}

# see https://registry.terraform.io/providers/bpg/proxmox/0.68.1/docs/data-sources/virtual_environment_vm
data "proxmox_virtual_environment_vm" "windows_template" {
  node_name = data.proxmox_virtual_environment_vms.windows_templates.vms[0].node_name
  vm_id     = data.proxmox_virtual_environment_vms.windows_templates.vms[0].vm_id
}

# the virtual machine cloudbase-init cloud-config.
# NB the parts are executed by their declared order.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/1.1.6/userdata.html#cloud-config
# see https://cloudbase-init.readthedocs.io/en/1.1.6/userdata.html#userdata
# see https://registry.terraform.io/providers/hashicorp/cloudinit/latest/docs/data-sources/config.html
# see https://developer.hashicorp.com/terraform/language/expressions#string-literals
data "cloudinit_config" "example" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content      = <<-EOF
      #cloud-config
      timezone: Europe/Lisbon
      users:
        - name: ${jsonencode(var.username)}
          passwd: ${jsonencode(var.password)}
          primary_group: Administrators
          ssh_authorized_keys:
            - ${jsonencode(trimspace(file("~/.ssh/id_rsa.pub")))}
      EOF
  }
}

# see https://registry.terraform.io/providers/bpg/proxmox/0.68.1/docs/resources/virtual_environment_file
resource "proxmox_virtual_environment_file" "example_ci_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_pve_node_name
  source_raw {
    file_name = "${var.prefix}-ci-user-data.txt"
    data      = data.cloudinit_config.example.rendered
  }
}

# see https://registry.terraform.io/providers/bpg/proxmox/0.68.1/docs/resources/virtual_environment_vm
resource "proxmox_virtual_environment_vm" "example" {
  name      = var.prefix
  node_name = var.proxmox_pve_node_name
  tags      = sort(["example-windows-sysprep-playground", "example", "terraform"])
  clone {
    vm_id = data.proxmox_virtual_environment_vm.windows_template.vm_id
    full  = false
  }
  cpu {
    type  = "host"
    cores = 4
  }
  memory {
    dedicated = 4 * 1024
  }
  network_device {
    bridge = "vmbr0"
  }
  disk {
    interface   = "scsi0"
    file_format = "raw"
    iothread    = true
    ssd         = true
    discard     = "on"
    size        = 64
  }
  agent {
    enabled = true
    trim    = true
  }
  # NB we use a custom user data because this terraform provider initialization
  #    block is not entirely compatible with cloudbase-init (the cloud-init
  #    implementation that is used in the windows base image).
  # see https://pve.proxmox.com/wiki/Cloud-Init_Support
  # see https://cloudbase-init.readthedocs.io/en/latest/services.html#openstack-configuration-drive
  # see https://registry.terraform.io/providers/bpg/proxmox/0.68.1/docs/resources/virtual_environment_vm#initialization
  initialization {
    user_data_file_id = proxmox_virtual_environment_file.example_ci_user_data.id
  }
  # NB this can only connect after about 3m15s (because the ssh service in the
  #    windows base image is configured as "delayed start").
  provisioner "file" {
    source      = "provision.ps1"
    destination = "C:/Windows/Temp/provision.ps1"
    connection {
      target_platform = "windows"
      type            = "ssh"
      host            = self.ipv4_addresses[index(self.network_interface_names, "Ethernet")][0]
      user            = var.username
      password        = var.password
    }
  }
  provisioner "remote-exec" {
    connection {
      target_platform = "windows"
      type            = "ssh"
      host            = self.ipv4_addresses[index(self.network_interface_names, "Ethernet")][0]
      user            = var.username
      password        = var.password
    }
    # NB this is executed as a batch script by cmd.exe.
    inline = [
      <<-EOF
      pwsh -File C:/Windows/Temp/provision.ps1
      EOF
    ]
  }
}

output "ip" {
  value = proxmox_virtual_environment_vm.example.ipv4_addresses[index(proxmox_virtual_environment_vm.example.network_interface_names, "Ethernet")][0]
}
