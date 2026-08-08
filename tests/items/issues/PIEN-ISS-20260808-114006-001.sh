#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tests/pi-en-coordination-context.sh

test_grep 'Generated Pi-en coordination context' designs/pi-agent-resources.md
test_grep 'pi-en-bwrap' README.md
test_grep '/home/pi/.pi/agent/AGENTS.md' README.md
test_grep 'prefer the `pien coord ...` namespace' pi-skill-templates/agent-coordination/AGENTS.md
test_grep 'pien coord requirements generate --output REQUIREMENTS.md' scripts/pi-en-bwrap

printf 'PIEN-ISS-20260808-114006-001 item test passed\n'
