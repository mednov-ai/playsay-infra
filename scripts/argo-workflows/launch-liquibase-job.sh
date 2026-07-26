#!/usr/bin/env bash
set -Eeuo pipefail

: "${MODULE_NAME:?MODULE_NAME is required}"
: "${CHANGELOG_DIR:?CHANGELOG_DIR is required}"
: "${DB_SECRET:?DB_SECRET is required}"
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${MIGRATION_NAMESPACE:=playsay-prod}"

case "${MODULE_NAME}" in
  *[!a-z0-9-]*|"") exit 2 ;;
esac
case "${DB_SECRET}" in
  playsay-app-db|playsay-keyboard-db) ;;
  *) exit 2 ;;
esac
[[ -f "${CHANGELOG_DIR}/db.changelog-master.xml" ]] || exit 2

source_suffix="${SOURCE_SHA:0:8}"
name_suffix="$(printf '%s-%s' "${MODULE_NAME}" "${source_suffix}" | tr -c 'a-z0-9-' '-' | cut -c1-44)"
job_name="playsay-prod-migrate-${name_suffix}"
configmap_name="playsay-prod-migration-${name_suffix}"
manifest_dir="$(mktemp -d /tmp/playsay-migration-manifest.XXXXXX)"
changelog_list="${manifest_dir}/changelog-files"

cleanup() {
  kubectl -n "${MIGRATION_NAMESPACE}" delete job "${job_name}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  kubectl -n "${MIGRATION_NAMESPACE}" delete configmap "${configmap_name}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  rm -rf "${manifest_dir}"
}
trap cleanup EXIT HUP INT TERM
cleanup

find "${CHANGELOG_DIR}" -type f -print | LC_ALL=C sort > "${changelog_list}"
[[ -s "${changelog_list}" ]] || {
  echo "No changelog files found below ${CHANGELOG_DIR}." >&2
  exit 2
}

configmap_args=()
configmap_items='[]'
file_index=0
while IFS= read -r changelog_file; do
  relative_path="${changelog_file#"${CHANGELOG_DIR}"/}"
  file_index="$((file_index + 1))"
  configmap_key="$(printf 'file-%04d' "${file_index}")"
  configmap_args+=("--from-file=${configmap_key}=${changelog_file}")
  configmap_items="$(
    jq -c \
      --arg key "${configmap_key}" \
      --arg path "${CHANGELOG_DIR}/${relative_path}" \
      '. + [{key: $key, path: $path}]' <<<"${configmap_items}"
  )"
done < "${changelog_list}"

kubectl -n "${MIGRATION_NAMESPACE}" create configmap "${configmap_name}" "${configmap_args[@]}" >/dev/null

jq -n \
  --arg namespace "${MIGRATION_NAMESPACE}" \
  --arg jobName "${job_name}" \
  --arg configMapName "${configmap_name}" \
  --arg dbSecret "${DB_SECRET}" \
  --arg moduleName "${MODULE_NAME}" \
  --arg sourceSha "${SOURCE_SHA}" \
  --argjson configMapItems "${configmap_items}" \
  '{
    apiVersion: "batch/v1",
    kind: "Job",
    metadata: {
      namespace: $namespace,
      name: $jobName,
      labels: {
        "app.kubernetes.io/name": "playsay-db-migration",
        "app.kubernetes.io/component": $moduleName,
        "app.kubernetes.io/managed-by": "argo-workflows",
        "playsay.io/source-sha": $sourceSha
      }
    },
    spec: {
      backoffLimit: 0,
      activeDeadlineSeconds: 600,
      ttlSecondsAfterFinished: 3600,
      template: {
        metadata: {
          labels: {
            "app.kubernetes.io/name": "playsay-db-migration",
            "app.kubernetes.io/component": $moduleName
          }
        },
        spec: {
          automountServiceAccountToken: false,
          restartPolicy: "Never",
          securityContext: {fsGroup: 1000, fsGroupChangePolicy: "OnRootMismatch"},
          initContainers: [{
            name: "postgresql-driver",
            image: "curlimages/curl:8.12.1",
            command: ["/bin/sh", "-ec"],
            args: ["cp -RL /changelog-source/backend /changelog/ && curl -fsSL https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.8/postgresql-42.7.8.jar -o /driver/postgresql.jar"],
            volumeMounts: [
              {name: "changelog-source", mountPath: "/changelog-source", readOnly: true},
              {name: "changelog", mountPath: "/changelog"},
              {name: "driver", mountPath: "/driver"}
            ],
            resources: {requests: {cpu: "10m", memory: "16Mi"}, limits: {cpu: "100m", memory: "64Mi"}},
            securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          }],
          containers: [{
            name: "liquibase",
            image: "liquibase/liquibase:5.0.3",
            command: ["/bin/sh", "/runner/run.sh"],
            env: [
              {name: "PLAYSAY_DB_JDBC_URL", valueFrom: {secretKeyRef: {name: $dbSecret, key: "jdbc-uri"}}},
              {name: "PLAYSAY_DB_USERNAME", valueFrom: {secretKeyRef: {name: $dbSecret, key: "username"}}},
              {name: "PLAYSAY_DB_PASSWORD", valueFrom: {secretKeyRef: {name: $dbSecret, key: "password"}}}
            ],
            volumeMounts: [
              {name: "runner", mountPath: "/runner", readOnly: true},
              {name: "changelog", mountPath: "/liquibase/changelog", readOnly: true},
              {name: "driver", mountPath: "/liquibase/lib/postgresql.jar", subPath: "postgresql.jar", readOnly: true}
            ],
            resources: {requests: {cpu: "50m", memory: "128Mi"}, limits: {cpu: "500m", memory: "512Mi"}},
            securityContext: {runAsUser: 1000, runAsGroup: 0, allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
          }],
          volumes: [
            {name: "runner", configMap: {name: "playsay-prod-liquibase-runner", defaultMode: 365}},
            {name: "changelog-source", configMap: {name: $configMapName, items: $configMapItems}},
            {name: "changelog", emptyDir: {}},
            {name: "driver", emptyDir: {}}
          ]
        }
      }
    }
  }' | kubectl create -f - >/dev/null

echo "Running ${MODULE_NAME} production migration as Job ${job_name}."
deadline="$(( $(date +%s) + 660 ))"
while [[ "$(date +%s)" -lt "${deadline}" ]]; do
  succeeded="$(kubectl -n "${MIGRATION_NAMESPACE}" get job "${job_name}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  failed="$(kubectl -n "${MIGRATION_NAMESPACE}" get job "${job_name}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  if [[ "${succeeded:-0}" -ge 1 ]]; then
    echo "${MODULE_NAME} database migration completed."
    exit 0
  fi
  if [[ "${failed:-0}" -ge 1 ]]; then
    kubectl -n "${MIGRATION_NAMESPACE}" logs "job/${job_name}" -c liquibase || true
    echo "${MODULE_NAME} database migration failed." >&2
    exit 1
  fi
  sleep 5
done

kubectl -n "${MIGRATION_NAMESPACE}" describe job "${job_name}" || true
echo "Timed out waiting for ${MODULE_NAME} database migration." >&2
exit 1
