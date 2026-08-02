#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=../../lib/test-helpers.sh
source tests/lib/test-helpers.sh

bootstrap=scripts/pi-en-bootstrap-coordination
pien=scripts/pien
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

help_out="$tmpdir/bootstrap.help"
bash "$bootstrap" --help >"$help_out"
test_grep 'Coordination repository Git remote URL' "$help_out"
test_grep 'Coordination domain project name' "$help_out"
test_grep 'Domain-level item ID prefix stored in root PROJECT.md' "$help_out"
test_grep 'Implementation repo namespace to attach/register' "$help_out"
test_grep 'Implementation repository Git remote URL for registration' "$help_out"

wrapper_help="$tmpdir/pien-bootstrap.help"
bash "$pien" coord bootstrap --help >"$wrapper_help"
test_grep 'Coordination repository Git remote URL' "$wrapper_help"
test_grep 'Coordination domain project name' "$wrapper_help"
test_grep 'Domain-level item ID prefix stored in root PROJECT.md' "$wrapper_help"
test_grep 'Implementation repo namespace to attach/register' "$wrapper_help"
test_grep 'Implementation repository Git remote URL for registration' "$wrapper_help"

impl="$tmpdir/impl"
mkdir -p "$impl"
git -C "$impl" init --initial-branch=main >/dev/null 2>&1 \
  || git -C "$impl" init >/dev/null
plan_out="$tmpdir/plan.out"
env -u PI_EN_COORD_REMOTE -u PI_EN_COORD_DIR -u PI_EN_COORD_PROJECT \
  -u PI_EN_COORD_PROJECT_KEY -u PI_EN_COORD_REPO_ID \
  bash "$bootstrap" --project-root "$impl" --remote "$tmpdir/domain.git" \
    --project product-domain --project-key PROD --repo-id backend-api \
    --implementation-remote git@example.com:org/backend-api.git \
    --dir "$impl/.pi-en/coordination" --print-only >"$plan_out"
test_grep 'Coordination domain project: product-domain' "$plan_out"
test_grep 'Domain item key:             PROD' "$plan_out"
test_grep "Coordination remote:         $tmpdir/domain.git" "$plan_out"
test_grep 'Implementation repo id:      backend-api' "$plan_out"
test_grep 'Implementation repo remote:  git@example.com:org/backend-api.git' "$plan_out"

# README keeps the three user-facing bootstrap cases and mutation warning in sync.
test_grep 'Create or bootstrap a local-only coordination domain' README.md
test_grep 'Attach an implementation repo to an existing coordination domain without' README.md
test_grep 'Attach and explicitly register a new implementation repo namespace' README.md
test_grep 'mutates shared coordination state by creating `repos/backend-api/REPO.md`' README.md
test_grep '--repo-id backend-api' README.md
test_grep '--implementation-remote git@example.com:org/backend-api.git' README.md

test_note 'bootstrap domain/repo help and README guidance are covered'
