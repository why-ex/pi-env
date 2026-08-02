# Requirements Traceability Design

Traceability is built from coordination requirement items and design document
coverage tables. Generated reports make coverage visible without requiring
manual backlinks in every requirement item.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| DOC-000 | PIEN-QRQ-20260612-210000-001 |
| DOC-001 | PIEN-QRQ-20260612-210000-002 |
| DOC-003 | PIEN-QRQ-20260614-180310-001 |
| CRQ-010 | PIEN-CRQ-20260613-090617-001 |

## 1. Sources of truth

Requirement items in the coordination repository are the source of truth for
requirement identity, type, public key, and body text. `README.md` is the
user-facing documentation surface required by `DOC-001`, while design
documents are the source of truth for architectural rationale.
`REQUIREMENTS_COVERAGE.md` is a generated view and should not be manually
edited for semantic changes.

This separation keeps coordination state stable while allowing designs to be
split, merged, or rewritten as implementation understanding improves.

## 2. Coverage tables

Every design document that claims requirement coverage includes a `## Covers`
table with the requirement public key and coordination item ID. The public key
is the stable human reference used in prose. The coordination item ID lets the
coverage generator validate that the key still maps to a live item.

Invalid table rows should fail coverage validation. A generated preview may be
used during authoring to show missing or stale references before the report is
updated.

## 3. No manual backlinks

Requirements do not need hand-maintained lists of design documents. Backlinks
are derived by scanning active design coverage tables. That avoids drift when a
design is renamed or when one document covers many requirements.

## 4. Report interpretation

Uncovered requirements in `REQUIREMENTS_COVERAGE.md` mean no current design
claims architectural coverage. Some low-level or documentation-only
requirements may remain intentionally uncovered when their behavior is fully
specified by the requirement itself and verified by review or tests. The report
makes those choices visible for follow-up planning.
