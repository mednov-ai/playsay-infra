terraform {
  required_version = ">= 1.12.0, < 1.13.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.9.8"
    }
  }
}
