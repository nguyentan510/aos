# ADR-0006 — P2 Read-only CLI Boundary

**Status:** Accepted
**Date:** 2026-07-26
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `ROADMAP.md`, `README.md`, `DESIGN.md`

## Context

The CLI Specification reserves `aos init` and defines an explicit `--apply`
path, while P2 is intended to prove read-only Project Intelligence before
repository mutation. Implementing mutation before read-only inspection is
verified would blur the P2/P3 maturity gate.

## Decision

P2 implements only:

- `aos version`;
- `aos inspect`;
- `aos validate`; and
- `aos doctor`.

These commands are read-only and cannot create `.aos/`, write project files,
repair state, or invoke an AI provider.

`aos init` remains a reserved command name. In P2 it returns an explicit
unsupported result and exit category `6`; governed plan/apply behavior belongs
to P3 after P2's exit gate.

## Consequences

### Positive

- P2 proves safe discovery, diagnostics, output, and error behavior first.
- No live or destructive path is introduced accidentally.
- P3 can implement mutation against tested read-only repository semantics.

### Negative

- P2 cannot initialize a project.
- Some CLI contract cases remain deferred until P3.

### Risks and controls

- Users may expect `aos init` to work. README and CLI diagnostics must label it
  as reserved and deferred.
- Repository control data cannot be validated as initialized without the future
  physical schema. P2 reports an explicit candidate/unsupported state.

## Compatibility and migration

P2's read-only commands and exit categories conform to `AOS-SPEC-004`.
P3 may add `aos init --dry-run` and `--apply` behavior without changing the
read-only guarantees.

## Conformance

- P2 tests prove read-only commands do not mutate fixtures.
- `aos init` returns unsupported category `6`.
- P2 evidence records the exact test and build commands.
