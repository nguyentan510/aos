# ADR-0003 — `aos init` as the Bootstrap Command

**Status:** Accepted
**Date:** 2026-07-25
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `README.md`, `DESIGN.md`, `ROADMAP.md`

## Context

Two separate lifecycle operations need distinct language:

1. obtaining an AOS CLI/runtime distribution in the user environment; and
2. adopting AOS control data in a project repository.

Using the same term for both creates ambiguity in documentation, package
managers, support, and eventual upgrade or removal behavior.

## Decision

`aos init` is the canonical future command for proposing and creating AOS-owned
control data in a project repository.

Installing the AOS distribution is a separate, environment-level operation. The
CLI Specification will define exact syntax, dry-run behavior, idempotency,
ownership, rollback, and failure semantics before the command is implemented.

The command name is reserved by this decision, but its executable behavior is
not yet specified or available.

## Consequences

### Positive

- Distribution installation and project initialization are unambiguous.
- The command follows common repository-bootstrap semantics.
- Future diagnostics, upgrades, and removal can address managed-project
  lifecycle explicitly.

### Negative

- Earlier examples using `aos install` must be updated.
- Users must learn separate distribution and project lifecycle operations.

### Risks and controls

- Documentation may imply the command already exists. Canonical docs label it
  as planned until implementation evidence exists.
- The name could encourage unsafe immediate mutation. The future specification
  must require inspection, a dry-run plan, conflict checks, and recovery.

## Alternatives considered

### `aos install`

Rejected as the canonical project command because it is easily confused with
installing the CLI distribution.

### Support both names

Deferred. An alias is unnecessary before an implementation or compatibility
requirement exists.

## Compatibility and migration

No command has been released, so no executable compatibility path is needed.
Design examples are updated to use the canonical planned name.

## Conformance

- README marks `aos init` as planned.
- DESIGN separates distribution installation from project initialization.
- P3 in the roadmap owns transactional initialization.
