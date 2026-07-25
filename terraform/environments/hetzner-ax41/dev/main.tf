module "dev" {
  source = "../../../modules/libvirt-vm"

  name                 = "playsay-dev"
  hostname             = "playsay-dev"
  vcpu                 = 2
  memory_mib           = 10240
  disk_gib             = 120
  pool_name            = "playsay"
  network_name         = "playsay-workloads"
  mac_address          = "52:54:00:60:00:30"
  io_weight            = 300
  admin_ssh_public_key = var.admin_ssh_public_key
}

output "domain_uuid" {
  value = module.dev.domain_uuid
}
