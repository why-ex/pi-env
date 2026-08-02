#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  ROLE_MANAGER_STATE_CUSTOM_TYPE,
  ROLE_SOURCE_KINDS,
  activeRoleNameFromEntries,
  activeRoleStateFromEntries,
  discoverRoleSources,
  formatActiveRoleSystemPrompt,
  loadRoleRegistry,
  resolveActiveRoleName,
  resolveActiveRoleState,
} from "./role-manager/lib/role-loader.mjs";
import { formatRoleWarning } from "./role-manager/lib/role-schema.mjs";

function roleMarkdown({ name, description, marker }) {
  return `---
name: ${name}
description: ${description}
tools: ["read"]
---
# ${description}

## Mission

${marker} mission.

## Allowed actions

${marker} allowed.

## Forbidden actions

${marker} forbidden.

## One-cycle workflow

${marker} workflow.

## Expected final report

${marker} final report.

## Coordination behavior

${marker} coordination.
`;
}

function writeRole(dir, filename, role) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, filename), roleMarkdown(role));
}

const tmp = mkdtempSync(join(tmpdir(), "pi-en-role-loader-"));
const baseRoles = join(tmp, "base", "roles");
const globalAgent = join(tmp, "global-agent");
const commonAgent = join(tmp, "common-agent");
const coordination = join(tmp, "coordination");
const project = join(tmp, "project");
const projectCwd = join(project, "src", "nested");
mkdirSync(projectCwd, { recursive: true });

writeRole(baseRoles, "architect.md", {
  name: "architect",
  description: "Base architect",
  marker: "BASE architect",
});
writeRole(baseRoles, "developer.md", {
  name: "developer",
  description: "Base developer",
  marker: "BASE developer",
});
writeRole(join(globalAgent, "roles"), "developer.md", {
  name: "developer",
  description: "Global developer",
  marker: "GLOBAL developer",
});
writeRole(join(commonAgent, "roles"), "developer.md", {
  name: "developer",
  description: "Common developer",
  marker: "COMMON developer",
});
writeRole(join(commonAgent, "roles"), "common-only.md", {
  name: "common_only",
  description: "Common only",
  marker: "COMMON only",
});
writeRole(join(coordination, "roles"), "developer.md", {
  name: "developer",
  description: "Coordination developer",
  marker: "COORD developer",
});
writeRole(join(project, ".pi", "roles"), "developer.md", {
  name: "developer",
  description: "Project developer",
  marker: "PROJECT developer",
});
writeRole(join(project, ".pi", "roles", "nested"), "reviewer.md", {
  name: "reviewer",
  description: "Nested reviewer",
  marker: "PROJECT nested reviewer",
});
writeFileSync(
  join(project, ".pi", "roles", "invalid.md"),
  `---\ndescription: Missing name\n---\n# Invalid\n`,
);

const sources = discoverRoleSources({
  cwd: projectCwd,
  packageRolesDir: baseRoles,
  agentDir: globalAgent,
  commonAgentDir: commonAgent,
  coordinationDir: coordination,
  env: {},
  homeDir: join(tmp, "home"),
});
assert.deepEqual(
  sources.map((source) => source.kind),
  [
    ROLE_SOURCE_KINDS.BASE,
    ROLE_SOURCE_KINDS.GLOBAL,
    ROLE_SOURCE_KINDS.COMMON,
    ROLE_SOURCE_KINDS.COORDINATION,
    ROLE_SOURCE_KINDS.PROJECT,
  ],
);
assert.equal(
  sources.find((source) => source.kind === ROLE_SOURCE_KINDS.PROJECT).roleDir,
  join(project, ".pi", "roles"),
);

const registry = loadRoleRegistry(sources);
const warningText = registry.warnings.map(formatRoleWarning).join("\n");
assert.ok(registry.rolesByName.has("architect"), warningText);
assert.ok(registry.rolesByName.has("developer"), warningText);
assert.ok(registry.rolesByName.has("common_only"), warningText);
assert.ok(registry.rolesByName.has("reviewer"), warningText);
assert.equal(registry.invalidRoles.length, 1, warningText);
assert.match(warningText, /invalid\.md: invalid role file:/);
assert.match(warningText, /missing required frontmatter field "name"/);

const developer = registry.rolesByName.get("developer");
assert.equal(developer.source.kind, ROLE_SOURCE_KINDS.PROJECT);
assert.match(developer.body, /PROJECT developer mission/);
assert.equal(
  registry.overrides.filter((override) => override.name === "developer").length,
  4,
);

const prompt = formatActiveRoleSystemPrompt(developer);
assert.match(prompt, /Active Role: developer/);
assert.match(prompt, /PROJECT developer mission/);
assert.doesNotMatch(prompt, /BASE developer mission/);
assert.doesNotMatch(prompt, /COMMON only mission/);
assert.doesNotMatch(prompt, /PROJECT nested reviewer mission/);

const activeEntries = [
  {
    type: "custom",
    customType: ROLE_MANAGER_STATE_CUSTOM_TYPE,
    data: {
      activeRoleName: "developer",
      previousSettings: {
        provider: "anthropic",
        model: "claude-sonnet-4-5",
        thinkingLevel: "low",
        tools: ["read", "bash"],
      },
    },
  },
];
assert.equal(activeRoleNameFromEntries(activeEntries), "developer");
assert.deepEqual(activeRoleStateFromEntries(activeEntries), {
  found: true,
  roleName: "developer",
  previousSettings: {
    provider: "anthropic",
    model: "claude-sonnet-4-5",
    thinkingLevel: "low",
    tools: ["read", "bash"],
  },
  source: "session",
});
assert.equal(
  resolveActiveRoleName({ entries: activeEntries, env: { PI_ROLE: "architect" } }),
  "developer",
);
assert.equal(
  resolveActiveRoleName({ entries: [], env: { PI_ROLE_MANAGER_ACTIVE_ROLE: "reviewer" } }),
  "reviewer",
);
assert.deepEqual(
  resolveActiveRoleState({ entries: [], env: { PI_ROLE_MANAGER_ACTIVE_ROLE: "reviewer" } }),
  {
    found: true,
    roleName: "reviewer",
    previousSettings: undefined,
    source: "env",
  },
);
assert.equal(
  resolveActiveRoleName({
    entries: [
      ...activeEntries,
      {
        type: "custom",
        customType: ROLE_MANAGER_STATE_CUSTOM_TYPE,
        data: { activeRoleName: null },
      },
    ],
    env: { PI_ROLE: "architect" },
  }),
  undefined,
);

console.log("role manager loader tests passed");
NODE
