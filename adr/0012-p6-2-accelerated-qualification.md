# ADR-0012 — P6.2 Accelerated Qualification

**Status:** Accepted
**Date:** 2026-07-28
**Decision owners:** AOS project
**Supersedes:** ADR-0011 only for the P6.2 seven-day blocking exit condition
**Affected documents:** `README.md`, `ROADMAP.md`,
`evidence/P6.2-PRODUCTION-LIKE-QUALIFICATION.md`

## Context

P6.2 originally required seven samples over at least seven elapsed days. That
gate measures calendar endurance, but it makes development progress depend on
waiting even when the tested runtime is local-only, deterministic, immutable,
and has no external side effects.

Two official daily samples passed with zero failures, integrity failures, or
source mutation. The calendar lane proved that evidence survives across
separate days, but additional calendar time does not add new fault classes by
itself. The project needs a faster qualification route without changing
timestamps, deleting the daily evidence, or describing a short run as a
seven-day soak.

## Decision

P6.2 adopts two explicitly different evidence lanes:

1. The existing daily lane remains historical long-duration evidence. It is
   not rewritten, backdated, or counted as accelerated evidence.
2. A separate accelerated lane may close the bounded local P6.2 functional
   qualification when it passes at least eight consecutive samples in one
   controlled run.

The accelerated lane must use the same pinned binary, manifests, and harnesses
as the daily lane. It must also use the same three detached repository commits.
Its exit conditions are:

```text
samples >= 8
repeats per capability = 2
repositories per sample = 3
governed Extension Runs >= 96
failed samples = 0
result integrity failures = 0
source mutations = 0
all nested capabilities deterministic
all result digests revalidated
all pinned artifact hashes unchanged
all detached repositories clean and at exact pinned commits
```

Accelerated qualification is not elapsed-time evidence. A PASS allows P6.2 to
close as a bounded local production-like functional qualification. It does not
claim seven-day resilience, hardware fault endurance, distributed runtime
readiness, or production readiness.

The accelerated and daily result roots are separate. Samples are immutable and
cannot be copied between lanes. A failed accelerated sample remains evidence
and fails the lane; it may not be deleted to obtain a PASS.

## Consequences

### Positive

- P6.2 progress depends on executed evidence rather than calendar waiting.
- Eight clean process-level samples exercise 96 governed Extension Runs.
- The original daily observations remain truthful and auditable.
- Core, extension, Governance, Work, Run, and Audit semantics do not change.

### Negative

- Short accelerated qualification cannot reveal slow resource leaks or
  degradation that only appears after days.
- The maturity claim must retain the explicit local and accelerated boundary.
- Long-duration stability would require a later soak if operational evidence
  shows that risk is material.

## Alternatives considered

### Rewrite the daily lane with zero minimum duration

Rejected because it would change the meaning of already collected official
evidence and make a same-day run appear to satisfy the original gate.

### Fabricate sample timestamps

Rejected because it destroys provenance and does not execute any additional
behavior.

### Continue waiting for seven calendar days

Rejected as the blocking project gate. The daily evidence remains available,
but calendar waiting no longer blocks the bounded local qualification.

## Rollback and review condition

If accelerated samples expose any failure, integrity mismatch, non-determinism,
source mutation, or commit drift, P6.2 returns to `ACTIVE` and the failure is
retained. If later deployment introduces long-lived processes, external
providers, network effects, or distributed execution, a new duration soak is
required before making a corresponding production claim.
