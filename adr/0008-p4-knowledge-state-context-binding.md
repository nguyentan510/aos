# ADR-0008 — P4 Knowledge, State, and Context Binding

**Status:** Accepted
**Date:** 2026-07-26
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `README.md`, `DESIGN.md`, `ROADMAP.md`, `specifications/001-information-model.md`, `specifications/004-cli.md`

## Context

P4 must make Project Knowledge and State durable and retrievable without
allowing a provider or producer to declare itself authoritative. The accepted
Information Model requires immutable revisions, provenance, authority,
lifecycle, freshness, explicit conflict behavior, and provider-independent
queries.

## Decision

P4 stores immutable JSON Information Object revisions under:

```text
.aos/
├── knowledge/
│   └── <id>.r<revision>.json
└── state/
    └── <id>.r<revision>.json
```

Identifiers are caller-supplied opaque safe tokens and remain unique across
Knowledge and State. Revisions are monotonic and immutable. Revision files are
created through a temporary file, synchronized, closed, and atomically renamed
to their final path.

`aos knowledge` and `aos state` query records read-only. A record request uses
`--record` with object identity, subject, content or observed value, and source
reference. It plans by default; mutation requires `--apply --authority
<REFERENCE>`.

P4 creates only `proposed` objects. An attempt to record an authoritative
object fails closed because promotion requires Governance. Sensitive-looking
content is rejected from ordinary Knowledge or State storage.

`aos context` uses a deterministic default policy:

- consider the highest revision for each identity;
- select active authoritative Knowledge;
- select active authoritative State only when freshness is `confirmed`;
- withhold proposed, stale, unknown, superseded, retired, duplicate, or
  over-limit records;
- explain every withheld record; and
- order identities deterministically without using an AI provider.

## Consequences

### Positive

- Project intelligence is repository-native, immutable, attributable, and
  provider-independent.
- Producers cannot silently promote their own output.
- Stale and unknown State cannot enter default confirmed context.
- Context selection is reproducible and explainable.

### Negative

- P4 provides exact filtering rather than semantic ranking or embeddings.
- Governance promotion, lifecycle transitions, and richer provenance graphs
  remain later capabilities.
- JSON parsing is intentionally limited to the accepted P4 object binding.

## Alternatives considered

### Mutable aggregate JSON files

Rejected because rewriting a shared aggregate risks destroying revision history
and complicates concurrency and recovery.

### Provider-generated context selection

Rejected because provider output cannot own authority and would make the
default context non-deterministic.

### Database or vector store

Deferred until measured retrieval requirements justify operational complexity.

## Compatibility and migration

Every record declares `AOS-SPEC-001`. Future field or layout changes require a
versioned migration that preserves identity, revision ancestry, provenance,
authority, lifecycle, and freshness.

## Conformance

- Proposed Knowledge and State revisions retain source and authority references.
- Repeated updates create new immutable revision files.
- Cross-kind identity reuse is rejected.
- Missing authority prevents mutation.
- Sensitive content is rejected without writing.
- Default context excludes proposed, stale, and unknown records.
- Repeated context queries over the same snapshot produce identical output.
