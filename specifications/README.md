# AOS Specifications

**Status:** Governance established; `AOS-SPEC-001` through `AOS-SPEC-006` accepted

Specifications define normative, externally observable AOS behavior. They turn
the product semantics in [DESIGN.md](../DESIGN.md) into versioned contracts that
implementations and extensions can test for conformance.

## Authority

A specification:

- must advance a goal in [VISION.md](../VISION.md);
- must comply with [PRINCIPLES.md](../PRINCIPLES.md);
- must fit the concepts and boundaries in [DESIGN.md](../DESIGN.md);
- cannot use implementation behavior to redefine the product silently; and
- requires an ADR when it introduces or changes an architectural decision.

Accepted specifications are normative for their declared scope. When an
accepted ADR changes a specification decision, the affected specification and
canonical design documents must be updated in the same change.

## Identifier

Every specification uses the identifier:

```text
AOS-SPEC-NNN
```

`NNN` is a zero-padded, monotonically increasing number. An identifier is never
reused, even when its specification is deprecated or superseded.

## Lifecycle

| State | Meaning |
| --- | --- |
| `Draft` | Under design; not an implementation contract |
| `Accepted` | Approved normative behavior with conformance criteria |
| `Deprecated` | Still recognized but discouraged, with an explicit transition |
| `Superseded` | Replaced by a named later specification |

Only an Accepted specification can authorize implementation of its normative
behavior. A state change must be recorded in the specification change history.

## Normative language

The keywords **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
express requirement levels:

- **MUST** and **MUST NOT** define conformance requirements.
- **SHOULD** and **SHOULD NOT** require a documented reason when not followed.
- **MAY** identifies optional behavior.

Normative keywords should be used only where a conformance test or review can
determine whether the requirement is satisfied.

## Required structure

Every specification is created from [TEMPLATE.md](TEMPLATE.md) and contains:

1. metadata and status;
2. purpose and motivation;
3. scope and non-goals;
4. terminology;
5. normative requirements;
6. interfaces and data flow;
7. lifecycle and state transitions;
8. failure behavior;
9. security and governance;
10. compatibility and migration;
11. conformance tests;
12. unresolved questions; and
13. change history.

A specification cannot become Accepted while normative requirements,
compatibility behavior, or conformance tests remain unresolved.

## Planned specification queue

The initial queue is dependency ordered. An entry becomes a Draft or Accepted
specification only when its file is deliberately created with the corresponding
status.

| Order | ID | Subject | State | Depends on |
| --- | --- | --- | --- |
| 1 | [`AOS-SPEC-001`](001-information-model.md) | Information Model | `Accepted` | P0 Reference Model |
| 2 | [`AOS-SPEC-002`](002-repository.md) | Repository | `Accepted` | Information Model |
| 3 | [`AOS-SPEC-003`](003-protocol.md) | Protocol | `Accepted` | Information Model and Repository |
| 4 | [`AOS-SPEC-004`](004-cli.md) | CLI | `Accepted` | Repository and Protocol |
| 5 | [`AOS-SPEC-005`](005-runtime.md) | Runtime | `Accepted` | Protocol and CLI boundaries |
| 6 | [`AOS-SPEC-006`](006-extension.md) | Extension | `Accepted` | Core contracts and Runtime boundaries |

Creating a specification out of this order requires an ADR explaining how its
dependencies are satisfied without inventing conflicting semantics.

## Acceptance process

Before a specification becomes Accepted:

1. its dependency specifications are Accepted;
2. its terms match the ubiquitous language;
3. every normative behavior has conformance coverage;
4. failure, unknown-state, and compatibility behavior are explicit;
5. security and governance boundaries are reviewed;
6. affected canonical documents and ADRs are consistent; and
7. the design-foundation validator passes.

## Current accepted specification

`AOS-SPEC-001 — Information Model` through `AOS-SPEC-006 — Extension` are the
current Accepted specifications. Their review evidence is recorded in
[P1-AOS-SPEC-001-REVIEW.md](../evidence/P1-AOS-SPEC-001-REVIEW.md) and
[P1-AOS-SPEC-002-REVIEW.md](../evidence/P1-AOS-SPEC-002-REVIEW.md) and
[P1-AOS-SPEC-003-REVIEW.md](../evidence/P1-AOS-SPEC-003-REVIEW.md),
[P1-AOS-SPEC-004-REVIEW.md](../evidence/P1-AOS-SPEC-004-REVIEW.md),
[P1-AOS-SPEC-005-REVIEW.md](../evidence/P1-AOS-SPEC-005-REVIEW.md), and
[P1-AOS-SPEC-006-REVIEW.md](../evidence/P1-AOS-SPEC-006-REVIEW.md).
