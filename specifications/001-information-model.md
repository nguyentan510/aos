# AOS-SPEC-001 — Information Model

**Status:** Accepted
**Authors:** AOS project
**Created:** 2026-07-26
**Updated:** 2026-07-26
**Depends on:** P0 Reference Model
**Supersedes:** None

## Purpose

This specification defines the logical Information Model used by AOS to
represent Project, Knowledge, State, Work, Protocol, and Governance without
prescribing a physical file format, database, programming language, or API.

It establishes the minimum semantics required for durable, attributable,
versioned, and governable project intelligence.

## Motivation

The Reference Model defines the AOS domain concepts, but implementations need a
precise contract for identity, ownership, revision, provenance, authority,
freshness, lifecycle, and relationships. Without that contract, different
tools could serialize incompatible meanings while claiming to manage the same
Project.

This specification advances:

- VISION G1 — Repository-native project intelligence.
- VISION G2 — Explicit and attributable truth.
- VISION G3 — Protocol-driven work.
- VISION G4 — Human-governed automation.
- VISION G5 — Progressive context.

It is constrained by PRINCIPLES P1, P2, P4, P5, P6, P7, P8, P9, and P11 and
implements the domain boundary in `DESIGN.md`.

## Scope

This specification defines:

- the logical Information Object envelope;
- the six AOS domain concepts and their minimum required meaning;
- ownership, producer, authority, provenance, freshness, and lifecycle;
- typed references and relationship integrity;
- logical operations and state transitions;
- validation, conflict, unknown-state, and partial-update behavior;
- compatibility and migration obligations; and
- conformance cases for implementations and future specifications.

## Non-goals

This specification does not define:

- serialization beyond the minimal P4 Knowledge and State revision binding;
- `.aos/` layout outside the P4 Knowledge and State namespaces;
- a database, cache, event bus, or remote service;
- CLI command syntax;
- Protocol execution semantics;
- model-provider or extension APIs;
- semantic ranking, embedding, vector search, or provider-selected context; or
- project-specific business entities.

## Terminology

### Information Object

A logically identifiable record that participates in the AOS Project model.
Project, Knowledge, State, Work, Protocol, and Governance are Information
Object kinds.

### Revision

An immutable version of an Information Object. A correction or substantive
change creates a new Revision linked to the previous one.

### Principal

A human, organization, service, tool, or other identity that may own, produce,
review, or authorize an object. A producer is not automatically an authority.

### Evidence

An attributable observation, source reference, artifact, decision, or validation
result supporting an object or a derived claim.

### Provenance

The record of where an object or claim came from, who or what produced it, when
it was observed or generated, and which inputs or derivation produced it.

### Authority

The explicit basis under which an object may be treated as project truth.
Authority is classified as `proposed` or `authoritative`.

### Freshness

The current validity assessment of a State observation: `confirmed`, `stale`, or
`unknown`. Freshness is distinct from authority.

### Lifecycle

The retention state of an object: `active`, `superseded`, or `retired`.

## Normative requirements

### Common object envelope

**IM-001.** Every Information Object **MUST** have exactly one `kind` from:
`Project`, `Knowledge`, `State`, `Work`, `Protocol`, or `Governance`.

**IM-002.** Every Information Object **MUST** have an opaque, stable `id` that
is unique within its Project. An implementation **MUST NOT** infer identity from
display names, paths, content hashes, or array position.

**IM-003.** Every non-root Information Object **MUST** identify its owning
Project. A Project **MUST** be the root scope for its own identity and
project-local objects.

**IM-004.** Every Information Object **MUST** declare the model or contract
version used to interpret its logical fields. An implementation **MUST NOT**
silently interpret an unsupported version.

**IM-005.** Every Information Object **MUST** expose a monotonic `revision`
within its identity history. A published revision **MUST** be immutable.

**IM-006.** A change to an authoritative object **MUST** create a new revision
linked to the prior revision. In-place replacement that destroys the prior
authoritative meaning **MUST NOT** be treated as a valid update.

**IM-007.** Every Information Object **MUST** identify an owner Principal and a
producer Principal. A producer **MUST NOT** be treated as an authority without
an explicit governance decision.

**IM-008.** Every Information Object **MUST** carry an unambiguous creation
instant and last-observed or last-produced instant as appropriate. The logical
value **MUST** identify a UTC instant; physical timestamp encoding is defined by
the Repository Specification.

**IM-009.** Every Information Object **MUST** have an explicit `authority`
classification and `lifecycle` classification.

### Provenance and authority

**IM-010.** An object classified as `authoritative` **MUST** identify its
authority basis, owner, and supporting provenance.

**IM-011.** A derived object or claim **MUST** identify the input object
revisions, derivation rule or operation, and producer version used to create it.

**IM-012.** An object without sufficient provenance or authority evidence
**MUST** remain `proposed` or be reported as an unresolved observation. It
**MUST NOT** be promoted silently.

**IM-013.** If two authoritative objects make incompatible claims about the
same subject and no accepted precedence rule exists, the implementation **MUST**
represent the conflict explicitly and **MUST NOT** overwrite either claim.

**IM-014.** A provenance reference that cannot be resolved **MUST** be reported
as unresolved. The implementation **MUST NOT** fabricate, silently drop, or
replace the missing evidence.

**IM-015.** Provenance **MUST** distinguish at least the source reference,
producer, observation or production instant, and whether the object is derived.

### Authority and lifecycle

**IM-016.** `authority` **MUST** be one of `proposed` or `authoritative`.

**IM-017.** A transition from `proposed` to `authoritative` **MUST** identify
the responsible governance decision or accepted authority rule.

**IM-018.** `lifecycle` **MUST** be one of `active`, `superseded`, or `retired`.

**IM-019.** A `superseded` object **MUST** reference the replacement revision or
object. A `retired` object **MUST** remain discoverable for audit unless a
later retention specification explicitly permits redaction.

**IM-020.** An object classified as `proposed` **MUST NOT** be presented as
current authoritative Project truth by a default consumer.

**IM-021.** A proposed State **MUST** have freshness `unknown` unless a later
observation explicitly establishes a different freshness classification.

### Project

**IM-022.** A Project **MUST** identify its name, purpose or description,
ownership, project boundaries, and authoritative external systems where they
exist.

**IM-023.** A Project **MUST** provide the scope under which its child
Information Objects are interpreted. Child objects **MUST NOT** silently
belong to multiple Projects.

**IM-024.** Project identity changes **MUST** be represented as new revisions
with provenance; display-name changes **MUST NOT** create a new Project identity.

### Knowledge

**IM-025.** Knowledge **MUST** identify the subject it describes and provide
content or a reference to content plus provenance.

**IM-026.** Knowledge that represents a decision, specification, architecture
rule, concept, or glossary entry **MUST** identify its authority and lifecycle.

**IM-027.** A Knowledge revision **MUST** preserve the relation to the prior
revision when its meaning changes.

### State

**IM-028.** State **MUST** identify the subject, observed value or explicit
unknown value, observation instant, observer or producer, and freshness.

**IM-029.** Freshness **MUST** be one of `confirmed`, `stale`, or `unknown`.
Freshness evaluation **MUST** identify the policy, observation, or reason used.

**IM-030.** A State with freshness `stale` or `unknown` **MUST NOT** be used by
default as if it were a confirmed current condition.

**IM-031.** A State that records an explicit unknown condition **MUST** remain
distinguishable from a missing State object.

### P4 Knowledge and State serialization

P4 serializes immutable Knowledge revisions as
`.aos/knowledge/<id>.r<revision>.json` and State revisions as
`.aos/state/<id>.r<revision>.json`.

Every P4 record **MUST** contain `kind`, `id`, `project_id`,
`contract_version`, `revision`, `previous_revision`, `owner`, `producer`,
creation or observation time, `authority`, `lifecycle`, `subject`,
`source_reference`, derivation classification, authority basis, and authority
reference in `authority_reference`. Knowledge additionally **MUST** contain
`content`. State additionally
**MUST** contain `observed_value`, `observation_instant_unix`, `observer`,
`freshness`, and `freshness_policy`.

P4 record creation **MUST** produce `proposed` objects only. Authoritative
promotion requires Governance and **MUST NOT** be inferred from an `--apply`
flag or authority reference. A new meaning **MUST** create a higher immutable
revision with `previous_revision`; an existing revision file **MUST NOT** be
overwritten.

Default P4 context retrieval **MUST** select the highest revision for each
identity deterministically. It **MUST** select only active authoritative
Knowledge and active authoritative State with `confirmed` freshness. Every
proposed, stale, unknown, non-active, duplicate, or over-limit record **MUST**
be withheld with an explicit reason.

### Work

**IM-032.** Work **MUST** identify an intent, owner, scope, relevant context,
expected output, and verification evidence requirements.

**IM-033.** Work **MUST** identify the Protocol version that governs its
execution when it is authorized or beyond the proposed stage.

**IM-034.** Work **MUST** expose one lifecycle status from
`proposed`, `authorized`, `in_progress`, `blocked`, `completed`, `failed`, or
`cancelled`.

**IM-035.** Work classified as `completed` **MUST** reference verification
evidence. Work classified as `failed` or `blocked` **MUST** expose the reason
and unresolved condition.

### Protocol

**IM-036.** A Protocol **MUST** identify its name, immutable version, purpose,
required inputs, expected outputs, checks, and governance points.

**IM-037.** A Protocol revision **MUST NOT** change the meaning of an accepted
version. A changed behavior **MUST** use a new version and compatibility
statement.

**IM-038.** Protocol execution details, ordering, retries, and recovery are
defined by the Protocol Specification; the Information Model only records the
Protocol identity and version referenced by Work.

### Governance

**IM-039.** Governance **MUST** distinguish the policy, authority grant,
decision, or audit record it represents.

**IM-040.** A Governance decision **MUST** identify the subject, responsible
Principal, decision instant, decision outcome, and evidence or policy basis.

**IM-041.** Governance **MUST** be able to represent approval, rejection,
exception, and reconciliation outcomes without deleting the prior decision.

### Relationships and scope

**IM-042.** A relationship between Information Objects **MUST** identify its
source object, target object, relationship kind, and provenance where the
relationship is derived or externally asserted.

**IM-043.** A relationship **MUST NOT** imply ownership, authority, or
permission unless its declared kind explicitly has that meaning.

**IM-044.** A reference to an object that does not exist, is unsupported, or is
outside the declared Project scope **MUST** be reported as invalid or
unresolved.

**IM-045.** General Knowledge relationships MAY form cycles. Provenance and
revision ancestry **MUST NOT** contain cycles.

### Security and sensitive data

**IM-046.** Secrets, credentials, private keys, and equivalent authentication
material **MUST NOT** be stored as ordinary Information Object content.

**IM-047.** Sensitive references **MUST** retain enough provenance and
classification to explain what was withheld without exposing the secret.

## Interfaces and data flow

The logical operations below are the minimum behaviors that future Repository,
Protocol, and CLI Specifications must expose without requiring these names as
literal command or API names:

| Operation | Input | Result |
| --- | --- | --- |
| Observe | Evidence or external observation | Proposed or authoritative object according to authority |
| Propose | Human or tool intent | Proposed revision with provenance |
| Validate | Object revision and referenced evidence | Valid, invalid, unresolved, or conflict result |
| Authorize | Proposed object plus Governance decision | Authoritative revision or explicit rejection |
| Revise | Existing revision plus change and provenance | New immutable revision |
| Supersede | Existing object plus replacement | Existing object marked superseded with replacement link |
| Retire | Existing object plus retention decision | Retired object retained for audit |
| Query | Project scope, object kind, and selection constraints | Objects with authority, freshness, provenance, and revision context |

All operations **MUST** preserve object identity, provenance, authority, and
lifecycle semantics. A failed operation **MUST** return an explicit failure or
unknown result and **MUST NOT** claim a successful state transition.

## Lifecycle and state transitions

### Common object lifecycle

```text
proposed authority
        |
        | governance authorization
        v
authoritative + active
        |
        +--> superseded + replacement reference
        |
        `--> retired + audit retention
```

Rejection of a proposal is a Governance outcome; it is not an authoritative
object and must remain auditable as a decision.

### State freshness

```text
confirmed <--> stale
    |
    `-------> unknown
```

An observation can become stale under its declared freshness policy. An unknown
condition is an explicit result, not an absent record. A proposed State starts
with freshness `unknown`.

### Work lifecycle

```text
proposed -> authorized -> in_progress -> completed
                         |             |
                         |             +--> failed
                         +------------------> blocked
proposed -> cancelled
authorized -> cancelled
blocked -> in_progress
```

The Protocol Specification will define which transitions require approval,
which are retryable, and how partial execution is reconciled.

## Failure behavior

| Condition | Required behavior |
| --- | --- |
| Missing required field | Reject validation; do not publish the revision |
| Unsupported model version | Return unsupported status; do not guess semantics |
| Duplicate identity/revision | Reject; do not overwrite either object |
| Unresolved reference | Preserve the object as unresolved and report the reference |
| Provenance conflict | Represent conflict explicitly; do not choose silently |
| Stale or unknown State | Report freshness; do not use as confirmed by default |
| Unauthorized promotion | Reject authority transition and record the decision |
| Partial revision write | Reconcile before claiming success; preserve prior revision |
| Sensitive content detected | Reject or redact according to policy; preserve audit metadata |

## Security and governance

- A human or organization remains accountable for authoritative Project truth.
- Producers, including AI tools, are identifiable but are not authorities by
  default.
- Authority promotion requires a Governance decision or an explicitly accepted
  rule.
- Consumers must be able to distinguish authoritative, proposed, stale,
  unknown, superseded, and retired information.
- Sensitive data is excluded from ordinary Information Object content.
- Every mutation of authoritative meaning is auditable through revision and
  provenance history.

## Compatibility and migration

1. A logical contract version is required on every Information Object.
2. A reader that does not support a version **MUST** report unsupported status
   rather than infer fields or silently downgrade meaning.
3. A compatible migration **MUST** preserve object identity, revision ancestry,
   provenance, authority, lifecycle, and unresolved/conflict status.
4. A breaking interpretation **MUST** use a new contract version and provide a
   rejection or migration path.
5. Additional serialization, storage, and transport compatibility are deferred
   to later specifications; the P4 revision binding above is normative.

## Conformance tests

| Case | Requirement coverage | Expected result |
| --- | --- | --- |
| IM-C001 valid Project root and child Knowledge | IM-001–IM-009, IM-022–IM-024 | Accepted as valid |
| IM-C002 duplicate ID or destroyed revision history | IM-002, IM-005–IM-006 | Rejected without overwrite |
| IM-C003 missing owner or producer | IM-007 | Rejected |
| IM-C004 derived Knowledge with complete inputs | IM-010–IM-011, IM-025–IM-027 | Valid derived object |
| IM-C005 derived claim without evidence | IM-012, IM-015 | Remains proposed or unresolved |
| IM-C006 conflicting authoritative State claims | IM-013 | Conflict is explicit; neither claim is overwritten |
| IM-C007 unresolved provenance reference | IM-014, IM-044 | Unresolved result is reported |
| IM-C008 proposed-to-authoritative transition without decision | IM-016–IM-017 | Rejected |
| IM-C009 supersede and retire object | IM-018–IM-020 | Replacement and audit links retained |
| IM-C010 proposed and stale State | IM-021, IM-028–IM-031 | Not treated as confirmed current truth |
| IM-C011 Work without Protocol after authorization | IM-032–IM-035 | Rejected |
| IM-C012 completed Work without evidence | IM-035 | Rejected |
| IM-C013 changed accepted Protocol version | IM-036–IM-038 | Requires new version |
| IM-C014 Governance approval and rejection records | IM-039–IM-041 | Both outcomes remain auditable |
| IM-C015 invalid cross-scope or cyclic provenance reference | IM-042–IM-045 | Rejected or unresolved; no provenance cycle |
| IM-C016 secret-bearing Information Object | IM-046–IM-047 | Rejected or policy redacted |
| IM-C017 unsupported model version | Compatibility 1–2 | Explicit unsupported result |
| IM-C018 partial revision failure | Failure table and Compatibility 3 | Prior revision retained; reconciliation required |

## Unresolved questions

## Change history

| Date | Status | Change |
| --- | --- | --- |
| 2026-07-26 | Accepted | Initial Information Model contract |
| 2026-07-26 | Accepted | P4 immutable Knowledge/State and deterministic context binding |
