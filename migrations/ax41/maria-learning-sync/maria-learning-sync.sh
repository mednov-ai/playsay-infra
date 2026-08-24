#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bundle_tool="$script_dir/bundle_tool.py"
export_template="$script_dir/export.sql.in"
apply_template="$script_dir/apply.sql.in"

usage() {
  cat <<'EOF'
Usage:
  maria-learning-sync.sh export --source-environment vdsina|dev --target-environment dev|prod
    --pg-service NAME --maria-subject-file PATH
    --s3-alias NAME --s3-bucket NAME --public-key PATH --output-dir PATH
    --platform-commit SHA --infra-commit SHA

  maria-learning-sync.sh verify-bundle --bundle PATH --encrypted-key PATH
    --private-key PATH [--transport-checksums PATH]

  maria-learning-sync.sh plan --environment dev|prod --pg-service NAME
    --bundle PATH --encrypted-key PATH --private-key PATH
    --target-subjects-file PATH [--output PATH]

  maria-learning-sync.sh apply --environment dev|prod --pg-service NAME
    --s3-alias NAME --s3-bucket NAME --bundle PATH --encrypted-key PATH
    --private-key PATH --target-subjects-file PATH --backup-dir PATH
    --backup-public-key PATH --maintenance-guard-command PATH
    --confirm-manifest-sha256 SHA256
    [--operator-production-approval]

  maria-learning-sync.sh verify-target --environment dev|prod --pg-service NAME
    --s3-alias NAME --s3-bucket NAME --bundle PATH --encrypted-key PATH
    --private-key PATH --target-subjects-file PATH

  maria-learning-sync.sh rollback --environment dev|prod --pg-service NAME
    --s3-alias NAME --s3-bucket NAME --backup-dir PATH
    --private-key PATH --maintenance-guard-command PATH --confirm-backup-id ID
    [--operator-production-approval]

Database credentials must come from a libpq service; S3 credentials must come
from an existing MinIO Client alias. No credential-bearing URLs are accepted.
Use the fixed Python route entrypoints instead of invoking this internal driver directly.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || die "required file is missing: $1"; }
require_dir() { [[ -d "$1" ]] || die "required directory is missing: $1"; }
require_value() { [[ -n "$2" ]] || die "$1 is required"; }

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

check_common_tools() {
  local command_name
  for command_name in python3 jq openssl tar gzip mktemp sed sort comm psql pg_dump pg_restore mc xxd; do
    command -v "$command_name" >/dev/null 2>&1 || die "missing command: $command_name"
  done
}

safe_name() {
  [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]] || die "unsafe name: $1"
}

validate_subject_file() {
  require_file "$1"
  [[ "$(wc -l <"$1" | tr -d ' ')" -le 1 ]] || die "subject file must contain exactly one line"
  local subject
  subject="$(tr -d '\r\n' <"$1")"
  [[ -n "$subject" && ${#subject} -le 255 ]] || die "subject file is empty or invalid"
}

validate_subject_inventory() {
  local payload="$1"
  local inventory="$2"
  require_file "$inventory"
  local work missing_count
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-subject-check.XXXXXX")"
  sort -u "$payload/cohort-subjects.txt" >"$work/source"
  tr -d '\r' <"$inventory" | sed '/^$/d' | sort -u >"$work/target"
  missing_count="$(comm -23 "$work/source" "$work/target" | wc -l | tr -d ' ')"
  rm -rf -- "$work"
  [[ "$missing_count" == "0" ]] || die "$missing_count required cohort identities are absent from target Keycloak inventory"
}

render_export_sql() {
  local output_dir="$1"
  local maria_subject_file="$2"
  local rendered="$3"
  [[ "$output_dir" != *'|'* && "$maria_subject_file" != *'|'* ]] || die "unsafe temporary path"
  sed -e "s|__OUTPUT_DIR__|$output_dir|g" \
      -e "s|__MARIA_SUBJECT_FILE__|$maria_subject_file|g" \
      "$export_template" >"$rendered"
}

extract_database_scope() {
  local pg_service="$1"
  local maria_subject_file="$2"
  local output_dir="$3"
  local cutoff="$4"
  mkdir -p "$output_dir/tables"
  local rendered="$output_dir/export.sql"
  render_export_sql "$output_dir" "$maria_subject_file" "$rendered"
  # The export SQL writes only session-local temporary tables. PostgreSQL rejects
  # CREATE TEMP TABLE AS when default_transaction_read_only is forced at session
  # level, so consistency is provided by the explicit transaction in the template
  # plus the externally verified source write freeze.
  PGSERVICE="$pg_service" psql -X --no-psqlrc -v ON_ERROR_STOP=1 -f "$rendered" >/dev/null
  rm -f -- "$rendered"
  python3 "$bundle_tool" normalize-reminders \
    --file "$output_dir/tables/lesson_email_reminder.csv" --cutoff "$cutoff"
  python3 "$bundle_tool" build-objects \
    --keys "$output_dir/object-keys.tsv" --output "$output_dir/objects-selection.json"
}

decrypt_bundle() {
  local bundle="$1"
  local encrypted_key="$2"
  local private_key="$3"
  local output_dir="$4"
  local transport_checksums="${5:-}"
  require_file "$bundle"
  require_file "$encrypted_key"
  require_file "$private_key"
  if [[ -n "$transport_checksums" ]]; then
    require_file "$transport_checksums"
    (cd "$(dirname "$transport_checksums")" && shasum -a 256 -c "$(basename "$transport_checksums")" >/dev/null)
  fi
  mkdir -p "$output_dir/payload"
  openssl pkeyutl -decrypt -inkey "$private_key" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
    -in "$encrypted_key" -out "$output_dir/data-key.txt"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
    -pass "file:$output_dir/data-key.txt" -in "$bundle" -out "$output_dir/payload.tar.gz"
  gzip -t "$output_dir/payload.tar.gz"
  tar -tzf "$output_dir/payload.tar.gz" >/dev/null
  tar -xzf "$output_dir/payload.tar.gz" -C "$output_dir/payload"
  (cd "$output_dir/payload" && shasum -a 256 -c PAYLOAD_SHA256SUMS >/dev/null)
  python3 "$bundle_tool" validate --payload "$output_dir/payload" >/dev/null
}

copy_selected_objects_from_s3() {
  local payload="$1"
  local alias_name="$2"
  local bucket="$3"
  mkdir -p "$payload/objects"
  local key_hex relative_file key
  while IFS=$'\t' read -r key_hex relative_file; do
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc cp --quiet "$alias_name/$bucket/$key" "$payload/$relative_file" >/dev/null
  done < <(jq -r '.[] | [.keyHex, .file] | @tsv' "$payload/objects-selection.json")
}

verify_selected_objects_on_s3() {
  local payload="$1"
  local alias_name="$2"
  local bucket="$3"
  local key_hex relative_file expected key local_tmp
  local_tmp="$(mktemp -d "${TMPDIR:-/tmp}/playsay-object-verify.XXXXXX")"
  while IFS=$'\t' read -r key_hex relative_file expected; do
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc cp --quiet "$alias_name/$bucket/$key" "$local_tmp/object" >/dev/null
    [[ "$(sha256_file "$local_tmp/object")" == "$expected" ]] || {
      rm -rf -- "$local_tmp"
      die "target object checksum mismatch"
    }
    rm -f -- "$local_tmp/object"
  done < <(jq -r '.objects[] | [.keyHex, .file, .sha256] | @tsv' "$payload/manifest.json")
  rm -rf -- "$local_tmp"
}

backup_touched_objects() {
  local source_payload="$1"
  local target_scope="$2"
  local alias_name="$3"
  local bucket="$4"
  local backup_dir="$5"
  mkdir -p "$backup_dir/objects"
  jq -s 'add | unique_by(.keySha256)' \
    "$source_payload/objects-selection.json" "$target_scope/objects-selection.json" \
    >"$backup_dir/touched-objects.json"
  : >"$backup_dir/present-objects.tsv"
  : >"$backup_dir/absent-objects.tsv"
  local key_hex key_sha key
  while IFS=$'\t' read -r key_hex key_sha; do
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    if mc stat "$alias_name/$bucket/$key" >/dev/null 2>&1; then
      mc cp --quiet "$alias_name/$bucket/$key" "$backup_dir/objects/$key_sha" >/dev/null
      printf '%s\t%s\n' "$key_hex" "$key_sha" >>"$backup_dir/present-objects.tsv"
    else
      printf '%s\t%s\n' "$key_hex" "$key_sha" >>"$backup_dir/absent-objects.tsv"
    fi
  done < <(jq -r '.[] | [.keyHex, .keySha256] | @tsv' "$backup_dir/touched-objects.json")
  (
    cd "$backup_dir"
    find objects -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done >OBJECT_SHA256SUMS
  )
}

restore_objects() {
  local backup_dir="$1"
  local alias_name="$2"
  local bucket="$3"
  local key_hex key_sha key
  if [[ -s "$backup_dir/OBJECT_SHA256SUMS" ]]; then
    (cd "$backup_dir" && shasum -a 256 -c OBJECT_SHA256SUMS >/dev/null)
  fi
  while IFS=$'\t' read -r key_hex key_sha; do
    [[ -n "$key_hex" ]] || continue
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc cp --quiet "$backup_dir/objects/$key_sha" "$alias_name/$bucket/$key" >/dev/null
  done <"$backup_dir/present-objects.tsv"
  while IFS=$'\t' read -r key_hex key_sha; do
    [[ -n "$key_hex" ]] || continue
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc rm --force "$alias_name/$bucket/$key" >/dev/null 2>&1 || true
  done <"$backup_dir/absent-objects.tsv"
}

write_source_objects() {
  local payload="$1"
  local alias_name="$2"
  local bucket="$3"
  local key_hex relative_file key
  while IFS=$'\t' read -r key_hex relative_file; do
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc cp --quiet "$payload/$relative_file" "$alias_name/$bucket/$key" >/dev/null
  done < <(jq -r '.objects[] | [.keyHex, .file] | @tsv' "$payload/manifest.json")
}

delete_target_only_objects() {
  local source_payload="$1"
  local target_scope="$2"
  local alias_name="$3"
  local bucket="$4"
  local work key_hex key
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-object-delete.XXXXXX")"
  jq -r '.[].keySha256' "$source_payload/objects-selection.json" | sort -u >"$work/source"
  jq -r '.[] | select(([.sourceKinds[]?] | any(. == "MATERIAL_ASSET" or . == "YOUTUBE_CACHE")) | not) | [.keySha256,.keyHex] | @tsv' \
    "$target_scope/objects-selection.json" | sort -u >"$work/target"
  while IFS=$'\t' read -r key_sha key_hex; do
    grep -qx "$key_sha" "$work/source" && continue
    key="$(printf '%s' "$key_hex" | xxd -r -p)"
    mc rm --force "$alias_name/$bucket/$key" >/dev/null
  done <"$work/target"
  rm -rf -- "$work"
}

restore_database() {
  local pg_service="$1"
  local dump="$2"
  require_file "$dump"
  require_file "$dump.sha256"
  [[ "$(sha256_file "$dump")" == "$(cat "$dump.sha256")" ]] || die "database backup checksum mismatch"
  PGSERVICE="$pg_service" pg_restore --clean --if-exists --no-owner --no-privileges \
    --single-transaction --exit-on-error --dbname="service=$pg_service" "$dump" >/dev/null
}

encrypt_rollback_backup() {
  local plaintext_dir="$1"
  local output_dir="$2"
  local public_key_path="$3"
  local backup_id="$4"
  mkdir -p "$output_dir"
  local archive data_key encrypted_bundle encrypted_key
  (
    cd "$plaintext_dir"
    find . -type f ! -name BACKUP_SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done >BACKUP_SHA256SUMS
  )
  archive="$plaintext_dir/../$backup_id.rollback.tar.gz"
  tar -C "$plaintext_dir" -czf "$archive" .
  data_key="$plaintext_dir/../$backup_id.rollback.key.txt"
  openssl rand -hex 32 >"$data_key"
  encrypted_bundle="$output_dir/$backup_id.rollback.tar.gz.enc"
  encrypted_key="$output_dir/$backup_id.rollback.key.enc"
  [[ ! -e "$encrypted_bundle" && ! -e "$encrypted_key" ]] || die "encrypted backup artifact already exists"
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 \
    -pass "file:$data_key" -in "$archive" -out "$encrypted_bundle"
  openssl pkeyutl -encrypt -pubin -inkey "$public_key_path" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
    -in "$data_key" -out "$encrypted_key"
  (
    cd "$output_dir"
    shasum -a 256 "$(basename "$encrypted_bundle")" "$(basename "$encrypted_key")" \
      >"$backup_id.rollback.transport.sha256"
  )
  chmod 600 "$encrypted_bundle" "$encrypted_key" "$output_dir/$backup_id.rollback.transport.sha256"
}

decrypt_rollback_backup() {
  local encrypted_dir="$1"
  local backup_id="$2"
  local private_key_path="$3"
  local output_dir="$4"
  local encrypted_bundle="$encrypted_dir/$backup_id.rollback.tar.gz.enc"
  local encrypted_key="$encrypted_dir/$backup_id.rollback.key.enc"
  local transport="$encrypted_dir/$backup_id.rollback.transport.sha256"
  require_file "$encrypted_bundle"; require_file "$encrypted_key"; require_file "$transport"; require_file "$private_key_path"
  (cd "$encrypted_dir" && shasum -a 256 -c "$(basename "$transport")" >/dev/null)
  mkdir -p "$output_dir"
  openssl pkeyutl -decrypt -inkey "$private_key_path" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
    -in "$encrypted_key" -out "$output_dir/data-key.txt"
  openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 \
    -pass "file:$output_dir/data-key.txt" -in "$encrypted_bundle" -out "$output_dir/rollback.tar.gz"
  mkdir -p "$output_dir/payload"
  gzip -t "$output_dir/rollback.tar.gz"
  tar -xzf "$output_dir/rollback.tar.gz" -C "$output_dir/payload"
  (cd "$output_dir/payload" && shasum -a 256 -c BACKUP_SHA256SUMS >/dev/null)
}

run_maintenance_guard() {
  local guard="$1"
  require_file "$guard"
  [[ -x "$guard" ]] || die "maintenance guard must be executable"
  "$guard" >/dev/null || die "maintenance guard rejected the operation"
}

render_apply_sql() {
  local data_dir="$1"
  local maria_subject_file="$2"
  local cutoff_file="$3"
  local rendered="$4"
  sed -e "s|__DATA_DIR__|$data_dir|g" \
      -e "s|__MARIA_SUBJECT_FILE__|$maria_subject_file|g" \
      -e "s|__CUTOFF_FILE__|$cutoff_file|g" \
      "$apply_template" >"$rendered"
}

check_environment_name() {
  local environment="$1"
  [[ "$environment" == "dev" || "$environment" == "prod" ]] || die "environment must be dev or prod"
}

check_environment_approval() {
  local environment="$1"
  local production_approval="$2"
  check_environment_name "$environment"
  if [[ "$environment" == "prod" && "$production_approval" != "true" ]]; then
    die "production requires --operator-production-approval"
  fi
}

check_route() {
  case "$source_environment:$target_environment" in
    vdsina:dev|dev:prod) ;;
    *) die "unsupported route: $source_environment -> $target_environment" ;;
  esac
}

check_payload_route() {
  local payload="$1"
  [[ "$(jq -r '.sourceEnvironment' "$payload/manifest.json")" == "$source_environment" ]] \
    || die "bundle source environment does not match this route"
  [[ "$(jq -r '.targetEnvironment' "$payload/manifest.json")" == "$target_environment" ]] \
    || die "bundle target environment does not match this route"
}

command_export() {
  check_common_tools
  require_value --pg-service "$pg_service"
  require_value --maria-subject-file "$maria_subject_file"
  require_value --s3-alias "$s3_alias"
  require_value --s3-bucket "$s3_bucket"
  require_value --public-key "$public_key"
  require_value --output-dir "$output_dir"
  require_value --platform-commit "$platform_commit"
  require_value --infra-commit "$infra_commit"
  check_route
  safe_name "$pg_service"; safe_name "$s3_alias"; safe_name "$s3_bucket"
  validate_subject_file "$maria_subject_file"; require_file "$public_key"
  umask 077
  mkdir -p "$output_dir"
  local work payload created_at cutoff_at bundle_id archive data_key encrypted_bundle encrypted_key
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-export.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  payload="$work/payload"
  mkdir -p "$payload/tables" "$payload/objects"
  cp "$maria_subject_file" "$payload/maria-subject.txt"
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cutoff_at="$created_at"
  bundle_id="maria-learning-$source_environment-to-$target_environment-$(date -u +%Y%m%dT%H%M%SZ)"
  extract_database_scope "$pg_service" "$payload/maria-subject.txt" "$payload" "$cutoff_at"
  copy_selected_objects_from_s3 "$payload" "$s3_alias" "$s3_bucket"
  python3 "$bundle_tool" build-manifest --payload "$payload" \
    --maria-subject-file "$payload/maria-subject.txt" --bundle-id "$bundle_id" \
    --created-at "$created_at" --cutoff-at "$cutoff_at" \
    --platform-commit "$platform_commit" --infra-commit "$infra_commit" \
    --source-environment "$source_environment" --target-environment "$target_environment"
  (
    cd "$payload"
    find . -type f ! -name PAYLOAD_SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done >PAYLOAD_SHA256SUMS
  )
  archive="$work/$bundle_id.tar.gz"
  tar -C "$payload" -czf "$archive" .
  data_key="$work/data-key.txt"
  openssl rand -hex 32 >"$data_key"
  encrypted_bundle="$output_dir/$bundle_id.tar.gz.enc"
  encrypted_key="$output_dir/$bundle_id.key.enc"
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 \
    -pass "file:$data_key" -in "$archive" -out "$encrypted_bundle"
  openssl pkeyutl -encrypt -pubin -inkey "$public_key" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 \
    -in "$data_key" -out "$encrypted_key"
  (
    cd "$output_dir"
    shasum -a 256 "$(basename "$encrypted_bundle")" "$(basename "$encrypted_key")" \
      >"$bundle_id.transport.sha256"
  )
  printf '%s  %s\n' "$(sha256_file "$payload/manifest.json")" manifest.json \
    >"$output_dir/$bundle_id.manifest.sha256"
  chmod 600 "$encrypted_bundle" "$encrypted_key" "$output_dir/$bundle_id.transport.sha256" "$output_dir/$bundle_id.manifest.sha256"
  jq -n --arg bundleId "$bundle_id" --arg manifestSha256 "$(sha256_file "$payload/manifest.json")" \
    --argjson tableCount "$(jq '.tables | length' "$payload/manifest.json")" \
    --argjson objectCount "$(jq '.objects | length' "$payload/manifest.json")" \
    '{bundleId:$bundleId,manifestSha256:$manifestSha256,tableCount:$tableCount,objectCount:$objectCount}'
  rm -rf -- "$work"
  trap - EXIT
}

command_verify_bundle() {
  check_common_tools; check_route
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-verify.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  decrypt_bundle "$bundle" "$encrypted_key" "$private_key" "$work" "$transport_checksums"
  check_payload_route "$work/payload"
  python3 "$bundle_tool" validate --payload "$work/payload"
  rm -rf -- "$work"; trap - EXIT
}

prepare_target_scope() {
  local payload="$1"
  local target_dir="$2"
  validate_subject_inventory "$payload" "$target_subjects_file"
  extract_database_scope "$pg_service" "$payload/maria-subject.txt" "$target_dir" "$(jq -r '.cutoffAt' "$payload/manifest.json")"
  python3 "$bundle_tool" validate-schema-compatibility --source "$payload" --target "$target_dir"
}

command_plan() {
  check_common_tools; check_environment_name "$environment"; check_route
  [[ "$environment" == "$target_environment" ]] || die "environment does not match route target"
  require_value --pg-service "$pg_service"; safe_name "$pg_service"
  require_value --target-subjects-file "$target_subjects_file"
  local work report
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-plan.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  decrypt_bundle "$bundle" "$encrypted_key" "$private_key" "$work/source" "$transport_checksums"
  check_payload_route "$work/source/payload"
  prepare_target_scope "$work/source/payload" "$work/target"
  report="${plan_output:-$work/plan.json}"
  python3 "$bundle_tool" plan --source "$work/source/payload" --target "$work/target" --output "$report"
  if [[ -n "$plan_output" ]]; then
    jq '{bundleId,tables,objects}' "$report"
  else
    cat "$report"
  fi
  rm -rf -- "$work"; trap - EXIT
}

command_verify_target_inner() {
  local payload="$1"
  local work_root="$2"
  prepare_target_scope "$payload" "$work_root/target-verify"
  python3 "$bundle_tool" compare-target --source "$payload" --target "$work_root/target-verify" >/dev/null
  verify_selected_objects_on_s3 "$payload" "$s3_alias" "$s3_bucket"
}

command_apply() {
  check_common_tools; check_environment_approval "$environment" "$production_approval"; check_route
  [[ "$environment" == "$target_environment" ]] || die "environment does not match route target"
  require_value --pg-service "$pg_service"; require_value --s3-alias "$s3_alias"; require_value --s3-bucket "$s3_bucket"
  require_value --backup-dir "$backup_dir"; require_value --maintenance-guard-command "$maintenance_guard"
  require_value --backup-public-key "$backup_public_key"; require_file "$backup_public_key"
  require_value --confirm-manifest-sha256 "$confirm_manifest_sha256"
  safe_name "$pg_service"; safe_name "$s3_alias"; safe_name "$s3_bucket"
  local work payload manifest_sha backup_id rendered rollback_dir apply_failed=false
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-apply.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  decrypt_bundle "$bundle" "$encrypted_key" "$private_key" "$work/source" "$transport_checksums"
  payload="$work/source/payload"
  check_payload_route "$payload"
  manifest_sha="$(sha256_file "$payload/manifest.json")"
  [[ "$manifest_sha" == "$confirm_manifest_sha256" ]] || die "manifest confirmation hash does not match"
  prepare_target_scope "$payload" "$work/target-before"
  run_maintenance_guard "$maintenance_guard"
  printf '%s\n' "$(jq -r '.cutoffAt' "$payload/manifest.json")" >"$work/cutoff"
  rendered="$work/apply.sql"
  render_apply_sql "$payload" "$payload/maria-subject.txt" "$work/cutoff" "$rendered"
  sed '$s/^COMMIT;$/ROLLBACK;/' "$rendered" >"$work/preflight.sql"
  PGSERVICE="$pg_service" psql -X --no-psqlrc -v ON_ERROR_STOP=1 -f "$work/preflight.sql" >/dev/null
  umask 077; mkdir -p "$backup_dir"
  backup_id="$(jq -r '.bundleId' "$payload/manifest.json")-$environment-$(date -u +%Y%m%dT%H%M%SZ)"
  rollback_dir="$work/rollback"
  mkdir -p "$rollback_dir"
  printf '%s\n' "$backup_id" >"$rollback_dir/backup-id"
  printf '%s\n' "$environment" >"$rollback_dir/environment"
  printf '%s\n' "$manifest_sha" >"$rollback_dir/manifest-sha256"
  PGSERVICE="$pg_service" pg_dump --format=custom --no-owner --no-privileges \
    --file="$rollback_dir/application-postgresql.dump"
  pg_restore --list "$rollback_dir/application-postgresql.dump" >/dev/null
  sha256_file "$rollback_dir/application-postgresql.dump" >"$rollback_dir/application-postgresql.dump.sha256"
  backup_touched_objects "$payload" "$work/target-before" "$s3_alias" "$s3_bucket" "$rollback_dir"
  encrypt_rollback_backup "$rollback_dir" "$backup_dir" "$backup_public_key" "$backup_id"
  decrypt_rollback_backup "$backup_dir" "$backup_id" "$private_key" "$work/rollback-proof"
  if ! write_source_objects "$payload" "$s3_alias" "$s3_bucket"; then
    restore_objects "$rollback_dir" "$s3_alias" "$s3_bucket"
    die "object write failed; pre-apply objects were restored"
  fi
  if ! PGSERVICE="$pg_service" psql -X --no-psqlrc -v ON_ERROR_STOP=1 -f "$rendered" >/dev/null; then
    apply_failed=true
  fi
  if [[ "$apply_failed" == "true" ]]; then
    restore_objects "$rollback_dir" "$s3_alias" "$s3_bucket"
    die "database apply failed; pre-apply objects were restored"
  fi
  if ! delete_target_only_objects "$payload" "$work/target-before" "$s3_alias" "$s3_bucket" \
    || ! command_verify_target_inner "$payload" "$work"; then
    restore_database "$pg_service" "$rollback_dir/application-postgresql.dump"
    restore_objects "$rollback_dir" "$s3_alias" "$s3_bucket"
    die "post-apply verification failed; database and objects were rolled back"
  fi
  printf '%s\n' "$manifest_sha" >"$backup_dir/$backup_id.apply-complete"
  chmod -R go-rwx "$backup_dir"
  jq -n --arg backupId "$backup_id" --arg bundleId "$(jq -r '.bundleId' "$payload/manifest.json")" \
    --arg environment "$environment" '{status:"complete",backupId:$backupId,bundleId:$bundleId,environment:$environment}'
  rm -rf -- "$work"; trap - EXIT
}

command_verify_target() {
  check_common_tools; check_environment_name "$environment"; check_route
  [[ "$environment" == "$target_environment" ]] || die "environment does not match route target"
  require_value --pg-service "$pg_service"; require_value --s3-alias "$s3_alias"; require_value --s3-bucket "$s3_bucket"
  safe_name "$pg_service"; safe_name "$s3_alias"; safe_name "$s3_bucket"
  local work payload
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-target-verify.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  decrypt_bundle "$bundle" "$encrypted_key" "$private_key" "$work/source" "$transport_checksums"
  payload="$work/source/payload"
  check_payload_route "$payload"
  command_verify_target_inner "$payload" "$work"
  jq -n --arg bundleId "$(jq -r '.bundleId' "$payload/manifest.json")" --arg environment "$environment" \
    '{status:"verified",bundleId:$bundleId,environment:$environment}'
  rm -rf -- "$work"; trap - EXIT
}

command_rollback() {
  check_common_tools; check_environment_approval "$environment" "$production_approval"; check_route
  [[ "$environment" == "$target_environment" ]] || die "environment does not match route target"
  require_value --pg-service "$pg_service"; require_value --s3-alias "$s3_alias"; require_value --s3-bucket "$s3_bucket"
  require_value --backup-dir "$backup_dir"; require_value --maintenance-guard-command "$maintenance_guard"
  require_value --confirm-backup-id "$confirm_backup_id"
  safe_name "$pg_service"; safe_name "$s3_alias"; safe_name "$s3_bucket"
  require_dir "$backup_dir"; require_file "$private_key"
  run_maintenance_guard "$maintenance_guard"
  local work rollback_payload
  work="$(mktemp -d "${TMPDIR:-/tmp}/playsay-maria-rollback.XXXXXX")"
  trap "rm -rf -- '$work'" EXIT
  decrypt_rollback_backup "$backup_dir" "$confirm_backup_id" "$private_key" "$work"
  rollback_payload="$work/payload"
  [[ "$(cat "$rollback_payload/backup-id")" == "$confirm_backup_id" ]] || die "backup confirmation ID does not match"
  [[ "$(cat "$rollback_payload/environment")" == "$environment" ]] || die "backup belongs to another environment"
  restore_database "$pg_service" "$rollback_payload/application-postgresql.dump"
  restore_objects "$rollback_payload" "$s3_alias" "$s3_bucket"
  jq -n --arg backupId "$confirm_backup_id" --arg environment "$environment" \
    '{status:"rolled-back",backupId:$backupId,environment:$environment}'
}

[[ $# -gt 0 ]] || { usage; exit 2; }
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi
command="$1"; shift
pg_service=""; maria_subject_file=""; s3_alias=""; s3_bucket=""; public_key=""; output_dir=""; backup_public_key=""
platform_commit=""; infra_commit=""; bundle=""; encrypted_key=""; private_key=""; transport_checksums=""
environment=""; target_subjects_file=""; plan_output=""; backup_dir=""; maintenance_guard=""
confirm_manifest_sha256=""; confirm_backup_id=""; production_approval="false"
source_environment=""; target_environment=""

while (($#)); do
  case "$1" in
    --pg-service) pg_service="${2:?missing value}"; shift 2 ;;
    --maria-subject-file) maria_subject_file="${2:?missing value}"; shift 2 ;;
    --s3-alias) s3_alias="${2:?missing value}"; shift 2 ;;
    --s3-bucket) s3_bucket="${2:?missing value}"; shift 2 ;;
    --public-key) public_key="${2:?missing value}"; shift 2 ;;
    --backup-public-key) backup_public_key="${2:?missing value}"; shift 2 ;;
    --output-dir) output_dir="${2:?missing value}"; shift 2 ;;
    --platform-commit) platform_commit="${2:?missing value}"; shift 2 ;;
    --infra-commit) infra_commit="${2:?missing value}"; shift 2 ;;
    --source-environment) source_environment="${2:?missing value}"; shift 2 ;;
    --target-environment) target_environment="${2:?missing value}"; shift 2 ;;
    --bundle) bundle="${2:?missing value}"; shift 2 ;;
    --encrypted-key) encrypted_key="${2:?missing value}"; shift 2 ;;
    --private-key) private_key="${2:?missing value}"; shift 2 ;;
    --transport-checksums) transport_checksums="${2:?missing value}"; shift 2 ;;
    --environment) environment="${2:?missing value}"; shift 2 ;;
    --target-subjects-file) target_subjects_file="${2:?missing value}"; shift 2 ;;
    --output) plan_output="${2:?missing value}"; shift 2 ;;
    --backup-dir) backup_dir="${2:?missing value}"; shift 2 ;;
    --maintenance-guard-command) maintenance_guard="${2:?missing value}"; shift 2 ;;
    --confirm-manifest-sha256) confirm_manifest_sha256="${2:?missing value}"; shift 2 ;;
    --confirm-backup-id) confirm_backup_id="${2:?missing value}"; shift 2 ;;
    --operator-production-approval) production_approval="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$command" in
  export) command_export ;;
  verify-bundle) command_verify_bundle ;;
  plan) command_plan ;;
  apply) command_apply ;;
  verify-target) command_verify_target ;;
  rollback) command_rollback ;;
  *) usage >&2; die "unknown command: $command" ;;
esac
