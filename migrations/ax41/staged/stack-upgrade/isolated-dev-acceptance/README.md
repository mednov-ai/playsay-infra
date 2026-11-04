# Staged isolated candidate acceptance fixture

This chart is inactive and is not referenced by an ArgoCD application. It
renders nothing by default and refuses production namespaces and mutable image
references. It is preparation only: it has not been deployed or accepted.

The four containers share a network namespace: the synthetic PostgreSQL 17.11
database listens only on loopback and uses ephemeral container storage; the API
runs its own migrations against that database and uses in-memory material
storage; collaboration calls that API on loopback; the web container serves
the selected candidate image. No shared application database, object-storage
bucket, PVC, public Service or Ingress is configured. A deny-ingress network
policy permits egress only to DEV Keycloak and cluster DNS. The API points all
unneeded service integrations at an unavailable loopback port and disables
background features. It uses the existing DEV identity, LiveKit and RF TURN
credentials only for the requested synthetic lesson; never supply production
credentials. DEV identity sessions and temporary LiveKit rooms are real DEV
state, even though the lesson database and material bytes are synthetic.

Before considering activation: verify the current DEV lesson window and
resource headroom; check that the namespace, NetworkPolicy implementation,
secret key names and Kubernetes port forwarding behave as intended; prove
that the actual pod cannot reach shared databases or other services; and
validate the selected immutable images and full security reports. Ensure the
deny policy is active before any application container starts. The approximate
sum of memory limits is 1.344 GiB, so the earlier observation of approximately
2.3 GiB available alone is insufficient to approve an uninterrupted launch.
Use a separately reviewed DEV-only GitOps change with a bounded removal plan;
the chart alone creates neither an ArgoCD application nor an activation.
At a 2026-11-04 read-only preflight the DEV identity and DNS selectors each
matched one ready pod, all required keys in four referenced Secrets existed, no existing
network policy could select the fixture's label, and kube-router chains were
present. The existing API used 775 MiB and the collaboration pod 33 MiB;
these are point-in-time observations, not proof of enforced isolation or
future capacity.
The fixture uses smaller JVM and Node memory limits than the regular DEV
deployment. An out-of-memory failure in the fixture is a failed test, not
evidence of production behavior.

An enabled chart defaults to `probeOnly: true`: it creates the policy and a
two-hour, no-secret probe Job, not the application. After confirming the
policy is active and the real DEV database and collaboration services are
healthy from outside the policy, execute `probe_inside_fixture.py` inside the
verified probe pod. It must reach DEV identity JWKS while being unable to open
TCP connections to the two healthy shared DEV services. DNS or identity errors,
a reachable shared service, probe expiry or an unknown policy state block the
application stage. Only after retaining that evidence may a separate reviewed
DEV GitOps change set `probeOnly: false` and the exact three image digests.

The browser harness must fail closed: serve web, API and collaboration only
from this fixture, forward DEV authentication and LiveKit only to their real
DEV endpoints, and never silently fall back to the shared DEV API. Validate
both direct and RF routes and bidirectional media with synthetic devices, then
remove only the fixture through GitOps and verify that its pod and temporary
data are gone. A source or health check alone is not lesson acceptance.
The fixture routes web, API and collaboration through its loopback tunnel, so
even a successful RF-media run does not independently validate the public RF
web/API/collaboration ingress or a real RF last mile.

`prepare_smoke.py SOURCE OUTPUT` creates a new isolated copy of the existing
task-owned group smoke without overwriting the source. Set
`STACK_ACCEPTANCE_API_PORT`, `STACK_ACCEPTANCE_WEB_PORT`, and
`STACK_ACCEPTANCE_COLLAB_PORT` to distinct verified loopback forwards, and set
`PLAY_SAY_SMOKE_API_BASE_URL` to `http://127.0.0.1:<api-port>`. The adapter
blocks service workers, requires the isolated API address, routes application
HTTP and collaboration WebSocket traffic to those ports, and blocks unknown
origins. Only DEV identity and DEV LiveKit traffic may leave the browser
directly. Each forward must be tied to the verified fixture pod UID and image
digests; an arbitrary loopback listener is not evidence of isolation.

Local checks: `helm lint .`, `python3 test_fixture.py -v`, and
`node --test router.test.mjs`. PostgreSQL's synthetic bootstrap was separately
exercised with the exact pinned image in a network-isolated disposable local
container. None of these checks proves the full fixture, actual NetworkPolicy,
browser integration, DEV capacity or lesson flow.
