# Role Template Architecture

This document describes the optional role-template layer for `pi-en` and
`pi-coding-agent` sessions.

The goal is to let a user switch the active agent role, optionally start a
fresh session for that role, and run exactly one role cycle while keeping
project-specific role extensions easy to add.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| CMD-016 | PIEN-FRQ-20260612-210000-047 |
| CMD-017 | PIEN-FRQ-20260613-090608-001 |
| CMD-019 | PIEN-FRQ-20260613-183411-001 |
| DOC-002 | PIEN-QRQ-20260613-183457-001 |
| TEST-031 | PIEN-QRQ-20260612-210000-033 |

## Summary

Implement roles as **Markdown role definitions managed by a Pi extension**.
Plain Pi prompt templates are useful for one-shot prompts, but they do not
provide enough control for persistent role state, tool selection, fresh
sessions, visual status, or role-aware coordination commits.

The role layer is packaged as:

```text
role-manager package
  extensions/
    role-manager.ts
  roles/
    architect.md
    developer.md
    builder.md
    tester.md
    reviewer.md
```

The extension loads role definition files, applies the selected role to the
system prompt for each turn, controls active tools/model/thinking when a role
requests them, exposes slash commands, and renders the current role in the
interactive UI.

## Non-goals

- Do not make default `pi-en` startup automatically claim, mark done, review,
  verify, close, commit, push, or otherwise mutate coordination state.
- Do not make every role always visible in the model context.
- Do not change the project repository Git committer identity just because a
  role is active.
- Do not hard-code project-specific roles into `pi-en` itself.

## Role definition format

Each role is a Markdown file with frontmatter plus model-readable
instructions.

```markdown
---
name: architect
description: Designs architecture and produces implementation plans
icon: 🧭
thinking: high
tools: ["read", "grep", "find", "ls", "bash", "edit", "write"]
coordCommitter: architect
---

# Architect Role

## Mission

Understand the system, identify trade-offs, produce a clear design, update
architecture or coordination documents when asked, and use shell commands for
coordination/Git workflows.

## One-cycle workflow

1. Pull/read coordination state when coordination is in scope.
2. Inspect relevant project files.
3. Identify architecture constraints, risks, and alternatives.
4. Produce a concise design and next steps.
5. Update coordination state only when explicitly working on an item.
6. Stop after the cycle report.
```

Recommended fields are formalized in `role-manager/ROLE_FILE_SCHEMA.md`:

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Stable role id used by commands and status. |
| `description` | yes | Human-facing summary in selectors. |
| `icon` | no | Short visual marker for footer/title/status. |
| `thinking` | no | Requested Pi thinking level. |
| `tools` | no | Active tool allowlist while the role is active. |
| `model` / `provider` | no | Optional model override for the role. |
| `coordCommitter` | no | Role name used for coordination commits. |

The Markdown body should define:

- mission;
- allowed and forbidden actions;
- one-cycle workflow;
- expected final report;
- coordination behavior.

## Resource discovery and override order

Roles should be loaded without putting all role bodies into context. Only the
active role is injected for a turn.

Suggested merge order, with later entries overriding earlier entries by
`name`:

1. base package roles shipped with the role-manager package;
2. common/global roles, for example `~/.pi/agent/roles`;
3. common roles imported through `PI_EN_BWRAP_COMMON_AGENT_DIR/roles`;
4. optional workspace roles in a coordination repo, for example
   `coordination/roles`;
5. project roles in `.pi/roles`.

Project-specific roles therefore live next to other project Pi resources:

```text
project/
  .pi/
    roles/
      domain-architect.md
      release-builder.md
    extensions/
    skills/
    prompts/
    settings.json
```

## Commands

The extension should expose these commands:

```text
/role                       Select a role interactively
/role <name>                Switch the current session to a role
/role-clear                 Clear role state and restore previous defaults
/role-cycle <name> <goal>   Run one cycle in the current session
/role-new <name> <goal>     Start a fresh session and run one role cycle
```

`/role-new` should use Pi's session replacement API to create a fresh session,
request that Pi preserve the existing UI screen, set a session name such as
`[architect] design roles`, persist role state, and send the one-cycle prompt
in the replacement session.

## One-cycle behavior

A role cycle is one bounded unit of work for the active role. The cycle prompt
should include:

- active role name;
- user goal;
- whether project and coordination changes are allowed;
- the role's one-cycle checklist once at kickoff;
- instruction to follow the role's one-cycle workflow;
- instruction to stop after the final role report.

For robust termination, the extension should register a final tool named
`role_cycle_done`. The role-cycle prompt instructs the model to call the tool
when the cycle is complete with:

- summary;
- files inspected;
- files changed;
- tests or checks run;
- coordination updates;
- recommended next role.

The tool should return `terminate: true` so Pi does not automatically continue
with another model turn after the final report.

## Visual role indicator

Interactive sessions should make the active role obvious:

- footer status, for example `🧭 role:architect`;
- terminal title, for example `pi - architect`;
- no persistent checklist widget; the checklist is shown once in the kickoff
  prompt so it does not repeat before later prompts.

The extension should clear all role UI when `/role-clear` is used or when no
role is active.

## Coordination identity

Coordination state remains plain Git and Markdown. Role support should not make
default `pi-en` startup mutate coordination automatically.

When a role is active and coordination helper commands commit coordination
state, those commits should be attributable to the role. The implemented
behavior is:

- coordination helpers accept `--role ROLE` and read `PI_EN_COORD_ROLE`;
- coordination item events store actor ID and role explicitly, and helper
  commits may use an effective actor such as `pi/architect`;
- coordination commits use a role-specific Git identity through per-command
  `git -c` options, for example:

  ```bash
  git -c user.name="pi/architect" \
      -c user.email="pi+architect@coordination.local" \
      commit -m "Claim <PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>"
  ```

The role manager propagates the active role to coordination commands by setting
`PI_EN_COORD_ROLE` for Pi subprocesses to the role's `coordCommitter` value, or the
role name when that field is omitted. Project repository commits continue to use
the normal imported Git identity unless the user explicitly requests a role
identity there too.

## Base roles

Initial built-in roles should be small and composable:

| Role | Purpose | Default tools |
|------|---------|---------------|
| `architect` | Design, trade-offs, decisions, implementation plans. | `read`, `grep`, `find`, `ls`, `bash`, `edit`, `write` |
| `developer` | Focused source changes that implement an accepted plan. | `read`, `grep`, `find`, `ls`, `edit`, `write`, `bash` |
| `builder` | Build, package, integration, CI and release-prep failures. | `read`, `grep`, `find`, `ls`, `bash`, `edit` |
| `tester` | Reproduction, tests, verification, coverage gaps. | `read`, `grep`, `find`, `ls`, `bash`, `edit`, `write` |
| `reviewer` | Diff review, risk review, security and maintainability feedback. | `read`, `grep`, `find`, `ls`, `bash` |

## Pi-en integration

The role-template layer should remain optional. `pi-en` should provide the
runtime support needed to use it across projects:

- ship the role-manager as a Pi package whose extension discovers its bundled
  `roles/` directory;
- allow common `roles/` directories to be imported with other common Pi
  resources when role support is enabled;
- keep project-local `.pi/roles` available through the `/workspace` mount;
- document required extra tools if a role-manager extension registers custom
  tools such as `role_cycle_done`;
- keep default `pi-en` startup behavior predictable unless the user enables the
  role package or extension.

## Implementation roadmap

The coordination repository tracked PIEN role-template items that split this
design into implementable work. The current implementation follows this
architecture while keeping role support optional.
