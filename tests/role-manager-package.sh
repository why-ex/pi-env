#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ROLE_SOURCE_KINDS,
  discoverRoleSources,
  loadRoleRegistry,
} from "./role-manager/lib/role-loader.mjs";
import { formatRoleWarning, validateRoleFile } from "./role-manager/lib/role-schema.mjs";

const repoRoot = process.env.REPO_ROOT;
const packageRoot = join(repoRoot, "role-manager");
const expectedRoleTools = new Map([
  ["architect", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
  ["builder", ["read", "grep", "find", "ls", "bash", "edit"]],
  ["developer", ["read", "grep", "find", "ls", "edit", "write", "bash"]],
  ["reviewer", ["read", "grep", "find", "ls", "bash"]],
  ["tester", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
]);
const manifest = JSON.parse(readFileSync(join(packageRoot, "package.json"), "utf8"));

assert.equal(manifest.name, "pi-en-role-manager");
assert.ok(manifest.keywords.includes("pi-package"), "package is not tagged as a Pi package");
assert.deepEqual(manifest.pi.extensions, ["./extensions/role-manager.ts"]);
assert.ok(existsSync(join(packageRoot, "extensions", "role-manager.ts")));
assert.ok(existsSync(join(packageRoot, "lib", "role-loader.mjs")));
assert.ok(existsSync(join(packageRoot, "roles", "architect.md")));

const flake = readFileSync(join(repoRoot, "flake.nix"), "utf8");
const piBwrap = readFileSync(join(repoRoot, "scripts", "pi-en-bwrap"), "utf8");
assert.match(flake, /mkRoleManagerPackage/);
assert.match(flake, /pi-role-manager = roleManagerPackage/);
assert.match(flake, /PI_EN_ROLE_MANAGER_PACKAGE/);
assert.match(piBwrap, /for common_dir_name in skills prompts roles; do/);

const exampleProject = join(repoRoot, "examples", "project-role-override");
const exampleRolePath = join(
  exampleProject,
  ".pi",
  "roles",
  "domain-architect.md",
);
const exampleValidation = validateRoleFile(exampleRolePath, { requireSections: true });
assert.equal(
  exampleValidation.valid,
  true,
  exampleValidation.warnings.map(formatRoleWarning).join("\n"),
);

const sources = discoverRoleSources({
  cwd: exampleProject,
  packageRolesDir: join(packageRoot, "roles"),
  agentDir: join(repoRoot, "tests", "fixtures", "empty-agent"),
  env: {},
  homeDir: join(repoRoot, "tests", "fixtures", "empty-home"),
});
const registry = loadRoleRegistry(sources);
const warnings = registry.warnings.map(formatRoleWarning).join("\n");
assert.equal(registry.invalidRoles.length, 0, warnings);
for (const [roleName, tools] of expectedRoleTools) {
  assert.ok(registry.rolesByName.has(roleName), `${roleName} missing: ${warnings}`);
  const role = registry.rolesByName.get(roleName);
  assert.equal(role.source.kind, ROLE_SOURCE_KINDS.BASE, `${roleName} should load from package roles`);
  assert.deepEqual(role.tools, tools, `${roleName} package tools do not match CMD-017`);
}
assert.ok(registry.rolesByName.has("domain-architect"), warnings);
assert.equal(
  registry.rolesByName.get("domain-architect").source.kind,
  ROLE_SOURCE_KINDS.PROJECT,
);
assert.match(registry.rolesByName.get("domain-architect").body, /project's domain model/);

console.log("role manager package tests passed");
NODE
