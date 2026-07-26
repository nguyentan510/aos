# P1 AOS-SPEC-002 Review

**Status:** PASS
**Reviewed:** 2026-07-26
**Specification:** `AOS-SPEC-002 — Repository`
**Decision:** Accepted

## Review objective

Verify that the Repository contract protects the artifact boundary, defines a
safe adoption lifecycle, and gives later CLI and Runtime specifications enough
behavior to implement without inventing ownership or recovery semantics.

## Entry gate

| Condition | Evidence | Result |
| --- | --- | --- |
| P0 is complete | [P0 Design Foundation Review](P0-DESIGN-FOUNDATION-REVIEW.md) | PASS |
| Information Model is accepted | [AOS-SPEC-001](../specifications/001-information-model.md) and its review | PASS |
| Artifact boundary is stable | `DESIGN.md` and ADR-0001 | PASS |
| Bootstrap name is stable | ADR-0003 and `DESIGN.md` | PASS |

## Contract review

| Area | Evidence | Result |
| --- | --- | --- |
| Repository identity and scope | RM-001–RM-005 | PASS |
| User/AOS/shared ownership | RM-006–RM-011 | PASS |
| Root discovery and boundary safety | RM-012–RM-017 | PASS |
| Adoption lifecycle | RM-018–RM-025 | PASS |
| Snapshot and recovery | RM-026–RM-031 | PASS |
| Control root and compatibility | RM-032–RM-039 | PASS |
| Security and operational boundaries | RM-040–RM-042 | PASS |
| Logical repository operations | Discover, Inspect, Plan, Validate, Apply, Reconcile, Migrate, Retire | PASS |
| Failure behavior | Boundary, ownership, unsupported, stale, partial, and sensitive-data cases | PASS |
| Conformance | RM-C001–RM-C010 | PASS |

## Boundary review

The specification deliberately leaves these concerns to later contracts:

- CLI syntax, flags, exit codes, and output;
- physical files inside `.aos/`;
- serialization and storage technology;
- version-control provider semantics;
- Protocol execution and Work transitions;
- Runtime, AI provider, and Extension APIs; and
- indexing, embeddings, and context ranking.

The specification does define the `.aos/` ownership namespace, because that
boundary is required to protect user content and make adoption safe.

## Safety review

The contract requires:

- deterministic root selection;
- no default traversal through links outside the root;
- read-only inspection;
- explicit ownership classification;
- reviewable adoption plans;
- explicit authority before apply;
- snapshot validation before mutation;
- idempotent repeated adoption;
- preservation of user content during partial failure;
- explicit degraded or unknown outcomes; and
- auditable migration and reconciliation.

These requirements preserve PRINCIPLES P1, P5, P7, P8, P10, and P12.

## Findings

### Blocking findings

None.

### Accepted limitations

- No CLI command syntax is defined.
- No physical `.aos/` filenames or serialization are defined.
- No version-control system is required.
- No real mutation is implemented.
- Protocol, Runtime, and Extension behavior remain deferred to their dependent
  specifications.

These limitations are intentional dependency boundaries.

## Verification

Required commands:

```bash
node scripts/validate-design-foundation.mjs
node scripts/validate-specifications.mjs
```

Required results:

```text
AOS_DESIGN_FOUNDATION_OK
AOS_SPECIFICATIONS_OK
```

## Decision

`AOS-SPEC-002 — Repository` is **Accepted** on 2026-07-26. It authorizes
dependent Protocol and CLI specification work, but it does not authorize
executable repository mutation.
