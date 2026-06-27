#!/usr/bin/env bash
set -Eeuo pipefail

# Run safe local checks for lesson 75.
#
# This script is the "one command before commit" helper. It does not call AWS and does not run
# terraform apply/destroy. By default it runs checks that should work offline: shell syntax,shellcheck,
# policy tests, risk-classifier tests, and fmt.
#
# Optional checks:
# - RUN_OPA=true runs OPA parity tests.
# - RUN_TERRAFORM=true runs Terraform init/test/validate without backend.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LESSON_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${LESSON_DIR}/../.." && pwd)"

RUN_OPA="${RUN_OPA:-false}"
RUN_TERRAFORM="${RUN_TERRAFORM:-false}"

run() {
  echo
  echo "+ $*"
  "$@"
}

cd "$REPO_ROOT"

run find "$LESSON_DIR" -type f -name '*.sh' -print0
find "$LESSON_DIR" -type f -name '*.sh' -print0 | xargs -0 bash -n

if command -v shellcheck >/dev/null 2>&1; then
  # ShellCheck does not accept NUL-delimited input directly, so use mapfile.
  mapfile -t shell_scripts < <(find "$LESSON_DIR" -type f -name '*.sh' | sort)
  run shellcheck "${shell_scripts[@]}"
else
  echo "[WARN] shellcheck not found; skipping shellcheck."
fi

run packer fmt -check -recursive "$LESSON_DIR/lab_75/packer"
run terraform fmt -check -recursive "$LESSON_DIR/lab_75/terraform"

run "$LESSON_DIR/policies/test-policy.sh"
run "$LESSON_DIR/policies/test-cost-policy.sh"
run "$LESSON_DIR/policies/test-risk-classifier.sh"

if [[ "$RUN_OPA" == "true" ]]; then
  if command -v opa >/dev/null 2>&1; then
    run "$LESSON_DIR/policies/test-opa.sh"
  else
    echo "[WARN] RUN_OPA=true but opa is not installed; skipping OPA tests."
  fi
fi

if [[ "$RUN_TERRAFORM" == "true" ]]; then
  run env TF_DATA_DIR=/tmp/l75-module-test-data \
    terraform -chdir="$LESSON_DIR/lab_75/terraform/modules/network" \
    init -backend=false -input=false -no-color

  run env TF_DATA_DIR=/tmp/l75-module-test-data \
    terraform -chdir="$LESSON_DIR/lab_75/terraform/modules/network" \
    test -no-color

  for env_name in dev stage prod; do
    run env TF_DATA_DIR="/tmp/l75-${env_name}-data" \
      terraform -chdir="$LESSON_DIR/lab_75/terraform/envs/${env_name}" \
      init -backend=false -input=false -no-color

    run env TF_DATA_DIR="/tmp/l75-${env_name}-data" \
      terraform -chdir="$LESSON_DIR/lab_75/terraform/envs/${env_name}" \
      validate -no-color
  done
fi

echo
echo "lesson 75 local checks passed"
