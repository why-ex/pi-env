#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

REPO_ROOT="$repo_root" node --input-type=module <<'NODE'
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createJiti } from "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/jiti/lib/jiti.mjs";
import { ROLE_MANAGER_STATE_CUSTOM_TYPE } from "./role-manager/lib/role-loader.mjs";

const repoRoot = process.env.REPO_ROOT;
const jiti = createJiti(import.meta.url);
const roleManager = (await jiti.import("./role-manager/extensions/role-manager.ts")).default;

function roleMarkdown({ name, marker, coordCommitter = name }) {
  return `---
name: ${name}
description: Project ${name}
icon: 🧪
thinking: high
tools: ["read", "bash", "missing_tool"]
coordCommitter: ${coordCommitter}
provider: anthropic
model: target
---
# Project ${name}

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

const tmp = mkdtempSync(join(tmpdir(), "pi-en-role-commands-"));
const cwd = join(tmp, "project");
mkdirSync(join(cwd, ".pi", "roles"), { recursive: true });
writeFileSync(
  join(cwd, ".pi", "roles", "modeler.md"),
  roleMarkdown({
    name: "modeler",
    marker: "PROJECT modeler",
    coordCommitter: "project-modeler",
  }),
);

const previousEnv = {
  PI_CODING_AGENT_DIR: process.env.PI_CODING_AGENT_DIR,
  PI_EN_BWRAP_COMMON_AGENT_DIR: process.env.PI_EN_BWRAP_COMMON_AGENT_DIR,
  PI_EN_COORD_DIR: process.env.PI_EN_COORD_DIR,
  PI_EN_COORD_ROLE: process.env.PI_EN_COORD_ROLE,
  PI_ACTIVE_ROLE: process.env.PI_ACTIVE_ROLE,
  PI_ROLE_MANAGER_ACTIVE_ROLE: process.env.PI_ROLE_MANAGER_ACTIVE_ROLE,
  PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE:
    process.env.PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE,
};
process.env.PI_CODING_AGENT_DIR = join(tmp, "agent");
delete process.env.PI_EN_BWRAP_COMMON_AGENT_DIR;
process.env.PI_EN_COORD_DIR = join(tmp, "coordination");
process.env.PI_EN_COORD_ROLE = "ambient-role";
delete process.env.PI_ACTIVE_ROLE;
delete process.env.PI_ROLE_MANAGER_ACTIVE_ROLE;
delete process.env.PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE;

const models = [
  { provider: "anthropic", id: "original", name: "Original", api: "anthropic-messages", baseUrl: "", reasoning: true, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 1000, maxTokens: 100 },
  { provider: "anthropic", id: "target", name: "Target", api: "anthropic-messages", baseUrl: "", reasoning: true, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 1000, maxTokens: 100 },
];

const expectedBundledRoleTools = new Map([
  ["architect", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
  ["developer", ["read", "grep", "find", "ls", "edit", "write", "bash"]],
  ["builder", ["read", "grep", "find", "ls", "bash", "edit"]],
  ["tester", ["read", "grep", "find", "ls", "bash", "edit", "write"]],
  ["reviewer", ["read", "grep", "find", "ls", "bash"]],
]);

function createHarness(initialEntries = [], options = {}) {
  const entries = initialEntries;
  const builtinToolNames = options.builtinToolNames ?? [
    "read",
    "bash",
    "edit",
    "write",
    "grep",
    "find",
    "ls",
  ];
  const commands = new Map();
  const tools = new Map();
  const handlers = new Map();
  const notifications = [];
  const sentUserMessages = [];
  const newSessionRequests = [];
  const newSessionSetups = [];
  const replacementNotifications = [];
  const replacementSentUserMessages = [];
  const statuses = [];
  const widgets = [];
  const titles = [];
  const shutdownCalls = [];
  const hasUI = options.hasUI ?? true;
  const includeRoleUiMethods = options.includeRoleUiMethods ?? true;
  const state = {
    currentModel: models[0],
    thinkingLevel: "low",
    activeTools: ["read", "edit"],
    selection: undefined,
    sessionFile: join(tmp, "sessions", "original.jsonl"),
    newSessionCancelled: false,
  };

  const pi = {
    on(event, handler) {
      if (!handlers.has(event)) handlers.set(event, []);
      handlers.get(event).push(handler);
    },
    registerCommand(name, options) {
      commands.set(name, options);
    },
    registerTool(tool) {
      tools.set(tool.name, tool);
    },
    appendEntry(customType, data) {
      entries.push({ type: "custom", customType, data });
    },
    sendUserMessage(content, options) {
      sentUserMessages.push({ content, options });
    },
    getSessionName() {
      return state.sessionName;
    },
    getThinkingLevel() {
      return state.thinkingLevel;
    },
    setThinkingLevel(level) {
      state.thinkingLevel = level;
    },
    getActiveTools() {
      return [...state.activeTools];
    },
    getAllTools() {
      const builtinTools = builtinToolNames.map((name) => ({
        name,
        description: name,
        parameters: {},
        sourceInfo: { source: "builtin" },
      }));
      return [...builtinTools, ...tools.values()];
    },
    setActiveTools(tools) {
      state.activeTools = [...tools];
    },
    async setModel(model) {
      state.currentModel = model;
      return true;
    },
  };

  const ui = {
    notify(message, type) {
      notifications.push({ message, type });
    },
    async select(_title, options) {
      return state.selection ?? options[0];
    },
    theme: {
      fg(_color, text) {
        return text;
      },
    },
  };

  if (includeRoleUiMethods) {
    ui.setStatus = (key, text) => {
      statuses.push({ key, text });
    };
    ui.setWidget = (key, content, options) => {
      widgets.push({ key, content, options });
    };
    ui.setTitle = (title) => {
      titles.push(title);
    };
  }

  const ctx = {
    get model() {
      return state.currentModel;
    },
    cwd,
    hasUI,
    modelRegistry: {
      find(provider, id) {
        return models.find((model) => model.provider === provider && model.id === id);
      },
      getAll() {
        return models;
      },
    },
    sessionManager: {
      getBranch() {
        return entries;
      },
      getEntries() {
        return entries;
      },
      getSessionFile() {
        return state.sessionFile;
      },
    },
    ui,
    isIdle() {
      return true;
    },
    async waitForIdle() {},
    shutdown() {
      shutdownCalls.push({ at: new Date().toISOString() });
    },
    async newSession(options = {}) {
      newSessionRequests.push(options);
      if (state.newSessionCancelled) {
        return { cancelled: true };
      }

      const replacementEntries = [];
      const sessionInfoNames = [];
      const setupSessionManager = {
        appendSessionInfo(name) {
          sessionInfoNames.push(name);
          replacementEntries.push({ type: "session_info", name });
        },
        appendCustomEntry(customType, data) {
          replacementEntries.push({ type: "custom", customType, data });
        },
        getEntries() {
          return replacementEntries;
        },
        buildSessionContext() {
          return { messages: [] };
        },
      };

      if (options.setup) {
        await options.setup(setupSessionManager);
      }
      newSessionSetups.push({ sessionInfoNames: [...sessionInfoNames], entries: [...replacementEntries] });

      if (options.withSession) {
        const replacementCtx = {
          cwd,
          hasUI: true,
          model: state.currentModel,
          modelRegistry: ctx.modelRegistry,
          sessionManager: {
            getBranch() {
              return replacementEntries;
            },
            getEntries() {
              return replacementEntries;
            },
            getSessionFile() {
              return join(tmp, "sessions", "replacement.jsonl");
            },
          },
          ui: {
            notify(message, type) {
              replacementNotifications.push({ message, type });
            },
          },
          isIdle() {
            return true;
          },
          async waitForIdle() {},
          async sendUserMessage(content, options) {
            replacementSentUserMessages.push({ content, options });
          },
        };
        await options.withSession(replacementCtx);
      }

      return { cancelled: false };
    },
  };

  async function emit(event, payload) {
    for (const handler of handlers.get(event) ?? []) {
      await handler(payload, ctx);
    }
  }

  async function buildSystemPrompt(base = "base system prompt") {
    let systemPrompt = base;
    for (const handler of handlers.get("before_agent_start") ?? []) {
      const result = await handler(
        {
          type: "before_agent_start",
          prompt: "test",
          systemPrompt,
          systemPromptOptions: {},
        },
        ctx,
      );
      if (result?.systemPrompt) systemPrompt = result.systemPrompt;
    }
    return systemPrompt;
  }

  roleManager(pi);

  return {
    entries,
    commands,
    tools,
    handlers,
    notifications,
    sentUserMessages,
    newSessionRequests,
    newSessionSetups,
    replacementNotifications,
    replacementSentUserMessages,
    statuses,
    widgets,
    titles,
    shutdownCalls,
    state,
    ctx,
    emit,
    buildSystemPrompt,
  };
}

try {
  const harness = createHarness([]);
  await harness.emit("session_start", { type: "session_start", reason: "startup" });

  assert.ok(harness.commands.has("role"), "/role command is registered");
  assert.ok(harness.commands.has("role-clear"), "/role-clear command is registered");
  assert.ok(harness.commands.has("role-cycle"), "/role-cycle command is registered");
  assert.ok(harness.commands.has("role-new"), "/role-new command is registered");
  assert.ok(harness.tools.has("role_cycle_done"), "role_cycle_done tool is registered");

  const roleCycleDoneTool = harness.tools.get("role_cycle_done");
  const preparedDoneArgs = roleCycleDoneTool.prepareArguments({
    summary: "Implemented the role-cycle done tool.",
    inspectedFiles: ["role-manager/extensions/role-manager.ts"],
    changedFiles: "role-manager/extensions/role-manager.ts",
    checksRun: ["tests/role-manager-commands.sh passed"],
    coordination: "Claimed PIEN-ISS-20260606-140754-005",
    nextRole: "reviewer",
  });
  const doneResult = await roleCycleDoneTool.execute(
    "call-1",
    preparedDoneArgs,
    undefined,
    undefined,
    harness.ctx,
  );
  assert.equal(doneResult.terminate, true);
  assert.equal(doneResult.details.summary, "Implemented the role-cycle done tool.");
  assert.deepEqual(doneResult.details.filesInspected, [
    "role-manager/extensions/role-manager.ts",
  ]);
  assert.deepEqual(doneResult.details.filesChanged, [
    "role-manager/extensions/role-manager.ts",
  ]);
  assert.deepEqual(doneResult.details.testsChecksRun, [
    "tests/role-manager-commands.sh passed",
  ]);
  assert.deepEqual(doneResult.details.coordinationUpdates, ["Claimed PIEN-ISS-20260606-140754-005"]);
  assert.equal(doneResult.details.recommendedNextRole, "reviewer");
  assert.match(
    roleCycleDoneTool.renderResult(doneResult, { expanded: false }).render(80).join("\n"),
    /Role cycle complete/,
  );
  assert.match(
    roleCycleDoneTool.renderResult(doneResult, { expanded: true }).render(80).join("\n"),
    /Tests\/checks run/,
  );

  for (const [roleName, tools] of expectedBundledRoleTools) {
    const roleHarness = createHarness([]);
    await roleHarness.emit("session_start", { type: "session_start", reason: "startup" });
    await roleHarness.commands.get("role").handler(roleName, roleHarness.ctx);
    assert.deepEqual(
      roleHarness.state.activeTools,
      tools,
      `${roleName} activation tools do not match CMD-017`,
    );
    assert.equal(roleHarness.entries.at(-1).data.activeRoleName, roleName);
    if (roleName === "architect") {
      assert.equal(roleHarness.state.thinkingLevel, "high");
    }
    await roleHarness.commands.get("role-clear").handler("", roleHarness.ctx);
    assert.equal(process.env.PI_EN_COORD_ROLE, "ambient-role");
  }

  const missingArchitectTool = createHarness([], {
    builtinToolNames: ["read", "grep", "find", "ls", "bash", "edit"],
  });
  await missingArchitectTool.emit("session_start", { type: "session_start", reason: "startup" });
  await missingArchitectTool.commands.get("role").handler("architect", missingArchitectTool.ctx);
  assert.deepEqual(missingArchitectTool.state.activeTools, [
    "read",
    "grep",
    "find",
    "ls",
    "bash",
    "edit",
  ]);
  assert.ok(
    missingArchitectTool.notifications.some((notice) =>
      notice.message.includes("requested unknown tools: write"),
    ),
    "missing architect tools are reported by name",
  );
  await missingArchitectTool.commands.get("role-clear").handler("", missingArchitectTool.ctx);
  assert.equal(process.env.PI_EN_COORD_ROLE, "ambient-role");

  const missingDeveloperTool = createHarness([], {
    builtinToolNames: ["read", "grep", "find", "ls", "edit", "bash"],
  });
  await missingDeveloperTool.emit("session_start", { type: "session_start", reason: "startup" });
  await missingDeveloperTool.commands.get("role").handler("developer", missingDeveloperTool.ctx);
  assert.deepEqual(missingDeveloperTool.state.activeTools, [
    "read",
    "grep",
    "find",
    "ls",
    "edit",
    "bash",
  ]);
  assert.ok(
    missingDeveloperTool.notifications.some((notice) =>
      notice.message.includes("requested unknown tools: write"),
    ),
    "missing developer tools are reported by name",
  );
  await missingDeveloperTool.commands.get("role-clear").handler("", missingDeveloperTool.ctx);
  assert.equal(process.env.PI_EN_COORD_ROLE, "ambient-role");

  await harness.commands.get("role").handler("modeler", harness.ctx);

  const activeEntry = harness.entries.find(
    (entry) => entry.customType === ROLE_MANAGER_STATE_CUSTOM_TYPE,
  );
  assert.equal(activeEntry.data.activeRoleName, "modeler");
  assert.deepEqual(activeEntry.data.previousSettings, {
    provider: "anthropic",
    model: "original",
    thinkingLevel: "low",
    tools: ["read", "edit"],
  });
  assert.equal(harness.state.currentModel.id, "target");
  assert.equal(harness.state.thinkingLevel, "high");
  assert.deepEqual(harness.state.activeTools, ["read", "bash"]);
  assert.equal(process.env.PI_EN_COORD_ROLE, "project-modeler");
  assert.equal(harness.statuses.at(-1).key, "role-manager");
  assert.match(harness.statuses.at(-1).text, /🧪 role:modeler/);
  assert.match(harness.titles.at(-1), /role:modeler/);
  assert.equal(harness.widgets.at(-1).key, "role-manager-cycle");
  assert.equal(harness.widgets.at(-1).content, undefined);
  assert.ok(
    harness.notifications.some((notice) => notice.message.includes("missing_tool")),
    "unknown role tools are reported",
  );

  const prompt = await harness.buildSystemPrompt();
  assert.match(prompt, /Active Role: 🧪 modeler/);
  assert.match(prompt, /coordination role: project-modeler/);
  assert.match(prompt, /PI_EN_COORD_ROLE/);
  assert.match(prompt, /PROJECT modeler mission/);

  const restart = createHarness([...harness.entries]);
  restart.state.currentModel = models[0];
  restart.state.thinkingLevel = "off";
  restart.state.activeTools = ["ls"];
  await restart.emit("session_start", { type: "session_start", reason: "reload" });
  assert.equal(restart.state.currentModel.id, "target");
  assert.equal(restart.state.thinkingLevel, "high");
  assert.deepEqual(restart.state.activeTools, ["read", "bash"]);
  assert.equal(process.env.PI_EN_COORD_ROLE, "project-modeler");
  assert.match(restart.statuses.at(-1).text, /🧪 role:modeler/);
  assert.match(restart.titles.at(-1), /role:modeler/);

  process.env.PI_ROLE_MANAGER_ACTIVE_ROLE = "modeler";
  const envActiveRole = createHarness([]);
  await envActiveRole.emit("session_start", { type: "session_start", reason: "startup" });
  assert.deepEqual(envActiveRole.state.activeTools, [
    "read",
    "bash",
    "role_cycle_done",
  ]);
  assert.equal(process.env.PI_EN_COORD_ROLE, "project-modeler");
  delete process.env.PI_ROLE_MANAGER_ACTIVE_ROLE;

  await harness.commands.get("role-clear").handler("", harness.ctx);
  const clearEntry = harness.entries.at(-1);
  assert.equal(clearEntry.data.activeRoleName, null);
  assert.equal(harness.state.currentModel.id, "original");
  assert.equal(harness.state.thinkingLevel, "low");
  assert.deepEqual(harness.state.activeTools, ["read", "edit"]);
  assert.equal(harness.statuses.at(-1).text, undefined);
  assert.equal(harness.widgets.at(-1).content, undefined);
  assert.doesNotMatch(harness.titles.at(-1), /role:/);
  assert.equal(process.env.PI_EN_COORD_ROLE, "ambient-role");
  assert.doesNotMatch(await harness.buildSystemPrompt(), /Active Role:/);

  harness.state.selection = "developer";
  await harness.commands.get("role").handler("", harness.ctx);
  assert.equal(harness.entries.at(-1).data.activeRoleName, "developer");
  assert.equal(harness.state.thinkingLevel, "medium");
  assert.equal(process.env.PI_EN_COORD_ROLE, "developer");

  const cycle = createHarness([]);
  await cycle.emit("session_start", { type: "session_start", reason: "startup" });
  await cycle.commands.get("role-cycle").handler("modeler design role manager", cycle.ctx);

  const cycleEntry = cycle.entries.find(
    (entry) => entry.customType === ROLE_MANAGER_STATE_CUSTOM_TYPE,
  );
  assert.equal(cycleEntry.data.activeRoleName, "modeler");
  assert.equal(cycleEntry.data.roleCycle.mode, "current-session");
  assert.equal(cycleEntry.data.roleCycle.goal, "design role manager");
  assert.equal(typeof cycleEntry.data.roleCycle.startedAt, "string");
  assert.ok(cycleEntry.data.roleCycle.checklist.includes("PROJECT modeler workflow."));
  assert.equal(cycle.state.currentModel.id, "target");
  assert.equal(cycle.state.thinkingLevel, "high");
  assert.equal(process.env.PI_EN_COORD_ROLE, "project-modeler");
  assert.deepEqual(cycle.state.activeTools, ["read", "bash", "role_cycle_done"]);
  assert.equal(cycle.sentUserMessages.length, 1);
  assert.match(cycle.sentUserMessages[0].content, /Role cycle kickoff/);
  assert.match(cycle.sentUserMessages[0].content, /Goal: design role manager/);
  assert.match(cycle.sentUserMessages[0].content, /One-cycle checklist/);
  assert.match(cycle.sentUserMessages[0].content, /PROJECT modeler workflow/);
  assert.match(cycle.sentUserMessages[0].content, /exactly one bounded cycle/);
  assert.match(cycle.sentUserMessages[0].content, /role_cycle_done/);
  assert.match(cycle.sentUserMessages[0].content, /filesInspected/);
  assert.match(cycle.sentUserMessages[0].content, /testsChecksRun/);
  assert.match(cycle.sentUserMessages[0].content, /do not output JSON/);
  assert.equal(cycle.statuses.at(-1).key, "role-manager");
  assert.match(cycle.statuses.at(-1).text, /🧪 role:modeler/);
  assert.match(cycle.titles.at(-1), /role:modeler/);
  assert.equal(cycle.widgets.at(-1).key, "role-manager-cycle");
  assert.equal(cycle.widgets.at(-1).content, undefined);

  const cycleDoneResult = await cycle.tools.get("role_cycle_done").execute(
    "call-cycle",
    roleCycleDoneTool.prepareArguments({
      summary: "Finished cycle UI checks.",
      filesInspected: [],
      filesChanged: [],
      testsChecksRun: ["role manager command tests"],
      coordinationUpdates: [],
      recommendedNextRole: "none",
    }),
    undefined,
    undefined,
    cycle.ctx,
  );
  assert.equal(cycleDoneResult.terminate, true);
  const completedCycleEntry = cycle.entries.at(-1);
  assert.equal(completedCycleEntry.data.activeRoleName, "modeler");
  assert.equal(typeof completedCycleEntry.data.roleCycle.completedAt, "string");
  assert.equal(completedCycleEntry.data.roleCycle.summary, "Finished cycle UI checks.");
  assert.equal(cycle.widgets.at(-1).key, "role-manager-cycle");
  assert.equal(cycle.widgets.at(-1).content, undefined);
  assert.deepEqual(cycle.shutdownCalls, []);

  const autoShutdown = createHarness([]);
  process.env.PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE = "1";
  const autoShutdownResult = await autoShutdown.tools.get("role_cycle_done").execute(
    "call-auto-shutdown",
    roleCycleDoneTool.prepareArguments({
      summary: "Finished watched auto-exit cycle.",
      filesInspected: [],
      filesChanged: [],
      testsChecksRun: [],
      coordinationUpdates: [],
      recommendedNextRole: "none",
    }),
    undefined,
    undefined,
    autoShutdown.ctx,
  );
  assert.equal(autoShutdownResult.terminate, true);
  assert.equal(autoShutdown.shutdownCalls.length, 1);
  process.env.PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE = "0";

  const nonInteractive = createHarness([], {
    hasUI: false,
    includeRoleUiMethods: false,
  });
  await nonInteractive.emit("session_start", { type: "session_start", reason: "startup" });
  await nonInteractive.commands.get("role").handler("modeler", nonInteractive.ctx);
  await nonInteractive.commands.get("role-clear").handler("", nonInteractive.ctx);
  assert.equal(nonInteractive.entries.at(-1).data.activeRoleName, null);
  assert.deepEqual(nonInteractive.statuses, []);
  assert.deepEqual(nonInteractive.widgets, []);
  assert.deepEqual(nonInteractive.titles, []);

  const fresh = createHarness([]);
  await fresh.emit("session_start", { type: "session_start", reason: "startup" });
  await fresh.commands.get("role-new").handler("modeler design role manager", fresh.ctx);

  assert.equal(fresh.newSessionRequests.length, 1);
  assert.equal(fresh.newSessionRequests[0].parentSession, fresh.state.sessionFile);
  assert.equal(fresh.newSessionRequests[0].preserveScreen, true);
  assert.deepEqual(fresh.newSessionSetups[0].sessionInfoNames, ["[modeler] design role manager"]);
  assert.deepEqual(fresh.entries, [], "fresh session command must not mutate the original session state");
  assert.deepEqual(fresh.sentUserMessages, [], "fresh session command must not use the old pi sender");
  assert.deepEqual(fresh.replacementSentUserMessages, [
    { content: "/role-cycle modeler design role manager", options: undefined },
  ]);
  assert.ok(
    fresh.replacementNotifications.some((notice) =>
      notice.message.includes("starting fresh modeler role cycle"),
    ),
  );

  const cancelled = createHarness([]);
  await cancelled.emit("session_start", { type: "session_start", reason: "startup" });
  cancelled.state.newSessionCancelled = true;
  await cancelled.commands.get("role-new").handler("modeler design role manager", cancelled.ctx);

  assert.equal(cancelled.newSessionRequests.length, 1);
  assert.equal(cancelled.newSessionRequests[0].preserveScreen, true);
  assert.equal(cancelled.newSessionSetups.length, 0);
  assert.deepEqual(cancelled.entries, []);
  assert.deepEqual(cancelled.sentUserMessages, []);
  assert.deepEqual(cancelled.replacementSentUserMessages, []);
  assert.equal(cancelled.state.currentModel.id, "original");
  assert.equal(cancelled.state.thinkingLevel, "low");
  assert.deepEqual(cancelled.state.activeTools, ["read", "edit"]);
  assert.ok(
    cancelled.notifications.some((notice) => notice.message.includes("new role session cancelled")),
  );

  console.log("role manager command tests passed");
} finally {
  for (const [key, value] of Object.entries(previousEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
}
NODE
