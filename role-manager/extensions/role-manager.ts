import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  ROLE_MANAGER_STATE_CUSTOM_TYPE,
  discoverRoleSources,
  findRole,
  formatActiveRoleSystemPrompt,
  loadRoleRegistry,
  resolveActiveRoleName,
  resolveActiveRoleState,
} from "../lib/role-loader.mjs";
import { formatRoleWarning } from "../lib/role-schema.mjs";

const extensionDir = dirname(fileURLToPath(import.meta.url));
const packageRoot = join(extensionDir, "..");
const bundledRolesDir = join(packageRoot, "roles");
const ROLE_STATE_VERSION = 1;
const ROLE_CYCLE_DONE_TOOL_NAME = "role_cycle_done";
const ROLE_UI_STATUS_KEY = "role-manager";
const ROLE_CYCLE_WIDGET_KEY = "role-manager-cycle";
const ROLE_CYCLE_SECTION_TITLE = "One-cycle workflow";
const PI_EN_COORD_ROLE_ENV = "PI_EN_COORD_ROLE";
const ROLE_CYCLE_AUTO_SHUTDOWN_ENV = "PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE";

const ROLE_CYCLE_DONE_PARAMETERS = {
  type: "object",
  additionalProperties: false,
  required: [
    "summary",
    "filesInspected",
    "filesChanged",
    "testsChecksRun",
    "coordinationUpdates",
    "recommendedNextRole",
  ],
  properties: {
    summary: {
      type: "string",
      description: "Concise final summary of the completed role cycle.",
    },
    filesInspected: {
      type: "array",
      description: "Files or resources inspected during the cycle. Use [] if none.",
      items: { type: "string" },
    },
    filesChanged: {
      type: "array",
      description: "Files changed during the cycle. Use [] if none.",
      items: { type: "string" },
    },
    testsChecksRun: {
      type: "array",
      description: "Tests or checks run, including result notes. Use [] if none.",
      items: { type: "string" },
    },
    coordinationUpdates: {
      type: "array",
      description: "Coordination repo updates made during the cycle. Use [] if none.",
      items: { type: "string" },
    },
    recommendedNextRole: {
      type: "string",
      description: "Recommended next role, or \"none\" if no follow-up role is needed.",
    },
  },
} as const;

interface RuntimeSettingsSnapshot {
  provider?: string;
  model?: string;
  thinkingLevel?: string;
  tools?: string[];
}

interface ParsedRoleCycleArgs {
  roleName: string;
  goal: string;
}

interface RoleCycleDoneInput {
  summary: string;
  filesInspected: string[];
  filesChanged: string[];
  testsChecksRun: string[];
  coordinationUpdates: string[];
  recommendedNextRole: string;
}

interface RoleCycleDoneDetails extends RoleCycleDoneInput {
  completedAt: string;
}

interface RoleCycleState {
  mode?: string;
  goal?: string;
  startedAt?: string;
  completedAt?: string;
  checklist?: string[];
  summary?: string;
  recommendedNextRole?: string;
}

interface RoleDisplayInfo {
  name: string;
  icon?: string;
  body?: string;
}

const MAX_ROLE_SESSION_NAME_LENGTH = 80;

function notifyWarning(ctx: ExtensionContext, message: string) {
  try {
    if (ctx.hasUI) {
      ctx.ui.notify(message, "warning");
    } else {
      console.warn(message);
    }
  } catch (_error) {
    console.warn(message);
  }
}

function notifyInfo(ctx: ExtensionContext, message: string) {
  try {
    if (ctx.hasUI) {
      ctx.ui.notify(message, "info");
    } else {
      console.warn(message);
    }
  } catch (_error) {
    console.warn(message);
  }
}

function notifyError(ctx: ExtensionContext, message: string) {
  try {
    if (ctx.hasUI) {
      ctx.ui.notify(message, "error");
    } else {
      console.error(message);
    }
  } catch (_error) {
    console.error(message);
  }
}

function getSessionEntries(ctx: ExtensionContext) {
  try {
    return ctx.sessionManager.getBranch();
  } catch (_error) {
    try {
      return ctx.sessionManager.getEntries();
    } catch (_innerError) {
      return [];
    }
  }
}

function normalizeText(value: unknown) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function collapseWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function normalizeStringArray(value: unknown) {
  if (Array.isArray(value)) {
    return value
      .map((item) => normalizeText(item))
      .filter((item): item is string => Boolean(item));
  }

  const text = normalizeText(value);
  return text ? [text] : [];
}

function normalizeRoleCycleState(value: unknown): RoleCycleState | undefined {
  if (!value || typeof value !== "object") return undefined;

  const data = value as Record<string, unknown>;
  const checklist = normalizeStringArray(data.checklist);
  const state: RoleCycleState = {
    mode: normalizeText(data.mode),
    goal: normalizeText(data.goal),
    startedAt: normalizeText(data.startedAt),
    completedAt: normalizeText(data.completedAt),
    checklist: checklist.length > 0 ? checklist : undefined,
    summary: normalizeText(data.summary),
    recommendedNextRole: normalizeText(data.recommendedNextRole),
  };

  if (
    !state.mode &&
    !state.goal &&
    !state.startedAt &&
    !state.completedAt &&
    !state.summary &&
    !state.recommendedNextRole &&
    !state.checklist
  ) {
    return undefined;
  }

  return state;
}

function isRoleCycleRunning(cycle: RoleCycleState | undefined) {
  return Boolean(cycle && !cycle.completedAt && (cycle.goal || cycle.startedAt));
}

function headingText(line: string) {
  const match = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line.trim());
  if (!match) return undefined;
  return { level: match[1].length, title: match[2].trim() };
}

function extractMarkdownSection(body: string | undefined, title: string) {
  if (!body) return "";

  const lines = body.split(/\r?\n/);
  let start = -1;
  let level = 0;

  for (let index = 0; index < lines.length; index++) {
    const heading = headingText(lines[index]);
    if (heading?.title.toLowerCase() === title.toLowerCase()) {
      start = index;
      level = heading.level;
      break;
    }
  }

  if (start < 0) return "";

  let end = lines.length;
  for (let index = start + 1; index < lines.length; index++) {
    const heading = headingText(lines[index]);
    if (heading && heading.level <= level) {
      end = index;
      break;
    }
  }

  return lines.slice(start + 1, end).join("\n").trim();
}

function stripMarkdownInline(value: string) {
  return value
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/_([^_]+)_/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function extractRoleCycleChecklist(role: RoleDisplayInfo) {
  const section = extractMarkdownSection(role.body, ROLE_CYCLE_SECTION_TITLE);
  const items: string[] = [];
  let currentIndex = -1;

  for (const line of section.split(/\r?\n/)) {
    const item = /^\s*(?:[-*+]\s+(?:\[[ xX]\]\s*)?|\d+[.)]\s+)(.+?)\s*$/.exec(line);
    if (item) {
      const text = normalizeText(stripMarkdownInline(item[1]));
      if (text) {
        items.push(text);
        currentIndex = items.length - 1;
      }
      continue;
    }

    const continuation = normalizeText(stripMarkdownInline(line));
    if (currentIndex >= 0 && continuation && /^\s{2,}\S/.test(line)) {
      items[currentIndex] = `${items[currentIndex]} ${continuation}`;
    }
  }

  if (items.length > 0) return items;

  const fallback = normalizeText(stripMarkdownInline(section));
  if (fallback) return [fallback];

  return [
    "Follow the role's one-cycle workflow.",
    `Call ${ROLE_CYCLE_DONE_TOOL_NAME} with the final report.`,
  ];
}

function formatRoleStatusText(role: RoleDisplayInfo) {
  return `${role.icon ? `${role.icon} ` : ""}role:${role.name}`;
}

function formatRoleTerminalTitle(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  roleName?: string,
) {
  const cwdName = basename(ctx.cwd || process.cwd()) || "workspace";
  const sessionName = normalizeText(pi.getSessionName());
  const parts = ["π"];
  if (sessionName) parts.push(sessionName);
  if (roleName) parts.push(`role:${roleName}`);
  parts.push(cwdName);
  return parts.join(" - ");
}

function themeText(ctx: ExtensionContext, color: string, text: string) {
  const theme = (ctx.ui as any)?.theme;
  if (typeof theme?.fg === "function") {
    try {
      return theme.fg(color, text);
    } catch (_error) {
      return text;
    }
  }
  return text;
}

function setRoleStatus(ctx: ExtensionContext, text: string | undefined) {
  if (!ctx.hasUI) return;
  const setStatus = (ctx.ui as any)?.setStatus;
  if (typeof setStatus !== "function") return;

  try {
    setStatus.call(ctx.ui, ROLE_UI_STATUS_KEY, text);
  } catch (_error) {
    // UI decoration must never break role commands or non-interactive modes.
  }
}

function setRoleWidget(ctx: ExtensionContext, lines: string[] | undefined) {
  if (!ctx.hasUI) return;
  const setWidget = (ctx.ui as any)?.setWidget;
  if (typeof setWidget !== "function") return;

  try {
    setWidget.call(ctx.ui, ROLE_CYCLE_WIDGET_KEY, lines);
  } catch (_error) {
    // UI decoration must never break role commands or non-interactive modes.
  }
}

function setRoleTitle(pi: ExtensionAPI, ctx: ExtensionContext, roleName?: string) {
  if (!ctx.hasUI) return;
  const setTitle = (ctx.ui as any)?.setTitle;
  if (typeof setTitle !== "function") return;

  try {
    setTitle.call(ctx.ui, formatRoleTerminalTitle(pi, ctx, roleName));
  } catch (_error) {
    // UI decoration must never break role commands or non-interactive modes.
  }
}

function formatRoleCycleChecklistPrompt(role: RoleDisplayInfo) {
  const checklist = extractRoleCycleChecklist(role);
  if (checklist.length === 0) return "";

  return [
    "One-cycle checklist:",
    ...checklist.map((item, index) => `${index + 1}. ${item}`),
    "",
  ].join("\n");
}

function applyRoleUI(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  role: RoleDisplayInfo | undefined,
  _cycleValue?: unknown,
) {
  if (!role?.name) {
    clearRoleUI(pi, ctx);
    return;
  }

  setRoleStatus(ctx, themeText(ctx, "accent", formatRoleStatusText(role)));
  setRoleTitle(pi, ctx, role.name);

  // Keep the cycle checklist in the kickoff prompt only. A persistent widget
  // repeats before later prompts and makes /role-new behavior feel different
  // across sessions depending on UI/tool availability.
  setRoleWidget(ctx, undefined);
}

function clearRoleUI(pi: ExtensionAPI, ctx: ExtensionContext) {
  setRoleStatus(ctx, undefined);
  setRoleWidget(ctx, undefined);
  setRoleTitle(pi, ctx);
}

function prepareRoleCycleDoneArguments(args: unknown): RoleCycleDoneInput | unknown {
  if (!args || typeof args !== "object") return args;

  const input = args as Record<string, unknown>;
  return {
    summary: normalizeText(input.summary ?? input.result ?? input.report) ?? "",
    filesInspected: normalizeStringArray(
      input.filesInspected ?? input.inspectedFiles ?? input.files_inspected,
    ),
    filesChanged: normalizeStringArray(
      input.filesChanged ?? input.changedFiles ?? input.files_changed,
    ),
    testsChecksRun: normalizeStringArray(
      input.testsChecksRun ??
        input.testsRun ??
        input.checksRun ??
        input.tests_checks_run ??
        input.tests ??
        input.checks,
    ),
    coordinationUpdates: normalizeStringArray(
      input.coordinationUpdates ?? input.coordination ?? input.coordination_updates,
    ),
    recommendedNextRole:
      normalizeText(
        input.recommendedNextRole ?? input.nextRole ?? input.recommended_next_role,
      ) ?? "none",
  };
}

function formatListCount(label: string, items: string[]) {
  const count = items.length;
  return `${label}: ${count}`;
}

function formatBulletSection(label: string, items: string[]) {
  if (items.length === 0) return `${label}: none`;
  return `${label}:\n${items.map((item) => `- ${item}`).join("\n")}`;
}

function truncateInline(value: string, maxLength = 96) {
  const normalized = collapseWhitespace(value);
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
}

function wrapPlainLine(line: string, width: number) {
  if (line.length <= width) return [line];

  const chunks: string[] = [];
  let remaining = line;
  while (remaining.length > width) {
    chunks.push(remaining.slice(0, width));
    remaining = remaining.slice(width);
  }
  chunks.push(remaining);
  return chunks;
}

function textBlock(text: string) {
  return {
    render(width: number) {
      const safeWidth = Number.isFinite(width) && width > 0 ? Math.floor(width) : 80;
      return text.split("\n").flatMap((line) => wrapPlainLine(line, safeWidth));
    },
    invalidate() {},
  };
}

function formatRoleCycleDoneCompact(details: RoleCycleDoneDetails) {
  const counts = [
    formatListCount("inspected", details.filesInspected),
    formatListCount("changed", details.filesChanged),
    formatListCount("checks", details.testsChecksRun),
    formatListCount("coordination", details.coordinationUpdates),
  ].join(" • ");

  return [
    "✓ Role cycle complete",
    details.summary,
    counts,
    `Next role: ${details.recommendedNextRole}`,
  ].join("\n");
}

function formatRoleCycleDoneExpanded(details: RoleCycleDoneDetails) {
  return [
    "✓ Role cycle complete",
    `Summary: ${details.summary}`,
    `Completed: ${details.completedAt}`,
    formatBulletSection("Files inspected", details.filesInspected),
    formatBulletSection("Files changed", details.filesChanged),
    formatBulletSection("Tests/checks run", details.testsChecksRun),
    formatBulletSection("Coordination updates", details.coordinationUpdates),
    `Recommended next role: ${details.recommendedNextRole}`,
  ].join("\n\n");
}

function parseRoleCycleArgs(args: string): ParsedRoleCycleArgs | undefined {
  const trimmed = args.trim();
  if (!trimmed) return undefined;

  const match = /^(\S+)(?:\s+([\s\S]+))?$/.exec(trimmed);
  if (!match) return undefined;

  const roleName = normalizeText(match[1]);
  const goal = normalizeText(match[2]);
  if (!roleName || !goal) return undefined;

  return { roleName, goal };
}

function formatRoleCyclePrompt(role: any, goal: string) {
  const roleName = role.name ?? "unknown";
  const roleTitle = role.icon ? `${role.icon} ${roleName}` : roleName;
  const checklist = formatRoleCycleChecklistPrompt(role);

  return `## Role cycle kickoff

Active role: ${roleTitle}
Goal: ${goal.trim()}

${checklist}Run exactly one bounded cycle for the active role.

Operating constraints:

- Follow the active role instructions and its one-cycle workflow.
- Work only on the stated goal; do not start unrelated tasks.
- Project changes are allowed only when directly needed for the goal and
  permitted by the current repository instructions.
- Coordination changes are allowed only when directly needed for the goal and
  permitted by the current coordination rules.
- Use only context available in this session. If this is a fresh session, do
  not assume parent-session conversation details unless they are included here.
- Finish by calling \`role_cycle_done\` as the final action of the cycle when
  that tool is available. Treat that structured tool report as the role's
  expected final report.
- Populate every \`role_cycle_done\` field: \`summary\`, \`filesInspected\`,
  \`filesChanged\`, \`testsChecksRun\`, \`coordinationUpdates\`, and
  \`recommendedNextRole\`. Use empty arrays for list fields with no entries,
  and use \`none\` when there is no recommended next role.
- If \`role_cycle_done\` is unavailable, do not output JSON. End with the
  role's normal prose final report instead.
- After calling \`role_cycle_done\`, stop. Do not emit another assistant
  response and do not begin a second role cycle.
`;
}

function formatRoleSessionName(roleName: string, goal: string) {
  const prefix = `[${roleName}] `;
  const fallbackGoal = "role cycle";
  const normalizedGoal = collapseWhitespace(goal) || fallbackGoal;
  const maxGoalLength = Math.max(1, MAX_ROLE_SESSION_NAME_LENGTH - prefix.length);

  if (normalizedGoal.length <= maxGoalLength) {
    return `${prefix}${normalizedGoal}`;
  }

  if (maxGoalLength > 3) {
    return `${prefix}${normalizedGoal.slice(0, maxGoalLength - 3).trimEnd()}...`;
  }

  return `${prefix}${normalizedGoal.slice(0, maxGoalLength)}`;
}

function formatRoleCycleCommand(roleName: string, goal: string) {
  return `/role-cycle ${roleName} ${goal.trim()}`;
}

function uniqueToolNames(tools: string[]) {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const tool of tools) {
    if (seen.has(tool)) continue;
    seen.add(tool);
    result.push(tool);
  }
  return result;
}

function envFlagEnabled(name: string) {
  const value = process.env[name]?.trim();
  return Boolean(value && !/^(0|false|no|off)$/i.test(value));
}

function requestAutoShutdownAfterRoleCycle(ctx: ExtensionContext | undefined) {
  if (!ctx || !envFlagEnabled(ROLE_CYCLE_AUTO_SHUTDOWN_ENV)) return;

  try {
    ctx.shutdown();
  } catch (error) {
    console.warn(
      `role-manager: failed to request automatic shutdown after ${ROLE_CYCLE_DONE_TOOL_NAME}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function sameModel(left: unknown, right: unknown) {
  const leftModel = left as { provider?: unknown; id?: unknown } | undefined;
  const rightModel = right as { provider?: unknown; id?: unknown } | undefined;
  return (
    leftModel?.provider === rightModel?.provider && leftModel?.id === rightModel?.id
  );
}

export default function roleManager(pi: ExtensionAPI) {
  pi.registerTool({
    name: ROLE_CYCLE_DONE_TOOL_NAME,
    label: "Role Cycle Done",
    description:
      "Terminate a role cycle with a structured completion report. Use this as the final action for /role-cycle or /role-new work after the bounded cycle is complete.",
    promptSnippet: "Finish a role cycle with a structured report and terminate",
    promptGuidelines: [
      "Use role_cycle_done as the final action of a role cycle after all required work, checks, and coordination updates are complete.",
      "When calling role_cycle_done, populate summary, filesInspected, filesChanged, testsChecksRun, coordinationUpdates, and recommendedNextRole; use [] for none and \"none\" for no next role.",
      "After calling role_cycle_done, do not emit another assistant response in the same turn.",
    ],
    parameters: ROLE_CYCLE_DONE_PARAMETERS as any,
    prepareArguments: prepareRoleCycleDoneArguments as any,
    async execute(
      _toolCallId: string,
      params: RoleCycleDoneInput,
      _signal?: AbortSignal,
      _onUpdate?: unknown,
      ctx?: ExtensionContext,
    ) {
      const details: RoleCycleDoneDetails = {
        summary: normalizeText(params.summary) ?? "",
        filesInspected: normalizeStringArray(params.filesInspected),
        filesChanged: normalizeStringArray(params.filesChanged),
        testsChecksRun: normalizeStringArray(params.testsChecksRun),
        coordinationUpdates: normalizeStringArray(params.coordinationUpdates),
        recommendedNextRole: normalizeText(params.recommendedNextRole) ?? "none",
        completedAt: new Date().toISOString(),
      };

      completeRoleCycle(details, ctx);
      requestAutoShutdownAfterRoleCycle(ctx);

      return {
        content: [
          {
            type: "text",
            text: `Role cycle complete. Summary: ${details.summary}`,
          },
        ],
        details,
        terminate: true,
      };
    },
    renderCall(args: Partial<RoleCycleDoneInput> | undefined) {
      const summary = normalizeText(args?.summary);
      return textBlock(
        summary
          ? `${ROLE_CYCLE_DONE_TOOL_NAME} — ${truncateInline(summary)}`
          : ROLE_CYCLE_DONE_TOOL_NAME,
      );
    },
    renderResult(result, { expanded }: { expanded: boolean }) {
      const details = result.details as RoleCycleDoneDetails | undefined;
      if (!details) {
        const first = result.content?.[0];
        return textBlock(first?.type === "text" ? first.text : "Role cycle complete");
      }

      return textBlock(
        expanded
          ? formatRoleCycleDoneExpanded(details)
          : formatRoleCycleDoneCompact(details),
      );
    },
  });

  let roleRegistry = loadRoleRegistry([]);
  let warnedMissingActiveRoles = new Set<string>();
  let activeRoleOriginalSettings: RuntimeSettingsSnapshot | undefined;
  let originalCoordRoleValue: string | undefined;
  let originalCoordRoleCaptured = false;

  function refreshRoles(ctx: ExtensionContext) {
    try {
      const sources = discoverRoleSources({
        cwd: ctx.cwd,
        packageRolesDir: bundledRolesDir,
      });
      roleRegistry = loadRoleRegistry(sources);
      warnedMissingActiveRoles = new Set<string>();

      for (const warning of roleRegistry.warnings) {
        notifyWarning(ctx, formatRoleWarning(warning));
      }
    } catch (error) {
      const details = error instanceof Error ? error.message : String(error);
      roleRegistry = loadRoleRegistry([]);
      notifyWarning(ctx, `role-manager: could not load role files: ${details}`);
    }
  }

  function snapshotRuntimeSettings(ctx: ExtensionContext): RuntimeSettingsSnapshot {
    return {
      provider: normalizeText(ctx.model?.provider),
      model: normalizeText(ctx.model?.id),
      thinkingLevel: normalizeText(pi.getThinkingLevel()),
      tools: pi.getActiveTools(),
    };
  }

  function coordinationRoleNameFor(role: { name?: string; coordCommitter?: string }) {
    return normalizeText(role.coordCommitter) ?? normalizeText(role.name);
  }

  function captureOriginalCoordRole() {
    if (originalCoordRoleCaptured) return;
    originalCoordRoleValue = process.env[PI_EN_COORD_ROLE_ENV];
    originalCoordRoleCaptured = true;
  }

  function setActiveCoordRole(role: { name?: string; coordCommitter?: string }) {
    const coordRole = coordinationRoleNameFor(role);
    if (!coordRole) return;
    captureOriginalCoordRole();
    process.env[PI_EN_COORD_ROLE_ENV] = coordRole;
  }

  function restoreOriginalCoordRole() {
    if (!originalCoordRoleCaptured) return;

    if (originalCoordRoleValue === undefined) {
      delete process.env[PI_EN_COORD_ROLE_ENV];
    } else {
      process.env[PI_EN_COORD_ROLE_ENV] = originalCoordRoleValue;
    }

    originalCoordRoleValue = undefined;
    originalCoordRoleCaptured = false;
  }

  function currentRoleState(ctx: ExtensionContext) {
    return resolveActiveRoleState({
      entries: getSessionEntries(ctx),
      env: process.env,
    });
  }

  function availableRoleNames() {
    return roleRegistry.roles.map((role) => role.name).sort((a, b) => a.localeCompare(b));
  }

  function formatAvailableRoles() {
    const names = availableRoleNames();
    return names.length > 0 ? names.join(", ") : "(none loaded)";
  }

  function roleArgumentCompletions(prefix: string) {
    const trimmedPrefix = prefix.trimStart();
    if (/\s/.test(trimmedPrefix)) return null;

    const normalizedPrefix = trimmedPrefix.toLowerCase();
    const items = roleRegistry.roles
      .filter((role) => role.name.toLowerCase().startsWith(normalizedPrefix))
      .map((role) => ({
        value: role.name,
        label: role.icon ? `${role.icon} ${role.name}` : role.name,
        description: role.description,
      }));
    return items.length > 0 ? items : null;
  }

  function resolveRoleModel(role: { name?: string; provider?: string; model?: string }, ctx: ExtensionContext) {
    const provider = normalizeText(role.provider);
    const modelId = normalizeText(role.model);

    if (!provider && !modelId) {
      return { model: undefined, warning: undefined };
    }

    if (provider && !modelId) {
      return {
        model: undefined,
        warning: `role-manager: role ${role.name ?? JSON.stringify(provider)} specifies provider without model`,
      };
    }

    if (provider && modelId) {
      const model = ctx.modelRegistry.find(provider, modelId);
      return {
        model,
        warning: model
          ? undefined
          : `role-manager: model not found for role setting: ${provider}/${modelId}`,
      };
    }

    const allModels = ctx.modelRegistry.getAll();
    const exactMatches = allModels.filter((candidate) => candidate.id === modelId);
    if (exactMatches.length === 1) {
      return { model: exactMatches[0], warning: undefined };
    }
    if (exactMatches.length > 1) {
      return {
        model: undefined,
        warning: `role-manager: role model ${JSON.stringify(modelId)} is ambiguous; add provider`,
      };
    }

    const slashIndex = modelId?.indexOf("/") ?? -1;
    if (slashIndex > 0 && slashIndex < (modelId?.length ?? 0) - 1) {
      const parsedProvider = modelId!.slice(0, slashIndex);
      const parsedModel = modelId!.slice(slashIndex + 1);
      const model = ctx.modelRegistry.find(parsedProvider, parsedModel);
      return {
        model,
        warning: model
          ? undefined
          : `role-manager: model not found for role setting: ${modelId}`,
      };
    }

    return {
      model: undefined,
      warning: `role-manager: model not found for role setting: ${modelId}`,
    };
  }

  function ensureRoleCycleDoneToolActive(ctx: ExtensionContext) {
    const allToolNames = new Set(pi.getAllTools().map((tool) => tool.name));
    if (!allToolNames.has(ROLE_CYCLE_DONE_TOOL_NAME)) {
      notifyWarning(ctx, `role-manager: ${ROLE_CYCLE_DONE_TOOL_NAME} tool is not registered`);
      return false;
    }

    const activeTools = pi.getActiveTools();
    if (!activeTools.includes(ROLE_CYCLE_DONE_TOOL_NAME)) {
      pi.setActiveTools([...activeTools, ROLE_CYCLE_DONE_TOOL_NAME]);
    }
    return true;
  }

  async function applyRoleRuntimeSettings(role: any, ctx: ExtensionContext) {
    if (role.thinking && pi.getThinkingLevel() !== role.thinking) {
      pi.setThinkingLevel(role.thinking);
    }

    if (Array.isArray(role.tools) && role.tools.length > 0) {
      const requestedTools = uniqueToolNames(role.tools);
      const allToolNames = new Set(pi.getAllTools().map((tool) => tool.name));
      const validTools = requestedTools.filter((tool) => allToolNames.has(tool));
      const invalidTools = requestedTools.filter((tool) => !allToolNames.has(tool));

      if (invalidTools.length > 0) {
        notifyWarning(
          ctx,
          `role-manager: role ${role.name} requested unknown tools: ${invalidTools.join(", ")}`,
        );
      }

      if (validTools.length > 0) {
        pi.setActiveTools(validTools);
      }
    }

    const modelResolution = resolveRoleModel(role, ctx);
    if (modelResolution.warning) {
      notifyWarning(ctx, modelResolution.warning);
    }
    if (modelResolution.model && !sameModel(ctx.model, modelResolution.model)) {
      const success = await pi.setModel(modelResolution.model);
      if (!success) {
        notifyWarning(
          ctx,
          `role-manager: no API key for role model ${modelResolution.model.provider}/${modelResolution.model.id}`,
        );
      }
    }
  }

  async function restoreRuntimeSettings(
    settings: RuntimeSettingsSnapshot | undefined,
    ctx: ExtensionContext,
  ) {
    if (!settings) return false;

    let restoredAny = false;

    if (settings.provider && settings.model) {
      const model = ctx.modelRegistry.find(settings.provider, settings.model);
      if (model) {
        if (!sameModel(ctx.model, model)) {
          const success = await pi.setModel(model);
          if (!success) {
            notifyWarning(
              ctx,
              `role-manager: no API key for previous model ${settings.provider}/${settings.model}`,
            );
          }
        }
        restoredAny = true;
      } else {
        notifyWarning(
          ctx,
          `role-manager: previous model not found: ${settings.provider}/${settings.model}`,
        );
      }
    }

    if (settings.thinkingLevel) {
      pi.setThinkingLevel(settings.thinkingLevel as any);
      restoredAny = true;
    }

    if (Array.isArray(settings.tools)) {
      const allToolNames = new Set(pi.getAllTools().map((tool) => tool.name));
      const validTools = uniqueToolNames(settings.tools).filter((tool) => allToolNames.has(tool));
      const invalidTools = uniqueToolNames(settings.tools).filter((tool) => !allToolNames.has(tool));

      if (invalidTools.length > 0) {
        notifyWarning(
          ctx,
          `role-manager: previous tool selection contains unknown tools: ${invalidTools.join(", ")}`,
        );
      }

      if (validTools.length > 0 || settings.tools.length === 0) {
        pi.setActiveTools(validTools);
        restoredAny = true;
      }
    }

    return restoredAny;
  }

  function persistRoleState(
    roleName: string | null,
    previousSettings: RuntimeSettingsSnapshot | undefined,
    extra: Record<string, unknown> = {},
  ) {
    pi.appendEntry(ROLE_MANAGER_STATE_CUSTOM_TYPE, {
      version: ROLE_STATE_VERSION,
      activeRoleName: roleName,
      previousSettings,
      updatedAt: new Date().toISOString(),
      ...extra,
    });
  }

  function latestRoleManagerStateData(ctx: ExtensionContext) {
    const entries = getSessionEntries(ctx);
    for (let index = entries.length - 1; index >= 0; index--) {
      const entry = entries[index] as
        | { type?: string; customType?: string; data?: Record<string, unknown> }
        | undefined;
      if (entry?.type !== "custom") continue;
      if (entry.customType !== ROLE_MANAGER_STATE_CUSTOM_TYPE) continue;
      return entry.data;
    }
    return undefined;
  }

  function roleDisplayInfoFor(roleName: string): RoleDisplayInfo {
    const role = findRole(roleRegistry, roleName);
    if (role) return role;
    return { name: roleName };
  }

  function updateRoleUIForCurrentState(ctx: ExtensionContext, cycleOverride?: unknown) {
    const state = currentRoleState(ctx);
    if (!state.roleName) {
      clearRoleUI(pi, ctx);
      return;
    }

    const data = latestRoleManagerStateData(ctx);
    applyRoleUI(
      pi,
      ctx,
      roleDisplayInfoFor(state.roleName),
      cycleOverride ?? data?.roleCycle,
    );
  }

  function completeRoleCycle(
    details: RoleCycleDoneDetails,
    ctx: ExtensionContext | undefined,
  ) {
    if (!ctx) return;

    const state = currentRoleState(ctx);
    if (!state.roleName) return;

    const data = latestRoleManagerStateData(ctx);
    const existingCycle = normalizeRoleCycleState(data?.roleCycle);
    if (!isRoleCycleRunning(existingCycle)) return;

    persistRoleState(state.roleName, state.previousSettings ?? activeRoleOriginalSettings, {
      roleCycle: {
        ...existingCycle,
        completedAt: details.completedAt,
        summary: details.summary,
        recommendedNextRole: details.recommendedNextRole,
      },
    });
    updateRoleUIForCurrentState(ctx);
  }

  async function activateRole(
    roleName: string,
    ctx: ExtensionContext,
    extraState: Record<string, unknown> = {},
  ) {
    const role = findRole(roleRegistry, roleName);
    if (!role) {
      notifyError(
        ctx,
        `role-manager: unknown role ${JSON.stringify(roleName)}. Available: ${formatAvailableRoles()}`,
      );
      return false;
    }

    const state = currentRoleState(ctx);
    const previousSettings = state.roleName
      ? state.previousSettings ?? activeRoleOriginalSettings ?? snapshotRuntimeSettings(ctx)
      : snapshotRuntimeSettings(ctx);

    activeRoleOriginalSettings = previousSettings;
    persistRoleState(role.name, previousSettings, {
      activatedAt: new Date().toISOString(),
      ...extraState,
    });
    setActiveCoordRole(role);
    await applyRoleRuntimeSettings(role, ctx);
    updateRoleUIForCurrentState(ctx, extraState.roleCycle);
    notifyInfo(ctx, `role-manager: activated role ${role.name}`);
    return true;
  }

  async function clearRole(ctx: ExtensionContext) {
    const state = currentRoleState(ctx);
    const previousSettings = state.roleName
      ? state.previousSettings ?? activeRoleOriginalSettings
      : activeRoleOriginalSettings;

    persistRoleState(null, previousSettings, { clearedAt: new Date().toISOString() });
    activeRoleOriginalSettings = undefined;
    restoreOriginalCoordRole();
    clearRoleUI(pi, ctx);

    const restored = await restoreRuntimeSettings(previousSettings, ctx);
    if (restored) {
      notifyInfo(ctx, "role-manager: role cleared and previous settings restored");
    } else {
      notifyInfo(ctx, "role-manager: role cleared");
    }
  }

  async function restoreActiveRoleFromState(ctx: ExtensionContext) {
    const state = currentRoleState(ctx);
    if (!state.roleName) {
      activeRoleOriginalSettings = undefined;
      restoreOriginalCoordRole();
      clearRoleUI(pi, ctx);
      return;
    }

    const role = findRole(roleRegistry, state.roleName);
    activeRoleOriginalSettings = state.previousSettings ?? snapshotRuntimeSettings(ctx);
    if (role) {
      setActiveCoordRole(role);
      await applyRoleRuntimeSettings(role, ctx);
      if (state.source === "env") {
        ensureRoleCycleDoneToolActive(ctx);
      }
    } else {
      setActiveCoordRole({ name: state.roleName });
    }
    updateRoleUIForCurrentState(ctx);
  }

  pi.registerCommand("role", {
    description: "Switch the active role",
    getArgumentCompletions: roleArgumentCompletions,
    handler: async (args, ctx) => {
      await ctx.waitForIdle();

      const requestedRoleName = normalizeText(args);
      if (requestedRoleName) {
        await activateRole(requestedRoleName, ctx);
        return;
      }

      const names = availableRoleNames();
      if (names.length === 0) {
        notifyWarning(ctx, "role-manager: no roles are loaded");
        return;
      }

      if (!ctx.hasUI) {
        notifyInfo(ctx, `role-manager: available roles: ${names.join(", ")}`);
        return;
      }

      const selected = await ctx.ui.select("Select role:", names);
      if (!selected) return;
      await activateRole(selected, ctx);
    },
  });

  pi.registerCommand("role-clear", {
    description: "Clear the active role and restore previous settings",
    handler: async (_args, ctx) => {
      await ctx.waitForIdle();
      await clearRole(ctx);
    },
  });

  pi.registerCommand("role-cycle", {
    description: "Activate a role and run one bounded role cycle in this session",
    getArgumentCompletions: roleArgumentCompletions,
    handler: async (args, ctx) => {
      await ctx.waitForIdle();

      const parsed = parseRoleCycleArgs(args);
      if (!parsed) {
        notifyError(ctx, "Usage: /role-cycle <role> <goal>");
        return;
      }

      const role = findRole(roleRegistry, parsed.roleName);
      if (!role) {
        notifyError(
          ctx,
          `role-manager: unknown role ${JSON.stringify(parsed.roleName)}. Available: ${formatAvailableRoles()}`,
        );
        return;
      }

      const startedAt = new Date().toISOString();
      const activated = await activateRole(role.name, ctx, {
        roleCycle: {
          mode: "current-session",
          goal: parsed.goal,
          startedAt,
          checklist: extractRoleCycleChecklist(role),
        },
      });
      if (!activated) return;
      ensureRoleCycleDoneToolActive(ctx);

      pi.sendUserMessage(formatRoleCyclePrompt(role, parsed.goal));
    },
  });

  pi.registerCommand("role-new", {
    description: "Start a fresh session and run one bounded role cycle there",
    getArgumentCompletions: roleArgumentCompletions,
    handler: async (args, ctx) => {
      await ctx.waitForIdle();

      const parsed = parseRoleCycleArgs(args);
      if (!parsed) {
        notifyError(ctx, "Usage: /role-new <role> <goal>");
        return;
      }

      const role = findRole(roleRegistry, parsed.roleName);
      if (!role) {
        notifyError(
          ctx,
          `role-manager: unknown role ${JSON.stringify(parsed.roleName)}. Available: ${formatAvailableRoles()}`,
        );
        return;
      }

      const parentSession = ctx.sessionManager.getSessionFile();
      const sessionName = formatRoleSessionName(role.name, parsed.goal);
      const roleCycleCommand = formatRoleCycleCommand(role.name, parsed.goal);

      const result = await ctx.newSession({
        parentSession,
        preserveScreen: true,
        setup: async (sessionManager) => {
          sessionManager.appendSessionInfo(sessionName);
        },
        withSession: async (replacementCtx) => {
          replacementCtx.ui.notify(
            `role-manager: starting fresh ${role.name} role cycle`,
            "info",
          );
          await replacementCtx.sendUserMessage(roleCycleCommand);
        },
      } as any);

      if (result.cancelled) {
        notifyInfo(ctx, "role-manager: new role session cancelled");
      }
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    refreshRoles(ctx);
    await restoreActiveRoleFromState(ctx);
  });

  pi.on("session_tree", async (_event, ctx) => {
    await restoreActiveRoleFromState(ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    clearRoleUI(pi, ctx);
  });

  pi.on("before_agent_start", async (event, ctx) => {
    const activeRoleName = resolveActiveRoleName({
      entries: getSessionEntries(ctx),
      env: process.env,
    });
    if (!activeRoleName) return;

    const activeRole = findRole(roleRegistry, activeRoleName);
    if (!activeRole) {
      if (!warnedMissingActiveRoles.has(activeRoleName)) {
        warnedMissingActiveRoles.add(activeRoleName);
        notifyWarning(
          ctx,
          `role-manager: active role not found: ${activeRoleName}`,
        );
      }
      return;
    }

    return {
      systemPrompt:
        event.systemPrompt + "\n\n" + formatActiveRoleSystemPrompt(activeRole),
    };
  });
}
