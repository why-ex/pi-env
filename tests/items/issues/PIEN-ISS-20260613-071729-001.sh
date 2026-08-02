#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ROLE_SOURCE_KINDS,
  discoverRoleSources,
  loadRoleRegistry,
} from "./role-manager/lib/role-loader.mjs";
import { formatRoleWarning } from "./role-manager/lib/role-schema.mjs";

const repoRoot = process.env.REPO_ROOT;
const packageRoot = join(repoRoot, "role-manager");
const externalProject = join(repoRoot, "examples", "project-role-override");
const expectedTools = ["read", "grep", "find", "ls", "bash", "edit", "write"];

const sources = discoverRoleSources({
  cwd: externalProject,
  packageRolesDir: join(packageRoot, "roles"),
  agentDir: join(repoRoot, "tests", "fixtures", "empty-agent"),
  env: {},
  homeDir: join(repoRoot, "tests", "fixtures", "empty-home"),
});
const registry = loadRoleRegistry(sources);
const warnings = registry.warnings.map(formatRoleWarning).join("\n");
const architect = registry.rolesByName.get("architect");
assert.ok(architect, warnings);
assert.equal(architect.source.kind, ROLE_SOURCE_KINDS.BASE);
assert.deepEqual(architect.tools, expectedTools);

const extensionSource = readFileSync(
  join(packageRoot, "extensions", "role-manager.ts"),
  "utf8",
);
assert.match(extensionSource, /requested unknown tools/);
assert.match(extensionSource, /pi\.setActiveTools\(validTools\)/);
NODE

printf 'PIEN-ISS-20260613-071729-001 passed\n'
