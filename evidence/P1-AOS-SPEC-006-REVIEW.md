# P1 AOS-SPEC-006 Review

**Status:** PASS
**Reviewed:** 2026-07-26
**Specification:** `AOS-SPEC-006 — Extension`
**Decision:** Accepted

## Review objective

Verify that Extensions can add optional capability without redefining AOS Core,
bypassing Governance, expanding authority, corrupting Project truth, or
weakening compatibility and isolation.

## Entry gate

| Condition | Evidence | Result |
| --- | --- | --- |
| Information Model is accepted | `AOS-SPEC-001` | PASS |
| Protocol is accepted | `AOS-SPEC-003` | PASS |
| Runtime is accepted | `AOS-SPEC-005` | PASS |
| Core/Runtime boundary is governed | ADR-0004 and `DESIGN.md` | PASS |

## Contract review

| Area | Evidence | Result |
| --- | --- | --- |
| Identity and manifest | EX-001–EX-005 | PASS |
| Core and capability boundaries | EX-006–EX-011 | PASS |
| Data, namespace, and provenance | EX-012–EX-016 | PASS |
| Dependencies and compatibility | EX-017–EX-022 | PASS |
| Lifecycle and operations | EX-023–EX-029 | PASS |
| Security and isolation | EX-030–EX-035 | PASS |
| Compatibility and evolution | EX-036–EX-038 | PASS |
| Conformance | EX-C001–EX-C010 | PASS |

## Safety review

The contract requires namespaced data, dependency validation, capability
intersection, explicit enablement, quarantine, safe disable/remove behavior,
secret protection, and preservation of Core truth.

## Findings

### Blocking findings

None.

### Accepted limitations

- No package registry, marketplace, or ABI is selected.
- Extension discovery and distribution are not implemented.
- Extension conformance is scenario-based until executable tests exist.

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

`AOS-SPEC-006 — Extension` is **Accepted** on 2026-07-26. It authorizes
extension ecosystem planning but does not authorize unrestricted dynamic code
execution or external distribution.
