# AOS-SPEC-003 — Protocol

**Status:** Accepted
**Authors:** AOS project
**Created:** 2026-07-26
**Updated:** 2026-07-26
**Depends on:** AOS-SPEC-001 — Information Model; AOS-SPEC-002 — Repository
**Supersedes:** None

## Purpose

This specification defines the logical contract for an AOS Protocol: a
versioned, inspectable, governed set of rules that validates and coordinates
Work. It defines execution semantics without selecting a CLI, Runtime adapter,
AI provider, transport, or programming language.

## Motivation

The AOS Reference Model requires Protocol over Prompt and places Governance
between intent and consequential execution. Information Model and Repository
contracts now define the objects and safe repository boundary, but a system
still needs explicit rules for validation, authorization, execution, retry,
unknown state, partial completion, and reconciliation.

This specification advances:

- VISION G3 — Protocol-driven work.
- VISION G4 — Human-governed automation.
- VISION G5 — Progressive context.
- VISION G6 — Open and extensible interoperability.

It is constrained by PRINCIPLES P2, P3, P5, P6, P7, P8, P9, P10, P11, and P12.

## Scope

This specification defines:

- Protocol identity, version, structure, and immutable acceptance;
- Work binding and context snapshots;
- input, precondition, capability, and output validation;
- read-only and mutating execution modes;
- Governance authorization and capability scope;
- step execution, verification, retry, and cancellation;
- failure, partial, unknown, blocked, and reconciliation behavior;
- provenance, audit, security, and compatibility; and
- conformance cases for future CLI, Runtime, and Extension contracts.

## Non-goals

This specification does not define:

- CLI commands, flags, output, or process lifecycle;
- a Runtime adapter or provider API;
- prompt templates or model selection;
- physical storage or wire serialization;
- repository-specific mutation details beyond `AOS-SPEC-002`;
- scheduling, distributed orchestration, or queue infrastructure;
- a universal policy language; or
- business strategy or domain-specific Work semantics.

## Terminology

### Protocol

A versioned contract that defines how a class of Work is validated, authorized,
executed, verified, and reconciled.

### Protocol Step

An ordered unit of Protocol work with declared inputs, preconditions,
capabilities, effects, verification, and failure behavior.

### Protocol Run

An operational record of one attempt to apply one immutable Protocol version to
one Work revision and context snapshot. It is not a new core domain concept.

### Context Snapshot

The exact Project, Knowledge, State, Repository, and policy revisions selected
for a Protocol Run.

### Capability

A bounded authority to inspect or affect a declared resource. Capability is
scoped, attributable, and not implied by a Protocol name.

### Reconciliation

The governed process of determining actual state after failure, timeout,
partial completion, or an unknown external result.

### Required check

A validation or verification condition that must pass before a Work or Protocol
Run can advance to its declared terminal success state.

## Normative requirements

### Protocol identity and structure

**PR-001.** Every Protocol **MUST** have a stable identity, immutable version,
purpose, owner, and lifecycle status.

**PR-002.** An accepted Protocol version **MUST** declare its required inputs,
expected outputs, ordered steps, required checks, governance points, execution
mode, and failure behavior.

**PR-003.** Every Protocol Step **MUST** declare its inputs, preconditions,
required capabilities, expected effects, verification checks, and failure
behavior.

**PR-004.** Normative Protocol behavior **MUST NOT** depend on an undisclosed
prompt, model memory, provider convention, or chat history.

**PR-005.** A Protocol Step graph **MUST** be ordered and acyclic by default.
Parallel execution **MAY** be declared only when the Protocol proves resource
independence, ordering safety, and deterministic reconciliation.

### Work binding and context

**PR-006.** Work that is authorized or beyond the proposed stage **MUST**
reference an accepted Protocol identity and immutable version.

**PR-007.** A Protocol Run **MUST** bind one Work revision, one Protocol
version, one Repository/Project scope, and one Context Snapshot.

**PR-008.** The Context Snapshot **MUST** identify the Information Object
revisions, Repository Snapshot, policy versions, and external evidence used for
validation or execution.

**PR-009.** A Protocol **MUST NOT** silently widen its Work scope, Repository
Root, Project identity, or capability set during execution.

### Validation and preconditions

**PR-010.** A Protocol Run **MUST** validate all required inputs, object
references, contract versions, permissions, and preconditions before the first
step executes.

**PR-011.** A failed, unresolved, stale, or unsupported precondition **MUST**
block execution and produce an explicit validation result.

**PR-012.** Validation **MUST** distinguish invalid input, unresolved evidence,
conflict, stale state, unsupported version, unauthorized capability, and
unknown external state.

**PR-013.** Validation for the same Protocol version, Work revision, Context
Snapshot, policy, and declared environment **MUST** be deterministic.

### Governance and authorization

**PR-014.** A mutating Protocol Run **MUST** receive explicit Governance
authorization before its first mutating step.

**PR-015.** Authorization **MUST** identify the approving Principal, scope,
allowed capabilities, Protocol version, Work revision, expiry or validity
condition, and required checks.

**PR-016.** A read-only Protocol Run MAY use a policy path that does not require
mutation approval, but it **MUST** still pass input, scope, and capability
validation.

**PR-017.** A Protocol, Runtime, provider, or extension **MUST NOT** grant
itself authority or convert a proposal into an approval.

**PR-018.** An expired, revoked, scope-mismatched, or superseded authorization
**MUST** block the affected step and require a new decision or reconciliation.

### Execution and verification

**PR-019.** Every Protocol Run **MUST** have an immutable run identity,
start time, executor Principal, Protocol version, Work revision, and result
history.

**PR-020.** A step **MUST** report one result from `succeeded`, `failed`,
`blocked`, `unknown`, `skipped`, or `cancelled` and **MUST** include evidence
or an explicit reason.

**PR-021.** A mutating step **MUST** verify its declared effect or produce an
unknown result before a dependent mutating step can begin.

**PR-022.** A Protocol Run **MUST NOT** report successful completion until all
required steps and required final checks pass and repository/external state is
reconciled.

**PR-023.** A Protocol **MUST** declare whether each step is read-only,
idempotent, retryable, compensatable, or requires reconciliation after an
unknown result.

**PR-024.** Steps execute sequentially unless the Protocol explicitly declares
a safe parallel group. A failed or unknown step **MUST** stop dependent steps.

**PR-025.** Cancellation **MUST** stop new steps, preserve run history, and
report which already-started effects require reconciliation.

### Retry, failure, and reconciliation

**PR-026.** A retry **MUST** be permitted by the step's declared retry policy,
bounded by a maximum attempt count, and recorded in the run history.

**PR-027.** A non-idempotent step **MUST NOT** be retried after an unknown
result until reconciliation establishes whether the effect occurred.

**PR-028.** A failed or blocked Work **MUST** expose the reason, failed step,
evidence, unresolved condition, and next allowed recovery action.

**PR-029.** A partial or unknown Run **MUST** map Work to `blocked` or another
explicit non-success state until reconciliation completes.

**PR-030.** Reconciliation **MUST** be idempotent, attributable, and based on
current observations rather than assumptions about an attempted effect.

**PR-031.** A Protocol **MUST** declare compensation or rollback behavior where
it exists. AOS **MUST NOT** assume that rollback is possible.

**PR-032.** A reconciliation result **MUST** preserve prior evidence and record
the actual observed state, authority, timestamp, and resulting Work transition.

### Context, outputs, and provenance

**PR-033.** A Protocol Run **MUST** use only the declared Context Snapshot or
explicitly record and validate any newly required context before use.

**PR-034.** Provider or Runtime output **MUST** remain proposed evidence until
the Protocol's required validation and Governance rules promote it.

**PR-035.** Every derived output **MUST** reference input revisions, producing
step, executor version, and verification evidence.

**PR-036.** A Protocol Run **MUST** distinguish output that was produced,
verified, rejected, withheld, or unknown.

### Audit and security

**PR-037.** A Run history **MUST** record the Work, Protocol version, Context
Snapshot, authorizations, step order, capabilities, attempts, outputs,
verification, failures, retries, cancellations, and reconciliation.

**PR-038.** Run history **MUST NOT** store secrets or credentials as ordinary
output. Sensitive values **MUST** be withheld or redacted while preserving
provenance and reason.

**PR-039.** Each capability **MUST** declare its resource scope, operation
class, owner, and authority basis. A capability **MUST NOT** silently expand.

**PR-040.** A Protocol Run **MUST** fail closed when authority, scope, input,
precondition, external result, or reconciliation status is unknown.

### Compatibility and evolution

**PR-041.** An accepted Protocol version **MUST** be immutable. Any behavior
change **MUST** use a new version and declare compatibility and migration.

**PR-042.** A consumer that does not support a Protocol version **MUST** report
unsupported status and **MUST NOT** guess its steps, effects, or authority.

**PR-043.** A Protocol migration **MUST** preserve Work identity, prior Run
history, provenance, authority decisions, and unresolved conditions.

**PR-044.** A deprecated Protocol **MUST** remain inspectable and **MUST NOT**
be selected for new Work unless an explicit compatibility policy allows it.

## Interfaces and data flow

The logical operations below are the minimum behaviors later CLI, Runtime, and
Extension specifications must expose without requiring these names as literal
commands or API methods:

| Operation | Input | Result |
| --- | --- | --- |
| Define | Protocol draft and owner | Versioned Draft or validation failure |
| Accept | Protocol candidate and Governance decision | Immutable Accepted version |
| Bind | Work revision, Protocol version, scope, and context | Protocol Run proposal |
| Validate | Run proposal, inputs, preconditions, policy | Valid, invalid, unresolved, or conflict result |
| Authorize | Valid mutating proposal and Governance authority | Approved or rejected authorization |
| Start | Valid proposal and authorization | Running Protocol Run |
| Execute step | Run, step, capability, inputs | Step result with evidence |
| Verify | Declared effect and checks | Verified, failed, or unknown result |
| Retry | Retryable failed step and policy | New bounded attempt or refusal |
| Reconcile | Unknown/partial result and current observation | Reconciled state and Work transition |
| Complete | All required results and checks | Completed Run and verified Work |
| Cancel | Active Run and authority | Cancelled Run with recovery obligations |

The canonical flow is:

```text
Work + accepted Protocol
          |
          v
Context Snapshot
          |
          v
Input and precondition validation
          |
          v
Governance authorization
          |
          v
Protocol Run
          |
          v
Step execution and verification
          |
          +--> retryable failure -> bounded retry
          |
          +--> unknown/partial -> reconciliation
          |
          v
Final checks and state synchronization
          |
          v
Completed, failed, blocked, or cancelled Work
```

## Lifecycle and state transitions

### Protocol lifecycle

```text
Draft -> Accepted -> Deprecated -> Superseded
  |
  `-------> Rejected
```

Only Accepted Protocol versions can govern authorized Work. Acceptance freezes
the version's normative behavior.

### Protocol Run lifecycle

```text
proposed -> validated -> authorized -> running -> verifying -> completed
    |           |            |           |           |
    |           |            |           +--> failed  +--> failed
    |           |            +--------------> blocked
    |           +---------------------------> rejected
    +---------------------------------------> cancelled

blocked/unknown -> reconciling -> running | completed | failed | cancelled
```

- `proposed`: Work and Protocol are bound but not validated.
- `validated`: required inputs and preconditions pass.
- `authorized`: Governance permits the declared mutating scope.
- `running`: declared steps may execute.
- `verifying`: effects and required checks are being evaluated.
- `completed`: all required checks and reconciliation pass.
- `failed`: a terminal declared failure occurred.
- `blocked`: progress requires an external decision, condition, or recovery.
- `unknown`: an operation outcome cannot yet be established.
- `reconciling`: current state is being established after uncertainty or
  partial completion.
- `cancelled`: no new steps may start; recovery obligations remain explicit.

## Failure behavior

| Condition | Required behavior |
| --- | --- |
| Missing or invalid input | Reject before execution; identify the requirement |
| Stale or unresolved context | Block validation; require a new snapshot |
| Unsupported Protocol version | Refuse binding or execution; do not guess |
| Missing mutation authorization | Reject or remain proposed; do not mutate |
| Expired or scope-mismatched authority | Block affected step; require decision |
| Failed precondition | Do not start the step; report reason and evidence |
| Failed idempotent step | Retry only under declared bounded policy |
| Unknown non-idempotent result | Stop dependents; reconcile before retry |
| Failed required verification | Mark failed or blocked; do not complete |
| Partial external effect | Preserve history; enter blocked/unknown and reconcile |
| Sensitive output | Redact or withhold; preserve provenance and reason |
| Protocol version changed | Start only under a new accepted version |
| Cancellation during effect | Stop new work; report reconciliation obligations |

## Security and governance

- Governance authorizes scope and capabilities; Protocol coordinates them.
- A Runtime executes declared capability, but cannot expand it.
- AI and tool providers are producers, not authorities by default.
- Mutating Work requires explicit approval before its first mutating step.
- Unknown external state stops dependent mutation by default.
- Run history is an audit record, not a secret store.
- Protocols must preserve user and Project ownership rules from
  `AOS-SPEC-002`.

## Compatibility and migration

1. An accepted Protocol version is immutable and independently addressable.
2. A consumer that cannot interpret a version reports unsupported status.
3. A compatible migration preserves Work, Run, context, authority, provenance,
   and unresolved-state history.
4. A changed step effect, precondition, capability, check, retry policy, or
   failure meaning requires a new Protocol version.
5. Existing Runs remain bound to their original version even after deprecation.
6. Physical serialization and transport compatibility are deferred to later
   Repository, CLI, Runtime, and Extension specifications.

## Conformance tests

| Case | Requirement coverage | Expected result |
| --- | --- | --- |
| PR-C001 accepted immutable Protocol structure | PR-001–PR-005 | Accepted version is complete, ordered, and provider-neutral |
| PR-C002 Work binding and Context Snapshot | PR-006–PR-009 | Run is bound to one Work, scope, version, and snapshot |
| PR-C003 validation and deterministic preconditions | PR-010–PR-013 | Invalid, unresolved, stale, and unsupported inputs are blocked |
| PR-C004 authorization boundaries | PR-014–PR-018 | Mutations require scoped, valid Governance authority |
| PR-C005 step results and completion checks | PR-019–PR-025 | Run history is complete; no premature success |
| PR-C006 retries and unknown effects | PR-026–PR-032 | Bounded retries; non-idempotent unknown results reconcile first |
| PR-C007 context and provenance | PR-033–PR-036 | Outputs remain attributable proposed evidence until verified |
| PR-C008 audit and capability isolation | PR-037–PR-040 | Audit is complete; secrets and scope expansion are blocked |
| PR-C009 version evolution | PR-041–PR-044 | Changed behavior uses new version; prior Runs remain inspectable |
| PR-C010 cancelled active Run | Lifecycle and failure table | New steps stop; recovery obligations remain explicit |
| PR-C011 failed required verification | PR-021–PR-022 | Run cannot complete and Work is failed or blocked |
| PR-C012 reconciliation after partial mutation | PR-029–PR-032 | Actual state is observed before any resume or retry |

## Unresolved questions

## Change history

| Date | Status | Change |
| --- | --- | --- |
| 2026-07-26 | Accepted | Initial Protocol contract |
