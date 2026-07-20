variable "name" {
  description = "Unique libvirt domain name."
  type        = string
}

variable "hostname" {
  description = "Guest hostname configured by cloud-init."
  type        = string
}

variable "vcpu" {
  description = "Number of virtual CPUs."
  type        = number

  validation {
    condition     = var.vcpu >= 1 && var.vcpu <= 10
    error_message = "vCPU must be between 1 and 10."
  }
}

variable "memory_mib" {
  description = "Fixed guest memory in MiB; ballooning is intentionally not configured."
  type        = number

  validation {
    condition     = var.memory_mib >= 4096 && var.memory_mib <= 43008
    error_message = "Guest memory must be between 4 GiB and 42 GiB."
  }
}

variable "disk_gib" {
  description = "Maximum virtual root-disk capacity in GiB."
  type        = number
}

variable "pool_name" {
  description = "Existing libvirt storage pool managed by the platform state."
  type        = string
}

variable "network_name" {
  description = "Existing isolated libvirt network managed by the platform state."
  type        = string
}

variable "mac_address" {
  description = "Stable MAC address matching the platform DHCP reservation."
  type        = string

  validation {
    condition     = can(regex("^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$", var.mac_address))
    error_message = "mac_address must be a colon-separated MAC address."
  }
}

variable "admin_ssh_public_key" {
  description = "Public SSH key installed for the playsay administrator."
  type        = string
}

variable "ubuntu_image_url" {
  description = "Pinned Ubuntu 24.04 cloud-image URL."
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "io_weight" {
  description = "Relative libvirt block I/O weight; prod must be higher than dev."
  type        = number
  default     = 500

  validation {
    condition     = var.io_weight >= 100 && var.io_weight <= 1000
    error_message = "io_weight must be between 100 and 1000."
  }
}
