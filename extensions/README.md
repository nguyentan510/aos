# AOS Declarative Extension Authoring Kit

P6 extensions are JSON manifest packages. They do not contain executable code
and can select only host operations compiled into the AOS allowlist.

## Start a package

1. Copy
   [`templates/repository-summary-extension.json`](templates/repository-summary-extension.json)
   into a directory inside an initialized downstream repository.
2. Replace the example identity, namespace, owner, and capability name.
3. Keep `data_ownership` equal to the extension namespace.
4. Validate without mutation:

   ```text
   aos extension validate <REPOSITORY> --manifest <PATH> --format=json
   ```

5. Inspect the enable plan:

   ```text
   aos extension enable <REPOSITORY> --manifest <PATH> --format=json
   ```

6. Apply only with an external authority and evidence reference:

   ```text
   aos extension enable <REPOSITORY> --manifest <PATH> \
     --apply --authority <PRINCIPAL> --evidence <REFERENCE> --format=json
   ```

The editor-facing JSON Schema is
[`schema/extension-manifest-v1.schema.json`](schema/extension-manifest-v1.schema.json).
The AOS CLI remains the authoritative runtime validator because it also checks
Core compatibility, enabled dependencies, namespace collisions, lifecycle,
digest, and repository scope.

## P6 limits

- Maximum manifest size: 256 KiB.
- Maximum Rust `Cargo.toml` adapter input: 1 MiB.
- No executable, subprocess, arbitrary shell, network, secret, environment, or
  caller-selected filesystem path.
- No direct invocation; capability execution requires authorized Work using
  `aos.extension.readonly@1.0.0`.
- Extension output is proposed evidence and cannot promote itself.

## Supported host operations

| Host operation | Exact scope | Purpose |
| --- | --- | --- |
| `repository.summary@1.0.0` | `repository:.` | Initialized repository identity and compatibility |
| `rust.cargo_manifest.summary@1.0.0` | `file:Cargo.toml` | Package/workspace metadata parsed in-process |

Adding a new host operation requires a reviewed AOS Core implementation and is
not accomplished by changing a manifest alone. Adding another package over an
already supported host operation does not change Core semantics.
