locals {
  root_disk_bytes = var.disk_gib * 1024 * 1024 * 1024
}

resource "libvirt_volume" "root" {
  name     = "${var.name}-root.qcow2"
  pool     = var.pool_name
  capacity = local.root_disk_bytes

  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Provider 0.9.8 imports the cloud image at its source virtual size and does
# not honor a larger capacity in the same create request. Keep the required
# post-import grow operation in the OpenTofu graph before the domain starts.
resource "terraform_data" "root_volume_capacity" {
  triggers_replace = [
    libvirt_volume.root.id,
    tostring(local.root_disk_bytes),
  ]

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      current_bytes="$(virsh vol-info --pool '${var.pool_name}' --bytes '${libvirt_volume.root.name}' | awk '$1 == "Capacity:" {print $2}')"
      target_bytes='${local.root_disk_bytes}'
      if (( current_bytes < target_bytes )); then
        virsh vol-resize --pool '${var.pool_name}' '${libvirt_volume.root.name}' "${local.root_disk_bytes}B"
      elif (( current_bytes > target_bytes )); then
        echo "Refusing to shrink ${libvirt_volume.root.name} from $current_bytes to $target_bytes bytes" >&2
        exit 1
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

resource "libvirt_cloudinit_disk" "config" {
  name = "${var.name}-cloud-init"
  user_data = templatefile("${path.module}/cloud-init.tftpl", {
    hostname             = var.hostname
    admin_ssh_public_key = trimspace(var.admin_ssh_public_key)
  })
  meta_data = yamlencode({
    instance-id    = var.name
    local-hostname = var.hostname
  })
}

resource "libvirt_volume" "cloud_init" {
  name = "${var.name}-cloud-init.iso"
  pool = var.pool_name

  create = {
    content = {
      url = libvirt_cloudinit_disk.config.path
    }
  }

  target = {
    format = {
      # libvirt reports cloud-init media as ISO. Declaring raw makes provider
      # 0.9.8 return an inconsistent post-apply value after creating it.
      type = "iso"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "libvirt_domain" "vm" {
  name        = var.name
  description = "Git/OpenTofu managed Play&Say guest; do not resize in Cockpit"
  type        = "kvm"
  running     = true
  autostart   = true
  memory      = var.memory_mib
  memory_unit = "MiB"
  vcpu        = var.vcpu

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  block_io_tune = {
    weight = var.io_weight
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.root_volume_capacity]

  devices = {
    disks = [
      {
        device = "disk"
        driver = {
          name    = "qemu"
          type    = "qcow2"
          discard = "unmap"
        }
        source = {
          file = {
            file = libvirt_volume.root.path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device    = "cdrom"
        read_only = true
        source = {
          file = {
            file = libvirt_volume.cloud_init.path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        mac = {
          address = var.mac_address
        }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = var.network_name
          }
        }
      }
    ]

    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}
