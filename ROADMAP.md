# AOS Roadmap

**Status:** Canonical delivery sequence
**Current maturity:** P6, P6.2 accelerated qualification, and P6.3 installation/DX complete; P6.6 qualification remains active
**Next eligible phase:** P7 only after qualification evidence and a measured scale need
**Maturity model:** Evidence-gated capabilities, not promised release dates

## Roadmap rules

- Only one delivery phase is active at a time unless an accepted ADR explains
  safe parallel work.
- A later phase cannot claim maturity before its entry conditions are met.
- Deliverables are not complete until their verification evidence exists.
- A phase may be deferred without being described as failed.
- Release versions will be assigned only after executable, testable behavior
  exists.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| `PLANNED` | Defined but not authorized to start |
| `ACTIVE` | Current authorized delivery phase |
| `COMPLETE` | Exit gate passed with recorded evidence |
| `DEFERRED` | Intentionally postponed without failing its gate |

## P0 — Design Foundation

**Status:** `COMPLETE`

**Entry conditions**

- AOS is recognized as an independent OSS product.
- Product name, descriptor, license, and canonical language are decided.

**Deliverables**

- Concise project entry point.
- Canonical Vision, Principles, and AOS Reference Model.
- Evidence-gated roadmap.
- Specification governance and template.
- ADR governance and foundational decisions.
- Dependency-free design-foundation validation.

**Verification evidence**

- All canonical documents are internally consistent and linked.
- Foundational ADRs are accepted and reflected in current truth.
- The design validation command emits `AOS_DESIGN_FOUNDATION_OK`.
- The formal review is recorded in
  [P0 Design Foundation Review](evidence/P0-DESIGN-FOUNDATION-REVIEW.md).

**Exit gate**

P0 becomes complete when the deliverables are reviewed, the validator passes,
and no unresolved contradiction exists between canonical documents and accepted
ADRs.

**Closeout:** Passed on 2026-07-26. P2 was authorized after the language and
CLI boundary decisions were accepted.

## P1 — Standards and Contracts

**Status:** `COMPLETE`

**Entry conditions**

- P0 exit gate is complete.
- Ubiquitous language and artifact boundaries are stable.

**Deliverables**

- [AOS-SPEC-001 — Information Model](specifications/001-information-model.md).
- [AOS-SPEC-002 — Repository](specifications/002-repository.md).
- [AOS-SPEC-003 — Protocol](specifications/003-protocol.md).
- [AOS-SPEC-004 — CLI](specifications/004-cli.md).
- [AOS-SPEC-005 — Runtime](specifications/005-runtime.md).
- [AOS-SPEC-006 — Extension](specifications/006-extension.md).

**Verification evidence**

- Every specification in the P1 deliverable set has Accepted status, conformance
  cases, and compatibility behavior.
- Cross-specification terminology and ownership are consistent.
- No specification bypasses the Reference Model.

**Current evidence**

- `AOS-SPEC-001` is Accepted with review evidence in
  [P1 Information Model Review](evidence/P1-AOS-SPEC-001-REVIEW.md).
- `AOS-SPEC-002` is Accepted with review evidence in
  [P1 Repository Review](evidence/P1-AOS-SPEC-002-REVIEW.md).
- `AOS-SPEC-003` is Accepted with review evidence in
  [P1 Protocol Review](evidence/P1-AOS-SPEC-003-REVIEW.md).
- `AOS-SPEC-004`, `AOS-SPEC-005`, and `AOS-SPEC-006` are Accepted with review
  evidence in the P1 evidence set.
- The aggregate closeout is recorded in
  [P1 Standards and Contracts Review](evidence/P1-STANDARDS-CONTRACTS-REVIEW.md).

**Exit gate**

The Information Model, Repository, Protocol, CLI, Runtime, and Extension
contracts are all accepted with conformance evidence. Their boundaries are
decision-complete for later implementation phases.

**Closeout:** Passed on 2026-07-26. P2 was subsequently activated and
completed with its own exit evidence.

## P2 — Read-only Project Intelligence CLI

**Status:** `COMPLETE`

**Entry conditions**

- Relevant P1 specifications are accepted.
- Implementation language and distribution approach have accepted ADRs.

**Deliverables**

- Read-only project discovery and inspection.
- Contract validation and diagnostics.
- Planned interfaces for `inspect`, `validate`, and `doctor`.
- Deterministic output and failure behavior.
- Rust `1.96.0` native binary target with a stdlib-first dependency policy.
- Explicitly deferred `aos init` mutation boundary.

**Verification evidence**

- Unit and contract tests.
- Fixtures for valid, invalid, stale, and unsupported project states.
- Proof that read-only commands do not mutate managed repositories.
- [P2 Read-only CLI Review](evidence/P2-READ-ONLY-CLI-REVIEW.md).

**Exit gate**

The CLI can inspect and explain a project safely without relying on an AI
provider. P2 uses exit categories `0`, `2`, `3`, `4`, and `6`; mutation and
provider-dependent categories remain deferred.

**Closeout:** Passed on 2026-07-26. P3 was authorized after the read-only CLI
exit gate and completed with its own exit evidence.

## P3 — Transactional Repository Initialization

**Status:** `COMPLETE`

**Entry conditions**

- P2 exit gate is complete.
- Repository ownership and compatibility rules are accepted.

**Deliverables**

- Governed `aos init`.
- Dry-run change plan.
- Idempotency, rollback, conflict detection, and ownership boundaries.
- Ownership boundary foundation for future upgrade and removal of AOS-owned data.
- Minimal `.aos/repository.json` control-root schema.
- Atomic temporary-root commit with verification and reconciliation reporting.

**Verification evidence**

- Repeated initialization is safe.
- User-owned content is never overwritten silently.
- Interrupted and partial operations are recoverable or reconcilable.
- [P3 Transactional Initialization Review](evidence/P3-TRANSACTIONAL-INIT-REVIEW.md).

**Exit gate**

A repository can adopt AOS transactionally with verified ownership and recovery.
P3 requires an explicit non-empty authority reference; full Governance
authority resolution remains a later capability.

**Closeout:** Passed on 2026-07-26. P4 was authorized after the transactional
initialization exit gate and completed with its own exit evidence.

## P4 — Knowledge and Context

**Status:** `COMPLETE`

**Entry conditions**

- P3 exit gate is complete.
- Information provenance and state freshness contracts are accepted.

**Deliverables**

- Project Knowledge and State lifecycle.
- Progressive context retrieval.
- Deterministic validation before provider-generated output becomes
  authoritative.
- Immutable `.aos/knowledge/` and `.aos/state/` revision bindings.
- Provider-independent `knowledge`, `state`, and `context` CLI behavior.

**Verification evidence**

- Provenance, freshness, and ownership tests.
- Context-selection fixtures and explainability evidence.
- Provider-independent behavior for core operations.
- [P4 Knowledge and Context Review](evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md).

**Exit gate**

Project intelligence can be retrieved, explained, and updated without losing
provenance or authority.

**Closeout:** Passed on 2026-07-26. P5 is now the next eligible phase.

## P5 — Work, Protocol, and Governance

**Status:** `COMPLETE`

**Entry conditions**

- P4 exit gate is complete.
- Work, Protocol, and Governance lifecycle contracts are accepted.

**Deliverables**

- Structured Work lifecycle.
- Protocol execution and verification.
- Policy evaluation, approvals, and audit records.
- Safe handling for failed, partial, or unknown operations.

**Verification evidence**

- Protocol and governance conformance tests.
- Authorization-denial and reconciliation scenarios.
- Complete trace from intent to accepted result.
- [P5 Governed Work Review](evidence/P5-GOVERNED-WORK-REVIEW.md).

**Current implementation**

- Immutable `.aos/work`, `.aos/protocol`, `.aos/governance`, `.aos/runs`, and
  `.aos/audit` bindings.
- `aos work create|authorize|run|reconcile|show`.
- `aos.local.verify@1.0.0` local-only deterministic Protocol.
- Self-authority denial, stale-context denial, rejection preservation, unknown
  Run blocking, and evidence-backed reconciliation.

**Exit gate**

AOS can coordinate governed work without allowing runtime or providers to bypass
project authority.

**Closeout:** Passed on 2026-07-27. Product-value, controlled-pilot, local
format/test/build/clippy/validator gates, and P5 smoke/hardening gates pass.
GitHub Actions run `30246501837` executed successfully on Windows and Ubuntu
for closeout commit `33b7cf48e91f870751dba576c6a9e3bf5bbf3e98`. Release workflow
`30246618788` built and published `v0.1.0-rc.2` for Windows and Linux with
verified checksums. P6 subsequently passed its governed declarative-local
extension closeout.

## P6 — Extension Ecosystem

**Status:** `COMPLETE`

**Entry conditions**

- P5 exit gate is complete.
- Extension contract and capability model are accepted.

**Deliverables**

- Accepted declarative-local physical binding in ADR-0010.
- Immutable versioned manifest snapshots and governed lifecycle revisions.
- Capability intersection across Manifest, Protocol, Governance, Runtime
  allowlist, and exact Repository scope.
- Generic Repository and Rust reference extensions.
- Proposed Extension Results traceable through Work, Run, Protocol,
  Governance, context, input digest, verification, and Audit.
- Windows/Ubuntu CI and an RC3 distribution containing both reference packages.

**Verification evidence**

- Contract, compatibility, dependency, lifecycle, replay, isolation, and
  failure tests.
- AOS and fixed-snapshot TRENUX process smokes.
- Proof that extensions cannot redefine Core semantics, bypass Governance,
  directly invoke capability code, widen resource scope, or lose provenance.

**Closeout:** Passed on 2026-07-27. Local implementation, both reference
smokes, digest-tamper quarantine, Governance binding denial, deterministic
replay, concurrent lifecycle safety, and the TRENUX fixed-snapshot smoke pass.
GitHub Actions run `30251035563` passed on Windows and Ubuntu. Release workflow
`30251174570` published `v0.1.0-rc.3` with Windows/Linux binaries, both
reference packages, and verified checksums.

**Exit gate**

Independent extensions can add capability without compromising core project
truth.

### P6.1 bounded adoption and hardening evidence

P6 remains closed. A bounded follow-on adds an editor-facing JSON Schema,
runtime-valid template, resource limits, interrupted-enable recovery coverage,
and a repeated controlled pilot over three fixed repository snapshots.

The pilot executes Generic Repository and Rust capabilities twice per
repository: 12 governed Extension Runs, zero normalized replay drift, and zero
source-repository mutations. Evidence is recorded in
[`P6.1 Adoption and Hardening Review`](evidence/P6.1-ADOPTION-HARDENING-REVIEW.md).
This evidence does not activate P7 or claim production-like readiness.

### P6.2 production-like qualification

**Status:** `COMPLETE`

P6.2 adds deterministic filesystem boundary injection, recovery of incomplete
digest-bound Governance/Audit enable traces, extension-aware reconciliation,
monotonic replay Run revisions, and an append-only installed-pilot metrics
harness.

Immediate local gates pass. The historical pinned calendar lane records two
passing samples, zero failures, zero integrity failures, 24 governed Extension
Runs, and 0.762998 observed days. ADR-0012 then closes the blocking gate through
an independent accelerated lane: 8/8 samples, 96 governed Extension Runs, zero
failures, zero integrity failures, zero source mutations, deterministic nested
capabilities, and revalidated result digests. Its observed duration is reported
as 0.000379 days and is not described as a seven-day soak.
Evidence is recorded in
[`P6.2 Production-like Qualification`](evidence/P6.2-PRODUCTION-LIKE-QUALIFICATION.md).

**Closeout:** Passed on 2026-07-28 through the ADR-0012 bounded accelerated
qualification. Production-like functional readiness is limited to the
declarative local slice; seven-day resilience and production readiness are not
claimed.

P7 remains ineligible without a measured performance, availability, or
coordination bottleneck and completion of the active P6.6 generalization gate.

### P6.3 one-command installation and developer experience

**Status:** `COMPLETE`

ADR-0011 authorized this follow-on in an isolated lane while the original P6.2
calendar qualification continued against pinned binary, manifest, harness,
and commit hashes outside the source repository. This was the accepted
exception to the single-active-phase rule. ADR-0012 later closed P6.2 through
separate accelerated evidence without rewriting the calendar observations.

P6.3 adds:

- `aos setup [PATH]` with one plan and confirmation;
- embedded Generic Repository and Rust reference manifests;
- deterministic root-level Rust detection;
- Windows PowerShell and Linux shell installers;
- exact SHA-256, staged extraction, versioned provenance, upgrade/rollback,
  and owned uninstall behavior;
- offline Windows/Linux CI gates; and
- RC4 hosted installation and governed-extension release smoke.

Contract, setup process tests, Windows/Linux offline installer smokes, hosted
Windows/Ubuntu CI, published-asset install/uninstall smokes, exact checksums,
and build provenance attestations pass.
Evidence is recorded in
[`P6.3 Installation and Developer Experience`](evidence/P6.3-INSTALLATION-DEVELOPER-EXPERIENCE.md).

P6.3 does not add package-manager distribution, network behavior to Core,
arbitrary plugin execution, or any P7 scaling capability.

**Closeout:** Passed on 2026-07-27. CI run `30274793870` passed on Windows and
Ubuntu for implementation commit
`d3a42e256faa90f31cfe85176048d65104cea0f1`. Release workflow `30274942709`
published `v0.1.0-rc.4`, attested all five assets, then installed, exercised
governed extensions, and uninstalled the published distribution successfully
on fresh Windows and Ubuntu runners while retaining downstream `.aos`.

### P6.4 controlled adoption pilot

**Status:** `COMPLETE`

P6.4 proves adoption without widening Core semantics. The published RC4 is
installed into an isolated root and used across empty, generic, and Rust
repositories. Setup, governed Knowledge promotion, deterministic bounded
context, both reference extensions, Agent-brief generation, idempotent rerun,
and owned uninstall all pass without source mutation or loss of downstream
`.aos`.

A real provider-neutral consumer qualification also passes onboarding, bugfix,
and feature tasks with independent `cargo test` verification and no mutation
of AOS control data. The cumulative Agent input-token count is high enough to
justify a later orchestration optimization slice; it is not a reason to weaken
the successful correctness or governance result.

Evidence is recorded in
[`P6.4 Controlled Adoption Pilot`](evidence/P6.4-CONTROLLED-ADOPTION-PILOT.md).

**Closeout:** Passed on 2026-07-27. Published RC4 adoption passes on three
repository types; real onboarding, bugfix, and feature Agent tasks pass; and
GitHub Actions run `30277600563` passes the structural pilot on fresh Windows
and Ubuntu runners for implementation commit
`bee4e369c20d0ada2fb9415e2a7573ce1825e77a`.

At P6.4 closeout, P6.2 was still active on its separate pinned calendar lane.
ADR-0012 subsequently closed P6.2 through bounded accelerated evidence. P7
remains planned pending P6.6 and a measured scaling bottleneck.

### P6.5 Agent efficiency qualification

**Status:** `COMPLETE`

P6.5 keeps AOS Core unchanged and optimizes the first consumer adapter. A
provider-neutral capsule bounds source expansion, batches the initial read,
combines final verification, preserves `.aos`, and removes irrelevant MCP
discovery from the task loop.

Across two repeats of the same onboarding, bugfix, and feature tasks, task
success remains 3/3 per repeat. Average total input tokens fall 46.284%,
commands fall 45.455%, output tokens fall 26.633%, and elapsed time falls
25.708%. Optimized input-token drift is 0.184%.

Uncached input increases 7.209% because provider cache state differs; this is
reported explicitly and prevents interpreting total-token reduction as an
exact billing reduction. Evidence is recorded in
[`P6.5 Agent Efficiency Qualification`](evidence/P6.5-AGENT-EFFICIENCY-QUALIFICATION.md).

**Closeout:** Passed on 2026-07-27. GitHub Actions run `30280170417`
passes Windows and Ubuntu for implementation commit
`ccaedf8b1203202e9fa26a8bf7d397332558a857`, including P6.4 regression and
P6.5 deterministic evaluator gates.

P6.5 does not activate P7. ADR-0012 subsequently changes only the P6.2 blocking
exit route while preserving the historical calendar evidence.

### P6.6 real repository generalization

**Status:** `ACTIVE`

P6.6 tests the P6.5 consumer capsule across 15 patch-and-test tasks on three
immutable repository snapshots: AOS, `trenux_rust`, and TRENUX. Each repository
has onboarding, architecture-owner, bugfix, feature, and
documentation-consistency tasks, with two baseline and two AOS executions per
task. The closeout gate therefore requires 60 valid consumer executions.

The 15-scenario structural matrix passes, and the first four-execution AOS
canary preserves 100% task success while reducing total input tokens 31.26%,
elapsed time 39.20%, and commands 50%. The remaining real-consumer run is
temporarily blocked by the configured consumer usage limit and is not counted
as product failure or PASS evidence. See
[`P6.6 Real Repository Generalization`](evidence/P6.6-REAL-REPOSITORY-GENERALIZATION.md).

P6.6 remains active until all 60 executions pass the aggregate evaluator and
emit `AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_OK`. It does not close P6.2,
activate P7, or change AOS Core semantics.

**Implementation baseline:** Commit
`901d3916c74ecf7d425735ca4ee6a3c8acba2af9` passes GitHub Actions run
`30326531785` on Windows and Ubuntu, including the P6.6 evaluator smoke. This
does not change the `ACTIVE` status of the real-consumer gate.

## P7 — Scale and Distributed Runtime

**Status:** `PLANNED`

**Entry conditions**

- Earlier local-first capabilities are production-proven.
- Measured performance, availability, or coordination needs justify
  distribution.

**Deliverables**

- Only the scaling capabilities required by measured bottlenecks.
- Explicit consistency, partition, recovery, and operational models.

**Verification evidence**

- Benchmarks from representative workloads.
- Failure-injection, recovery, and consistency tests.
- Evidence that distributed behavior preserves core invariants.

**Exit gate**

Scale requirements are met without weakening correctness, governance,
auditability, or local interoperability.
