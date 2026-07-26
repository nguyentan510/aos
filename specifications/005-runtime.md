# AOS-SPEC-005 — Runtime

**Status:** Accepted
**Authors:** AOS project
**Created:** 2026-07-26
**Updated:** 2026-07-26
**Depends on:** AOS-SPEC-003 — Protocol; AOS-SPEC-004 — CLI
**Supersedes:** None

## Purpose

This specification defines the logical Runtime contract that executes
authorized Protocol Runs through bounded capabilities and adapters. It
separates execution mechanics from Project truth, Governance authority, and
provider-specific behavior.

## Motivation

Protocol defines what Work may do and CLI defines how a user requests it. AOS
still needs an execution boundary that can invoke repository, tool, and
provider capabilities while preserving scope, provenance, cancellation,
unknown-state handling, and auditability.

This specification advances:

- VISION G3 — Protocol-driven work.
- VISION G4 — Human-governed automation.
- VISION G6 — Open and extensible interoperability.

It is constrained by PRINCIPLES P5, P6, P7, P8, P10, P11, and P12.

## Scope

This specification defines:

- Runtime identity and compatibility;
- Protocol Run admission;
- capability and adapter declarations;
- bounded step execution;
- isolation, timeouts, cancellation, and resource limits;
- provider-neutral result handling;
- verification, failure, recovery, and audit;
- lifecycle and health states; and
- conformance cases for future implementations.

## Non-goals

This specification does not define:

- a process supervisor, container technology, queue, or distributed scheduler;
- a specific programming language or plugin ABI;
- AI model selection or prompt construction;
- a physical `.aos/` runtime layout;
- a universal secrets manager;
- Protocol semantics already defined by `AOS-SPEC-003`; or
- Extension discovery and lifecycle defined by `AOS-SPEC-006`.

## Terminology

### Runtime

The AOS execution mechanism that admits and runs authorized Protocol Steps
through declared capabilities.

### Adapter

A bounded implementation that connects a Runtime capability to a repository,
tool, provider, or external system.

### Capability

An explicitly declared operation and resource scope that a Runtime may grant to
an Adapter for one Protocol Step.

### Execution Context

The immutable Run, Work, Protocol, Context Snapshot, authority, and capability
inputs made available to a step.

### Runtime Result

An attributable result containing status, output references, evidence,
resource information, and failure or unknown-state details.

### Runtime Health

The operational ability of a Runtime to accept work: `ready`, `degraded`,
`draining`, or `unavailable`.

## Normative requirements

### Runtime identity and admission

**RT-001.** Every Runtime **MUST** identify its implementation, version,
supported Protocol/CLI contract versions, and current Runtime Health.

**RT-002.** A Runtime **MUST** admit only a Protocol Run bound to an accepted
Protocol version and valid Work, Repository, and Context Snapshot.

**RT-003.** A Runtime **MUST** verify Governance authorization and capability
scope before starting a mutating Step.

**RT-004.** A Runtime **MUST** bind each admitted Run to one immutable execution
context and **MUST NOT** silently replace its Work, Protocol, scope, or policy.

**RT-005.** A Runtime with Health `degraded`, `draining`, or `unavailable`
**MUST** refuse new work that it cannot safely execute and **MUST** report the
reason.

### Capabilities and adapters

**RT-006.** Every Adapter **MUST** declare identity, version, capability set,
resource scope, operation class, supported contract versions, and failure
behavior.

**RT-007.** A Runtime **MUST** grant an Adapter only the capabilities declared
by the Protocol Step, authorization, and Runtime policy intersection.

**RT-008.** An Adapter **MUST NOT** access an undeclared path, Project,
Repository, provider, network target, secret, or operation class.

**RT-009.** Runtime capability names **MUST** be provider-neutral at the Core
contract level. Provider-specific behavior belongs behind an Adapter or
Extension boundary.

**RT-010.** A Runtime **MUST** expose whether a capability is read-only,
idempotent, retryable, compensatable, or reconciliation-required according to
the Protocol contract.

**RT-011.** A Runtime **MUST NOT** use Adapter output to grant authority,
change Protocol scope, or redefine Project truth.

### Execution behavior

**RT-012.** A Runtime **MUST** pass the declared Execution Context to each Step
without silently omitting required inputs or adding undeclared context.

**RT-013.** A Runtime **MUST** execute Steps in the order and parallel groups
declared by the Protocol.

**RT-014.** A Runtime **MUST** report one Runtime Result for every attempted
Step with status, evidence, output references, and resource/error details.

**RT-015.** A Runtime **MUST** stop dependent Steps after a failed, blocked, or
unknown Step unless the Protocol explicitly declares a safe recovery path.

**RT-016.** A Runtime **MUST** run required verification checks before reporting
the effect of a mutating Step as verified.

**RT-017.** A Runtime **MUST NOT** report a completed Protocol Run until the
Protocol completion, verification, and reconciliation requirements pass.

### Time, cancellation, and resources

**RT-018.** Every Step execution **MUST** have a declared timeout or an
explicit policy that permits no finite timeout.

**RT-019.** A timeout **MUST** produce a failed or unknown Runtime Result and
**MUST NOT** be interpreted as proof that the external effect did not occur.

**RT-020.** A Runtime **MUST** accept cancellation and stop starting new Steps
after cancellation is effective.

**RT-021.** Cancellation **MUST** preserve started-Step history and expose
effects requiring reconciliation.

**RT-022.** A Runtime **MUST** enforce declared resource limits for CPU, memory,
storage, process count, network, or equivalent capability dimensions where the
environment supports them.

**RT-023.** Exceeding a resource limit **MUST** produce an attributable failure
or unknown result and **MUST NOT** silently expand the limit.

**RT-024.** Parallel execution **MUST** be disabled unless the Protocol and
capability policy declare independence, resource safety, and deterministic
reconciliation.

### Failure and recovery

**RT-025.** A Runtime **MUST** distinguish adapter failure, timeout,
permission denial, unsupported capability, invalid input, conflict, and unknown
external result.

**RT-026.** A Runtime **MUST NOT** retry a Step unless the Protocol retry policy
and Adapter capability both permit the attempt.

**RT-027.** A non-idempotent Step with an unknown result **MUST** enter
reconciliation before any retry or dependent mutation.

**RT-028.** A Runtime crash or restart **MUST** preserve enough Run identity and
Step history to resume only through Protocol and reconciliation rules.

**RT-029.** A Runtime **MUST** expose Health `degraded` when it cannot guarantee
the declared execution, audit, or recovery semantics.

**RT-030.** A Runtime **MUST NOT** silently resume an uncertain Run after
restart.

### Provenance, audit, and security

**RT-031.** Every Runtime Result **MUST** identify Runtime version, Adapter
version, Step, Run, input revisions, start/end time, and verification status.

**RT-032.** A Runtime **MUST** preserve Protocol, Governance, Repository, and
Information Object provenance in every derived output.

**RT-033.** A Runtime **MUST NOT** store or emit secrets, credentials, or
private keys as ordinary Run output or logs.

**RT-034.** Runtime logs **MUST** distinguish redacted, withheld, failed, and
unknown values while retaining a reason and provenance reference.

**RT-035.** A Runtime **MUST** operate with least privilege and **MUST** fail
closed when scope, authority, contract, or external state is unknown.

**RT-036.** A Runtime **MUST NOT** mutate Project truth, ownership, or
Governance decisions directly; it reports results for validation and
synchronization.

### Compatibility and evolution

**RT-037.** A Runtime **MUST** reject unsupported Protocol, CLI, Repository, or
Adapter contract versions explicitly.

**RT-038.** A Runtime upgrade **MUST** preserve active Run identity, Step
history, provenance, authority, and reconciliation obligations.

**RT-039.** A changed capability effect, scope, failure meaning, or result
interpretation **MUST** use a new Adapter or contract version.

**RT-040.** Runtime and Adapter implementations **MUST** be replaceable without
changing the Information Model or Protocol meaning.

## Interfaces and data flow

| Operation | Input | Result |
| --- | --- | --- |
| Admit | Protocol Run, authority, context, Runtime policy | Accepted, rejected, or unsupported |
| Prepare | Run and declared capabilities | Immutable Execution Context |
| Execute | Context, Step, Adapter | Runtime Result |
| Verify | Result, declared checks, current observation | Verified, failed, or unknown |
| Cancel | Run identity and authority | Cancellation state and recovery obligations |
| Reconcile | Unknown/partial Run and current observations | Actual state and next transition |
| Recover | Persisted Run history and current Runtime Health | Resume, block, fail, or reconcile |
| Report health | Runtime and Adapter state | `ready`, `degraded`, `draining`, or `unavailable` |

The Runtime flow is:

```text
Protocol Run admission
        |
        v
Authority and capability intersection
        |
        v
Execution Context
        |
        v
Bounded Adapter execution
        |
        v
Result and evidence
        |
        +--> verify
        +--> retry under Protocol policy
        `--> reconcile on unknown/partial result
```

## Lifecycle and state transitions

### Runtime Health

```text
unavailable -> ready -> draining -> unavailable
                  |
                  `-> degraded -> ready
```

- `ready`: can admit declared work safely.
- `degraded`: can admit only work whose guarantees remain available.
- `draining`: accepts no new work but may finish or reconcile active Runs.
- `unavailable`: refuses new work.

### Step execution

```text
admitted -> prepared -> running -> verifying -> succeeded
                         |            |
                         +--> failed +--> unknown
                         |            |
                         `--> cancelled

unknown -> reconciling -> succeeded | failed | blocked
```

No Runtime transition can bypass Protocol or Governance requirements.

## Failure behavior

| Condition | Required behavior |
| --- | --- |
| Unsupported contract or capability | Reject admission; report unsupported |
| Missing or mismatched authority | Reject mutating Step |
| Scope expansion request | Reject; preserve original context |
| Timeout | Failed or unknown result; reconcile before retry if needed |
| Adapter permission denial | Failed result with evidence; no broader fallback |
| Unknown external result | Stop dependents and reconcile |
| Resource exhaustion | Failed or unknown result; do not expand limits |
| Runtime restart | Recover history; do not silently resume |
| Secret in output | Redact or withhold; preserve reason/provenance |
| Health unavailable | Refuse new work and report health |

## Security and governance

- Runtime executes authority; it does not create authority.
- Adapter scope is the intersection of Protocol, Governance, Runtime policy, and
  declared capability.
- Unknown state stops dependent mutation by default.
- Runtime and Adapter logs are audit evidence, not a secret store.
- Runtime cannot escape Repository boundaries from `AOS-SPEC-002`.
- Provider-specific output is proposed evidence until Protocol verification and
  Information Model synchronization promote it.

## Compatibility and migration

1. Runtime, Adapter, CLI, Repository, and Protocol contract versions are
   explicit at admission.
2. Unsupported versions are rejected without guessed behavior.
3. Runtime upgrades preserve Run identity, history, provenance, authority, and
   reconciliation obligations.
4. Changed capability effects or result meanings require a new version.
5. Active Runs may be drained or reconciled during upgrade; they must not be
   silently reinterpreted.

## Conformance tests

| Case | Requirement coverage | Expected result |
| --- | --- | --- |
| RT-C001 Runtime admission and identity | RT-001–RT-005 | Valid Run admitted; unsupported/unsafe health rejected |
| RT-C002 capability declaration and scope | RT-006–RT-011 | Only authorized declared capabilities are available |
| RT-C003 Execution Context and ordering | RT-012–RT-017 | Steps follow Protocol; dependent work stops safely |
| RT-C004 timeout, cancellation, and resources | RT-018–RT-024 | Limits and cancellation produce attributable outcomes |
| RT-C005 failure and recovery | RT-025–RT-030 | Unknown/partial states reconcile; no silent resume |
| RT-C006 provenance, audit, and security | RT-031–RT-036 | Results are attributable; secrets and authority bypass blocked |
| RT-C007 compatibility and replacement | RT-037–RT-040 | Unsupported versions reject; implementation can be replaced |
| RT-C008 unknown non-idempotent effect | RT-019, RT-026–RT-028 | Reconciliation precedes retry or dependent mutation |
| RT-C009 degraded Runtime health | RT-005, RT-029 | New unsafe work is refused while safe work may be constrained |
| RT-C010 Adapter output promotion | RT-031–RT-036 | Provider result remains proposed until verification |

## Unresolved questions

## Change history

| Date | Status | Change |
| --- | --- | --- |
| 2026-07-26 | Accepted | Initial Runtime contract |
