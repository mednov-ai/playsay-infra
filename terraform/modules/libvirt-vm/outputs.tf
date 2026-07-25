output "domain_name" {
  value = libvirt_domain.vm.name
}

output "domain_uuid" {
  value = libvirt_domain.vm.uuid
}

output "root_volume_path" {
  value = libvirt_volume.root.path
}
