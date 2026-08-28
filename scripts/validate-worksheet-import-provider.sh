#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="$repo_root/helm-charts/worksheet-import-service"
prod_values="$chart_dir/values-prod.yaml"
task_tmp="$(mktemp -d "${TMPDIR:-/tmp}/worksheet-provider-render.XXXXXX")"
trap 'rm -rf "$task_tmp"' EXIT

for command_name in helm yq; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

stub_render="$task_tmp/stub.yaml"
openai_render="$task_tmp/openai.yaml"

helm lint "$chart_dir" -f "$prod_values" >/dev/null
helm template worksheet-import "$chart_dir" -f "$prod_values" > "$stub_render"
helm template worksheet-import "$chart_dir" -f "$prod_values" \
  --set analysis.provider=openai \
  --set analysis.model=gpt-5.6-sol \
  --set analysis.reasoningEffort=low \
  --set analysis.requestTimeout=PT120S > "$openai_render"

env_value() {
  rendered="$1"
  env_name="$2"
  yq -r "select(.kind == \"Deployment\") | .spec.template.spec.containers[0].env[] | select(.name == \"$env_name\") | .value" "$rendered"
}

assert_equal() {
  expected="$1"
  actual="$2"
  label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$label: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_equal stub "$(env_value "$stub_render" PLAYSAY_WORKSHEET_AI_PROVIDER)" "stub provider"
if yq -e 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "PLAYSAY_AI_OPENAI_API_KEY")' "$stub_render" >/dev/null 2>&1; then
  echo "Stub render must not reference the OpenAI API key." >&2
  exit 1
fi

assert_equal openai "$(env_value "$openai_render" PLAYSAY_WORKSHEET_AI_PROVIDER)" "OpenAI provider"
assert_equal gpt-5.6-sol "$(env_value "$openai_render" PLAYSAY_AI_OPENAI_MODEL)" "OpenAI model"
assert_equal low "$(env_value "$openai_render" PLAYSAY_AI_WORKSHEET_REASONING)" "worksheet reasoning effort"
assert_equal PT120S "$(env_value "$openai_render" PLAYSAY_WORKSHEET_AI_REQUEST_TIMEOUT)" "worksheet request timeout"

secret_name="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "PLAYSAY_AI_OPENAI_API_KEY") | .valueFrom.secretKeyRef.name' "$openai_render")"
secret_key="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[0].env[] | select(.name == "PLAYSAY_AI_OPENAI_API_KEY") | .valueFrom.secretKeyRef.key' "$openai_render")"
assert_equal playsay-openai "$secret_name" "OpenAI Secret name"
assert_equal api-key "$secret_key" "OpenAI Secret key"

image="$(yq -r 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image' "$openai_render")"
if [[ ! "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
  echo "Production worksheet image is not immutable: $image" >&2
  exit 1
fi

echo "Worksheet provider render contract is valid."
