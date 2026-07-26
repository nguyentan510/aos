# ADR-0007 — Transactional Repository Initialization

**Status:** Accepted
**Date:** 2026-07-26
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `README.md`, `DESIGN.md`, `ROADMAP.md`, `specifications/002-repository.md`

## Context

P3 must turn the accepted Repository and CLI contracts into a safe first
mutation path. The implementation needs a physical control-root binding,
ownership protection, explicit authority, idempotency, stale-state handling,
and a recovery boundary without modifying application content.

## Decision

The initial P3 control root is:

```text
.aos/
└── repository.json
```

`repository.json` is an AOS-owned manifest with schema version `1` and
contract version `AOS-SPEC-002`. It records the canonical root, Project and
Repository identities, ownership policy, initialization revision, operation
identity, authority reference, and initialization timestamp.

`aos init` creates an Adoption Plan by default. `--dry-run` makes the
non-mutating intent explicit. Mutation requires both `--apply` and a non-empty
`--authority <REFERENCE>`. Full Governance authority resolution is deferred to
the later Governance capability; P3 records the caller-supplied reference and
does not treat it as permission to bypass ownership or compatibility checks.

Apply writes the manifest inside a temporary sibling control root, synchronizes
the file, closes it, and atomically renames the temporary root to `.aos`.
Unknown existing control roots are conflicts and remain untouched. A committed
root is inspected again before success is reported. Repeating adoption against
a supported manifest is a verified no-op.

## Consequences

### Positive

- User-owned project files are outside the mutation boundary.
- Plan and apply remain observable and distinct.
- Directory rename gives a narrow commit point and avoids partial manifest
  visibility.
- Repeated initialization is safe and explainable.

### Negative

- The first physical schema is intentionally small and does not cover future
  Knowledge, State, Work, or audit storage.
- Authority is represented as an explicit reference but is not yet resolved by
  a Governance engine.
- Filesystem behavior and atomic rename semantics remain platform-sensitive and
  require continued conformance testing.

## Alternatives considered

### Write `.aos` files directly

Rejected because a process interruption could expose a partial control root and
make recovery ambiguous.

### Overwrite an existing `.aos` directory

Rejected because unknown artifacts may be user-owned or belong to another
version of AOS; conflict and inspection are safer.

### Use a dependency-heavy serialization framework

Deferred because the current binary is stdlib-first and the manifest shape is
small enough for controlled deterministic serialization.

## Compatibility and migration

The manifest schema version and Repository contract version are explicit.
Future schema changes require a specification update, migration plan, and ADR.
Unsupported manifests remain inspectable but are not mutated by normal `aos
init`.

## Conformance

- `aos init [PATH]` returns a plan without mutation.
- `aos init --dry-run [PATH]` returns the same non-mutating plan class.
- `aos init --apply [PATH]` fails with exit `7` without authority.
- `aos init --apply --authority <REFERENCE> [PATH]` creates and verifies the
  manifest transactionally.
- Repeated compatible apply is idempotent.
- Unknown `.aos` content returns exit `5` and is preserved.
- Apply failure or verification uncertainty returns exit `8` with reconciliation
  evidence.
