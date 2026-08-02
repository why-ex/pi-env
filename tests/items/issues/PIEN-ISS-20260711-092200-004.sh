#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

# shellcheck source=tests/lib/test-helpers.sh
. "$repo_root/tests/lib/test-helpers.sh"

# User docs should present pien as the canonical namespace while documenting
# the hard rename to pi-en-prefixed lower-level commands. State paths and
# environment variable names are intentionally unchanged.
test_grep '`pien` is the canonical user-facing command namespace' README.md
test_grep 'The old non-prefixed names' README.md
test_grep 'are intentionally not compatibility entrypoints' README.md
test_grep 'Operational state paths such' README.md
test_grep 'as `.pi-en/` and environment variables such as' README.md

test_grep '^| `pien coord status \[options\]` | `pi-en-coord-status \[options\]` |$' README.md
test_grep '^| `pien roles serial \[options\]` | `pi-en-serial-roles \[options\]` |$' README.md
test_grep '^| `pien install \[options\]` | `pi-en-install-non-nix \[options\]` |$' README.md
test_grep 'pien completion bash' designs/pien-command-namespace.md

test_grep '^pien help$' README.md
test_grep '^pien help coord$' README.md
test_grep '^pien help coord status$' README.md
test_grep '^pien coord status --help$' README.md
test_grep '^pien completion bash$' README.md
test_grep '^source <(pien completion bash)$' README.md

test_grep '^pien -- shell$' README.md
test_grep '^pien -- coord status$' README.md
test_grep '^pien sandbox shell -- -l$' README.md

test_grep 'Host runtime is' README.md
test_grep 'unpinned and uses admitted host tools' README.md
test_grep 'Nix runtime is reproducible and pinned' README.md

test_grep '^pien raw -- --model' README.md
test_grep '^pien$' README.md
test_grep '^PI_EN_BWRAP_PROJECT_ROOT=/path/to/repo pien' README.md
test_grep '^pien coord bootstrap' README.md
test_grep '^pien coord init$' README.md
test_grep '^pien coord clone$' README.md
test_grep '^pien coord new --repo-id pi-en --type issue --category bug' README.md
test_grep '^pien coord push -m "Add PIEN documentation item"$' README.md
test_grep '^pien coord status$' README.md
test_grep '^pien coord rules upgrade --preview$' README.md
test_grep '^PI_EN_ROLE_MANAGER_AUTO=0 pien$' README.md
test_grep '^pien sandbox install -l "\$PI_EN_ROLE_MANAGER_PACKAGE"$' README.md
test_grep '^pien sandbox install -l "\$(readlink -f result)"$' README.md
test_grep '^pien roles serial --sleep 30$' README.md
test_grep '^pien roles serial --once$' README.md
test_grep '^pien roles serial --issue ISSUE-1 --issue ISSUE-2 --max-jobs 2$' README.md

if grep -q '^PI_EN_BWRAP_[^#]* pi-en\($\|[[:space:]]#\)' README.md; then
  test_fail 'per-project override examples should prefer pien'
fi
if grep -q '^\(pi-en-bootstrap-coordination\|pi-en-coord-init\|pi-en-coord-clone\|pi-en-coord-new\|pi-en-coord-push\|pi-en-coord-list\|pi-en-coord-upgrade-rules\)' README.md; then
  test_fail 'coordination setup examples should prefer pien coord commands'
fi
if grep -q '^PI_EN_ROLE_MANAGER_AUTO=0 pi-en\($\|[[:space:]]\)' README.md; then
  test_fail 'role-manager opt-out examples should prefer pien'
fi
if grep -q '^pi-en-bwrap install ' README.md; then
  test_fail 'role-manager install examples should prefer pien sandbox'
fi
if grep -q '^pi-en-serial-roles\($\|[[:space:]]\)' README.md; then
  test_fail 'serial role examples should prefer pien roles serial'
fi

echo 'PIEN-ISS-20260711-092200-004 pien documentation tests passed'
