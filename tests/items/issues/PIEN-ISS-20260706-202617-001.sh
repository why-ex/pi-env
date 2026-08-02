#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

fake_root="$(mktemp -d)"
trap 'rm -rf "$fake_root"' EXIT

mkdir -p "$fake_root/bin" "$fake_root/state" "$fake_root/pkg"
: >"$fake_root/extfile"
cat >"$fake_root/bin/pi" <<'FAKE_PI'
#!/usr/bin/env bash
echo "fake pi should only be resolved, not run" >&2
exit 99
FAKE_PI
chmod +x "$fake_root/bin/pi"

cat >"$fake_root/bin/fake-bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
: "${PI_EN_TEST_BWRAP_TRACE:?}"
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_TRACE"
FAKE_BWRAP
chmod +x "$fake_root/bin/fake-bwrap"

run_pi_bwrap() {
  local trace="$1"
  shift
  PATH="$fake_root/bin:$PATH" \
  PI_EN_RUNTIME_PATH=/nix/store/fake/bin \
  PI_EN_BWRAP_BWRAP="$fake_root/bin/fake-bwrap" \
  PI_EN_BWRAP_STATE_DIR="$fake_root/state" \
  PI_EN_BWRAP_IMPORT_COMMON=0 \
  PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
  PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
  PI_EN_BWRAP_IMPORT_AUTH=0 \
  PI_EN_BWRAP_IMPORT_SESSIONS=0 \
  PI_EN_TEST_BWRAP_TRACE="$trace" \
  bash scripts/pi-en-bwrap "$@" >/dev/null
}

normal_trace="$fake_root/normal.trace"
shell_trace="$fake_root/shell.trace"
run_pi_bwrap "$normal_trace" -- --model fake-model
run_pi_bwrap "$shell_trace" --shell -- -lc 'printf shell'

TRACE_NORMAL="$normal_trace" TRACE_SHELL="$shell_trace" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const normal = readFileSync(process.env.TRACE_NORMAL, "utf8").trimEnd().split("\n");
const shell = readFileSync(process.env.TRACE_SHELL, "utf8").trimEnd().split("\n");
const normalSep = normal.indexOf("--");
const shellSep = shell.indexOf("--");
assert.notEqual(normalSep, -1, "normal bwrap trace has command separator");
assert.notEqual(shellSep, -1, "shell bwrap trace has command separator");
const stripPromptCommand = (args) => {
  const out = [];
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === "--setenv" && args[i + 1] === "PROMPT_COMMAND") {
      i += 2;
      continue;
    }
    out.push(args[i]);
  }
  return out;
};
assert.deepEqual(stripPromptCommand(shell.slice(0, shellSep)), normal.slice(0, normalSep));
assert.deepEqual(normal.slice(normalSep + 2, normalSep + 5), ["-lc", "exec pi \"$@\"", "pi"]);
assert.deepEqual(normal.slice(-2), ["--model", "fake-model"]);
assert.deepEqual(shell.slice(shellSep + 2), ["-lc", "printf shell"]);
assert.equal(shell.includes("--tools"), false);
assert.equal(shell.includes("--continue"), false);
NODE

shell_arg_trace="$fake_root/shell-args.trace"
run_pi_bwrap "$shell_arg_trace" --shell -- --package "$fake_root/pkg" --extension="$fake_root/extfile"
if grep -q -- '/pi-en-resources' "$shell_arg_trace"; then
  echo "shell mode must not add Pi package resource binds for shell arguments" >&2
  exit 1
fi
grep -Fx -- "$fake_root/pkg" "$shell_arg_trace" >/dev/null
grep -Fx -- "--extension=$fake_root/extfile" "$shell_arg_trace" >/dev/null
