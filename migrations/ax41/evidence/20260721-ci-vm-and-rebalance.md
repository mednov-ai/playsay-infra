# AX41 CI VM and guest rebalance evidence — 2026-07-21

Applied infra commit: `17ce57cd4a029e9bee72761fb982a2f6fd599781` on branch `codex/separate-jenkins-ci`.

## Safety and plans

- The first platform plan attempted to replace `playsay-workloads` when adding a DHCP host and was rejected without apply.
- The corrected design assigns `10.60.0.40/24` to the new guest through cloud-init; the second platform plan was clean with no changes.
- Dev plan: one in-place domain update, memory `12288 -> 10240` MiB, no create/destroy/replace.
- Prod plan: one in-place domain update, memory `43008 -> 38912` MiB, no create/destroy/replace.
- CI plan: five creates, no update/destroy/replace.
- Pre-apply encrypted states `playsay-tofu-dev-20260721T063237Z` and `playsay-tofu-prod-20260721T063238Z` were copied off AX41 and passed transport, decrypt, payload and JSON checks.
- Post-apply encrypted states `playsay-tofu-dev-20260721T064051Z`, `playsay-tofu-prod-20260721T064052Z` and `playsay-tofu-ci-20260721T064052Z` were copied off AX41 and passed the same verification.

Encrypted files are stored outside Git under `/Users/evgeniymednov/Backups/PlayAndSay/opentofu-state`; the RSA private key remains separate under the operator's SSH directory.

## Result

- `playsay-dev`: 2 vCPU, 10240 MiB, autostart; guest reports about 9.7 GiB total and about 5.0 GiB available after restart. Node Ready and all 19 ArgoCD applications Synced/Healthy.
- `playsay-prod`: 8 vCPU, 38912 MiB, autostart; guest reports about 37 GiB total and about 35 GiB available after restart. Node Ready and all 15 ArgoCD applications Synced/Healthy.
- `playsay-ci`: UUID `79262faf-1ced-40e0-b945-8e99ded7e791`, 2 vCPU, 8192 MiB, 100 GiB disk, I/O weight 150, autostart and static `10.60.0.40/24`.
- CI cloud-init completed, root filesystem grew to about 96 GiB, 2 GiB swap is active, qemu guest agent and k3s are active, and `playsay-ci` is Ready on k3s `v1.35.5+k3s1` with pod/service CIDRs `10.46.0.0/16` and `10.47.0.0/16`.
- CI contains only the base k3s system workloads; no product application, ArgoCD or migrated Jenkins PVC/history was installed.
