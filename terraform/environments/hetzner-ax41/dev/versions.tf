terraform {
  required_version = ">= 1.12.0, < 1.13.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.9.8"
    }
  }

  # Temporary single-operator backend for the accelerated first cutover.
  # Migrate it to the versioned S3 backend after service stabilization.
  backend "local" {
    path = "/var/lib/playsay-opentofu-state/dev/terraform.tfstate"
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
