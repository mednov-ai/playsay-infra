# Terraform

Terraform/OpenTofu automation starts after Sprint 0 manual VPS creation is proven.

For Sprint 0 the server lifecycle is human-owned and Ansible starts from a filled inventory.

The target is three OpenTofu-managed KVM/libvirt guests on the provisioned Hetzner AX41: product `dev`, product `prod` and dedicated `ci`, plus a separate `platform` state for their shared network and storage pool. Ubuntu host bootstrap, mdadm RAID1 and host networking remain human/Ansible-owned. The reviewed `dmacvicar/libvirt` 0.9.x provider runs locally on the host through `qemu:///system`; its current line does not support remote libvirt connections. The detailed resource, state, networking and safety contract is in [../docs/hetzner-ax41-dev-prod-plan.md](../docs/hetzner-ax41-dev-prod-plan.md), with the active CI/domain checklist in [../../specs/ax41-ci-migration.md](../../specs/ax41-ci-migration.md).

All OpenTofu configuration and provider lock files are committed. State, plans containing sensitive values and backend credentials are never committed.

For the accelerated first `honey.school` cutover, OpenTofu runs only as the named `playsay` operator on the AX41 and uses four permission-restricted local states under `/var/lib/playsay-opentofu-state/{platform,dev,prod,ci}`. No Jenkins apply or second operator is allowed in this temporary mode. Before and after every apply, copy an encrypted state snapshot off the AX41 and record the Git commit plus plan checksum. After the first production stabilization window, migrate all four states to the planned versioned/locked encrypted S3 backend with `tofu init -migrate-state`; the checked-in `backend.s3.tfbackend.example` files remain the migration templates.

OpenTofu is retained as the authoritative change path even when operators prefer a graphical interface. Cockpit Machines provides the VPN-only visual view of the AX41 host and libvirt guests, while pull requests and Jenkins expose formatting, validation and plan results before an explicitly approved apply. Cockpit may be used for inventory, metrics, console and routine VM power actions, but VM topology, resources, storage and networking are changed only in Git/OpenTofu. Production apply is never automatic on merge, and a scheduled read-only plan detects out-of-band drift.
