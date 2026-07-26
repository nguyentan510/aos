# P4 Knowledge and Context Review

**Status:** PASS
**Date:** 2026-07-26
**Decision:** P4 exit gate satisfied

## Review objective

Verify that AOS can record, retrieve, and explain Project Knowledge and State
without losing provenance, revision ancestry, authority classification, or
freshness, and without relying on an AI provider.

## Entry gate

- P3 transactional repository initialization is complete.
- `AOS-SPEC-001` defines provenance, immutable revision, authority, lifecycle,
  and State freshness contracts.
- [ADR-0008](../adr/0008-p4-knowledge-state-context-binding.md) accepts the P4
  storage and deterministic context policy.

## Deliverable matrix

| Deliverable | Implementation | Evidence |
| --- | --- | --- |
| Immutable Knowledge revisions | `.aos/knowledge/<id>.r<revision>.json` | two-revision smoke test preserves revision one |
| Immutable State revisions | `.aos/state/<id>.r<revision>.json` | freshness and provenance smoke test |
| Plan/apply recording | `knowledge` and `state` commands | dry-run, missing-authority, and apply fixtures |
| Provider-independent query | `aos knowledge`, `aos state` | deterministic filesystem query |
| Progressive context | `aos context --limit N` | selected and withheld fixture comparison |
| Authority protection | proposed-only P4 mutation | authoritative-promotion boundary and context filtering |

## Safety review

P4 writes only immutable revision files under the initialized AOS Control Root.
It never overwrites an existing revision and rejects cross-kind identity
conflicts. Record mutation requires explicit apply intent and an authority
reference, but the resulting object remains `proposed`. Content resembling an
API key, password, secret, or token is rejected before a record file is
created.

Default context selects only active authoritative Knowledge and active
authoritative State with confirmed freshness. Proposed, stale, unknown,
non-active, superseded, and over-limit records are withheld with explicit
reasons. No AI provider participates in selection.

## Verification

The following commands passed:

```text
cargo fmt --check
cargo test
cargo build --locked
cargo clippy --all-targets -- -D warnings
node scripts/validate-aos.mjs
```

Test result:

- 6 Rust unit tests passed.
- 16 CLI process smoke tests passed.
- Coverage includes immutable ancestry, provenance, freshness, missing
  authority, sensitive-content rejection, invalid-record reporting,
  deterministic context, and explained withholding.

## Decision

P4 is complete. P5 is the next eligible phase and owns authoritative promotion,
Work lifecycle, Protocol execution, Governance policy, approvals, and audit
records.
