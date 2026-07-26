# ADR-0002 — DESIGN.md as the Canonical Reference Model

**Status:** Accepted
**Date:** 2026-07-25
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `README.md`, `DESIGN.md`, `specifications/README.md`,
`adr/README.md`

## Context

AOS requires a stable architecture reference that contributors and AI-assisted
tools can use for consistent implementation. Maintaining both a root
architecture overview and a separate foundational reference model would create
two documents with overlapping authority and predictable drift.

## Decision

`DESIGN.md` is the canonical AOS Reference Model.

It defines product semantics, ubiquitous language, artifact boundaries,
architectural mechanisms, invariants, and conformance rules. Detailed
specifications may refine observable behavior but cannot redefine the Reference
Model silently.

If `DESIGN.md` later becomes too large, supporting design documents may be
introduced. They will remain subordinate to a concise canonical model in
`DESIGN.md`; authority will not move implicitly.

## Consequences

### Positive

- Contributors have one architecture entry point.
- README can remain concise and informative.
- Specifications have a stable semantic parent.
- Design drift is easier to detect and review.

### Negative

- Changes to `DESIGN.md` require deliberate cross-document review.
- The document must remain abstract enough to outlive implementation choices.

### Risks and controls

- The Reference Model could become an implementation specification. Reviews
  must reject premature physical schemas, technologies, and executable APIs.
- Supporting documents could compete for authority. Their relationship must be
  stated explicitly and validated.

## Alternatives considered

### Root overview plus a separate `design/00-aos-reference-model.md`

Rejected for the foundation phase because the two documents would repeat core
concepts and boundaries before complexity justifies the split.

### Architecture defined only by specifications

Rejected because individual specifications cannot provide a stable,
technology-independent model of the whole product.

## Compatibility and migration

The existing monolithic README is decomposed. Its architectural content is
normalized into `DESIGN.md`; no executable compatibility impact exists.

## Conformance

- README identifies `DESIGN.md` as canonical.
- Specification governance requires conformance to `DESIGN.md`.
- Accepted ADRs update affected canonical documents in the same change.
