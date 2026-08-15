#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

help_out="$(mktemp)"
cleanup() {
  rm -f "$help_out"
}
trap cleanup EXIT

bash scripts/pi-en-bwrap --help >"$help_out"

test_grep 'generated read-only shadow directory over' README.md
test_grep '/home/pi/.pi/agent/bin' README.md
test_grep 'default curated shadow list includes `rg`, `fd`' README.md
test_grep 'PI_EN_RUNTIME_PATH' README.md
test_grep '`PI_EN_BWRAP_EXTRA_PATH`; Pi-en does not scan arbitrary host paths' README.md
test_grep 'PI_EN_BWRAP_AGENT_BIN_SHADOW=0' README.md
test_grep 'PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS' README.md
test_grep 'Missing tools in an explicit list emit warnings' README.md
test_grep 'if the list is empty or no listed tool resolves' README.md

test_grep 'PI_EN_BWRAP_AGENT_BIN_SHADOW=0' "$help_out"
test_grep 'PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS="rg fd ..."' "$help_out"
test_grep 'empty or unresolved lists skip the shadow bind' "$help_out"

test_grep 'agent-bin shadow directory' designs/nix-runtime.md
test_grep 'resolved only from `PI_EN_RUNTIME_PATH`' designs/nix-runtime.md
test_grep 'does not delete or mutate user agent state' designs/nix-runtime.md
test_grep '`/home/pi/.pi/agent/bin` with a generated read-only directory' designs/bubblewrap-sandbox.md
test_grep 'resolved only from trusted Nix-store runtime or' designs/bubblewrap-sandbox.md

echo 'Nix agent-bin shadowing documentation coverage passed'
