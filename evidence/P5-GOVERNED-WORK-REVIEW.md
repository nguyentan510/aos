# P5 Governed Work Vertical Slice Review

**Status:** COMPLETE
**Date:** 2026-07-27
**Decision:** P5 exit gate passed; P6 is eligible to start

## Review objective

Verify that AOS can promote eligible proposed context through an attributable
Governance decision, authorize structured Work, execute one deterministic
local-only Protocol, preserve verification evidence, block uncertain outcomes,
and expose an end-to-end audit trace.

## Entry-gate truth

- P4 contract, implementation, runtime smoke, and consumer smoke are present.
- `AOS_CONTEXT_CONSUMER_SMOKE_OK` is present.
- The provider-neutral structural benchmark is present.
- The final AOS aggregate emits `AOS_P4_VALUE_BENCHMARK_OK` with 40.67% token
  reduction, 29.56% elapsed-time reduction, 36.71% time-to-first-patch
  reduction, and 6/6 success in both modes.
- The fixed-snapshot TRENUX Rust aggregate emits
  `AOS_P4_VALUE_BENCHMARK_OK` with 53.40% token reduction, 35.83% elapsed-time
  reduction, 37.92% time-to-first-patch reduction, and 6/6 success in both
  modes.
- The controlled downstream pilot emits
  `AOS_CONTROLLED_DOWNSTREAM_PILOT_OK`.

The P5 implementation, product-value gate, downstream pilot, local
CI-equivalent gates, and GitHub-hosted CI are verified. GitHub Actions run
`30244142128` attempt 2 executed the Windows and Ubuntu jobs successfully on
commit `be558069df10a4182be12252a1c95008bff4792e`.

## Implemented vertical slice

```text
proposed Knowledge/State
→ Governance approval or rejection
→ authoritative context revision
→ proposed/authorized Work
→ aos.local.verify@1.0.0 Run
→ completed/failed/blocked Work
→ reconciliation
→ Work/Governance/Run/Audit query
```

Physical records are immutable JSON revisions under `.aos/work`,
`.aos/protocol`, `.aos/governance`, `.aos/runs`, and `.aos/audit`.

## Safety evidence

- `aos-cli`, `runtime:*`, and `provider:*` cannot authorize themselves.
- Approval requires an explicit Principal and evidence reference.
- Rejection retains the proposed Work.
- Stale, unknown, inactive, and cross-Project context is denied.
- Only `aos.local.verify@1.0.0` is accepted.
- The Protocol performs no caller-supplied shell command or external mutation.
- Successful Work retains `in_progress` and `completed` revisions.
- Partial and unknown results remain blocked until reconciliation.
- Duplicate Runs are denied by the Work state machine.
- Audit records retain actor, authority basis, subject, timestamp, outcome, and
  evidence reference.
- Hardening covers scope mismatch, cross-Project context, unsupported Protocol
  records, secret-like evidence, audit-write uncertainty, and concurrent
  immutable revision writes.

## Verification

Canonical commands:

```text
cargo fmt --check
cargo test
cargo build --locked
cargo clippy --all-targets -- -D warnings
node scripts/validate-aos.mjs
powershell -ExecutionPolicy Bypass -File scripts/run_p5_governed_work_smoke.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_p5_hardening_gate.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_controlled_downstream_pilot.ps1
```

Expected markers:

```text
AOS_P5_GOVERNED_WORK_CONTRACT_OK
AOS_P5_GOVERNED_WORK_SMOKE_OK
AOS_P5_GOVERNANCE_RECONCILIATION_OK
AOS_P5_HARDENING_OK
AOS_P4_VALUE_BENCHMARK_OK
AOS_CONTROLLED_DOWNSTREAM_PILOT_OK
```

Latest verified run:

```text
run_id: p5-20260727T065045Z
Rust unit tests: 8 passed
CLI process tests: 30 passed
format/build/clippy: PASS
design/specification/governance validators: PASS
AOS_P5_HARDENING_OK: PASS
controlled pilot: pilot-20260727T065102Z PASS
release candidate: v0.1.0-rc.1 local-verified
hosted CI qualification: run 30244142128 attempt 2 PASS
closeout commit CI: run 30246501837 PASS
CI-built release candidate: v0.1.0-rc.2 PASS
```

Hosted CI evidence:

```text
qualification run: 30244142128 attempt 2 PASS
qualification commit: be558069df10a4182be12252a1c95008bff4792e
closeout commit run: 30246501837 PASS
closeout commit: 33b7cf48e91f870751dba576c6a9e3bf5bbf3e98
Windows job 89914662756: PASS
Ubuntu job 89914663510: PASS
Rust unit tests: 8/8 on Windows and Ubuntu
CLI process tests: 30/30 on Windows and Ubuntu
Windows P5 governed Work smoke: PASS
Windows P5 hardening gate: PASS
design/specification/governance validators: PASS on Windows and Ubuntu
prior billing lock: RESOLVED
```

Release provenance:

```text
tag: v0.1.0-rc.2
tag commit: 33b7cf48e91f870751dba576c6a9e3bf5bbf3e98
release workflow: 30246618788 PASS
Linux build job 89915019958: PASS
Windows build job 89915020000: PASS
publish job 89915231777: PASS
artifact: aos-x86_64-pc-windows-msvc.zip
sha256: 1f1c240c8cffe2cbce3b15687f9b7a7ae2d8d31e802307b69d4231e508740f60
artifact: aos-x86_64-unknown-linux-gnu.tar.gz
sha256: cf509fb40ff1926b30a4a6d94cdfbcc3a9f94f119ea6cb6ab812830efcd2505c
checksum verification: AOS_RC2_CHECKSUMS_OK
```

## Maturity decision

```text
Contract-ready:                  PASS
Implementation-aligned:          PASS
Runtime-smoke-ready:             PASS
Production-like-runtime-ready:   NOT CLAIMED
Production-ready:                NOT CLAIMED
P5 roadmap closeout:             PASS
```
