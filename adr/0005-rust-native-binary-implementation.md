# ADR-0005 — Rust Native Binary Implementation

**Status:** Accepted
**Date:** 2026-07-26
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `ROADMAP.md`, `README.md`, `DESIGN.md`

## Context

P2 is the first phase that introduces executable AOS behavior. The repository
needs a canonical implementation language and a distribution direction that
supports safe filesystem boundaries, deterministic behavior, cross-platform
single-binary use, and future Runtime isolation.

The toolchain audit found Rust `1.96.0` and Go `1.25.3` available. No remote
module path or package ecosystem has been selected.

## Decision

AOS initial implementation is written in **Rust `1.96.0`** using Cargo.

The executable package is named `aos-cli` and produces the binary `aos`.
P2 uses a stdlib-first dependency policy for command parsing, path handling,
read-only repository inspection, output formatting, and tests. External
dependencies require a later ADR that records security, licensing, version,
build, and supply-chain impact.

The initial distribution target is a native single binary per supported
platform. Package managers, installers, release archives, signing, and
cross-compilation automation are deferred until executable behavior is proven.

## Consequences

### Positive

- Strong type and ownership guarantees for path and state handling.
- Straightforward cross-platform binary distribution.
- No module URL or hosted package namespace is required in P2.
- A small dependency surface reduces early supply-chain risk.

### Negative

- CLI parsing and machine output require more local implementation than using a
  framework.
- Contributors must install the pinned Rust toolchain.
- Release packaging is deferred and must be designed later.

### Risks and controls

- Manual parsing could drift from the CLI Specification. P2 tests map every
  supported command and failure category to the specification.
- Stdlib-only output code could mishandle escaping. Dedicated JSON escaping
  tests are required before P2 closeout.

## Alternatives considered

### Go

Rejected for the initial implementation because the project has not selected a
stable module path and Rust provides stronger path/state modeling for the
planned ownership and Runtime boundaries.

### Node package

Rejected because the first product target is a self-contained native binary,
not a runtime-dependent package.

## Compatibility and migration

The language decision does not change AOS product contracts. Future
implementations may use another language if they conform to accepted
specifications and an ADR records the migration and compatibility plan.

## Conformance

- `Cargo.toml` pins the Rust package and binary names.
- `rust-toolchain.toml` records Rust `1.96.0`.
- P2 tests verify CLI behavior without an AI provider or write path.
