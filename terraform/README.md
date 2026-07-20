# Terraform

Terraform/OpenTofu automation starts after Sprint 0 manual VPS creation is proven.

For Sprint 0 the server lifecycle is human-owned and Ansible starts from a filled inventory.

The next planned target is two OpenTofu-managed KVM/libvirt guests on the provisioned Hetzner AX41: separate platform, dev and prod states, while Ubuntu host bootstrap, mdadm RAID1 and networking remain human/Ansible-owned. The reviewed `dmacvicar/libvirt` 0.9.x provider runs locally on the host through `qemu:///system`; its current line does not support remote libvirt connections. The detailed resource, state, networking and safety contract is in [../docs/hetzner-ax41-dev-prod-plan.md](../docs/hetzner-ax41-dev-prod-plan.md).

All OpenTofu configuration and provider lock files are committed. State, plans containing sensitive values and backend credentials are never committed; the versioned encrypted remote state plus the recorded Git commit are the reproducibility boundary.

OpenTofu is retained as the authoritative change path even when operators prefer a graphical interface. Cockpit Machines provides the VPN-only visual view of the AX41 host and libvirt guests, while pull requests and Jenkins expose formatting, validation and plan results before an explicitly approved apply. Cockpit may be used for inventory, metrics, console and routine VM power actions, but VM topology, resources, storage and networking are changed only in Git/OpenTofu. Production apply is never automatic on merge, and a scheduled read-only plan detects out-of-band drift.
