module "ci" {
  source = "../../../modules/libvirt-vm"

  name                 = "playsay-ci"
  hostname             = "playsay-ci"
  vcpu                 = 2
  memory_mib           = 8192
  disk_gib             = 100
  pool_name            = "playsay"
  network_name         = "playsay-workloads"
  mac_address          = "52:54:00:60:00:40"
  io_weight            = 150
  admin_ssh_public_key = var.admin_ssh_public_key
}

output "domain_uuid" {
  value = module.ci.domain_uuid
}
