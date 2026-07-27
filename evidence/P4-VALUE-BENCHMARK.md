# P4 Value Benchmark

**Status:** QUALIFIED PATCH/TEST REPEATS COMPLETE; VALUE GATE NOT MET
**Date:** 2026-07-26
**Baseline:** recorded by `scripts/run_p4_value_benchmark.ps1`

## Purpose

Provide a reproducible, provider-neutral benchmark harness for comparing
repository discovery context with deterministic AOS context selection.

The harness deliberately does not fabricate model token counts or task success.
It now includes a Codex consumer runner and a qualified patch-and-test
manifest. Historical discovery-only runs remain recorded as calibration; they
cannot emit the final product-value marker.

## Implemented harness

- Scenario manifest: `benchmarks/p4/scenarios.json`
- Runner: `scripts/run_p4_value_benchmark.ps1`
- AI-facing runner: `scripts/run_p4_ai_facing_benchmark.ps1`
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
  - compact context projection;
  - explicit byte-budget enforcement;
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

The final `AOS_P4_VALUE_BENCHMARK_OK` marker is reserved for a qualified
patch-and-test manifest where the structural checks pass, all agent result
files satisfy the agreed thresholds, and every scenario declares a
verification command and expected patch files. Discovery-only calibration runs
are fail-closed and cannot produce that marker.

## Current decision

This evidence proves that the benchmark is executable, invokes a real AI
consumer, records provider usage and elapsed time, and remains fail-closed about
missing task verification. It does not yet prove product-level token reduction,
faster agent understanding, or task-success improvement.

## AI-facing calibration run

The first real Codex calibration used `@openai/codex@0.145.0` with model
`gpt-5.6-sol` on clean snapshots. The run was intentionally executed once to
calibrate the harness before paying for repeated measurements:

```text
run_id: p4-ai-20260726T112731Z
AOS commit: 9a4f1ac8e69a8b2ebeab7886fe1301d3839ff6af
TRENUX Rust commit: 3297389bd35ff3e8eb129dc74308ec3c8d165bf2
qualification: ai-facing-context-calibration
status: FAIL
marker: AOS_P4_VALUE_BENCHMARK_NOT_MET
result: %TEMP%\aos-p4-ai-facing-benchmark\p4-ai-20260726T112731Z\ai-facing-results.json
```

| Metric | Observed | Gate | Result |
| --- | ---: | ---: | --- |
| Input-token reduction | 20.49% | >= 25% | FAIL |
| Time reduction | 17.07% | >= 20% | FAIL |
| Baseline task success | 0% | comparison only | FAIL |
| AOS task success | 16.67% | all tasks pass | FAIL |
| Structural withholding reasons | present | required | PASS |
| Repetition count | 1 | >= 2 | CALIBRATION ONLY |

The historical result was useful: the runner measured real provider usage
rather than the structural byte estimate and exposed incomplete discovery
answers. The qualified patch-and-test follow-up is recorded below.

## Qualified patch-and-test split runs

The manifest is now `qualification_level: patch-and-test`. Each scenario
declares an expected patch file and a local verification command. The runner
uses separate disposable clones for baseline and AOS, captures the prompt and
event log, checks the actual changed files, and reruns verification after the
agent exits.

One-repeat split runs completed successfully at the task level:

| Scenario | Token reduction | Time reduction | Baseline success | AOS success |
| --- | ---: | ---: | ---: | ---: |
| AOS onboarding | 20.21% | 26.73% | 100% | 100% |
| AOS bugfix | 33.54% | 16.59% | 100% | 100% |
| AOS feature | 34.25% | 19.69% | 100% | 100% |
| **AOS aggregate** | **30.74%** | **20.18%** | **100%** | **100%** |

The aggregate exceeds the token, time, and task-success thresholds, but it is
not yet a final product-value proof because the aggregate is assembled from
three independent one-repeat runs.

All three AOS scenarios were then repeated twice on the same repository commit:

| Scenario | Run | Token reduction | Time reduction | Baseline success | AOS success |
| --- | --- | ---: | ---: | ---: | ---: |
| AOS onboarding | `p4-ai-20260726T124350Z` | 43.57% | 24.29% | 100% | 100% |
| AOS bugfix | `p4-ai-20260727T041623Z` | 19.18% | 19.79% | 100% | 100% |
| AOS feature | `p4-ai-20260727T042413Z` | 46.26% | 10.12% | 100% | 100% |
| **Repeated aggregate** | three split runs | **35.10%** | **18.32%** | **6/6** | **6/6** |

All runs used AOS commit
`9a4f1ac8e69a8b2ebeab7886fe1301d3839ff6af`. The repeated aggregate proves a
35.10% input-token reduction without task-success regression. It does not pass
the complete value gate because the 18.32% elapsed-time reduction is below the
20% threshold. The final multi-scenario `AOS_P4_VALUE_BENCHMARK_OK` marker
therefore remains withheld.

## Structural run

The first clean-snapshot run completed with:

```text
run_id: p4-20260726T104150Z
AOS commit: 01ba1f7
TRENUX Rust commit: 3297389bd35ff3e8eb129dc74308ec3c8d165bf2
structural marker: AOS_P4_VALUE_BENCHMARK_STRUCTURAL_OK
agent status: PENDING
```

The six scenarios produced the following provider-neutral compact-profile size
estimates under the default 900-byte budget:

| Scenario | Baseline estimate | AOS compact estimate | Structural reduction |
| --- | ---: | ---: | ---: |
| AOS onboarding | 6,294 | 157 | 97.51% |
| AOS CLI bugfix | 13,522 | 153 | 98.87% |
| AOS feature | 20,982 | 190 | 99.09% |
| TRENUX onboarding | 33,296 | 162 | 99.51% |
| TRENUX boundary bugfix | 31,126 | 166 | 99.47% |
| TRENUX feature | 32,418 | 168 | 99.48% |

These numbers compare listed baseline-file bytes with a manually authored P4
context fixture. They demonstrate that the envelope can be compact, but they
must not be presented as model-token savings or task-success improvement until
the same scenarios are executed by an external AI consumer.
