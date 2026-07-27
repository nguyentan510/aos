# AOS

> Project Intelligence Operating System for AI-assisted software development.

**Status:** P5 governed Work vertical slice implemented; phase closeout deferred

AOS is an open-source product for making software repositories understandable,
governable, and durable across human and AI-assisted development sessions. It
places a Project Intelligence layer around a repository so that project
knowledge, current state, work, protocols, and governance remain explicit
instead of being trapped in chat history or a specific tool.

AOS is a product in its own right. This repository contains the source and
design of AOS; it is not the `.aos/` directory that a future AOS distribution
will manage inside another repository.

## Why AOS

AI tools can generate code, but they do not automatically preserve a reliable
understanding of a project. Common failure modes include:

- losing project context between sessions;
- inferring progress or architecture from incomplete evidence;
- retrieving too much irrelevant context;
- keeping decisions in chat instead of the repository;
- bypassing project-specific workflows or governance; and
- producing knowledge that has no source or ownership.

AOS addresses these failures by making project intelligence repository-native,
explicit, traceable, and independent of any single AI provider.

## Product boundary

```text
AOS source repository
        |
        | build and release
        v
AOS CLI and runtime distribution
        |
        | transactional: aos init
        v
Managed project repository
        |
        `-- .aos/   project intelligence control data
```

The current Rust `1.96.0` binary implements repository inspection,
transactional `aos init`, immutable proposed Knowledge and State revisions,
deterministic context retrieval, and a governed Work lifecycle bound to the
local-only `aos.local.verify@1.0.0` Protocol. Mutating commands plan by default
and require explicit apply and authority evidence.

## Who AOS is for

- Project owners who need durable project truth and governance.
- Contributors who need reliable onboarding and current project state.
- AI and development-tool providers that need a stable project interface.
- AOS maintainers and extension authors building against versioned contracts.

## What AOS is not

AOS is not an AI model, coding agent, IDE, source-control replacement, CI/CD
platform, or permission for AI to act without human authority. It does not own
application business logic and does not make unverified inference canonical.

## Canonical design

The current source of truth is:

| Document | Responsibility |
| --- | --- |
| [VISION.md](VISION.md) | Mission, problem, goals, non-goals, and product strategy |
| [PRINCIPLES.md](PRINCIPLES.md) | Stable constraints governing every design decision |
| [DESIGN.md](DESIGN.md) | Canonical AOS Reference Model and system boundaries |
| [ROADMAP.md](ROADMAP.md) | Capability phases, evidence, and maturity gates |

Normative behavior will be defined under
[specifications/](specifications/README.md). Architectural decisions and their
consequences are recorded under [adr/](adr/README.md).

## Current maturity

The project has completed **P0 — Design Foundation**, **P1 — Standards and
Contracts**, **P2 — Read-only Project Intelligence CLI**, **P3 — Transactional
Repository Initialization**, and **P4 — Knowledge and Context**. The accepted
contracts are
[`AOS-SPEC-001 — Information Model`](specifications/001-information-model.md),
[`AOS-SPEC-002 — Repository`](specifications/002-repository.md),
[`AOS-SPEC-003 — Protocol`](specifications/003-protocol.md),
[`AOS-SPEC-004 — CLI`](specifications/004-cli.md),
[`AOS-SPEC-005 — Runtime`](specifications/005-runtime.md), and
[`AOS-SPEC-006 — Extension`](specifications/006-extension.md).

The formal closeout evidence is recorded in
[P0 Design Foundation Review](evidence/P0-DESIGN-FOUNDATION-REVIEW.md).
The first P1 contract review is recorded in
[P1 Information Model Review](evidence/P1-AOS-SPEC-001-REVIEW.md).
The Repository contract review is recorded in
[P1 Repository Review](evidence/P1-AOS-SPEC-002-REVIEW.md).
The Protocol contract review is recorded in
[P1 Protocol Review](evidence/P1-AOS-SPEC-003-REVIEW.md).
The CLI, Runtime, and Extension contract reviews are recorded in
[P1 CLI Review](evidence/P1-AOS-SPEC-004-REVIEW.md),
[P1 Runtime Review](evidence/P1-AOS-SPEC-005-REVIEW.md), and
[P1 Extension Review](evidence/P1-AOS-SPEC-006-REVIEW.md).
The aggregate phase closeout is recorded in
[P1 Standards and Contracts Review](evidence/P1-STANDARDS-CONTRACTS-REVIEW.md).

P2 is complete. Its implementation and verification evidence are recorded in
[P2 Read-only CLI Review](evidence/P2-READ-ONLY-CLI-REVIEW.md). The executable
package is `aos-cli`, built with Cargo from the pinned Rust `1.96.0` toolchain.
The implementation is stdlib-first.

P3 is complete. Its implementation and verification evidence are recorded in
[P3 Transactional Initialization Review](evidence/P3-TRANSACTIONAL-INIT-REVIEW.md).
The minimal physical schema is `.aos/repository.json`; unknown files remain
protected and full Governance authority resolution is deferred to a later
capability.

P4 is complete. Its evidence is recorded in
[P4 Knowledge and Context Review](evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md).
Knowledge revisions use `.aos/knowledge/`, State revisions use `.aos/state/`,
and `aos context` selects provider-independent context while explaining every
withheld stale, unknown, proposed, non-active, over-limit, or budget-excluded
record. Consumers may request a compact profile and an explicit byte budget.

The P5 vertical slice is implementation-aligned and runtime-smoke-ready. It
records immutable Work, Protocol, Governance, Run, and Audit data and exposes
`aos work create|authorize|run|reconcile|show`. Its evidence is recorded in
[P5 Governed Work Review](evidence/P5-GOVERNED-WORK-REVIEW.md). P5 phase
closeout remains deferred until the real AI-facing P4 value benchmark emits
`AOS_P4_VALUE_BENCHMARK_OK`.

Validate the complete design and standards governance with:

```bash
node scripts/validate-aos.mjs
```

Expected success marker:

```text
AOS_DESIGN_FOUNDATION_OK
AOS_SPECIFICATIONS_OK
AOS_GOVERNANCE_OK
```

## License

Licensed under the [Apache License 2.0](LICENSE).
