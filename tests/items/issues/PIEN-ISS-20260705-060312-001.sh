#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
lib="$repo_root/scripts/pi-en-coord-lib.sh"

export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

legacy_config_name=".pi""-coordination.yaml"
legacy_config_help_pattern="\\.pi""-coordination\\.yaml"

root_config="$repo_root/.pi-en-coordination.yaml"
test -f "$root_config"
grep -q '^version: 1$' "$root_config"
grep -q '^coordination_domain: pi-en$' "$root_config"
grep -q '^coordination_remote: .pi-en/agent-remotes/pi-en-coordination.git$' "$root_config"
grep -q '^repo_id: pi-en$' "$root_config"

for command in pi-en-coord-init pi-en-coord-clone pi-en-coord-done pi-en-coord-lint; do
  help="$($command --help)"
  grep -q '\.pi-en-coordination\.yaml' <<<"$help"
  if grep -q "$legacy_config_help_pattern" <<<"$help"; then
    printf '%s help should not advertise the old config filename\n' "$command" >&2
    exit 1
  fi
done

coord_dir="$tmp/coordination"
mkdir -p "$coord_dir"
cat >"$coord_dir/repositories.yaml" <<'YAML'
repositories:
  - repo_id: alpha
    active: true
    aliases:
      - legacy-alpha
  - repo_id: remote-project
    active: true
YAML

project="$tmp/project"
mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.name "Project Test"
git -C "$project" config user.email "project-test@example.invalid"
git -C "$project" commit --allow-empty -m "Project commit" >/dev/null
git -C "$project" remote add origin git@example.invalid:org/remote-project.git

cat >"$project/.pi-en-coordination.yaml" <<'YAML'
version: 1
coordination_domain: domain
coordination_remote: ssh://new-coordination.example.invalid/domain.git
repo_id: alpha
YAML
cat >"$project/$legacy_config_name" <<'YAML'
version: 1
coordination_domain: domain
coordination_remote: ssh://old-coordination.example.invalid/domain.git
repo_id: old-alpha
YAML

(
  cd "$project"
  # shellcheck source=/dev/null
  . "$lib"

  [ "$(coord_impl_config_path)" = "$project/.pi-en-coordination.yaml" ]
  [ "$(coord_impl_config_value repo_id 2>"$tmp/new-value.err")" = "alpha" ]
  test ! -s "$tmp/new-value.err"
  [ "$(coord_resolve_coordination_remote '' 2>"$tmp/new-remote.err")" = "ssh://new-coordination.example.invalid/domain.git" ]
  test ! -s "$tmp/new-remote.err"
  [ "$(coord_resolve_repo_id '' "$coord_dir" 2>"$tmp/new-repo.err")" = "alpha" ]
  test ! -s "$tmp/new-repo.err"

  rm .pi-en-coordination.yaml
  [ "$(coord_impl_config_value repo_id 2>"$tmp/old-value.err")" = "" ]
  test ! -s "$tmp/old-value.err"
  if coord_impl_config_source >"$tmp/old-source.out" 2>"$tmp/old-source.err"; then
    printf 'old config filename unexpectedly selected as a source\n' >&2
    exit 1
  fi
  test ! -s "$tmp/old-source.out"
  test ! -s "$tmp/old-source.err"
  if coord_impl_config_exists; then
    printf 'old config filename unexpectedly counted as existing\n' >&2
    exit 1
  fi
  if coord_resolve_coordination_remote '' >"$tmp/old-remote.out" 2>"$tmp/old-remote.err"; then
    printf 'coordination remote unexpectedly resolved from old config filename\n' >&2
    exit 1
  fi
  test ! -s "$tmp/old-remote.out"
  test ! -s "$tmp/old-remote.err"
  [ "$(coord_resolve_repo_id '' "$coord_dir" 2>"$tmp/old-repo.err")" = "remote-project" ]
  test ! -s "$tmp/old-repo.err"

  rm "$legacy_config_name"
  git remote remove origin
  if bash -c '. "$1"; coord_resolve_repo_id "" "$2"' bash "$lib" "$coord_dir" \
    >"$tmp/missing.out" 2>"$tmp/missing.err"; then
    printf 'missing repo id unexpectedly succeeded\n' >&2
    exit 1
  fi
  grep -q 'add repo_id to .pi-en-coordination.yaml' "$tmp/missing.err"
)
