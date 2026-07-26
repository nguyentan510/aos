# P3 Transactional Repository Initialization Review

**Status:** PASS
**Date:** 2026-07-26
**Decision:** P3 exit gate satisfied

## Review objective

Verify that `aos init` can plan and apply repository adoption transactionally
without overwriting user-owned content, while exposing ownership, authority,
operation, verification, and recovery evidence.

## Entry gate

- P2 Read-only Project Intelligence CLI is complete.
- Repository ownership and compatibility rules are Accepted in
  `AOS-SPEC-002`.
- [ADR-0007](../adr/0007-transactional-repository-initialization.md) accepts
  the `.aos/repository.json` binding and atomic apply boundary.

## Deliverable matrix

| Deliverable | Implementation | Evidence |
| --- | --- | --- |
| Plan-first `aos init` | `src/repository.rs` and `src/cli.rs` | default and `--dry-run` smoke test |
| Explicit authority | `--apply --authority <REFERENCE>` | exit `7` test without authority |
| Minimal control-root schema | `.aos/repository.json` | manifest verification and inspect status |
| Transactional apply | temporary sibling plus atomic rename | apply smoke test and post-apply verification |
| Idempotency | compatible manifest no-op | repeat apply returns `already_initialized` |
| Conflict protection | unknown `.aos` is never overwritten | ownership conflict fixture preserves user file |

## Safety review

The apply path only creates the AOS-owned `.aos` directory when it is absent.
Existing unknown, incompatible, or linked control roots are protected and
return conflict or incompatible findings. Application source, tests,
documentation, and configuration remain outside the mutation boundary. The
authority string is recorded as a caller reference; full Governance
authorization remains a later capability.

## Verification

The following commands passed:

```text
cargo fmt --check
cargo test
cargo build --locked
cargo clippy --all-targets -- -D warnings
node scripts/validate-aos.mjs
```

Test result:

- 6 Rust unit tests passed.
- 9 CLI process smoke tests passed.
- Coverage includes plan, dry-run, missing authority, transactional apply,
  idempotent repeat, unknown-root conflict, read-only commands, and root
  errors.

## Decision

P3 is complete. P4 is the next eligible phase and owns Knowledge and Context
capabilities; it must preserve the Repository manifest and P3 ownership
boundary.
