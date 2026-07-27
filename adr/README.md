# AOS Architecture Decision Records

Architecture Decision Records (ADRs) preserve the context, decision,
alternatives, and consequences of material AOS design choices.

## When an ADR is required

Create an ADR when a decision:

- changes product or artifact boundaries;
- changes the AOS Reference Model or ubiquitous language;
- introduces a public contract or compatibility rule;
- selects foundational implementation or distribution technology;
- changes trust, authority, security, or mutation behavior;
- permits an exception to a canonical principle; or
- reverses or supersedes an earlier architectural decision.

Routine editorial clarification that does not change meaning does not require an
ADR.

## Identifier and filename

ADRs use a zero-padded, monotonically increasing identifier:

```text
ADR-NNNN
```

The filename is:

```text
NNNN-short-kebab-case-title.md
```

Identifiers are never reused.

## Status

| Status | Meaning |
| --- | --- |
| `Proposed` | Under review and not authoritative |
| `Accepted` | Current architectural decision |
| `Deprecated` | Retained for history but no longer recommended |
| `Superseded` | Replaced by a named later ADR |
| `Rejected` | Considered and explicitly not adopted |

Accepted ADRs record decisions but do not form a competing source of current
truth. Every acceptance or supersession must update affected canonical design
documents and specifications in the same change.

## Process

1. Copy [TEMPLATE.md](TEMPLATE.md) and allocate the next identifier.
2. Describe the context without assuming the proposed decision.
3. Record the decision, alternatives, and consequences.
4. Identify every affected canonical document and specification.
5. Review security, compatibility, migration, and rollback implications.
6. Update affected current-truth documents with acceptance.
7. Run the design-foundation validator.

## Decision index

| ADR | Status | Decision |
| --- | --- | --- |
| [ADR-0001](0001-independent-product-boundary.md) | Accepted | AOS is an independent OSS product with three distinct artifacts |
| [ADR-0002](0002-design-canonical-reference-model.md) | Accepted | `DESIGN.md` is the canonical AOS Reference Model |
| [ADR-0003](0003-init-bootstrap-command.md) | Accepted | `aos init` is the canonical managed-project bootstrap command |
| [ADR-0004](0004-domain-runtime-separation.md) | Accepted | Domain concepts are separated from Runtime and Extension mechanisms |
| [ADR-0005](0005-rust-native-binary-implementation.md) | Accepted | Rust 1.96 is the initial implementation and binary distribution foundation |
| [ADR-0006](0006-p2-read-only-cli-boundary.md) | Accepted | P2 is read-only; `aos init` mutation is deferred to P3 |
| [ADR-0007](0007-transactional-repository-initialization.md) | Accepted | P3 adopts repositories transactionally through `.aos/repository.json` |
| [ADR-0008](0008-p4-knowledge-state-context-binding.md) | Accepted | P4 stores immutable Knowledge/State revisions and selects context deterministically |
| [ADR-0009](0009-p5-governed-work-vertical-slice.md) | Accepted | P5 binds governed Work to immutable context, Protocol, verification, and reconciliation |
| [ADR-0010](0010-p6-governed-declarative-extension-ecosystem.md) | Accepted | P6 binds declarative extensions to governed Work, allowlisted host operations, exact scope, and immutable provenance |
