# Serial Role Automation Design

This document describes the first, deliberately small automation step for
running the developer, reviewer, and tester roles over one project checkout and
one coordination checkout.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-024 | PIEN-FRQ-20260615-175835-001 |
| CMD-020 | PIEN-FRQ-20260615-175837-001 |
| AGENT-016 | PIEN-FRQ-20260615-175838-001 |
| CRQ-013 | PIEN-CRQ-20260615-175840-001 |
| TEST-032 | PIEN-QRQ-20260615-175842-001 |

## Goal

Provide a serial automation mode that repeatedly checks the Git-backed
coordination repository, selects one eligible issue, runs one fresh Pi job in
the appropriate role, and then returns to polling. The first implementation
uses one mutable project clone and one coordination clone. It does not spawn
parallel terminals, tmux panes, or separate worktrees.

The serial mode is intended to prove the workflow and prompts before adding
parallel role workers with per-role clones or worktrees.

## Non-goals

- No parallel developer/reviewer/tester execution in the first version.
- No tmux dependency.
- No cross-process Git locking beyond a local single-run lockfile under
  `.pi-en/locks/`.
- No reviewer/tester lease protocol yet; the serial orchestrator is the only
  worker using the clone.
- No hidden database or queue outside the coordination repository.
- No automatic selection of requirement, decision, or note work; the loop
  handles issue lifecycle work only.

## Execution model

Run a single long-lived shell orchestrator from the project root:

```text
serial orchestrator
  -> pull/rebase coordination
  -> select one tester, reviewer, or developer item
  -> launch one fresh pi-en job for that role and item
  -> wait for completion
  -> repeat
```

The orchestrator, not Pi, owns the idle polling loop. Pi is invoked only when
there is a concrete item to process. Each issue-related job is a new Pi session
by invoking `pi-en --raw -- ...` without `--continue`. The default
`--ui interactive` mode runs a watched normal Pi TUI with graceful shutdown
requested after `role_cycle_done`. The user can choose `--ui json` for headless
JSONL automation or `--ui none` for non-interactive `--print` output; every
mode still runs exactly one selected item and the orchestrator waits for Pi to
exit before polling again. The old hold-open interactive behavior is
intentionally removed and is not preserved under another selector.

## Role priority

Prefer draining downstream work before starting more development:

1. tester: done issues with `reviewed: true` and `verified: false`;
2. reviewer: done issues with `reviewed: false`;
3. developer: open issues.

This keeps completed developer work from piling up unreviewed or unverified.
If no item exists for any role, the orchestrator sleeps and polls again.

A caller may also provide an explicit batch with repeatable `--issue ID`
options. In that mode the same tester, reviewer, then developer priority is
applied only to the requested issue IDs. Within a single role tier, requested
issues are considered in caller-provided order. The default behavior with no
`--issue` options remains the full all-eligible queue. Explicit-batch mode
validates unknown IDs, duplicate IDs, and IDs that resolve to non-issue items
before running Pi, and exits successfully when the requested set has no
currently eligible work instead of sleeping because unrelated issues remain.

## Work selection

Initial selection can use existing helpers:

```bash
next_developer_item() {
  scripts/pi-en-coord-list issues open | head -n1 | cut -f1
}

next_reviewer_item() {
  scripts/pi-en-coord-list issues done |
    awk -F'\t' '$3 ~ /reviewed:false/ { print $1; exit }'
}

next_tester_item() {
  scripts/pi-en-coord-list issues done |
    awk -F'\t' '$3 ~ /reviewed:true/ && $3 ~ /verified:false/ { print $1; exit }'
}
```

A later implementation may replace this duplicated shell parsing with an
`pi-en-coord-next` helper, but that is not required for the serial MVP.

## Repository safety checks

Before every Pi job the orchestrator should:

- hold the default local lock at `.pi-en/locks/pi-en-serial-roles.lock`,
  creating `.pi-en/locks` when needed, so two serial workers cannot
  accidentally run in the same clone;
- ensure the project working tree is clean unless the previous role job left a
  documented failure state that the user must resolve;
- treat a dirty coordination checkout during idle pre-selection polling as a
  temporary busy condition: do not pull/rebase, inspect, claim, reset, stash, or
  discard; count the poll as idle and retry after the normal sleep;
- pull/rebase coordination before inspecting or mutating items when the
  coordination checkout is clean;
- ensure the coordination working tree is clean before running a Pi job and
  after every job completes, except during an intentional helper mutation;
- stop rather than auto-reset, auto-stash, or discard project changes.

Developer jobs must commit implementation changes before marking an item done
and must pass a structured implementation ref to `pi-en-coord-done` when
possible. Reviewer and tester jobs should review or verify committed project
state, not uncommitted leftovers.

## Pi invocation

Serial automation logs and future local diagnostics, when written, should
default under `.pi-en/logs/` so serial-role operational artifacts stay grouped
with other Pi-en generated state.

The orchestrator should render a role-specific prompt that names exactly one
item and says not to select other work. The prompt should tell the role to use
sandbox-visible coordination helpers for lifecycle transitions. Packaged runs
can expose the helper directory with
`PI_EN_BWRAP_EXTRA_PATH`; source-checkout runs should name paths under the mounted
`/workspace` when the helpers live in the project checkout:

- developer: `pi-en-coord-claim` before work, then `pi-en-coord-done` with
  implementation refs after project commits;
- reviewer: `pi-en-coord-review --pass` or `pi-en-coord-review --fail`;
- tester: `pi-en-coord-verify --pass` or `pi-en-coord-verify --fail`;
- optional final close may be configurable and should only run after both
  review and verification have passed.

Because `pi-en-bwrap` clears the environment, role activation through environment
variables requires explicit pass-through when used. A safe invocation shape is:

```bash
PI_EN_BWRAP_PASS_ENV=PI_ACTIVE_ROLE \
PI_ACTIVE_ROLE="$role" \
PI_EN_COORD_ROLE="$role" \
PI_EN_COORD_AGENT_ID="$agent_id" \
PI_EN_BWRAP_COORDINATION_DIR="$coordination_dir" \
pi-en --raw -- \
  -e "$PI_EN_ROLE_MANAGER_PACKAGE" \
  --tools read,bash,edit,write,grep,find,ls,role_cycle_done \
  --print "$prompt"
```

The important properties for `--ui none` print mode are: non-interactive
response output, no `--mode json`, no `-p`, no `--continue`, one item in the
prompt, active role context, the role-manager extension, the `role_cycle_done`
tool, and a mounted/writable coordination checkout.

For structured automation, the same environment, role manager extension,
coordination mount, and tool allowlist are used, but the Pi command adds
`--mode json` instead of `--print`. The final lifecycle report can be parsed
from the `role_cycle_done` `tool_execution_end` event.

For default watched auto-exit work, the same environment, role manager
extension, coordination mount, and tool allowlist are used, but the Pi command
omits both `--mode json` and `--print` and launches the normal TUI with the
generated prompt as the initial message. `pi-en-serial-roles` additionally passes
`PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1` through the sandbox:

```bash
PI_EN_BWRAP_PASS_ENV="PI_ACTIVE_ROLE PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE" \
PI_ROLE_MANAGER_AUTO_SHUTDOWN_ON_DONE=1 \
PI_ACTIVE_ROLE="$role" \
PI_EN_COORD_ROLE="$role" \
PI_EN_COORD_AGENT_ID="$agent_id" \
PI_EN_BWRAP_COORDINATION_DIR="$coordination_dir" \
pi-en --raw -- \
  -e "$PI_EN_ROLE_MANAGER_PACKAGE" \
  --tools read,bash,edit,write,grep,find,ls,role_cycle_done \
  "$prompt"
```

The role-manager extension checks that flag in `role_cycle_done` and calls Pi's
graceful `ctx.shutdown()` API after recording the final structured result. Pi
defers interactive shutdown until the agent becomes idle, which preserves
normal tool-result rendering/logging before the process exits. No supported
`--ui` mode keeps the previous manual hold-open TUI behavior.

## Failure behavior

The orchestrator should fail closed:

- if `git pull --rebase` fails, sleep and retry or stop with a clear message;
- if a Pi job exits non-zero, record enough log context for the human and do
  not start another item until the project and coordination trees are clean;
- if developer work leaves the project dirty without a commit, stop;
- if reviewer/tester finds a failure, use the coordination helper failure path
  to reopen developer work instead of editing item status by hand;
- never force-push or rewrite coordination history.

## Migration to parallel workers

Once the serial orchestrator is stable, the same selection and role prompts can
be reused by parallel workers. Parallel mode should first move to per-role or
per-item clones/worktrees and add reviewer/tester lease claims before allowing
multiple workers to act concurrently.
