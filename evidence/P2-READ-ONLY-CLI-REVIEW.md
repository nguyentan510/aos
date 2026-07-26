# P2 Read-only Project Intelligence CLI Review

**Status:** PASS
**Date:** 2026-07-26
**Decision:** P2 exit gate satisfied

## Review objective

Verify that the first executable AOS slice can inspect and explain a repository
without an AI provider, without inventing a physical `.aos/` schema, and
without mutating user-owned files.

## Entry gate

- P0 Design Foundation is complete.
- All six P1 specifications are Accepted.
- [ADR-0005](../adr/0005-rust-native-binary-implementation.md) accepts Rust
  `1.96.0` and a Cargo-produced native binary.
- [ADR-0006](../adr/0006-p2-read-only-cli-boundary.md) limits P2 to read-only
  commands and defers `aos init` mutation to P3.

## Deliverable matrix

| Deliverable | Implementation | Evidence |
| --- | --- | --- |
| Native `aos` binary target | `Cargo.toml`, `rust-toolchain.toml` | Pinned toolchain and build gate |
| Repository discovery and inspection | `src/repository.rs` | unmanaged, candidate, incompatible, and root-error fixtures |
| `inspect`, `validate`, and `doctor` commands | `src/cli.rs` | unit and process smoke tests |
| Deterministic human/JSON envelope | `src/model.rs` | JSON escaping unit test and CLI JSON assertions |
| Explicit deferred mutation boundary | `aos init` returns exit category `6` | no `.aos/` created by smoke test |

## Safety review

P2 performs canonical path resolution and reads `.aos` metadata only. It does
not create, delete, modify, or repair repository content. An existing
directory is reported as a candidate with an unrecognized schema; a file or
unsafe link is reported as incompatible. No AI provider or extension is
required.

## Verification

The following commands passed:

```text
cargo fmt --check
cargo test
cargo build --locked
```

Test result:

- 4 Rust unit tests passed.
- 6 CLI process smoke tests passed.
- The smoke suite covered unmanaged, candidate, incompatible, missing-root,
  read-only diagnostics, and deferred `aos init` behavior.

## Decision

P2 is complete. P3 is the next eligible phase and owns transactional
repository initialization, including the physical `.aos/` schema, dry-run
plans, ownership checks, idempotency, conflict handling, and recovery.
