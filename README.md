# AOS

> Project Intelligence Operating System for AI-assisted software development.

**Status:** P6, P6.2 accelerated qualification, P6.3 installation/DX, P6.4 controlled adoption, and P6.5 Agent efficiency complete; P6.6 qualification remains active; P7 remains planned

AOS is an open-source product for making software repositories understandable,
governable, and durable across human and AI-assisted development sessions. It
places a Project Intelligence layer around a repository so that project
knowledge, current state, work, protocols, and governance remain explicit
instead of being trapped in chat history or a specific tool.

AOS is a product in its own right. This repository contains the source and
design of AOS; it is not the `.aos/` directory that a future AOS distribution
will manage inside another repository.

## Quick Start

Windows PowerShell:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/nguyentan510/aos/main/install.ps1))) -ProjectPath .
```

Linux x86_64 GNU:

```bash
curl -fsSL https://raw.githubusercontent.com/nguyentan510/aos/main/install.sh |
  sh -s -- --project-path .
```

If AOS is already installed:

```text
aos setup .
aos doctor .
aos context . --format json
```

`setup` displays one plan and asks once before mutation. CI and other
non-interactive callers use `aos setup . --yes`. It does not create the project
folder, initialize Git, modify source, or create Knowledge/Work records.

Distribution uninstall never removes downstream `.aos` project data:

```powershell
.\install.ps1 -Uninstall
```

```bash
sh ./install.sh --uninstall
```

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
Repository Initialization**, **P4 — Knowledge and Context**, and **P5 —
Work, Protocol, and Governance**, and **P6 — Extension Ecosystem** at the
governed declarative-local scope. P7 remains planned until a measured scale
bottleneck justifies it. The accepted contracts are
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

P5 is complete and runtime-smoke-ready. Its vertical slice
records immutable Work, Protocol, Governance, Run, and Audit data and exposes
`aos work create|authorize|run|reconcile|show`. Its evidence is recorded in
[P5 Governed Work Review](evidence/P5-GOVERNED-WORK-REVIEW.md) and
[P5 Controlled Downstream Pilot](evidence/P5-CONTROLLED-DOWNSTREAM-PILOT.md).
The P4 value benchmark, controlled downstream pilot, local CI-equivalent gates,
and GitHub-hosted Windows and Ubuntu CI pass. P6 provides governed, declarative,
local-read-only extension lifecycle and execution. The Generic Repository and
Rust reference manifests run only through authorized Work using
`aos.extension.readonly@1.0.0`; arbitrary executable, command, path, network,
secret, and provider inputs are not supported. Local AOS, fixed-snapshot
TRENUX, and hosted Windows/Ubuntu smokes pass. The CI-built
[`v0.1.0-rc.3`](https://github.com/nguyentan510/aos/releases/tag/v0.1.0-rc.3)
prerelease contains Windows and Linux binaries, both reference manifest
packages, and verified checksums. Production-like-runtime-ready and
production-ready remain explicitly unclaimed. See
[P6 Extension Ecosystem Review](evidence/P6-EXTENSION-ECOSYSTEM-REVIEW.md).

A bounded P6.1 follow-on adds an
[Extension Authoring Kit](extensions/README.md), manifest and Cargo input
limits, interrupted-enable recovery coverage, and a deterministic
three-repository pilot with two repeats per capability. The pilot records 12
Extension Runs with zero normalized replay drift and no source-repository
mutation. See
[P6.1 Adoption and Hardening Review](evidence/P6.1-ADOPTION-HARDENING-REVIEW.md).
This strengthens P6 evidence without activating P7.

P6.2 production-like functional qualification is complete for the bounded
declarative-local slice. Filesystem fault-injection and governed recovery pass,
and the ADR-0012 accelerated lane completes 8/8 pinned samples and 96 governed
Extension Runs with zero failures, integrity failures, or source mutations.
The separate historical calendar lane is retained at two real daily samples;
the accelerated result is not described as a seven-day soak. See
[P6.2 Production-like Qualification](evidence/P6.2-PRODUCTION-LIKE-QUALIFICATION.md).

P6.3 is a completed, isolated developer-experience follow-on governed by
[ADR-0011](adr/0011-p6-3-one-command-installation-and-setup.md). It adds
`aos setup`, embedded reference manifests, checksum-verified Windows/Linux
installers, offline installer gates, owned uninstall, and hosted release smoke.
The historical P6.2 calendar lane remains pinned outside this repository.
ADR-0012 later closed P6.2 through separate accelerated evidence without
rewriting that calendar lane. See
[P6.3 Installation and Developer Experience](evidence/P6.3-INSTALLATION-DEVELOPER-EXPERIENCE.md).
The CI-built
[`v0.1.0-rc.4`](https://github.com/nguyentan510/aos/releases/tag/v0.1.0-rc.4)
prerelease contains both binaries, both installers, exact checksums, and GitHub
build provenance attestations.

P6.4 controlled adoption runs the published RC4 across empty, generic, and
Rust repositories, then qualifies a provider-neutral Agent brief through real
onboarding, bugfix, and feature tasks. The released installation, governed
context, reference extensions, deterministic replay, task verification, and
owned uninstall gates pass without source or `.aos` control-data mutation.
Hosted Windows/Ubuntu portability also passes. See
[P6.4 Controlled Adoption Pilot](evidence/P6.4-CONTROLLED-ADOPTION-PILOT.md).

P6.5 Agent efficiency keeps the model, repository snapshot, and tasks fixed
while adding a bounded provider-neutral consumer capsule. Across two repeats,
task success remains 3/3 and average total input tokens fall 46.284%, commands
fall 45.455%, and elapsed time falls 25.708%. Uncached-token behavior is
reported separately and no provider billing reduction is claimed. See
[P6.5 Agent Efficiency Qualification](evidence/P6.5-AGENT-EFFICIENCY-QUALIFICATION.md).

P6.6 real repository generalization is active across 15 patch-and-test tasks
on fixed AOS, `trenux_rust`, and TRENUX snapshots. The complete structural
matrix passes, and the AOS onboarding canary keeps 100% task success while
reducing total input tokens 31.26%, elapsed time 39.20%, and commands 50%.
The first complete 60-execution matrix passed every functional and aggregate
efficiency gate but failed the original maximum per-scenario provider-token
drift gate. ADR-0015 preserves that failed evidence and requires a new
independent schema-v2 batch with prompt-bound aggregate repeatability before
P6.6 can close.
See
[P6.6 Real Repository Generalization](evidence/P6.6-REAL-REPOSITORY-GENERALIZATION.md).

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
