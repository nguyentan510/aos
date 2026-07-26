# ADR-0001 — Independent Product and Artifact Boundary

**Status:** Accepted
**Date:** 2026-07-25
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `README.md`, `VISION.md`, `DESIGN.md`, `ROADMAP.md`

## Context

AOS was initially described in a way that could be interpreted as a framework
directory copied directly into a software project. That interpretation mixes
the source of the AOS product with the control data it may later manage inside a
user repository.

The product needs an explicit boundary so that source development, release
distribution, managed-project ownership, compatibility, and removal can evolve
independently.

## Decision

AOS is an independent open-source product.

The architecture distinguishes three artifacts:

1. the AOS source repository, owned by AOS maintainers;
2. the released CLI/runtime distribution, installed in a user environment; and
3. a managed project repository, which may contain project-owned AOS control
   data under `.aos/`.

The AOS source repository is not the `.aos/` directory and is not a project
template. A future distribution may operate on `.aos/` only through specified
ownership, lifecycle, compatibility, and governance rules.

## Consequences

### Positive

- Product development and managed-project data have clear ownership.
- Distribution and upgrade behavior can be versioned independently.
- Removal can distinguish AOS-owned control data from user-owned source.
- AOS can serve multiple project types without copying its own source into them.

### Negative

- A distribution and compatibility model must be designed before executable
  adoption.
- Documentation must consistently distinguish source, distribution, and managed
  project.

### Risks and controls

- Terminology may drift back toward framework language. Canonical documents and
  validation checks enforce the three-artifact boundary.
- Future initialization could overreach into user content. Repository
  specifications must define ownership and transactional behavior first.

## Alternatives considered

### A framework installed as project source

Rejected because it couples product implementation to every managed repository,
blurs upgrade ownership, and makes clean compatibility difficult.

### A hosted service as the only product

Rejected because it conflicts with repository-native, local-first, and
provider-neutral goals.

## Compatibility and migration

There is no executable implementation or persisted AOS project data, so no
migration is required. Existing design language is replaced by the explicit
three-artifact model.

## Conformance

- `README.md` presents the source → distribution → managed-project flow.
- `DESIGN.md` defines ownership and responsibility for all three artifacts.
- Future Repository and CLI Specifications must reference this boundary.
