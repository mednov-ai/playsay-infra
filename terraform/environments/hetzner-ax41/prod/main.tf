module "prod" {
  source = "../../../modules/libvirt-vm"

  name                 = "playsay-prod"
  hostname             = "playsay-prod"
  vcpu                 = 8
  memory_mib           = 43008
  disk_gib             = 200
  pool_name            = "playsay"
  network_name         = "playsay-workloads"
  mac_address          = "52:54:00:60:00:20"
  io_weight            = 900
  admin_ssh_public_key = var.admin_ssh_public_key
}

output "domain_uuid" {
  value = module.prod.domain_uuid
}
