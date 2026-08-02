#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
lib="$repo_root/scripts/pi-en-coord-lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

coord_dir="$tmp/coordination"
mkdir -p "$coord_dir"
cat >"$coord_dir/repositories.yaml" <<'YAML'
repositories:
  - repo_id: backend-api
    active: true
    aliases:
      - api-old
  - repo_id: remote-api
    active: true
  - repo_id: inactive-api
    active: false
YAML

project="$tmp/project"
mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.name "Project Test"
git -C "$project" config user.email "project-test@example.invalid"
git -C "$project" commit --allow-empty -m "Project commit" >/dev/null
git -C "$project" remote add origin git@example.com:org/remote-api.git
cat >"$project/.pi-en-coordination.yaml" <<'YAML'
version: 1
coordination_domain: my-product
coordination_remote: git@example.com:org/my-product-coordination.git
repo_id: api-old
YAML

(
  cd "$project"
  # shellcheck source=/dev/null
  . "$lib"

  [ "$(coord_impl_config_path)" = "$project/.pi-en-coordination.yaml" ]
  [ "$(coord_impl_config_value repo_id)" = "api-old" ]
  [ "$(coord_resolve_coordination_remote '')" = "git@example.com:org/my-product-coordination.git" ]
  [ "$(coord_resolve_coordination_remote 'ssh://explicit')" = "ssh://explicit" ]

  [ "$(coord_resolve_repo_id backend-api "$coord_dir")" = "backend-api" ]
  PI_EN_COORD_REPO_ID=backend-api
  export PI_EN_COORD_REPO_ID
  [ "$(coord_resolve_repo_id '' "$coord_dir")" = "backend-api" ]
  unset PI_EN_COORD_REPO_ID

  alias_output="$(coord_resolve_repo_id '' "$coord_dir" 2>"$tmp/alias.err")"
  [ "$alias_output" = "backend-api" ]
  grep -q "api-old' is an alias" "$tmp/alias.err"

  nested_coord="$project/.pi-en/coordination"
  mkdir -p "$nested_coord/docs"
  git -C "$nested_coord" init -q
  touch "$nested_coord/AGENTS.md" \
    "$nested_coord/docs/SYNC_PROTOCOL.md" \
    "$nested_coord/docs/ITEM_FORMAT.md"
  (
    cd "$nested_coord"
    # shellcheck source=/dev/null
    . "$lib"
    [ "$(coord_project_root)" = "$project" ]
    [ "$(coord_impl_config_path)" = "$project/.pi-en-coordination.yaml" ]
    [ "$(coord_impl_config_value repo_id)" = "api-old" ]
    [ "$(coord_resolve_repo_id '' "$coord_dir" 2>"$tmp/nested-alias.err")" = "backend-api" ]
    grep -q "api-old' is an alias" "$tmp/nested-alias.err"
  )

  rm .pi-en-coordination.yaml
  [ "$(coord_resolve_repo_id '' "$coord_dir")" = "remote-api" ]

  command_coord_dir="$tmp/command-coordination"
  mkdir -p "$command_coord_dir/issues/open"
  git -C "$command_coord_dir" init -q
  git -C "$command_coord_dir" config user.name "Coordination Test"
  git -C "$command_coord_dir" config user.email "coordination-test@example.invalid"
  cp "$coord_dir/repositories.yaml" "$command_coord_dir/repositories.yaml"
  cat >"$command_coord_dir/issues/open/REMOTE-001.yaml" <<'YAML'
schema: coordination-item/v1
id: REMOTE-001
type: issue
status: claimed
owner: agent-a
updated: 2026-07-04T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
events: []
messages: []
YAML
  git -C "$command_coord_dir" add .
  git -C "$command_coord_dir" commit -m "Seed coordination item" >/dev/null
  "$repo_root/scripts/pi-en-coord-done" \
    --coord-dir "$command_coord_dir" \
    --agent-id agent-a \
    --role developer \
    --no-pull \
    --no-push \
    REMOTE-001 >/dev/null
  done_item="$command_coord_dir/issues/done/REMOTE-001.yaml"
  grep -q '^      - repo: remote-api$' "$done_item"
  grep -q '^        branch: master$\|^        branch: main$' "$done_item"
  grep -q "^        commit: $(git rev-parse HEAD)$" "$done_item"

  git remote remove origin
  if bash -c '. "$1"; coord_resolve_repo_id "" "$2"' bash "$lib" "$coord_dir" >"$tmp/missing.out" 2>"$tmp/missing.err"; then
    echo "missing repo id unexpectedly succeeded" >&2
    exit 1
  fi
  grep -q "pass --repo-id" "$tmp/missing.err"

  if bash -c '. "$1"; coord_resolve_repo_id inactive-api "$2"' bash "$lib" "$coord_dir" >"$tmp/invalid.out" 2>"$tmp/invalid.err"; then
    echo "inactive repo id unexpectedly succeeded" >&2
    exit 1
  fi
  grep -q "is not active" "$tmp/invalid.err"
)
