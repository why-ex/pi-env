# Coordination Git Synchronization Protocol

The coordination repository uses ordinary Git as the synchronization and
conflict-detection mechanism.

State group names are developer-centric: `open` means developer work is needed,
`blocked` means developer work cannot proceed yet, `done` means the developer
believes the implementation is complete, and `closed` means final acceptance
after review and verification.

## Required flow

1. Pull/rebase before reading or selecting work:

   ```bash
   git pull --rebase
   ```

2. Claim one issue item by editing its YAML current-state fields:

   ```yaml
   status: claimed
   owner: <agent-id>
   updated: <timestamp>
   current:
     event: evt-XXXX
     message: msg-XXXX
   ```

3. Append a chronological `claimed` event with explicit actor/role metadata
   and a linked Markdown message under `messages:`.
4. Commit and push the claim immediately.
5. Do project work in the relevant project clone.
6. Pull/rebase the coordination repository again.
7. Update progress, blockers, links, result, or status by appending new
   events/messages and updating the top-level current-state fields.
8. When developer work is complete, move issue items to `done/`, set
   `status: done`, reset `reviewed: false` and `verified: false`, append a
   `done` event, and include structured implementation refs with `repo`,
   `branch`, and full `commit` fields where possible.
9. Reviewers and testers work from `done/`: review pass sets
   `reviewed: true`, verification pass sets `verified: true`, and either
   failure moves the item back to `open/` with a failure event explaining what
   developer work is required.
10. Verification events should record exact commands and results. If an item is
    `testable: yes`, run or cite the matching project-repository script under
    `tests/items/.../<item-id>.sh`.
11. When an item is `done`, `reviewed: true`, and `verified: true`, move it to
    `closed/`, set `status: closed`, and append a final `closed` event.
12. Commit and push immediately.

Requirement, decision, note, and other non-issue item types may have their own
status values. They still use chronological events/messages and should link to
implementation or test evidence when relevant.

## Recommended clone settings

Run these once in each project-local coordination working clone
(`<project>/.pi-en/coordination`):

```bash
git config pull.rebase true
git config rebase.autoStash true
```

## Recommended lint checks

When the project provides the Pi-en helper, run:

```bash
pi-en-coord-lint --coord-dir .pi-en/coordination --project-root .
```

For release or handoff gates that require no active issue work, run:

```bash
pi-en-coord-lint --coord-dir .pi-en/coordination --project-root . \
  --require-done-or-closed
```

The lint helper checks issue status-directory consistency, closed item review
and verification flags, new-format ID/type consistency, `testable` metadata,
and item-matched test script linkage.

## Conflict handling

Git conflicts are the locking mechanism. If two agents claim, mark done,
review, verify, close, or otherwise update the same item, resolve the rebase or
push conflict conservatively.

- Preserve factual updates from both sides when possible.
- Preserve chronological order in `events:` and `messages:`.
- Ask the user when ownership or stale-claim behavior is ambiguous.
- Never force-push or rewrite public coordination history.
- Keep commits small so conflicts remain easy to inspect.
