# P4 Context Consumer Smoke

**Status:** PASS for provider-neutral consumer envelope
**Date:** 2026-07-26

## Objective

Verify that an external consumer can use the JSON output of `aos context`
without depending on an AI provider and without receiving proposed, stale, or
unknown records as default context.

## Implemented smoke

Runner:

```text
scripts/run_p4_context_consumer_smoke.ps1
```

The smoke creates an isolated initialized repository, adds authoritative
confirmed records plus proposed and stale records, and validates:

- deterministic repeated output;
- compact projection and an explicit byte budget;
- selected records retain source references;
- proposed and stale records are withheld;
- every withheld record has a reason;
- context policy is explicit;
- the output contains no secret-like value;
- the context limit is enforced.

## Verification marker

```text
AOS_CONTEXT_CONSUMER_SMOKE_OK
```

Latest run:

```text
consumer-20260726T104214Z
profile: compact
budget_bytes: 900
```

## Boundary

This proves the provider-neutral JSON consumer contract only. It does not claim
that Codex, Copilot, Claude Code, or another AI completed a real coding task.
An external agent run is still required for AI-facing token and task-success
evidence.
