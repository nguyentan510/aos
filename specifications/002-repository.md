# AOS-SPEC-002 — Repository

**Status:** Accepted
**Authors:** AOS project
**Created:** 2026-07-26
**Updated:** 2026-07-26
**Depends on:** AOS-SPEC-001 — Information Model
**Supersedes:** None

## Purpose

This specification defines how AOS identifies, inspects, adopts, and safely
operates on a managed project repository. It establishes the boundary between
user-owned project content and AOS-owned project intelligence and binds the
minimal P3 control-root serialization required for transactional adoption.

## Motivation

AOS is an independent product that may manage control data in another
repository. That boundary is unsafe unless repository identity, root discovery,
ownership, initialization, compatibility, and failure behavior are explicit.

This specification advances:

- VISION G1 — Repository-native project intelligence.
- VISION G2 — Explicit and attributable truth.
- VISION G4 — Human-governed automation.
- VISION G6 — Open and extensible interoperability.

It is constrained by PRINCIPLES P1, P2, P5, P6, P7, P8, P10, P11, and P12 and
depends on the Information Object semantics in `AOS-SPEC-001`.

## Scope

This specification defines:

- the logical Managed Repository boundary and identity;
- explicit and automatic root discovery behavior;
- ownership classes for user, AOS, and shared content;
- the reserved `.aos/` control namespace;
- inspection, adoption planning, and initialization lifecycle;
- idempotency, snapshot conflict detection, and recovery;
- compatibility, migration, and unsupported-state behavior;
- path, link, permission, and sensitive-data safety; and
- conformance cases for future CLI, Runtime, and Repository implementations.

## Non-goals

This specification does not define:

- CLI command names, flags, exit codes, or output formatting;
- AOS data formats beyond the minimal P3 repository manifest;
- JSON, YAML, TOML, SQL, graph, or binary serialization outside that manifest;
- a required version-control system or hosting provider;
- Protocol execution, Work transitions, or retry policy;
- AI provider, Runtime, or Extension interfaces;
- repository indexing, embeddings, search ranking, or context selection; or
- changes to application business logic.

## Terminology

### Managed Repository

A repository boundary that AOS can inspect and, after governed adoption, manage
through AOS-owned project intelligence. A Managed Repository contains exactly
one AOS Project scope.

### Repository Root

The canonical directory that bounds a Managed Repository. AOS operations do not
read or write outside this root unless a later specification explicitly grants
an external capability.

### AOS Control Root

The reserved `.aos/` directory at the Repository Root. It is the namespace for
AOS-owned project intelligence after adoption.

### Ownership class

The protection classification of a path or logical repository artifact:
`user`, `aos`, or `shared`.

### Adoption

The governed transition from an unmanaged repository to an AOS-initialized
Managed Repository.

### Adoption Plan

An immutable, reviewable description of proposed repository changes, including
ownership, paths, preconditions, compatibility, and recovery behavior.

### Snapshot

The observed repository identity, relevant path metadata, and control state
used to ensure that an Adoption Plan is still based on current inputs.

### Repository Status

The lifecycle condition of the repository from AOS's perspective:
`unmanaged`, `candidate`, `initialized`, `incompatible`, or `degraded`.

## Normative requirements

### Repository identity and scope

**RM-001.** Every AOS repository operation **MUST** have an explicit Repository
Root, either supplied by the caller or resolved by the discovery rules in this
specification.

**RM-002.** The Repository Root **MUST** be canonicalized before it is used for
path comparison, ownership, or mutation. A path string alone **MUST NOT** be
treated as a stable Repository identity.

**RM-003.** A Managed Repository **MUST** identify a stable Repository identity
and link it to exactly one Project identity from `AOS-SPEC-001`. Moving the
directory **MUST NOT** create a new identity by itself.

**RM-004.** A Repository Root **MUST** bound all default AOS reads, writes,
deletes, and link resolution. Operations that need external resources **MUST**
declare that capability and its authority separately.

**RM-005.** Inspection of a Repository **MUST** be read-only. Inspection
**MUST NOT** create, delete, rename, rewrite, or normalize project content.

### Ownership and protection

**RM-006.** Every path or logical repository artifact considered by an AOS
operation **MUST** have an ownership class: `user`, `aos`, or `shared`.

**RM-007.** Existing application source, tests, documentation, configuration,
and other project content **MUST** default to `user` ownership unless an
explicit project policy says otherwise.

**RM-008.** The `.aos/` directory at the Repository Root **MUST** be reserved
for AOS control data after adoption. AOS **MUST NOT** treat an arbitrary
`.aos/` directory outside the selected root as part of the Project.

**RM-009.** AOS **MUST NOT** overwrite, delete, rename, or reclassify
user-owned content during adoption or upgrade without explicit authority and a
reviewable plan.

**RM-010.** Shared content **MUST** be listed explicitly in an Adoption Plan
with its current owner, proposed change, authority, and recovery behavior.

**RM-011.** Every inspection and Adoption Plan **MUST** expose the ownership
classification and protection decision for each affected path or logical
artifact.

### Root discovery and safety

**RM-012.** When an explicit Repository Root is supplied, it **MUST** exist,
resolve to a directory, and be used as the sole root of the operation.

**RM-013.** When no root is supplied, discovery **MAY** start from the caller's
current directory and search ancestors for an existing `.aos/` control root.
If nested or conflicting control roots make the scope ambiguous, discovery
**MUST** return `ambiguous` and require an explicit root.

**RM-014.** If no existing control root is found, discovery **MUST** report an
unmanaged candidate rather than silently selecting an ancestor or mutating the
current directory.

**RM-015.** AOS **MUST NOT** follow a symbolic link, junction, mount, or
platform-equivalent reparse path outside the Repository Root by default. An
explicit external capability and authority are required for such access.

**RM-016.** A path that cannot be canonicalized, read, or permission-checked
**MUST** produce an explicit error or unknown result. AOS **MUST NOT** guess
ownership or continue with a partial boundary.

**RM-017.** Root discovery and inspection **MUST** be deterministic for the
same root, inputs, and repository snapshot. Environment-dependent heuristics
**MUST NOT** silently change the selected scope.

### Repository lifecycle and adoption

**RM-018.** A Repository **MUST** expose one Repository Status from `unmanaged`,
`candidate`, `initialized`, `incompatible`, or `degraded`.

**RM-019.** An unmanaged repository **MUST** be inspectable without creating
`.aos/` or changing user-owned content.

**RM-020.** An Adoption Plan **MUST** include the selected root, repository and
Project identities, AOS contract version, affected paths, ownership classes,
preconditions, authority requirement, and recovery behavior.

**RM-021.** An Adoption Plan **MUST** be deterministic for the same Repository
Snapshot and policy inputs.

**RM-022.** Applying an Adoption Plan **MUST** require explicit authority. Plan
creation and plan application **MUST** remain distinguishable operations.

**RM-023.** A successful adoption **MUST** create or verify the AOS Control
Root, establish the Repository-to-Project link, record the accepted contract
version, and report `initialized`.

**RM-024.** Repeating an already successful adoption with the same compatible
inputs **MUST** be idempotent and produce no destructive change.

**RM-025.** An adoption operation **MUST NOT** change application business
logic, user-owned source, or user-owned documentation as an implicit side
effect.

### Snapshot, concurrency, and recovery

**RM-026.** Every apply operation **MUST** validate that the Repository Snapshot
used to create its Adoption Plan still matches the relevant current inputs.

**RM-027.** If relevant content, ownership, permissions, control state, or
contract version changed after planning, AOS **MUST** reject the stale plan and
require a new inspection or plan.

**RM-028.** An interrupted or partially failed adoption **MUST** preserve
user-owned content and the last known valid AOS control state.

**RM-029.** A partial operation **MUST** report whether the result is
`initialized`, `degraded`, or `unknown` and **MUST NOT** report success merely
because some writes completed.

**RM-030.** Recovery **MUST** be explicit and auditable. AOS **MUST NOT** retry
or repair an uncertain repository state by guessing which writes succeeded.

**RM-031.** Every applied Adoption Plan **MUST** have an operation identity,
timestamp, authority reference, affected paths, result, and reconciliation
evidence.

### Control root and compatibility

**RM-032.** The AOS Control Root **MUST** be a directory within the Repository
Root. A file, link, junction, or path that resolves outside the root **MUST** be
rejected as an invalid control root.

**RM-033.** All AOS-owned control artifacts **MUST** remain within the AOS
Control Root unless a later accepted specification explicitly declares a shared
or external artifact.

**RM-034.** Unknown files or artifacts inside the AOS Control Root **MUST** be
reported and protected from deletion or overwrite by default.

**RM-035.** An initialized repository **MUST** contain a logical Repository
record that identifies the Project, Repository identity, contract version,
ownership policy, and initialization revision. P3 serializes this record as
`.aos/repository.json` with schema version `1`.

**RM-036.** A repository **MUST** expose compatibility status as `supported`,
`needs_migration`, or `unsupported` for its AOS contract version.

**RM-037.** An `unsupported` repository **MUST** remain inspectable where
possible but **MUST NOT** be mutated by a normal adoption, upgrade, or repair
operation.

**RM-038.** A migration **MUST** have a dry-run plan, explicit authority,
compatibility statement, preserved ownership, and recovery behavior.

**RM-039.** A migration **MUST** preserve Project and Repository identity,
Information Object revision ancestry, provenance, authority, and audit evidence.

### P3 control-root serialization

For the initial transactional implementation, the AOS Control Root **MUST**
be a directory containing `.aos/repository.json`. The manifest **MUST** contain
`schema_version`, `contract_version`, `status`, `root`, `project_id`,
`repository_id`, `ownership_policy`, `initialization_revision`,
`operation_id`, `authority_reference`, and `initialized_at_unix`.

The supported values for the initial binding are `schema_version = "1"`,
`contract_version = "AOS-SPEC-002"`, `status = "initialized"`, and
`ownership_policy = "user-by-default"`. The canonical root in the manifest
**MUST** match the selected Repository Root. Unknown files inside `.aos`
**MUST** remain protected and **MUST NOT** be overwritten by `aos init`.

The manifest is written to a temporary sibling control root, synchronized,
and committed with an atomic rename. Verification **MUST** read the committed
manifest before reporting success. A failed or unknown commit **MUST** report
reconciliation rather than retrying blindly.

### Security and operational boundaries

**RM-040.** Repository inspection and adoption **MUST** use least-privilege
filesystem capabilities and **MUST NOT** read secrets as ordinary project
content without explicit policy and authority.

**RM-041.** AOS **MUST** report permission denial, locked content, unsupported
filesystem behavior, and external changes explicitly. It **MUST NOT** silently
fall back to a broader or less safe scope.

**RM-042.** Repository operations **MUST** expose enough evidence to explain
what was inspected, what ownership was assumed, what was proposed or changed,
who authorized it, and what remains unknown.

## Interfaces and data flow

The logical repository operations below are the minimum behaviors that later
CLI, Runtime, and distribution specifications must expose without requiring
these names as literal commands or API methods:

| Operation | Input | Result |
| --- | --- | --- |
| Discover | Optional root, caller context, discovery policy | Explicit root, unmanaged candidate, ambiguous, or error |
| Inspect | Canonical root and snapshot policy | Repository status, identity, ownership, compatibility, and evidence |
| Plan adoption | Inspection snapshot, Project identity, policy | Immutable Adoption Plan or explicit conflict |
| Validate plan | Adoption Plan and current snapshot | Applicable, stale, incompatible, or invalid |
| Apply plan | Valid plan and explicit authority | Initialized, degraded, failed, or unknown result with evidence |
| Reconcile | Uncertain or partial operation | Current status and auditable recovery result |
| Migrate | Supported migration plan and authority | New compatible control state or explicit failure |
| Retire | Repository policy and authority | AOS-owned data retirement plan; user content remains protected |

The intended flow is:

```text
Root selection
      |
      v
Canonicalization and boundary checks
      |
      v
Snapshot and read-only inspection
      |
      v
Ownership and compatibility classification
      |
      v
Adoption or migration plan
      |
      v
Explicit authority and precondition validation
      |
      v
Bounded apply
      |
      v
Verification, reconciliation, and audit
```

## Lifecycle and state transitions

### Repository status

```text
unmanaged --> candidate --> initialized
    |            |              |
    |            |              +--> degraded
    |            +-----------------> incompatible
    +------------------------------> incompatible
```

- `unmanaged`: no accepted AOS control state is present.
- `candidate`: a root is selected and can be inspected or planned for adoption.
- `initialized`: the control root and Repository record are valid and
  compatible.
- `incompatible`: a control state exists but its contract cannot be safely
  interpreted.
- `degraded`: a known partial or failed operation requires reconciliation.

An `unknown` operation result is not a Repository Status; it is an operation
outcome that requires inspection before a status can be asserted.

### Adoption lifecycle

```text
inspect -> plan -> authorize -> apply -> verify
                           |              |
                           +--> reject   +--> initialized
                                          +--> degraded
                                          `--> unknown
```

No operation may skip inspection, plan validation, authority, or verification
when it changes the repository.

## Failure behavior

| Condition | Required behavior |
| --- | --- |
| Explicit root missing or not a directory | Reject operation with boundary error |
| Nested or conflicting discovered roots | Return `ambiguous`; require explicit root |
| No existing control root | Report unmanaged candidate; do not mutate |
| Boundary link resolves outside root | Reject access unless explicitly authorized |
| User-owned path would be overwritten | Reject plan or require explicit shared-content authority |
| Unknown control-root artifact | Report and protect it |
| Unsupported contract version | Inspect if possible; refuse normal mutation |
| Snapshot changed after planning | Reject stale plan and require replanning |
| Permission, lock, or filesystem denial | Report explicit failure; do not broaden scope |
| Partial apply | Preserve user content, report degraded or unknown, require reconciliation |
| Migration cannot preserve identity or provenance | Reject migration; retain prior valid state |
| Secret detected without policy | Refuse ordinary capture or apply policy redaction |

## Security and governance

- Project owners retain authority over user-owned and shared content.
- AOS owns only the control artifacts explicitly adopted under `.aos/`.
- Plan creation is not authorization to apply.
- An AI provider, Runtime, or extension cannot expand the Repository Root or
  ownership class without an explicit capability and authority.
- Repository evidence must retain source, time, producer, and operation identity.
- AOS must fail closed when scope, ownership, compatibility, or operation result
  is unknown.

## Compatibility and migration

1. A Repository record must declare the AOS contract version and Project link.
2. A reader that does not support the contract must report `unsupported` rather
   than guess the control state.
3. A compatible migration must preserve Repository and Project identity,
   ownership classification, Information Object history, provenance, and audit.
4. A migration must be planned and reviewable before application.
5. A failed migration must leave the previous valid control state available or
   report `degraded`/`unknown` with explicit reconciliation steps.
6. Additional physical serialization and package compatibility remain subject
   to later Repository distribution specifications; the P3 manifest binding is
   limited to the fields above.

## Conformance tests

| Case | Requirement coverage | Expected result |
| --- | --- | --- |
| RM-C001 explicit root and stable Project link | RM-001–RM-005 | Deterministic read-only inspection |
| RM-C002 ownership classification and protected user content | RM-006–RM-011 | User paths protected; `.aos/` reserved |
| RM-C003 missing, nested, and external-link roots | RM-012–RM-017 | Explicit unmanaged, ambiguous, or boundary error |
| RM-C004 unmanaged candidate and adoption plan | RM-018–RM-023 | Plan is reviewable; apply creates valid control state |
| RM-C005 repeated adoption and business-content protection | RM-024–RM-025 | Idempotent; no business logic mutation |
| RM-C006 changed snapshot and partial operation | RM-026–RM-031 | Stale plan rejected; recovery evidence required |
| RM-C007 control-root ownership and compatibility | RM-032–RM-039 | Unknown artifacts protected; unsupported state not mutated |
| RM-C008 permissions, secrets, and audit | RM-040–RM-042 | Fail closed with attributable evidence |
| RM-C009 migration preserves identity and provenance | Compatibility 1–5 | Compatible migration or explicit rejection |
| RM-C010 unknown operation result | Failure table and lifecycle | No success claim until reconciliation |

## Unresolved questions

## Change history

| Date | Status | Change |
| --- | --- | --- |
| 2026-07-26 | Accepted | Initial Repository contract |
| 2026-07-26 | Accepted | P3 transactional control-root and repository manifest binding |
