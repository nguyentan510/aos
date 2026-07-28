# ADR-0011 — P6.3 One-command Installation and Setup

**Status:** Accepted
**Date:** 2026-07-27
**Decision owners:** AOS project
**Supersedes:** None
**Superseded in part by:** ADR-0012 for the P6.2 seven-day blocking exit
condition
**Affected documents:** `README.md`, `ROADMAP.md`, `specifications/004-cli.md`,
`.github/workflows/ci.yml`, `.github/workflows/release.yml`

## Context

The P6 CLI and reference extensions are usable, but the maintainer path requires
a user to locate a binary, copy manifests, initialize a repository, and enable
extensions with several governance flags. That is too much incidental work for
first use.

P6.2 is simultaneously qualifying a pinned binary over real elapsed time.
Changing that qualification subject would invalidate the duration evidence.
Blocking all developer-experience work on elapsed time would not improve the
qualification. The two activities therefore need explicit isolation.

## Decision

The public project bootstrap is:

```text
aos setup [PATH]
```

`setup` is convenience orchestration over transactional repository
initialization and the existing governed extension-enable implementation. It
does not introduce a second authority path. It selects the embedded Generic
Repository manifest for every repository and also selects the embedded Rust
manifest only when a regular, non-symlink `Cargo.toml` exists at the Repository
Root.

Interactive human use receives one plan and one `y/N` confirmation. `--yes`
confirms the same plan for automation. `--dry-run`, JSON output without
`--yes`, and non-interactive use without `--yes` do not mutate. Setup never
creates the project directory, initializes Git, scans source broadly, or
creates Knowledge, State, or Work.

When no explicit Principal is supplied, setup records
`local-user:<normalized-os-user>` with an explicit local-bootstrap authority
basis. This is an environment-provided reference, not authenticated identity.
Failure to resolve a safe user requires `--authority`.

Reference manifests are embedded in the binary and validated through the same
P6 implementation as a file-based enable. Their canonical digest must match
the manifests packaged in the release. Downstream repositories receive only
immutable manifest snapshots, lifecycle, Governance, and Audit records.

Distribution installation remains separate from repository initialization as
required by ADR-0003. `install.ps1` and `install.sh` may compose installation
and setup only when `ProjectPath` is supplied, and must report each outcome.
The Rust CLI performs no network download, upgrade, or self-removal.

Installers support only Windows x86_64 and Linux x86_64 GNU in P6.3. They:

- resolve or accept a pinned release version;
- verify an exact `SHA256SUMS` entry before extraction;
- reject archive traversal;
- smoke the staged binary before committing;
- retain versioned installation provenance;
- switch the current binary atomically;
- support offline archive and checksum inputs;
- uninstall only recorded installer-owned distribution paths; and
- never search for or remove downstream `.aos` data.

P6.3 implementation may run in parallel with P6.2 because the official P6.2
evidence lane pins the binary, manifests, harness, source commit, and hashes
outside the source repository. A daily automation appends qualification
samples. This exception accelerates independent work; it does not fabricate
elapsed time, waive the seven-day gate, or permit a production-like claim.

## Failure and reconciliation

Setup is append-only after repository initialization commits. If a later
extension step fails, the outcome is `partial`, completed steps are retained,
and the caller reruns setup after resolving the diagnostic. No committed
`.aos` history is rolled back or overwritten.

Installers stage downloads and extraction under a temporary directory.
Checksum, platform, archive, or staged-binary failure leaves the current
installation unchanged. Uninstall rejects modified or unowned current
binaries.

## Consequences

### Positive

- First use becomes one command and one confirmation.
- Setup preserves the P3 and P6 authority, ownership, and audit contracts.
- Offline installer fixtures make supply-chain behavior testable in CI.
- P6.2 continues collecting valid evidence without blocking isolated DX work.

### Negative

- Package-manager integrations remain unavailable.
- The local Principal is attributable but not strongly authenticated.
- A partial setup is reconciled by safe rerun rather than cross-directory
  rollback.
- Installation readiness does not establish production-like runtime readiness.

## Alternatives considered

### Make `aos init` enable extensions implicitly

Rejected because it would change the accepted repository-adoption contract and
hide materially different mutations behind an existing command.

### Make the Rust CLI download or update itself

Rejected because it would add network, self-mutation, and distribution trust to
Core.

### Skip or synthetically advance the P6.2 duration gate

Rejected. Repeated accelerated smokes are useful for fault coverage, but they
do not replace real elapsed-time evidence.

## Conformance

- Setup plan and cancellation do not create `.aos`.
- Setup apply requires a safe Principal and uses existing init/enable paths.
- Generic and Rust selection is deterministic and repository-root bounded.
- Repeated setup is a verified no-op.
- Exact checksum mismatch and archive traversal fail before installation.
- Repeated install, version switch, rollback, and owned uninstall are safe.
- Distribution uninstall preserves every downstream `.aos`.
- Windows and Linux hosted release smokes use the published archive and
  checksums.
