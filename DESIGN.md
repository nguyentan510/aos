# AOS Reference Model

**Status:** Canonical
**Product:** AOS — Project Intelligence Operating System
**Scope:** Product semantics and architectural boundaries

## Purpose

This document is the canonical reference model for AOS. It defines stable
concepts, responsibilities, boundaries, and interactions that future
specifications and implementations must fit.

It intentionally does not define the physical `.aos/` layout, wire formats,
storage technology, AI provider, or executable API. Those details require
specifications or ADRs in later phases. The implementation binding for the
current phase is recorded separately in ADR-0005.

## Design authority

The current source of truth is divided by responsibility:

- [VISION.md](VISION.md) defines why AOS exists and what outcomes it pursues.
- [PRINCIPLES.md](PRINCIPLES.md) defines constraints that designs must obey.
- This document defines system semantics and architectural boundaries.
- [Specifications](specifications/README.md) define normative behavior and
  conformance.
- [ADRs](adr/README.md) record why architectural decisions were made.
- [ROADMAP.md](ROADMAP.md) orders delivery and reports maturity.

An accepted ADR that changes current truth must update every affected canonical
document in the same change. The roadmap and README cannot override design or
specifications.

## Current implementation binding

P2 through P4 are implemented as a native Rust `1.96.0` binary produced by
Cargo. The stdlib-first implementation exposes repository inspection,
transactional initialization, immutable proposed Knowledge and State revisions,
and deterministic context retrieval. P3 binds `.aos/repository.json`; P4 binds
`.aos/knowledge/` and `.aos/state/` as defined by `AOS-SPEC-001` and
`AOS-SPEC-002`.

Mutation requires a non-empty authority reference, but P4 never promotes a
producer's record to authoritative Project truth. Default context selects only
active authoritative Knowledge and active authoritative State with confirmed
freshness. Full Governance authority resolution and promotion remain later
capabilities.

## System context

### Actors

| Actor | Responsibility |
| --- | --- |
| Project owner | Owns project purpose, authority, and governance decisions |
| Contributor | Performs work within project protocols and permissions |
| AI or tool provider | Supplies optional assistance through bounded interfaces |
| AOS maintainer | Evolves the product, reference model, and core contracts |
| Extension author | Adds optional capabilities through versioned contracts |

### External systems

AOS may interact with source control, editors, CI/CD, issue trackers, knowledge
stores, and AI providers. These systems remain independent. AOS records their
role and evidence where relevant but does not silently replace their authority.

## Artifact boundary

AOS has three distinct artifacts:

| Artifact | Ownership | Responsibility |
| --- | --- | --- |
| AOS source repository | AOS maintainers | Product design, specifications, source, tests, and release inputs |
| AOS distribution | Release process and user environment | CLI/runtime binaries or packages used to operate AOS |
| Managed project | Project owner | Business source plus project-owned AOS control data under `.aos/` |

The AOS source repository is not a managed project template. The distributed
product may initialize and operate `.aos/` in another repository, but it must
preserve the boundary between AOS-owned control data and user-owned project
content.

## Ubiquitous language

### Project

The aggregate managed by AOS. A Project has identity, ownership, boundaries, and
links to its authoritative systems. Identity is part of Project, not an
independent top-level domain concept.

### Knowledge

Durable information that explains the Project. Knowledge includes provenance,
ownership, version, and lifecycle. Specifications, architecture, decisions,
concepts, and glossary entries may become Knowledge when their authority is
explicit.

### State

An explicit observation or declaration of current Project condition. State has
an authority classification (`proposed` or `authoritative`) and a separate
freshness classification (`confirmed`, `stale`, or `unknown`) as defined by
`AOS-SPEC-001`. A proposed State is not current truth merely because it is
recent.

### Work

An identified intent to inspect or change Project state. Work has an owner,
scope, lifecycle, relevant context, expected output, and verification evidence.
Task, bug, feature, and milestone are possible Work classifications rather than
separate core concepts.

### Protocol

A versioned set of rules for performing Work. A Protocol defines required
inputs, ordered activities, checks, outputs, failure behavior, and governance
points. Protocol is independent of a provider-specific prompt.

### Governance

The policies, authority, approvals, constraints, and audit evidence that decide
whether Work is permitted and accepted. Governance does not perform the work;
it constrains and records decisions about it.

## Architectural mechanisms

Runtime and Extension are architectural mechanisms, not domain concepts. They
operate on the domain model without redefining it.

### Interface plane

Exposes AOS capabilities to people and tools through future CLI or programmatic
interfaces. It validates requests and presents results but does not own domain
truth.

### Intelligence plane

Resolves Project, Knowledge, and State and selects attributable context. It
distinguishes repository evidence, external authority, observations, and
proposals.

### Coordination and control plane

Creates and advances Work according to Protocol. It coordinates activity but
does not bypass Governance or directly redefine State.

### Governance plane

Evaluates policy and authority, records decisions, and produces audit evidence.
Consequential operations cannot skip this plane.

### Runtime plane

Executes authorized capabilities through adapters for repositories, tools, and
providers. Runtime reports results and uncertainty; it cannot declare its own
output authoritative without validation and synchronization.

### Extension boundary

Allows optional domain, language, framework, provider, or tool capability
through versioned contracts. Extensions cannot redefine the ubiquitous
language, bypass governance, or access undeclared capabilities.

### Distribution and lifecycle

Packages AOS and manages compatibility between the distributed product and a
managed Project. It will own initialization, inspection, validation, upgrade,
and removal behavior once those behaviors are specified.

## Canonical interaction flow

```text
Human or tool intent
        |
        v
Interface validation
        |
        v
Project context retrieval
        |
        v
Work creation or selection
        |
        v
Protocol validation
        |
        v
Governance authorization
        |
        v
Runtime capability execution
        |
        v
Repository or external-system result
        |
        v
Verification and reconciliation
        |
        v
State, Knowledge, and audit synchronization
```

A read-only interaction may end after retrieval or validation. A mutating
interaction cannot omit authorization, verification, or reconciliation.

## System invariants

1. The managed Project owns its business source and project authority.
2. AOS never treats chat history or model memory as the sole durable truth.
3. Authoritative Knowledge and State carry provenance.
4. Unknown or stale State is not presented as confirmed.
5. Mutations are explicit, governed, auditable, and recoverable or reconcilable.
6. Runtime and extensions cannot grant themselves authority.
7. Extensions cannot bypass core contracts or governance.
8. Provider output is proposed evidence until deterministic checks promote it.
9. Compatibility changes are versioned and include migration or rejection
   behavior.
10. Scale and distribution require measured need and cannot weaken correctness.

## Planned project lifecycle

The intended lifecycle, subject to later specifications, is:

1. A user installs an AOS distribution outside the managed repository.
2. `aos init` inspects a repository and proposes AOS-owned project control data.
3. Read-only inspection, validation, and diagnostic capabilities operate on the
   Project.
4. Later governed capabilities coordinate Work and approved mutation.
5. Upgrade behavior migrates compatible AOS-owned data explicitly.
6. Removal behavior distinguishes AOS-owned data from user-owned project
   content.

The CLI specification defines exact command behavior. P2 currently exposes the
read-only commands `version`, `inspect`, `validate`, and `doctor`; the reference
model reserves the canonical managed-project mutation command `aos init` for
the governed P3 lifecycle.

## Trust and authority

- Human and organizational governance define authority.
- AOS components operate with declared, least-privilege capabilities.
- Secrets are not project knowledge and must not be stored as ordinary control
  data.
- External evidence retains its source and freshness.
- Timeouts, partial writes, or unknown external state require reconciliation
  before a result is considered complete.
- AOS must expose why context, policy, or an action was selected.

## Extension conformance

An extension is conformant only if it:

- declares its identity, version, compatibility, and capabilities;
- uses published core contracts;
- preserves provenance and audit requirements;
- cannot bypass governance or mutate undeclared resources;
- reports failure and unknown state explicitly; and
- can be disabled without corrupting core Project truth.

The Extension Specification will define the exact interface and validation
mechanism.

## Feature conformance

Before implementation, every proposed feature must identify:

1. the goal in [VISION.md](VISION.md) that it advances;
2. the principles in [PRINCIPLES.md](PRINCIPLES.md) that constrain it;
3. its owner plane and affected domain concepts in this reference model;
4. the accepted specification that defines observable behavior;
5. any ADR needed to change an existing decision;
6. its phase and entry gate in [ROADMAP.md](ROADMAP.md); and
7. the evidence that will prove conformance.

A feature that cannot provide this trace is not ready for AOS Core.
