#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

./pi-en-shell --help | grep -q 'pi-en-shell'
PI_EN_SHELL_MODE=1 bash scripts/pi-en-launcher --help | grep -q 'pi-en-shell'
bash scripts/pi-en-bwrap --help | grep -q 'pi-en-bwrap --shell'

fake_root="$(mktemp -d)"
trap 'rm -rf "$fake_root"' EXIT
cat >"$fake_root/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg"
done >"$PI_EN_TEST_BWRAP_TRACE"
FAKE_BWRAP
chmod +x "$fake_root/fake-bwrap"
PI_EN_RUNTIME_PATH=/nix/store/fake/bin \
PI_EN_BWRAP_BWRAP="$fake_root/fake-bwrap" \
PI_EN_BWRAP_STATE_DIR="$fake_root/state" \
PI_EN_BWRAP_EPHEMERAL_HOME=1 \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
PI_EN_TEST_BWRAP_TRACE="$fake_root/trace" \
bash scripts/pi-en-bwrap --shell -- -l >/dev/null
if grep -qx -- '--tools' "$fake_root/trace" || grep -qx -- '--continue' "$fake_root/trace"; then
  echo "pi-en-bwrap --shell with bash args must not use default Pi args" >&2
  exit 1
fi
tail -n 1 "$fake_root/trace" | grep -qx -- '-l'

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.env.REPO_ROOT;
const readme = readFileSync(join(root, "README.md"), "utf8");
const flake = readFileSync(join(root, "flake.nix"), "utf8");
const coverage = readFileSync(join(root, "REQUIREMENTS_COVERAGE.md"), "utf8");
const requirements = readFileSync(join(root, "REQUIREMENTS.md"), "utf8");

assert.match(readme, /`pien shell` owns runtime selection/);
assert.match(readme, /`pi-en-bwrap --shell \[--\] \[bash args\.\.\.\]`/);
assert.match(readme, /pien shell --runtime nix/);
assert.match(flake, /pi-en-shell = piEnShell;/);
assert.match(flake, /pi-en-shell --help >\/dev\/null/);
assert.match(requirements, /#### CMD-021 `pi-en-bwrap` shell mode/);
assert.match(requirements, /#### CMD-022 `pi-en-shell` runtime launcher/);
assert.match(coverage, /\| CMD-021 \| PIEN-FRQ-20260706-202632-001 \| designs\/launcher-layering\.md \|/);
assert.match(coverage, /\| CMD-022 \| PIEN-FRQ-20260706-202634-001 \| designs\/launcher-layering\.md \|/);
NODE
