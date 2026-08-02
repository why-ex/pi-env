#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

legacy_public_name="pi""-coordination"
legacy_config_name=".pi""-coordination.yaml"
legacy_remote_url_env="PI_EN_COORD_REMOTE""_URL"
legacy_root_env="PI_EN_COORD""_ROOT"

if git grep -n -- "$legacy_public_name" >"$tmp/legacy-public.out"; then
  cat "$tmp/legacy-public.out" >&2
  printf 'old public coordination package name remains in tracked files\n' >&2
  exit 1
fi

if git grep -n -- "$legacy_config_name" >"$tmp/legacy-config.out"; then
  cat "$tmp/legacy-config.out" >&2
  printf 'old implementation config filename remains in tracked files\n' >&2
  exit 1
fi

if git grep -n -- "$legacy_remote_url_env" >"$tmp/legacy-remote-url.out"; then
  cat "$tmp/legacy-remote-url.out" >&2
  printf 'legacy coordination remote URL alias remains in tracked files\n' >&2
  exit 1
fi

if git grep -n -- "$legacy_root_env" >"$tmp/legacy-root-env.out"; then
  cat "$tmp/legacy-root-env.out" >&2
  printf 'legacy coordination root environment variable remains in tracked files\n' >&2
  exit 1
fi

grep -q 'pi-en-coordination = piCoordination;' flake.nix
grep -q 'pi-en-coordination-smoke = smokeCheck "pi-en-coordination-smoke"' flake.nix
grep -q 'nix profile install ~/src/pi-en#pi-en-coordination' README.md
grep -q '`pi-en-coordination` contains the Git-backed coordination helper commands' \
  designs/nix-runtime.md

if grep -q 'legacy_impl_config' scripts/pi-en-coord-lib.sh; then
  printf 'legacy implementation config helper remains in pi-en-coord-lib.sh\n' >&2
  exit 1
fi

if grep -q 'deprecated:' scripts/pi-en-coord-lib.sh; then
  printf 'config deprecation warning path remains in pi-en-coord-lib.sh\n' >&2
  exit 1
fi
