output "pool_name" {
  value = libvirt_pool.playsay.name
}

output "network_name" {
  value = libvirt_network.workloads.name
}

output "bridge_name" {
  value = libvirt_network.workloads.bridge.name
}
