resource "libvirt_pool" "playsay" {
  name = "playsay"
  type = "dir"

  target = {
    path = "/var/lib/libvirt/playsay"
    permissions = {
      mode = "0711"
    }
  }
}

resource "libvirt_network" "workloads" {
  name      = "playsay-workloads"
  autostart = true

  forward = {
    mode = "nat"
  }

  bridge = {
    name  = "virbr60"
    stp   = "on"
    delay = "0"
  }

  domain = {
    name       = "playsay.internal"
    local_only = "yes"
  }

  dns = {
    enable = "yes"
  }

  ips = [
    {
      family  = "ipv4"
      address = "10.60.0.1"
      prefix  = 24
      dhcp = {
        ranges = [
          {
            start = "10.60.0.100"
            end   = "10.60.0.199"
          }
        ]
        hosts = [
          {
            name = "playsay-prod"
            mac  = "52:54:00:60:00:20"
            ip   = "10.60.0.20"
          },
          {
            name = "playsay-dev"
            mac  = "52:54:00:60:00:30"
            ip   = "10.60.0.30"
          }
        ]
      }
    }
  ]
}
