import { existsSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { validateRoleFile } from "./role-schema.mjs";

export const ROLE_SOURCE_KINDS = Object.freeze({
  BASE: "base",
  GLOBAL: "global",
  COMMON: "common",
  COORDINATION: "coordination",
  PROJECT: "project",
});

export const ROLE_MANAGER_STATE_CUSTOM_TYPE = "role-manager-state";

const ACTIVE_ROLE_ENV_KEYS = [
  "PI_ROLE_MANAGER_ACTIVE_ROLE",
  "PI_ACTIVE_ROLE",
  "PI_ROLE",
];

function makeWarning(sourcePath, message, field) {
  return { sourcePath, message, field };
}

function normalizePath(path, cwd = process.cwd()) {
  if (!path) return undefined;
  return isAbsolute(path) ? resolve(path) : resolve(cwd, path);
}

function findAncestorPath(cwd, relativePath) {
  let currentDir = normalizePath(cwd) ?? process.cwd();

  while (true) {
    const candidate = join(currentDir, relativePath);
    if (existsSync(candidate)) return candidate;

    const parent = dirname(currentDir);
    if (parent === currentDir) return join(cwd, relativePath);
    currentDir = parent;
  }
}

function addSource(sources, seenRoleDirs, source) {
  const roleDir = normalizePath(source.roleDir, source.cwd);
  if (!roleDir) return;

  const dedupeKey = roleDir;
  if (seenRoleDirs.has(dedupeKey)) return;
  seenRoleDirs.add(dedupeKey);

  sources.push({
    kind: source.kind ?? "custom",
    label: source.label ?? source.kind ?? roleDir,
    roleDir,
    optional: source.optional ?? true,
    requireSections: source.requireSections ?? false,
  });
}

export function discoverRoleSources(options = {}) {
  const cwd = normalizePath(options.cwd ?? process.cwd());
  const env = options.env ?? process.env;
  const home = options.homeDir ?? homedir();
  const sources = [];
  const seenRoleDirs = new Set();

  addSource(sources, seenRoleDirs, {
    kind: ROLE_SOURCE_KINDS.BASE,
    label: "base package roles",
    roleDir: options.packageRolesDir,
    cwd,
    optional: false,
    requireSections: true,
  });

  const agentDir =
    options.agentDir ?? env.PI_CODING_AGENT_DIR ?? join(home, ".pi", "agent");
  addSource(sources, seenRoleDirs, {
    kind: ROLE_SOURCE_KINDS.GLOBAL,
    label: "global agent roles",
    roleDir: join(agentDir, "roles"),
    cwd,
    optional: true,
  });

  const commonAgentDir = options.commonAgentDir ?? env.PI_EN_BWRAP_COMMON_AGENT_DIR;
  if (commonAgentDir) {
    addSource(sources, seenRoleDirs, {
      kind: ROLE_SOURCE_KINDS.COMMON,
      label: "common agent roles",
      roleDir: join(commonAgentDir, "roles"),
      cwd,
      optional: true,
    });
  }

  const coordinationDir = options.coordinationDir ?? env.PI_EN_COORD_DIR;
  if (coordinationDir) {
    addSource(sources, seenRoleDirs, {
      kind: ROLE_SOURCE_KINDS.COORDINATION,
      label: "coordination workspace roles",
      roleDir: join(coordinationDir, "roles"),
      cwd,
      optional: true,
    });
  } else {
    addSource(sources, seenRoleDirs, {
      kind: ROLE_SOURCE_KINDS.COORDINATION,
      label: "coordination workspace roles",
      roleDir: findAncestorPath(cwd, join("coordination", "roles")),
      cwd,
      optional: true,
    });
  }

  addSource(sources, seenRoleDirs, {
    kind: ROLE_SOURCE_KINDS.PROJECT,
    label: "project roles",
    roleDir: options.projectRolesDir ?? findAncestorPath(cwd, join(".pi", "roles")),
    cwd,
    optional: true,
  });

  return sources;
}

export function findRoleMarkdownFiles(roleDir) {
  const files = [];

  function visit(currentDir, relativeBase = "") {
    const entries = readdirSync(currentDir, { withFileTypes: true }).sort((a, b) =>
      a.name.localeCompare(b.name),
    );

    for (const entry of entries) {
      const relativePath = relativeBase
        ? `${relativeBase}/${entry.name}`
        : entry.name;
      const absolutePath = join(currentDir, entry.name);

      if (entry.isDirectory()) {
        visit(absolutePath, relativePath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        files.push({ absolutePath, relativePath });
      }
    }
  }

  visit(roleDir);
  return files;
}

function readSourceFiles(source) {
  try {
    if (!existsSync(source.roleDir)) {
      return {
        files: [],
        warnings: source.optional
          ? []
          : [makeWarning(source.roleDir, "could not read role directory: path does not exist")],
      };
    }

    const stats = statSync(source.roleDir);
    if (!stats.isDirectory()) {
      return {
        files: [],
        warnings: [makeWarning(source.roleDir, "could not read role directory: not a directory")],
      };
    }

    return { files: findRoleMarkdownFiles(source.roleDir), warnings: [] };
  } catch (error) {
    const details = error instanceof Error ? error.message : String(error);
    return {
      files: [],
      warnings: [makeWarning(source.roleDir, `could not read role directory: ${details}`)],
    };
  }
}

function normalizeSource(source, index) {
  return {
    index,
    kind: source.kind ?? "custom",
    label: source.label ?? source.kind ?? source.roleDir,
    roleDir: normalizePath(source.roleDir, source.cwd),
    optional: source.optional ?? true,
    requireSections: source.requireSections ?? false,
  };
}

export function loadRoleRegistry(sources, options = {}) {
  const normalizedSources = sources
    .map((source, index) => normalizeSource(source, index))
    .filter((source) => Boolean(source.roleDir));

  const registry = {
    sources: normalizedSources,
    roles: [],
    rolesByName: new Map(),
    invalidRoles: [],
    overrides: [],
    warnings: [],
  };

  for (const source of normalizedSources) {
    const sourceFiles = readSourceFiles(source);
    registry.warnings.push(...sourceFiles.warnings);

    for (const file of sourceFiles.files) {
      const validation = validateRoleFile(file.absolutePath, {
        requireSections: source.requireSections ?? options.requireSections,
      });
      registry.warnings.push(...validation.warnings);

      if (!validation.valid) {
        registry.invalidRoles.push({
          filePath: file.absolutePath,
          source,
          validation,
        });
        continue;
      }

      const role = {
        ...validation.role,
        source: {
          ...source,
          filePath: file.absolutePath,
          relativePath: file.relativePath,
        },
      };
      const previous = registry.rolesByName.get(role.name);
      if (previous) {
        registry.overrides.push({
          name: role.name,
          previous,
          replacement: role,
        });
      }
      registry.rolesByName.set(role.name, role);
    }
  }

  registry.roles = Array.from(registry.rolesByName.values()).sort((a, b) =>
    a.name.localeCompare(b.name),
  );

  return registry;
}

export function findRole(registry, name) {
  if (!registry || !name) return undefined;
  const normalized = String(name).trim();
  if (!normalized) return undefined;
  return registry.rolesByName.get(normalized);
}

export function formatActiveRoleSystemPrompt(role) {
  const title = role.icon ? `${role.icon} ${role.name}` : role.name;
  const metadata = [
    `- name: ${role.name}`,
    `- description: ${role.description}`,
  ];

  if (role.thinking) metadata.push(`- requested thinking: ${role.thinking}`);
  if (role.tools?.length) metadata.push(`- requested tools: ${role.tools.join(", ")}`);
  if (role.model) metadata.push(`- requested model: ${role.model}`);
  if (role.provider) metadata.push(`- requested provider: ${role.provider}`);
  const coordinationRole = role.coordCommitter ?? role.name;
  if (coordinationRole) {
    metadata.push(`- coordination role: ${coordinationRole}`);
  }

  return `## Active Role: ${title}

The current session has the \`${role.name}\` role active. Follow this role
for the current turn. Do not assume instructions from inactive roles.
When running coordination helper commands, preserve the active role by using
\`--role ${coordinationRole}\` or the role manager's \`PI_EN_COORD_ROLE\`
environment value. This affects coordination helper commits only; do not use
role-specific Git identity for project repository commits unless explicitly
requested.

### Role metadata

${metadata.join("\n")}

### Role instructions

${role.body.trim()}
`;
}

function normalizeRoleName(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeStringList(value) {
  if (!Array.isArray(value)) return undefined;
  const normalized = value
    .map((item) => normalizeRoleName(item))
    .filter((item) => Boolean(item));
  return normalized;
}

function normalizeRuntimeSettings(value) {
  if (!value || typeof value !== "object") return undefined;

  const settings = {
    provider: normalizeRoleName(value.provider),
    model: normalizeRoleName(value.model) ?? normalizeRoleName(value.modelId),
    thinkingLevel: normalizeRoleName(value.thinkingLevel),
    tools: normalizeStringList(value.tools),
  };

  if (
    settings.provider === undefined &&
    settings.model === undefined &&
    settings.thinkingLevel === undefined &&
    settings.tools === undefined
  ) {
    return undefined;
  }

  return settings;
}

function latestActiveRoleStateFromEntries(entries = []) {
  for (let index = entries.length - 1; index >= 0; index--) {
    const entry = entries[index];
    if (!entry || entry.type !== "custom") continue;
    if (entry.customType !== ROLE_MANAGER_STATE_CUSTOM_TYPE) continue;

    const data = entry.data ?? {};
    const previousSettings =
      normalizeRuntimeSettings(data.previousSettings) ??
      normalizeRuntimeSettings(data.originalSettings) ??
      normalizeRuntimeSettings(data.previousDefaults);

    if (
      data.activeRoleName === null ||
      data.activeRoleName === "" ||
      data.activeRole === null ||
      data.activeRole === "" ||
      data.role === null ||
      data.role === ""
    ) {
      return {
        found: true,
        roleName: undefined,
        previousSettings,
        source: "session",
      };
    }

    return {
      found: true,
      roleName:
        normalizeRoleName(data.activeRoleName) ??
        normalizeRoleName(data.activeRole) ??
        normalizeRoleName(data.role),
      previousSettings,
      source: "session",
    };
  }

  return { found: false, roleName: undefined, previousSettings: undefined, source: undefined };
}

export function activeRoleStateFromEntries(entries = []) {
  return latestActiveRoleStateFromEntries(entries);
}

export function activeRoleNameFromEntries(entries = []) {
  return latestActiveRoleStateFromEntries(entries).roleName;
}

export function activeRoleNameFromEnv(env = process.env) {
  for (const key of ACTIVE_ROLE_ENV_KEYS) {
    const value = normalizeRoleName(env[key]);
    if (value) return value;
  }
  return undefined;
}

export function resolveActiveRoleState(options = {}) {
  const entryState = latestActiveRoleStateFromEntries(options.entries ?? []);
  if (entryState.found) return entryState;

  const roleName = activeRoleNameFromEnv(options.env ?? process.env);
  if (roleName) {
    return {
      found: true,
      roleName,
      previousSettings: undefined,
      source: "env",
    };
  }

  return { found: false, roleName: undefined, previousSettings: undefined, source: undefined };
}

export function resolveActiveRoleName(options = {}) {
  return resolveActiveRoleState(options).roleName;
}
