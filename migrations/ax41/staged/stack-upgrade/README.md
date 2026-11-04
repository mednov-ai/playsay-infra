# DEV stack-upgrade staging

These files are deliberately outside `argocd-apps/dev/apps` and are not
referenced by the active DEV applications. Merging this preparation does not
create the Keycloak import cluster or restart the application database.

After the runbook's candidate security, backup, restore, admission and drain
gates pass, activate each change through its own reviewed GitOps commit in the
documented order. The Keycloak import must start only after Keycloak and all
other database writers have stopped. Preserve the source database and PVC;
after the new database receives writes, reverting to the source would lose
those writes. Recheck the current remote and deployed configuration before
activation.

`app-postgres-values-dev.yaml` is a Helm override for rendering the proposed
application database image; it does not by itself alter ArgoCD. The staged
Application points at the DEV-only identity import chart. Both use the exact
PostgreSQL image digest reviewed in the accompanying security evidence, which
is currently blocked by unresolved findings. The previous isolated import
fixture used the corresponding tag; verify this digest-pinned operator path
before cutover. LiveKit's active DEV image must be updated only to the exact
successfully scanned and published rebuilt image, never to an unscanned tag.
