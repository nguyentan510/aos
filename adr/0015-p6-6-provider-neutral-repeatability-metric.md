# ADR-0015 — P6.6 Provider-neutral Repeatability Metric

**Status:** Accepted
**Date:** 2026-07-28
**Decision owners:** AOS project
**Affected documents:** `README.md`, `ROADMAP.md`,
`evidence/P6.6-REAL-REPOSITORY-GENERALIZATION.md`

## Context

The first complete P6.6 matrix passed 60/60 tasks, verification, scope, and
aggregate token/time/command thresholds, but failed the maximum per-scenario
input-token drift gate. Provider-reported cached input varied by tens of
thousands of tokens even when prompt content, command count, patch scope, and
task outcome were stable. Aggregate AOS input across the two repeats differed
by only 0.584%, while the maximum individual scenario reported 24.557%.

Treating provider cache allocation as AOS semantic non-determinism makes the
qualification depend on a provider implementation detail that AOS cannot
control. Silently lowering the existing threshold or selecting favorable
retries would invalidate the evidence.

## Decision

P6.6 evaluator schema v2 separates repeatability into:

- a binding gate requiring identical prompt SHA-256 per scenario and mode;
- task, verification, exact scope, and isolation gates;
- aggregate AOS workload input-token drift of at most 10%;
- maximum per-scenario input-token drift retained as a mandatory diagnostic;
- cached and uncached provider token measurements retained without claiming
  they are billing-equivalent or Core semantics.

The v1 failed evaluation remains immutable evidence. Schema v2 may close P6.6
only on a new independent 60-execution batch produced after this decision. It
may not reuse the v1 checkpoint or replace selected scenarios.

## Consequences

- Qualification measures repeatability at the workload boundary used for the
  aggregate product claim.
- Provider cache variance remains visible instead of being hidden.
- A complete independent batch is required, increasing cost and duration.
- This decision changes benchmark governance only; AOS Core semantics do not
  change.

## Alternatives considered

Repeatedly rerunning only scenarios that failed drift was rejected as
selection bias. Removing repeatability entirely was rejected because it would
weaken the gate. Keeping maximum provider-token drift as the sole gate was
rejected because it conflates provider cache allocation with AOS output
determinism.

## Review condition

Revisit this decision if the provider exposes a stable billable-token
contract, if prompt hashes diverge, or if aggregate drift exceeds 10%. Any
future metric change requires a new evaluator schema and independent evidence.
