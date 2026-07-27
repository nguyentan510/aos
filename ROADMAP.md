# AOS Roadmap

**Status:** Canonical delivery sequence
**Current maturity:** P6 — Extension Ecosystem active
**Next eligible phase:** P7 only after P6 closeout and measured scale need
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
verified checksums. P6 is now the active phase.

## P6 — Extension Ecosystem

**Status:** `ACTIVE`

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

**Current evidence:** Local implementation, both reference smokes, digest
tamper quarantine, deterministic replay, and the TRENUX fixed-snapshot smoke
pass. Hosted Windows/Ubuntu CI and `v0.1.0-rc.3` provenance remain the closeout
gates.

**Exit gate**

Independent extensions can add capability without compromising core project
truth.

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
