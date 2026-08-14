#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

"$repo_root/tests/pi-en-coord-blackbox.sh"
"$repo_root/tests/pi-en-coord-lint.sh"
"$repo_root/tests/pi-en-coord-root-layout.sh"
