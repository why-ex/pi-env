#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

test_dir_exists designs
test_file_exists designs/agent-coordination.md
test_file_exists designs/role-manager.md

old_agent="AGENT_COORDINATION""_DESIGN.md"
old_role="ROLE_TEMPLATES""_DESIGN.md"
old_design_path_pattern="${old_agent}|${old_role}"

[ ! -e "$old_agent" ] || test_fail 'old agent coordination design path still exists'
[ ! -e "$old_role" ] || test_fail 'old role manager design path still exists'

test_grep 'designs/agent-coordination.md' README.md
test_grep 'designs/role-manager.md' README.md

if grep -R -n -E "$old_design_path_pattern" \
  README.md REQUIREMENTS.md scripts tests designs role-manager pi-en examples 2>/dev/null; then
  test_fail 'old top-level design paths are still referenced in active project files'
fi

if grep -n -E "${old_design_path_pattern}|designs/agent-coordination\.md|designs/role-manager\.md" \
  REQUIREMENTS.md .pi-en/coordination/requirements/*.yaml scripts/pi-en-coord-generate-requirements 2>/dev/null; then
  test_fail 'requirements content or generator links directly to design documents'
fi

echo "design document relocation tests passed"
