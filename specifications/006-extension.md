# AOS-SPEC-006 — Extension

**Status:** Accepted
**Authors:** AOS project
**Created:** 2026-07-26
**Updated:** 2026-07-26
**Depends on:** AOS-SPEC-001 — Information Model; AOS-SPEC-003 — Protocol;
AOS-SPEC-005 — Runtime
**Supersedes:** None

## Purpose

This specification defines the logical contract for extending AOS with
optional language, framework, domain, provider, tool, or integration
capabilities without redefining Core semantics or bypassing Governance.

## Motivation

AOS must support different project types and execution providers without
turning every capability into Core or coupling the product to one ecosystem.
Extensions need explicit identity, capabilities, compatibility, ownership,
isolation, lifecycle, and failure behavior.

This specification advances:

- VISION G6 — Open and extensible interoperability.
- VISION G1 — Repository-native project intelligence.
- VISION G4 — Human-governed automation.

It is constrained by PRINCIPLES P5, P6, P7, P8, P10, P11, and P12.

## Scope

This specification defines:

- Extension identity, manifest, type, and version;
- capability declaration and permission intersection;
- namespacing, data ownership, and provenance;
- dependency and compatibility handling;
- discovery, validation, enable, disable, quarantine, and removal;
- Runtime and Protocol integration boundaries;
- security, isolation, secrets, and failure behavior; and
- conformance cases for future extension implementations.

## Non-goals

This specification does not define:

- a marketplace, registry business model, or payment system;
- package-manager syntax or distribution channels;
- a specific plugin ABI, process model, or language;
- a physical `.aos/` extension layout;
- unrestricted dynamic code loading;
- authority delegation outside Governance; or
- extension-specific domain semantics.

## Terminology

### Extension

An optional, versioned capability bundle that integrates with AOS through
published contracts.

### Extension Manifest

The declared identity, version, type, dependencies, capabilities, compatibility,
ownership, and lifecycle information for an Extension.

### Extension Type

One of `domain`, `language`, `framework`, `provider`, `tool`, or `integration`.

### Extension Capability

A named, bounded operation that an Extension may offer or request through
Protocol, Runtime, or Information Model contracts.

### Extension Namespace

A unique naming scope for extension-owned concepts, schemas, outputs, and
configuration that prevents collisions with Core.

### Quarantine

The state in which an Extension is prevented from execution while its
compatibility, security, integrity, or failure condition is investigated.

## Normative requirements

### Identity and manifest

**EX-001.** Every Extension **MUST** declare a stable identity, version, type,
owner, compatibility range, and manifest contract version.

**EX-002.** An Extension **MUST** declare its dependencies, capabilities,
resource scopes, data ownership, security requirements, and failure behavior.

**EX-003.** An Extension **MUST** declare a unique namespace that does not
collide with AOS Core or another enabled Extension.

**EX-004.** An Extension **MUST** identify its producer/version in all derived
Information Objects, Protocol outputs, Runtime Results, and audit records.

**EX-005.** An Extension manifest **MUST** be inspectable before the Extension
is enabled or executed.

### Core and capability boundaries

**EX-006.** An Extension **MUST NOT** redefine Project, Knowledge, State, Work,
Protocol, or Governance semantics.

**EX-007.** An Extension **MUST** use published AOS contracts for interaction
with Information Model, Repository, Protocol, CLI, or Runtime.

**EX-008.** An Extension **MUST NOT** bypass Governance, Repository ownership,
Protocol validation, Runtime capability checks, or reconciliation.

**EX-009.** An Extension capability **MUST** be granted only when the
intersection of Extension declaration, Protocol Step, Governance authority,
Runtime policy, and Repository scope permits it.

**EX-010.** An Extension **MUST NOT** silently expand its resource scope,
network target, Repository Root, Project identity, or authority.

**EX-011.** An Extension **MUST** distinguish read-only, proposed, and
mutating capabilities and declare whether each is idempotent, retryable,
compensatable, or reconciliation-required.

### Data, namespace, and provenance

**EX-012.** Extension-owned data **MUST** use the Extension namespace and
**MUST** declare its owning Project, lifecycle, contract version, and retention
behavior.

**EX-013.** Extension data **MUST NOT** overwrite or impersonate Core
Information Objects. A mapping into Core **MUST** pass the target contract's
validation and authority rules.

**EX-014.** Derived Extension output **MUST** reference input revisions,
Extension version, producing capability, and verification evidence.

**EX-015.** An Extension result **MUST** remain proposed evidence until the
target Protocol, Governance, and Information Model rules promote it.

**EX-016.** Disabling or removing an Extension **MUST NOT** corrupt Core
Project truth, prior revisions, audit, or unresolved conditions.

### Dependencies and compatibility

**EX-017.** Extension dependencies **MUST** identify required Extension
identities, contract versions, and compatibility ranges.

**EX-018.** Dependency graphs **MUST** be acyclic. Missing, conflicting, or
unsupported dependencies **MUST** prevent enablement.

**EX-019.** An Extension **MUST** declare compatibility with the AOS Core,
Information Model, Repository, Protocol, CLI, Runtime, and relevant Extension
contracts it uses.

**EX-020.** A changed capability effect, schema meaning, permission, or
compatibility guarantee **MUST** use a new Extension version.

**EX-021.** An incompatible Extension **MUST** be reported as incompatible and
**MUST NOT** execute or mutate managed project state.

**EX-022.** Extension upgrade **MUST** provide migration, rejection, or
rollback behavior that preserves identity, provenance, authority, and audit.

### Lifecycle and operations

**EX-023.** An Extension **MUST** expose one lifecycle state:
`discovered`, `validated`, `enabled`, `disabled`, `incompatible`, or
`quarantined`.

**EX-024.** Discovery and validation **MUST** be read-only and **MUST NOT**
execute Extension capabilities.

**EX-025.** Enablement **MUST** validate manifest, dependencies, contracts,
capabilities, integrity, and Governance policy before execution.

**EX-026.** A disabled, incompatible, or quarantined Extension **MUST** reject
new capability execution.

**EX-027.** An Extension failure **MUST** identify Extension, version,
capability, Run/Work, error category, affected resources, and recovery state.

**EX-028.** An Extension that produces unknown or partial external effects
**MUST** enter quarantine or reconciliation according to its declared policy
and **MUST NOT** be retried blindly.

**EX-029.** Extension removal **MUST** be explicit, reviewable, and limited to
Extension-owned artifacts. User and Core artifacts remain protected.

### Security and isolation

**EX-030.** An Extension **MUST** operate with least privilege and declared
resource boundaries.

**EX-031.** An Extension **MUST NOT** read or emit secrets, credentials, or
private keys as ordinary output or logs.

**EX-032.** An Extension **MUST** report redacted, withheld, failed, and
unknown outputs with provenance and reason.

**EX-033.** An Extension **MUST NOT** execute arbitrary undeclared code,
commands, network targets, or filesystem paths through an AOS capability.

**EX-034.** Extension isolation failure **MUST** fail closed, preserve audit,
and prevent affected capabilities from continuing.

**EX-035.** Extension authors and providers **MUST NOT** be treated as Project
authorities by default.

### Compatibility and evolution

**EX-036.** An implementation that cannot interpret an Extension manifest or
contract version **MUST** report unsupported status and refuse enablement.

**EX-037.** Extension upgrades **MUST** preserve active Run history,
Information Object revision ancestry, provenance, authority, and reconciliation
obligations.

**EX-038.** Extension-specific semantics **MUST** remain replaceable without
changing AOS Core or Protocol meaning.

## Interfaces and data flow

| Operation | Input | Result |
| --- | --- | --- |
| Discover | Candidate identity and source | Manifest or discovery error |
| Inspect | Manifest and environment | Identity, type, dependencies, capabilities, compatibility |
| Validate | Manifest, contracts, dependencies, policy | Valid, incompatible, conflict, or unsupported |
| Enable | Valid Extension and Governance policy | Enabled lifecycle state or rejection |
| Invoke | Protocol Step, capability, Runtime context | Bounded result and provenance |
| Disable | Extension identity and authority | Disabled state; active effects reconciled |
| Quarantine | Failure, integrity, or security evidence | Quarantined state and recovery plan |
| Migrate | New Extension version and migration plan | Compatible state or explicit rejection |
| Remove | Extension identity, ownership plan, authority | Owned artifacts retired; Core/user data preserved |

The extension flow is:

```text
discover -> inspect -> validate -> authorize -> enable
                                      |
                                      v
                              Protocol/Runtime invoke
                                      |
                                      v
                         verify -> promote or quarantine
```

## Lifecycle and state transitions

```text
discovered -> validated -> enabled -> disabled
    |             |          |
    |             |          +--> incompatible
    |             +-------------> incompatible
    +---------------------------> quarantined

enabled -> quarantined -> validated | disabled
```

- `discovered`: manifest located but not trusted or validated.
- `validated`: manifest, dependencies, contracts, and policy pass.
- `enabled`: capabilities may be considered for authorized Protocol use.
- `disabled`: no new capability execution is accepted.
- `incompatible`: contract or dependency mismatch prevents enablement.
- `quarantined`: failure, integrity, or security evidence blocks execution.

## Failure behavior

| Condition | Required behavior |
| --- | --- |
| Missing or invalid manifest | Reject validation; do not execute |
| Namespace collision | Reject enablement |
| Missing/conflicting dependency | Mark incompatible |
| Unsupported contract | Refuse enablement and report version |
| Undeclared capability request | Reject and audit |
| Governance denial | Do not enable or invoke |
| Secret in output | Redact or withhold; preserve reason |
| Unknown/partial external effect | Quarantine or reconcile; no blind retry |
| Isolation breach | Fail closed and quarantine affected capability |
| Removal of shared/Core artifact | Reject removal plan |
| Upgrade cannot preserve history | Reject or roll back |

## Security and governance

- Extension capability is an offer, not authority.
- Governance authorizes use per Project, Work, Protocol, Run, and resource scope.
- Runtime enforces the capability intersection.
- Extension namespaces prevent semantic collision with Core.
- Extension outputs are evidence until target contracts promote them.
- Disable, quarantine, and removal are safe states, not implicit data deletion.

## Compatibility and migration

1. Extension identity, manifest, capability, and contract versions are explicit.
2. Unsupported or incompatible versions cannot be enabled.
3. Upgrades preserve Core and Extension provenance, audit, and active Run
   obligations.
4. Changed permissions or effects require a new Extension version.
5. Extension removal retires Extension-owned data and never silently removes
   user or Core data.

## Conformance tests

| Case | Requirement coverage | Expected result |
| --- | --- | --- |
| EX-C001 manifest identity and namespace | EX-001–EX-005 | Manifest is inspectable and attributable |
| EX-C002 Core and capability boundaries | EX-006–EX-011 | Extension cannot redefine Core or expand scope |
| EX-C003 data ownership and provenance | EX-012–EX-016 | Namespaced outputs preserve revisions and disable safely |
| EX-C004 dependencies and compatibility | EX-017–EX-022 | Missing/incompatible dependencies block enablement |
| EX-C005 lifecycle and operations | EX-023–EX-029 | Discovery is read-only; failures quarantine/reconcile |
| EX-C006 security and isolation | EX-030–EX-035 | Secrets, undeclared access, and authority bypass are blocked |
| EX-C007 evolution and replacement | EX-036–EX-038 | Unsupported versions reject; history remains preserved |
| EX-C008 namespace collision | EX-003, EX-012–EX-013 | Enablement rejected without Core overwrite |
| EX-C009 partial provider effect | EX-027–EX-028, EX-034 | Capability quarantined and reconciled |
| EX-C010 explicit removal | EX-016, EX-029, EX-037 | Only Extension-owned data is retired |

## Unresolved questions

## Change history

| Date | Status | Change |
| --- | --- | --- |
| 2026-07-26 | Accepted | Initial Extension contract |
