# ADR-0009 — P5 Governed Work Vertical Slice

**Status:** Accepted
**Date:** 2026-07-26
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `ROADMAP.md`, `specifications/001-information-model.md`, `specifications/003-protocol.md`, `specifications/004-cli.md`, `specifications/005-runtime.md`

## Context

P4 records only proposed Knowledge and State and withholds them from default
context. P5 must prove that explicit Governance can promote eligible context,
authorize structured Work, bind a deterministic Protocol Run, preserve
verification evidence, and reconcile unknown outcomes without allowing a
Runtime or provider to grant itself authority.

The first implementation must remain local-first and provider-neutral. It must
not introduce arbitrary command execution, external mutation, distributed
runtime behavior, or an identity provider before the governed lifecycle itself
is proven.

## Decision

P5 stores immutable JSON revisions under:

```text
.aos/
├── work/
├── protocol/
├── governance/
├── runs/
└── audit/
```

The CLI exposes one `work` command family:

```text
aos work create
aos work authorize
aos work run
aos work reconcile
aos work show
```

`create` records proposed Work with intent, owner, repository-local scope,
context reference, expected output, verification requirements, and the
immutable Protocol reference.

`authorize` requires an explicit responsible Principal and evidence reference.
The AOS CLI, Runtime identities, and provider identities cannot authorize
themselves. Approval records an immutable Governance decision, promotes an
eligible proposed Knowledge or confirmed State revision, and creates an
authorized Work revision. Rejection records the decision without changing or
deleting the proposal.

The only accepted Protocol in this vertical slice is:

```text
aos.local.verify@1.0.0
```

It is read-only, sequential, deterministic, local-only, and fail-closed. It
validates the initialized repository boundary, immutable context snapshot,
authority, lifecycle, freshness, Work revision, and Protocol version. It does
not execute caller-supplied shell commands.

Work revisions follow:

```text
proposed → authorized → in_progress → completed | failed | blocked
```

`partial` and `unknown` Run results map Work to `blocked`. A repeat Run is
denied until an attributable reconciliation records current evidence.
Reconciliation preserves prior Run and Governance history and returns Work to
`authorized` only when the result is explicitly resolved.

## Consequences

### Positive

- A complete intent-to-result audit chain exists without provider authority.
- Proposed, stale, unknown, inactive, cross-project, and unsupported inputs
  fail closed.
- Work, decisions, runs, verification, and reconciliation remain immutable and
  inspectable.
- The first Protocol proves lifecycle semantics without risky external effects.

### Negative

- The authority reference is caller-supplied and locally enforced; it is not a
  complete RBAC or identity system.
- Multi-file lifecycle writes may require reconciliation after interruption.
- The stdlib-first JSON binding is intentionally narrow.
- The vertical slice is runtime-smoke evidence, not production readiness.

## Alternatives considered

### Arbitrary verification commands

Rejected because a caller-controlled shell command would expand P5 into a
general execution runtime before capability, sandbox, and reconciliation
boundaries are proven.

### Runtime-owned approval

Rejected because a producer or executor cannot establish its own authority.

### Database-backed workflow engine

Deferred until filesystem evidence demonstrates a concrete concurrency or
query bottleneck.

## Compatibility and migration

Accepted Protocol versions are immutable. A changed step, effect, check,
failure meaning, scope, or reconciliation rule requires a new version.
Migration must preserve Work identity, revision ancestry, Governance decisions,
Run history, context snapshots, evidence, and unresolved conditions.

## Conformance

- Self-authority is denied before promotion or Work authorization.
- Approval promotes only active eligible context in the same Project.
- Rejection preserves the proposed Work and records the decision.
- Runs accept only `aos.local.verify@1.0.0`.
- Successful Runs retain `in_progress` and `completed` revisions.
- Failed Runs do not complete Work.
- Partial and unknown Runs block Work until reconciliation.
- `work show` returns Work, Governance, Run, and Audit evidence together.
