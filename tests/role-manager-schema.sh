#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  formatRoleWarning,
  REQUIRED_BODY_SECTIONS,
  validateRoleDirectory,
  validateRoleMarkdown,
} from "./role-manager/lib/role-schema.mjs";

const repoRoot = process.env.REPO_ROOT;
const rolesDir = join(repoRoot, "role-manager", "roles");
const expectedRoleTools = new Map([
  ["architect", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
  ["builder", ["read", "grep", "find", "ls", "bash", "edit"]],
  ["developer", ["read", "grep", "find", "ls", "edit", "write", "bash"]],
  ["reviewer", ["read", "grep", "find", "ls", "bash"]],
  ["tester", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
]);
const expectedRoles = [...expectedRoleTools.keys()];

const base = validateRoleDirectory(rolesDir, { requireSections: true });
assert.deepEqual(
  base.roles.map((role) => role.name),
  expectedRoles,
  base.warnings.map(formatRoleWarning).join("\n"),
);
assert.equal(
  base.invalidRoles.length,
  0,
  base.warnings.map(formatRoleWarning).join("\n"),
);
assert.equal(
  base.warnings.length,
  0,
  base.warnings.map(formatRoleWarning).join("\n"),
);

for (const role of base.roles) {
  assert.ok(role.description.length > 0, `${role.name} has no description`);
  assert.deepEqual(
    role.tools,
    expectedRoleTools.get(role.name),
    `${role.name} bundled tools do not match CMD-017`,
  );
  for (const section of REQUIRED_BODY_SECTIONS) {
    assert.ok(
      role.sections.includes(section),
      `${role.name} missing required section ${section}`,
    );
  }
}

const missingName = validateRoleMarkdown(
  `---\ndescription: Missing name\n---\n# Broken\n`,
  "missing-name.md",
);
assert.equal(missingName.valid, false);
assert.ok(
  missingName.warnings.some((warning) =>
    warning.message.includes('missing required frontmatter field "name"'),
  ),
  missingName.warnings.map(formatRoleWarning).join("\n"),
);

const missingDescription = validateRoleMarkdown(
  `---\nname: broken\n---\n# Broken\n`,
  "missing-description.md",
);
assert.equal(missingDescription.valid, false);
assert.ok(
  missingDescription.warnings.some((warning) =>
    warning.message.includes('missing required frontmatter field "description"'),
  ),
  missingDescription.warnings.map(formatRoleWarning).join("\n"),
);

const invalidTools = validateRoleMarkdown(
  `---\nname: broken\ndescription: Bad tools\ntools: bash\n---\n# Broken\n`,
  "invalid-tools.md",
);
assert.equal(invalidTools.valid, false);
assert.ok(
  invalidTools.warnings.some((warning) =>
    warning.message.includes('field "tools" must be a list'),
  ),
  invalidTools.warnings.map(formatRoleWarning).join("\n"),
);

const tmp = mkdtempSync(join(tmpdir(), "pi-en-roles-"));
writeFileSync(
  join(tmp, "invalid.md"),
  `---\nname: invalid\n---\n# Invalid\n`,
);
const invalidDir = validateRoleDirectory(tmp, { requireSections: true });
const warningText = invalidDir.warnings.map(formatRoleWarning).join("\n");
assert.equal(invalidDir.roles.length, 0, warningText);
assert.equal(invalidDir.invalidRoles.length, 1, warningText);
assert.match(warningText, /role-manager: .*invalid\.md: invalid role file:/);
assert.match(warningText, /missing required frontmatter field "description"/);

console.log("role manager schema tests passed");
NODE
