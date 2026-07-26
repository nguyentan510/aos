# P1 AOS-SPEC-004 Review

**Status:** PASS
**Reviewed:** 2026-07-26
**Specification:** `AOS-SPEC-004 — CLI`
**Decision:** Accepted

## Review objective

Verify that the CLI contract provides a small, safe, provider-neutral interface
over the accepted Information Model, Repository, and Protocol contracts.

## Entry gate

| Condition | Evidence | Result |
| --- | --- | --- |
| Information Model is accepted | `AOS-SPEC-001` | PASS |
| Repository is accepted | `AOS-SPEC-002` | PASS |
| Protocol is accepted | `AOS-SPEC-003` | PASS |
| Bootstrap command is governed | ADR-0003 and `AOS-SPEC-002` | PASS |

## Contract review

| Area | Evidence | Result |
| --- | --- | --- |
| Invocation and identity | CLI-001–CLI-005 | PASS |
| Command semantics | CLI-006–CLI-013 | PASS |
| Root and option handling | CLI-014–CLI-019 | PASS |
| Output contract | CLI-020–CLI-025 | PASS |
| Exit categories | CLI-026–CLI-028 | PASS |
| Safety and lifecycle | CLI-029–CLI-033 | PASS |
| Security and compatibility | CLI-034–CLI-037 | PASS |
| Conformance | CLI-C001–CLI-C010 | PASS |

## Safety review

The contract establishes read-only `inspect`, `validate`, and `doctor`; plan-first
`init`; explicit `--apply`; stable exit categories; machine output; no bypass
flags; stale-plan rejection; and safe handling of unknown or partial results.

## Findings

### Blocking findings

None.

### Accepted limitations

- No CLI implementation or packaging exists.
- Interactive confirmation wording is implementation-defined.
- Output serialization is logical; a concrete encoding remains an
  implementation concern.

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

`AOS-SPEC-004 — CLI` is **Accepted** on 2026-07-26. It authorizes read-only
CLI implementation planning but does not authorize executable mutation.
