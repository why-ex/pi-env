# Coordination Item Format

Coordination issue items are YAML files with chronological event history and
Markdown message bodies. Requirement and TODO items are current-state YAML
records with one renderable top-level `body: |-` block. The file content, not
Git commit messages, is the authoritative item record.

## Filename IDs

New items use ID-only filenames. The filename stem must match the YAML `id`:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>.yaml
```

Examples:

```text
PIEN-ISS-20260607-204155-001.yaml
PIEN-FRQ-20260607-204155-002.yaml
```

`PROJECTKEY` is uppercase alphanumeric text. Project item keys are stored in top-level `PROJECT.md` as `item_key`.

`TYPECODE` is an uppercase item-type abbreviation. Built-in mappings are:

- `ISS`: `issue`;
- `FRQ`: `functional-requirement`;
- `QRQ`: `quality-requirement`;
- `CRQ`: `constraint-requirement`;
- `TODO`: `todo`;
- `DEC`: `decision`;
- `NOTE`: `note`.

For custom types, use a short uppercase alphanumeric code derived from the
custom type. The timestamp is UTC. `NNN` is a three-digit collision/order
suffix for that exact timestamp and starts at `001`. It is not a global
sequence number.

When `pi-en-coord-new` needs to derive a project key, it uppercases the source
name and removes delimiters, whitespace, slashes, backslashes, pipes, and other
non-alphanumeric characters. Domain-common items derive from the coordination domain or project metadata.
Repo-scoped issue items derive from the owning repo's `repos/{repo_id}/REPO.md`
metadata when present.
`--id` may override the whole item ID when a caller needs to preserve or import
an ID.

Historical items may keep legacy IDs and slug filenames. Do not rename or
renumber existing items only to satisfy a newer naming convention.

## YAML structure

Issue items store current state near the top for quick scanning, followed by
append-only `events` and `messages` lists. Messages are Markdown block strings
linked to events.

```yaml
schema: coordination-item/v1
id: PIEN-ISS-20260607-204155-001
type: issue
category: bug
status: open
project: pi-en
title: Document pi config behavior
owner: null
priority: medium
created: 2026-06-07T20:41:55Z
updated: 2026-06-07T20:41:55Z
done: null
closed: null
reviewed: false
verified: false
testable: yes
testability_note: null
related: []
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: opened
    at: 2026-06-07T20:41:55Z
    actor:
      id: agent-a
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # Document pi config behavior

      ## Context

      Explain host and sandbox Pi configuration behavior.

      ## Acceptance criteria

      - [ ] README explains host `pi config`.
      - [ ] README explains sandbox `pi-en-bwrap -- config`.
```

Requirement items are specification records rather than workflow history
records. Active requirement files under `requirements/` store current metadata
and a single renderable body:

```yaml
schema: coordination-item/v1
id: PIEN-FRQ-20260607-204155-002
type: functional-requirement
status: active
project: pi-en
title: Example requirement
requirement_key: CMD-004
requirement_class: functional
requirement_kind: detailed-behavior
domain: commands
render_order: 1
render_section: '3.4 Command requirements'
source_refs:
  - 'REQUIREMENTS.md#CMD-004'
related_workflows: []
related_requirements: []
related_tests: []
related: []
testable: yes
testability_note: null
body: |-
  #### CMD-004 Example requirement

  Requirement text...
```

Issue items may include optional `category` metadata for listing
and grouping. Recommended values include `bug`, `feature-request`, `task`,
`question`, and `improvement`; project-specific slugs are allowed when a more
specific category is useful. The top-level `type` field remains the structural
coordination item type and should stay `issue` for issue workflow items.

Requirement and TODO items must not include top-level `current:`, `events:`,
or `messages:` sections. Do not add requirement design-reference fields such as
`design_refs`, `covered_by`, or `satisfied_by_design`; design coverage is
declared by design documents and generated coverage reports.

## Item types and directories

Issue items use developer-centric status directories inside the owning repo
namespace:

```text
repos/{repo_id}/issues/open/
repos/{repo_id}/issues/blocked/
repos/{repo_id}/issues/done/
repos/{repo_id}/issues/closed/
```

Historical root `issues/{status}/` paths may exist during migration, but new
issue items should be created under `repos/{repo_id}/issues/{status}/`.

Other item types live under shared semantic type directories and do not mirror
issue status directories by default. Requirements, decisions, and domain notes
remain common to the coordination domain. All requirement classes share the
root-level `requirements/` directory while preserving FRQ, QRQ, and CRQ item-ID
type codes.

```text
requirements/                           # functional, quality, and constraint requirements
todos/                                  # lightweight TODO records
decisions/
notes/
```

Preserve historical IDs and filenames; do not silently renumber or rewrite old
items just to satisfy the FRQ/QRQ/CRQ taxonomy.

Projects may define additional type-specific status values, but should avoid
moving test scripts when an item's lifecycle status changes.

## Issue state meanings

- `open`: developer work is available or required.
- `claimed`: developer work is actively owned; keep the file under `open/`.
- `blocked`: developer work is required but cannot proceed yet.
- `done`: developer believes implementation is complete; review and
  verification remain pending until flags say otherwise.
- `closed`: final accepted state after `reviewed: true` and `verified: true`.

New issue items start with `done: null`, `closed: null`, `reviewed: false`,
and `verified: false`. When marking an issue done, use `git mv` into `done/`,
set `status: done`, set `done: <timestamp>`, reset review/verification flags
to false, update `current`, and append a `done` event with a linked message and
implementation refs where possible. When final-closing an issue, use `git mv`
into `closed/`, set `status: closed`, set `closed: <timestamp>`, update
`current`, and append a `closed` event.

## Testability and test linkage

Every item should declare whether it requires a directly item-matched test:

```yaml
testable: yes
testability_note: null
```

or:

```yaml
testable: no
testability_note: 'Documentation-only; verified by review.'
```

Use `testable: yes` when the item should have a project-repository test script
whose filename stem exactly matches the item ID. Use `testable: no` only with a
short rationale, for example documentation-only work, a policy decision, or
coverage by another explicitly named requirement item.

Executable item tests live in the project repository, not the coordination
repository. Project item tests mirror the root item type, but not issue status directories
or repo namespaces:

```text
tests/items/issues/<item-id>.sh
tests/items/requirements/<item-id>.sh
tests/items/todos/<item-id>.sh
```

Examples:

```text
.pi-en/coordination/repos/pi-en/issues/closed/PIEN-ISS-20260607-204155-001.yaml
tests/items/issues/PIEN-ISS-20260607-204155-001.sh

.pi-en/coordination/requirements/PIEN-FRQ-20260607-204155-001.yaml
tests/items/requirements/PIEN-FRQ-20260607-204155-001.sh
```

A verification event should record the exact test command(s) and result. The
test script itself should remain in the project repo so it evolves with the
code commit it verifies.

## Repository namespaces

A coordination domain can cover several implementation repositories. Each pi
session is still attached to one implementation repository, and each issue item
belongs to one repository by its `repos/{repo_id}/issues/{status}/` path. Use
one issue per implementation repo for cross-repo work and link them with stable
item IDs in `related:` or message text. Avoid path-only references so repo-id
renames do not require rewriting old links.

Repository manifests live at `repos/{repo_id}/REPO.md` and are authoritative
for canonical repo ids, aliases, remotes, and active/retired status. Older
`repositories.yaml` registries may be read for compatibility; helpers should
warn when an alias or ambiguous remote is used.

Minimal implementation attachment file in an implementation repo root:

```yaml
version: 1
coordination_domain: my-product
coordination_remote: git@example.com:org/my-product-coordination.git
repo_id: backend-api
```

Repo-id lifecycle operations should be explicit: add creates
`repos/{repo_id}/REPO.md` and issue status directories; rename moves the
namespace and records the old id as an alias with warnings; retire keeps the
namespace for history but prevents new issue creation unless a force option is
used by policy.

## Domain generated files

`repos/{repo_id}/REPO.md` may declare generated, domain-wide files that are
committed by that implementation repository. Paths are relative to that
implementation repo root:

```yaml
---
repo_id: backend-api
status: active
domain_generated_files:
  - REQUIREMENTS.md
  - REQUIREMENTS_COVERAGE.md
---
```

The manifest's repo owns regeneration commits for those paths. More than one
active repo may list the same generated path when the domain intentionally
keeps committed copies in multiple implementation repositories. Generated files
are secondary views; update coordination items first, then regenerate the files
listed for the current implementation repo.

## Source references

Imported requirement items should record where they came from in a top-level
`source_refs` list. Use stable, human-readable strings for old requirement IDs,
document headings, and use-case sections, for example:

```yaml
source_refs:
  - "REQ-012"
  - "REQUIREMENTS.md#4-agent-coordination"
  - "USE_CASES.md#22-safer-code-review-and-automation-workflows"
```

For FRQ/QRQ/CRQ migrations, include at least one `REQUIREMENTS.md#...` or
`USE_CASES.md#...` reference when the item came from those documents. Legacy
numbered IDs may be included as additional entries when available. The lint
helper treats FRQ/QRQ/CRQ items marked as imported as missing metadata unless
`source_refs` contains at least one list entry.

## Events

Events are chronological and define issue item history. Every meaningful issue
item change should add one event and one linked message. Requirement item
changes are represented by the current requirement file content and Git history,
not embedded `events`/`messages`. Use these event types where possible:

- `opened`: initial item definition;
- `claimed`: ownership claim;
- `blocked`: blocker recorded;
- `reopened`: item returned to active work with the reason or revised
  definition;
- `done`: developer work completed and ready for review/verification;
- `reviewed`: independent review passed;
- `review_failed`: independent review failed and developer work reopened;
- `verified`: tester or automation verification passed;
- `verification_failed`: verification failed and developer work reopened;
- `closed`: final acceptance after done, reviewed, and verified;
- `updated`: factual update that is not a state transition;
- `linked`: later addition of implementation, PR, release, test, or commit
  refs;
- `superseded`: item replaced by another item.

Actors are explicit in each event:

```yaml
actor:
  id: pi
  role: developer
```

Use `role: null` when no role is active. Do not rely on `git blame` alone for
role attribution; Git history is audit data, while event metadata is the
workflow record.

## Implementation references

Done or linked events should include structured implementation references:

```yaml
implementation_refs:
  - repo: pi-en
    branch: main
    commit: 32225e01ffebef26b1aeca098e7081ff913066cc
```

Use the long-lived branch that contains the result, normally `main`, and the
full commit hash. If multiple done/review/verify/reopen cycles occur, record
each transition as its own event. Multiple references are allowed on one event.

## Messages

Issue messages are chronological and read like a dialog between actors. The
first message normally contains the original item definition. Reopen or update
messages may carry revised definitions. Done messages should summarize the
implementation and point to the implementation refs stored on the same event.
Review and verification messages should record pass/fail evidence, including
commands run for item-matched tests where applicable.

For requirements and TODOs, keep Markdown inside the top-level `body: |-`
readable as normal Markdown. Do not add a separate `## Activity` section; that
would duplicate issue YAML event history and is not part of single-body
records.
