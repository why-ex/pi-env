# Role File Schema

Role definitions are Markdown files with YAML-style frontmatter followed by a
model-readable instruction body. The role-manager package validates this schema
before using a role file.

```markdown
---
name: architect
description: Designs architecture and implementation plans
icon: 🧭
thinking: high
tools: ["read", "grep", "find", "ls", "bash", "edit", "write"]
coordCommitter: architect
---

# Architect Role

## Mission
...
```

## Frontmatter fields

| Field | Required | Type | Purpose |
|-------|----------|------|---------|
| `name` | yes | string | Stable role id. Must match `^[a-z][a-z0-9_-]*$`. |
| `description` | yes | string | Human-readable role summary for selectors and help. |
| `icon` | no | string | Short visual marker for status, title, or selectors. |
| `thinking` | no | string | Requested Pi thinking level: `off`, `minimal`, `low`, `medium`, `high`, or `xhigh`. |
| `tools` | no | string list | Tool allowlist requested while the role is active. |
| `coordCommitter` | no | string | Role value exported as `PI_EN_COORD_ROLE` for coordination helpers, such as `architect`. Helpers combine it with the agent ID to render actors like `pi/architect`. |
| `provider` | no | string | Optional provider override for future role activation. |
| `model` | no | string | Optional model override for future role activation. |

Unknown frontmatter fields are left in the parsed frontmatter for future or
project-specific extensions. They should not be required by the base roles.

The validator rejects a role file when `name` or `description` is missing or
empty. It also rejects malformed known fields such as a non-list `tools` value
or an unsupported `thinking` value.

## Instruction body

The Markdown body should be concise and readable by the model. Base roles must
include these sections:

1. `## Mission`
2. `## Allowed actions`
3. `## Forbidden actions`
4. `## One-cycle workflow`
5. `## Expected final report`
6. `## Coordination behavior`

Custom roles should use the same section names unless they have a strong reason
not to. Missing body sections are warnings by default and can be treated as
errors for bundled/base roles.

## Validation and startup behavior

`role-manager/lib/role-schema.mjs` exposes the parser and validator used by the
extension. The package extension validates bundled role files during
`session_start` and reports each issue as a clear warning, for example:

```text
role-manager: roles/example.md: invalid role file: missing required frontmatter field "name"
```

Validation is intentionally non-fatal at Pi startup. Invalid role files are
skipped by the validator, warnings are shown through Pi UI notifications when a
UI is available, and startup continues.
