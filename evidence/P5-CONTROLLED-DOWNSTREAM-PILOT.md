# P5 Controlled Downstream Pilot

**Status:** PASS
**Date:** 2026-07-27
**Scope:** Local-only governed pilot on an isolated TRENUX Rust snapshot

## Pilot boundary

The pilot used the successful AOS-mode patch workspace from
`p4-ai-20260727T062521Z`. The source repository was not mutated. The isolated
snapshot was pinned to:

```text
TRENUX Rust commit: 3297389bd35ff3e8eb129dc74308ec3c8d165bf2
changed file: docs/TRACEABILITY_MATRIX.md
patch verification: git diff --check
```

The governed flow was:

```text
verified benchmark patch
→ transactional AOS initialization
→ proposed downstream traceability Knowledge
→ governed Work creation
→ attributable authorization
→ authoritative compact context selection
→ aos.local.verify@1.0.0
→ completed Work
→ Governance/Run/Audit trace
```

## Result

```text
run_id: pilot-20260727T065102Z
benchmark evidence: p4-ai-20260727T062156Z
work: verify-downstream-consumer-traceability
status: completed
arbitrary command execution: not supported
external mutation: none
source repository mutation: none
```

The machine-readable result is stored at:

```text
%TEMP%\aos-controlled-downstream-pilot\
  pilot-20260727T065102Z\controlled-pilot-result.json
```

The canonical reproduction command is:

```powershell
powershell -ExecutionPolicy Bypass `
  -File scripts/run_controlled_downstream_pilot.ps1 `
  -DownstreamSnapshot <isolated-successful-benchmark-workspace> `
  -BenchmarkEvidenceRef p4-ai-20260727T062156Z
```

```text
AOS_CONTROLLED_DOWNSTREAM_PILOT_OK
```
