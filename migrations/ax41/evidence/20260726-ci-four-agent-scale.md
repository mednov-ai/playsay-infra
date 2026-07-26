# AX41 Jenkins four-agent scale evidence — 2026-07-26

## Change and safety

- Infra configuration commit `e2f6fe1` changed only `playsay-ci` from 2 to 4 vCPU and raised Jenkins Kubernetes cloud `containerCap`/`instanceCap` from 1 to 4. Guest memory remained fixed at 8192 MiB.
- OpenTofu plan SHA-256: `20eff7809abacac14307870159a83b309d8aa0e9d1689e602f791ef65ff48013`.
- The reviewed plan contained exactly one in-place update, `module.ci.libvirt_domain.vm` vCPU `2 -> 4`, with no create, destroy or replacement.
- Pre-apply encrypted off-host state `playsay-tofu-ci-pre4-20260726T162351Z` was transport-, decrypt-, payload- and JSON-verified at state serial 1.
- Apply result: `0 added, 1 changed, 0 destroyed`; domain UUID remained `79262faf-1ced-40e0-b945-8e99ded7e791`, memory remained 8192 MiB and state advanced to serial 2.
- Post-apply encrypted off-host state `playsay-tofu-ci-post4-20260726T181035Z` passed the same verification at serial 2.

The libvirt in-place update rebooted only `playsay-ci`. Prod and dev guests were not restarted. After recovery the guest and Kubernetes node both reported 4 allocatable CPUs, no pressure conditions and Jenkins returned `2/2 Running`.

## Jenkins rollout

- CI checked out infra `develop` commit `254b347`, which contains the scale commit plus subsequent dev image promotions.
- Jenkins Helm revision 5 rendered and loaded `containerCapStr: "4"` and `instanceCap: 4`.
- The dispatcher job XML exposed `MAX_PARALLEL_MODULE_JOBS` range `1..4` with default `4`.
- Dispatcher #28 was aborted before maintenance. Its parent and active downstream builds were terminated, the queue drained and the remaining orphan registration agent pod was deleted. No unrelated Jenkins job was stopped.

## Four-agent acceptance

Dispatcher #29 used platform source `c9aa97157e3fad27b8cccf0c5ff085aab272d01f`, `MAX_PARALLEL_MODULE_JOBS=4` and a controlled four-target override:

- collaboration #17: `SUCCESS`, 155.154 seconds;
- media #20: `SUCCESS`, 209.516 seconds;
- keyboard frontend #66: `SUCCESS`, 204.950 seconds;
- keyboard backend #28: `SUCCESS`, 280.785 seconds;
- dispatcher #29: `SUCCESS`, 341.993 seconds total.

All four Kubernetes agent pods were simultaneously `Running` and ready. Observed CI load1 peaked around `4.39` on four vCPUs, sampled `MemAvailable` stayed at or above approximately 3756 MiB, swap remained zero during the batch, and there were no OOM, eviction or node-pressure events. The AX41 host retained approximately 37 GiB `MemAvailable` in the sampled load window. Prod remained node Ready with all 15 ArgoCD applications `Synced/Healthy` and zero unready pods; dev remained Ready with all 18 applications `Synced/Healthy`. `honey.school`, `online.honey.school`, `key.honey.school` and `dev.online.honey.school` returned HTTP 200.

An unintended duplicate control dispatcher #30 was enqueued when an operator client retried after its first command returned a local syntax error after the Jenkins POST had already succeeded. It had `GITHUB_BEFORE == GITHUB_AFTER` and the same explicit four-target `FORCE_TARGETS`; it was not triggered by an additional source change. The duplicate also completed `SUCCESS` before the cancellation check, and no further dispatcher remained active.

## Active allocation and rollback

| Guest | vCPU | Fixed memory |
|---|---:|---:|
| `playsay-prod` | 8 | 38 GiB |
| `playsay-dev` | 2 | 10 GiB |
| `playsay-ci` | 4 | 8 GiB |
| Total guests | 14 | 56 GiB |

The AX41 has 12 logical CPUs and approximately 62 GiB usable RAM. Guest CPU is therefore overcommitted by two vCPUs (`14/12`, about `1.17x`) without pinning; no host CPU is reserved as a free pinned core. Fixed guest memory leaves approximately 6 GiB unassigned to guests for the host.

Keep the four-agent ceiling. Eight agents are not accepted on the current 4-vCPU/8-GiB CI VM: they would create 2:1 build CPU contention and can exceed the safe memory envelope. Reduce dispatcher fan-out to `1` or `2` if CI reports an OOM kill, sustained swap growth, `MemAvailable` below 1 GiB, node pressure, or production readiness/latency degradation.
