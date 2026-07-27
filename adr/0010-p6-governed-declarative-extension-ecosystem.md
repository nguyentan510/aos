# ADR-0010 — P6 Governed Declarative Extension Ecosystem

**Status:** Accepted
**Date:** 2026-07-27
**Decision owners:** AOS project
**Supersedes:** None
**Affected documents:** `ROADMAP.md`, `specifications/003-protocol.md`, `specifications/004-cli.md`, `specifications/005-runtime.md`, `specifications/006-extension.md`

## Context

P5 proves that AOS can authorize, run, verify, audit, and reconcile one
local-first Work lifecycle. P6 must prove that an independently packaged
capability can participate in that lifecycle without changing Core semantics,
granting itself authority, widening repository scope, or losing provenance.

Loading executable plugins, invoking arbitrary commands, or granting network
access would introduce an execution sandbox and provider trust problem before
the declarative lifecycle is proven. The first binding therefore needs a much
smaller attack surface.

## Decision

P6 uses JSON manifest packages and a declarative local execution model. An
extension can select only a host operation compiled into AOS and present in the
P6 allowlist. No extension executable, shell command, subprocess, network
target, secret, environment input, or caller-selected filesystem path is
accepted.

Reference manifests live in the AOS source and release distribution:

```text
extensions/reference/<extension-id>/extension.json
```

An initialized downstream repository persists immutable data under:

```text
.aos/extensions/
|-- manifests/<id>@<version>.json
|-- lifecycle/<id>.rN.json
`-- results/<work-id>.rN.json
```

Governance, Run, and Audit revisions remain in their P5 directories. Lifecycle
mutation is plan-first and requires `--apply`, an external Principal, and an
evidence reference. Discovery, validation, and inspection are read-only.
Removal records a disabled retired revision; it never deletes historical
manifests, results, Runs, Governance decisions, or Audit.

An enabled manifest is bound by its canonical JSON SHA-256 digest. One
extension identity can have only one enabled version per Project. A different
version requires disabling the current version first; re-enabling an older
snapshot is the rollback path.

Extension capability execution has no direct CLI entrypoint. It is available
only through:

```text
work create
  -> work authorize
  -> work run using aos.extension.readonly@1.0.0
```

Authorization and execution both require the intersection of manifest
declaration, Protocol capability, Governance decision, Runtime allowlist, and
exact repository resource scope. Run revalidates lifecycle, version, digest,
capability, and scope immediately before execution. Integrity, scope, or
isolation violations fail closed, quarantine the extension, block Work, and
require reconciliation.

P6 allows exactly two host operations:

- `repository.summary@1.0.0`;
- `rust.cargo_manifest.summary@1.0.0`.

The Rust operation reads only the canonical repository-root `Cargo.toml` and
parses it in-process. Every extension result is proposed evidence and retains
manifest digest, Work, Run, Protocol, Governance, input, resource, and
verification references.

## Consequences

### Positive

- A new declarative package can add an allowlisted capability without changing
  Core information semantics.
- Extension identity, authority, scope, inputs, results, and lifecycle remain
  locally inspectable and replayable.
- The execution surface excludes arbitrary code, process, network, and secret
  access.
- Disable, retirement, quarantine, and rollback preserve history.

### Negative

- A manifest cannot introduce a new host operation without a reviewed Core
  implementation and release.
- The initial authority reference remains caller-supplied rather than backed by
  RBAC or an identity provider.
- Filesystem revision coordination is local-first and not a distributed
  lifecycle service.
- Declarative-local ecosystem readiness is not production readiness.

## Alternatives considered

### WASM or dynamic executable plugins

Deferred because sandboxing, ABI stability, resource metering, supply-chain
policy, and effect reconciliation require a separate measured justification.

### JSON subprocess extensions

Rejected for P6 because a subprocess is executable code and could escape the
declared capability and filesystem boundaries.

### Direct `aos extension invoke`

Rejected because it would bypass governed Work, Protocol, and reconciliation.

### Marketplace or registry

Deferred until local package identity, compatibility, security, and lifecycle
behavior are proven.

## Compatibility and migration

Manifest identity, version, compatibility, dependency requirements, capability
meaning, effect class, scope, security declaration, and failure behavior are
versioned. A breaking meaning change requires a new extension version.
Unsupported manifest, Core, or contract versions fail with exit category `6`.
Historical snapshots remain immutable across disable, removal, upgrade, and
rollback.

## Conformance

- Discovery, validation, and inspection do not mutate `.aos`.
- Lifecycle mutation rejects missing or self-issued authority.
- Only one version of an extension identity is enabled per Project.
- Disabled, incompatible, quarantined, and retired extensions do not execute.
- Capability execution exists only through authorized governed Work.
- Digest, capability, Runtime allowlist, and resource scope are revalidated at
  Run time.
- Extension output remains proposed evidence with complete trace references.
- Isolation or integrity failure quarantines the extension and blocks Work.
