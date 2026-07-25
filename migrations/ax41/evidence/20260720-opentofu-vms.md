# AX41 OpenTofu network and VM evidence — 2026-07-20 UTC

Target: `65.109.55.110` (Hetzner AX41). OpenTofu executed locally on the host as the named `playsay` operator with separate permission-restricted state roots.

## Applied topology

- `playsay-workloads`: libvirt NAT network, bridge `virbr60`, subnet `10.60.0.0/24`.
- `playsay-prod`: `10.60.0.20`, 8 vCPU, 42 GiB RAM, 200-GiB qcow2, I/O weight 900, autostart enabled.
- `playsay-dev`: `10.60.0.30`, 2 vCPU, 12 GiB RAM, 120-GiB qcow2, I/O weight 300, autostart enabled.
- Both guests boot Ubuntu 24.04, accept only the reviewed SSH key, report a healthy QEMU guest agent and complete cloud-init without errors.

## Reviewed applies

- Platform foundation plan: 2 creates, no change/destroy; plan SHA-256 `95650788520e260acd9455365b45ac898b8034e00cc5bdbb0ca6af29133b4ac5`.
- Prod recovery plan after the provider ISO-format correction: 1 create, no change/destroy; commit `ec8b402`, plan SHA-256 `c027fb8caf571d1312482fce3188e05156b8122730c77c37241747d3874953ad`.
- Dev plan: 4 creates, no change/destroy; commit `ec8b402`, plan SHA-256 `5ec8f99423ccb200b0065b473778fced0ad646343fdac88ce0c4df81b57c35c6`.
- NAT correction: one deliberate replacement of the still-empty libvirt network while both guests were shut down; commit `f31978c`, plan SHA-256 `ae6fc22d467738ddd7c448c7f9352eb8c7c222e3d3b55d32ceeab08492465881`. Both guests restarted with their fixed addresses.

The first prod apply exposed that libvirt reports cloud-init media as ISO while provider 0.9.8 rejected a requested `raw` format. No domain had been created. The partial state was encrypted and verified off-host, the format declaration was corrected in Git, the taint was reconciled, and a new no-destroy plan was applied. The first boot then exposed the missing NAT declaration; this was corrected in Git before any cluster or application data existed.

## State and bootstrap verification

- Latest verified off-host encrypted states: `playsay-tofu-platform-20260720T212851Z`, `playsay-tofu-prod-20260720T212530Z`, and `playsay-tofu-dev-20260720T212549Z`.
- Every transport checksum, decrypted payload checksum and state/manifest JSON validation passed. Plaintext state remains only in the protected AX41 local-state directories; the RSA private key never entered the server.
- Both guests resolved Ubuntu repositories and reached them over HTTPS through libvirt NAT.
- Cloud-init was cleanly replayed after NAT correction. Both guests report `status: done`, no cloud-init errors, active `qemu-guest-agent`, no failed systemd units and the expected CPU/RAM allocation.
- Public firewall exposure did not change: administrative access remains SSH plus WireGuard while Cockpit stays VPN-only; workload HTTP/HTTPS cutover has not occurred at this evidence point.
