# P4 Value Benchmark

**Status:** STRUCTURAL-READY; AI RUNS PENDING
**Date:** 2026-07-26
**Baseline:** recorded by `scripts/run_p4_value_benchmark.ps1`

## Purpose

Provide a reproducible, provider-neutral benchmark harness for comparing
repository discovery context with deterministic AOS context selection.

The harness deliberately does not fabricate model token counts or task success.
Provider-specific agent measurements are supplied as per-scenario result files
only after an external consumer run has been completed.

## Implemented harness

- Scenario manifest: `benchmarks/p4/scenarios.json`
- Runner: `scripts/run_p4_value_benchmark.ps1`
- Repository inputs:
  - the clean AOS baseline repository;
  - the clean `D:\trenux_rust` repository snapshot.
- Three task classes per repository:
  - onboarding;
  - bugfix;
  - feature.
- Snapshot checks:
  - Git commit;
  - clean working tree unless `-AllowDirty` is explicitly supplied;
  - baseline file existence.
- AOS fixture checks:
  - transactional `.aos` initialization;
  - authoritative Knowledge/State fixture loading;
  - deterministic context selection;
  - selected/withheld count and explicit withholding reasons.

## Measurement policy

The runner reports a provider-neutral size estimate using UTF-8 bytes divided by
four. This is a structural comparison only. It is not a claim about any model's
tokenizer.

Actual AI evidence requires one result file per scenario under the generated
run directory with:

```json
{
  "status": "PASS",
  "discovery_tokens": 0,
  "total_context_tokens": 0,
  "time_to_first_patch_seconds": 0,
  "task_success": true,
  "files_read": 0,
  "rework_rounds": 0
}
```

The final `AOS_P4_VALUE_BENCHMARK_OK` marker is reserved for runs where the
structural checks pass and all agent result files satisfy the agreed thresholds.
Without those files the runner emits only
`AOS_P4_VALUE_BENCHMARK_STRUCTURAL_OK`.

## Current decision

This evidence proves that the benchmark is executable and fail-closed about
missing AI measurements. It does not yet prove token reduction, faster agent
understanding, or task-success improvement.
