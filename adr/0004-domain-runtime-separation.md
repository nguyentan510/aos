# ADR-0004 — Separation of Domain Concepts and Runtime Mechanisms

**Status:** Accepted
**Date:** 2026-07-25
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `DESIGN.md`, `PRINCIPLES.md`,
`specifications/README.md`

## Context

Early design material mixed information objects, product concepts, runtime
components, and extension mechanisms into competing core models. Treating
Runtime as project information makes persisted meaning depend on an
implementation. Treating Extensions as core semantics allows optional behavior
to redefine the product.

AOS needs a ubiquitous language that remains stable when execution technology,
providers, or extensions change.

## Decision

The AOS domain model contains:

- Project;
- Knowledge;
- State;
- Work;
- Protocol; and
- Governance.

Identity belongs to Project. Runtime and Extension are architectural mechanisms,
not domain concepts.

Runtime executes authorized capabilities against domain inputs and reports
results. Extensions add optional capability through versioned contracts.
Neither may redefine domain semantics, claim authority, or bypass Governance.

## Consequences

### Positive

- Project information remains independent of implementation technology.
- Runtime and providers can be replaced without redefining durable truth.
- Extension boundaries are easier to version and test.
- Ownership between information, coordination, authority, and execution is
  explicit.

### Negative

- Specifications must translate carefully between domain concepts and runtime
  interfaces.
- Some implementation objects may not map one-to-one to a domain concept.

### Risks and controls

- Runtime may become an implicit owner of State. Specifications must require
  validation and synchronization before runtime output becomes authoritative.
- Extensions may invent incompatible vocabulary. Conformance requires them to
  use published core contracts.

## Alternatives considered

### Runtime as a core domain concept

Rejected because an execution mechanism should not define persistent project
meaning.

### Identity as a separate top-level concept

Rejected because identity defines the Project aggregate and does not have an
independent lifecycle in the Reference Model.

### Provider-specific agent roles as core concepts

Rejected because AOS must remain provider-neutral and roles may be introduced
later as protocol or extension behavior.

## Compatibility and migration

There is no persisted implementation to migrate. Existing design terminology is
normalized into the canonical domain and architectural separation.

## Conformance

- DESIGN defines the six domain concepts and separate architectural planes.
- PRINCIPLES constrains Runtime and Extensions.
- Planned specifications follow the dependency order rooted in the Information
  Model.
