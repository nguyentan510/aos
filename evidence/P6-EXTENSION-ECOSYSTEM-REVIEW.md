# P6 Governed Declarative Extension Ecosystem Review

**Status:** COMPLETE
**Date:** 2026-07-27
**Decision:** P6 exit gate passed at governed declarative-local scope. P7
remains planned until a measured bottleneck justifies distributed behavior.

## Review objective

Verify that independently packaged declarative extensions can add bounded
capabilities without changing AOS Core semantics, issuing their own authority,
escaping repository scope, executing arbitrary code, or losing the trace from
manifest and governed Work to result and Audit.

## Accepted binding

[ADR-0010](../adr/0010-p6-governed-declarative-extension-ecosystem.md)
accepts:

```text
Manifest
-> discover/validate
-> Governance enable
-> authorized Work
-> capability intersection
-> local read-only host adapter
-> proposed Extension Result
-> Run/Work/Audit
-> complete or quarantine/reconcile
```

Source and release packages retain reference manifests under
`extensions/reference`. Downstream repositories retain only immutable manifest
snapshots, lifecycle revisions, and results under `.aos/extensions`.

## Implemented surface

- Manifest v1 parsing uses `serde` and `serde_json`.
- Versions and compatibility use SemVer.
- Canonical manifest snapshots and adapter inputs use SHA-256.
- Rust `Cargo.toml` parsing uses the `toml` crate in-process.
- Lifecycle actions are `discover`, `validate`, `inspect`, `enable`, `disable`,
  `quarantine`, and non-destructive `remove`.
- Lifecycle mutation is plan-first and requires explicit external authority
  and evidence.
- Only one version per extension identity may be enabled in a Project.
- Work stores the immutable extension reference, manifest digest, capability,
  exact scope, Protocol, and context snapshot.
- Run revalidates lifecycle, version, digest, capability, and exact scope.
- Result retains Work, Run, Protocol, Governance, context, manifest, input,
  resource, and verification references and remains proposed evidence.
- Integrity or isolation violation quarantines the extension, blocks Work, and
  requires reconciliation.

The only host operations are:

```text
repository.summary@1.0.0
rust.cargo_manifest.summary@1.0.0
```

There is no direct extension invocation, executable loading, caller command,
arbitrary path, network, provider action, or secret input.

## Reference extensions

```text
aos.reference.repository@1.0.0
  capability: aos.reference.repository.summary

aos.reference.rust@1.0.0
  capability: aos.reference.rust.cargo_manifest.summary
```

Both packages run end-to-end only through governed Work using
`aos.extension.readonly@1.0.0`.

## Local verification

Canonical commands:

```text
cargo fmt --check
cargo test --locked
cargo build --locked
cargo clippy --all-targets -- -D warnings
node scripts/validate-aos.mjs
powershell -ExecutionPolicy Bypass -File scripts/run_p6_extension_ecosystem_smoke.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_p6_trenux_snapshot_smoke.ps1 -RepositoryPath D:\trenux_rust
```

Required smoke markers:

```text
AOS_P6_EXTENSION_CONTRACT_OK
AOS_P6_EXTENSION_LIFECYCLE_OK
AOS_P6_EXTENSION_ISOLATION_OK
AOS_P6_REFERENCE_EXTENSION_SMOKE_OK
AOS_P6_EXTENSION_ECOSYSTEM_OK
```

Latest evidence at implementation review:

```text
Rust unit tests: 15 passed
CLI process tests: 39 passed
P6 local smoke: p6-20260727T083735Z PASS
Generic reference extension: PASS
Rust reference extension: PASS
digest tamper -> quarantine + blocked Work: PASS
disabled extension denial: PASS
direct invocation absent: PASS
deterministic normalized replay: PASS
static P6 validator: PASS
TRENUX source: D:\trenux_rust
TRENUX fixed commit: 3297389bd35ff3e8eb129dc74308ec3c8d165bf2
TRENUX snapshot smoke: trenux-3297389bd35f-20260727T083742Z PASS
TRENUX source mutation: false
AOS_P6_TRENUX_SNAPSHOT_SMOKE_OK: PASS
hosted Windows/Ubuntu CI: PASS
v0.1.0-rc.3 provenance: PASS
```

The downstream smoke copies only the fixed repository-root `Cargo.toml` and
source commit evidence to a temporary initialized snapshot. It compares the
TRENUX Git status before and after and does not write `.aos` into the source
repository.

## Denial and failure coverage

- unsupported schema/contract/Core compatibility;
- invalid SemVer and dependency requirements;
- missing/conflicting dependency and dependency cycle;
- namespace collision;
- missing authority, self-authority, and secret-like evidence;
- unsupported host operation and undeclared capability;
- exact resource scope mismatch and manifest path escape;
- disabled, quarantined, incompatible, and retired lifecycle denial;
- digest tampering and immutable manifest conflict;
- missing or malformed `Cargo.toml`;
- unauthorized and duplicate Work transition;
- non-destructive disable/remove with retained history.

## Release candidate contract

The Windows and Linux archives for `v0.1.0-rc.3` must contain:

```text
aos or aos.exe
extensions/reference/aos.reference.repository/extension.json
extensions/reference/aos.reference.rust/extension.json
```

The GitHub prerelease publishes both archives and `SHA256SUMS`.

## Hosted CI evidence

```text
implementation qualification run: 30250829548 PASS
qualified commit: 2218e8f938560615bc183053a40db433cdfeae1e
Windows job: 89928200227 PASS
Ubuntu job: 89928200245 PASS

packaging-fix qualification run: 30251035563 PASS
qualified commit: 0ece434518b793503b2640382893c27eba20077c
Windows job: 89928843709 PASS
Ubuntu job: 89928843777 PASS

Rust unit tests: 15/15 on Windows and Ubuntu
CLI process tests: 39/39 on Windows and Ubuntu
P6 governed extension ecosystem smoke: PASS on Windows and Ubuntu
P5 regression smoke/hardening: PASS on Windows
design/specification/P6/governance validators: PASS on Windows and Ubuntu
```

The first hosted P6 run `30250680786` exposed a PowerShell Core harness exit
propagation issue after all five expected markers had printed. The normalized
exit fix was then qualified by run `30250829548`. The first RC3 workflow
`30250953661` exposed a Linux archive output-path error before publishing any
release; the exact failed tag was replaced only after confirming no GitHub
Release existed and qualifying the packaging fix.

## Release provenance

```text
tag: v0.1.0-rc.3
tag commit: 0ece434518b793503b2640382893c27eba20077c
release workflow: 30251174570 PASS
Linux build job: 89929276235 PASS
Windows build job: 89929276295 PASS
publish job: 89929491098 PASS

artifact: aos-x86_64-pc-windows-msvc.zip
sha256: a0737358a1d6377f542fd91ac61d46fea811b43cc69267899e43c1b7359831f7
contents: aos.exe plus two reference manifests

artifact: aos-x86_64-unknown-linux-gnu.tar.gz
sha256: b56b4bbced18965f25bfad8a2a38c72532a8872af2c8e0ab9f9412442221edd9
contents: aos plus two reference manifests

checksum file: SHA256SUMS
checksum verification: AOS_RC3_CHECKSUMS_OK
```

## Current maturity

```text
Contract-ready:                  PASS
Implementation-aligned:          PASS
Runtime-smoke-ready:             PASS
Extension-ecosystem-ready:       PASS at declarative-local scope
Production-like-runtime-ready:   NOT CLAIMED
Production-ready:                NOT CLAIMED
P6 roadmap closeout:             PASS
P7:                              PLANNED pending measured bottleneck
```
