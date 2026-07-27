use crate::extension;
use crate::intelligence::QueryResult;
use crate::model::{Diagnostic, OperationSummary, OwnershipDecision, PlanSummary};
use crate::repository;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const GENERIC_MANIFEST: &str =
    include_str!("../extensions/reference/aos.reference.repository/extension.json");
const RUST_MANIFEST: &str =
    include_str!("../extensions/reference/aos.reference.rust/extension.json");

#[derive(Debug)]
pub struct SetupInput {
    pub path: Option<PathBuf>,
    pub apply: bool,
    pub authority: Option<String>,
    pub authority_basis: String,
}

pub fn execute(input: SetupInput) -> QueryResult {
    let planned_init = repository::init(input.path.as_deref(), false, None);
    if planned_init.exit_code != 0 {
        return init_failure(planned_init);
    }
    let summary = planned_init
        .repository
        .clone()
        .expect("successful init planning resolves repository");
    let root = display_root_path(&summary.root);
    let rust_detected = detects_rust(&root);
    let extensions = selected_extensions(rust_detected);
    let principal = match resolve_principal(input.authority.as_deref()) {
        Ok(value) => value,
        Err(message) if input.apply => {
            return QueryResult {
                repository: Some(summary),
                diagnostics: vec![Diagnostic::error("AOS-SETUP-AUTHORITY-REQUIRED", message)],
                evidence: vec!["setup:bootstrap-authority".to_string()],
                data: setup_data(None, &input.authority_basis, rust_detected, &extensions),
                plan: setup_plan(planned_init.plan, &extensions),
                operation: None,
                exit_code: 7,
                outcome: "authorization_required".to_string(),
            };
        }
        Err(_) => None,
    };
    let plan = setup_plan(planned_init.plan, &extensions);
    let data = setup_data(
        principal.as_deref(),
        &input.authority_basis,
        rust_detected,
        &extensions,
    );
    if !input.apply {
        return QueryResult {
            repository: Some(summary),
            diagnostics: vec![Diagnostic::info(
                "AOS-SETUP-PLAN-READY",
                "setup plan created; no repository mutation was requested",
            )],
            evidence: vec![
                "setup:project-detection".to_string(),
                "setup:plan-first".to_string(),
            ],
            data,
            plan,
            operation: None,
            exit_code: 0,
            outcome: "plan_ready".to_string(),
        };
    }

    let principal = principal.expect("apply requires a resolved principal");
    let init = repository::init(input.path.as_deref(), true, Some(&principal));
    if init.exit_code != 0 {
        return init_failure(init);
    }
    let initialized_summary = init
        .repository
        .clone()
        .expect("successful init apply resolves repository");
    let mut changed_paths = init
        .operation
        .as_ref()
        .map(|operation| operation.changed_paths.clone())
        .unwrap_or_default();
    let mut diagnostics = init.diagnostics;
    let mut evidence = init.evidence;
    let mut extension_references = Vec::new();
    let mut extension_digests = Vec::new();

    for (reference, manifest) in bundled_manifests(rust_detected) {
        let extension_result = extension::enable_bundled(
            &root,
            manifest,
            &principal,
            &format!("setup:auto-detected:{reference}"),
        );
        diagnostics.extend(extension_result.diagnostics);
        evidence.extend(extension_result.evidence);
        if extension_result.exit_code != 0 {
            return QueryResult {
                repository: extension_result.repository.or(Some(initialized_summary)),
                diagnostics,
                evidence,
                data: json!({
                    "status": "partial",
                    "principal_ref": principal,
                    "authority_basis": input.authority_basis,
                    "completed_extension_references": extension_references,
                    "failed_extension_reference": reference,
                    "reconciliation": "rerun aos setup after resolving the reported extension finding",
                })
                .to_string(),
                plan,
                operation: Some(OperationSummary {
                    id: format!("op-setup-partial-{}", unix_timestamp()),
                    result: "partial".to_string(),
                    changed_paths,
                    verification: "repository initialization committed before extension failure"
                        .to_string(),
                    reconciliation: "required".to_string(),
                    audit_evidence: vec![format!("authority:{principal}")],
                    timestamp: unix_timestamp().to_string(),
                }),
                exit_code: if extension_result.exit_code == 8 {
                    8
                } else {
                    extension_result.exit_code
                },
                outcome: "partial".to_string(),
            };
        }
        if let Some(operation) = extension_result.operation {
            changed_paths.extend(operation.changed_paths);
        }
        let digest = extension_digest(&extension_result.data).unwrap_or_default();
        extension_references.push(reference.to_string());
        extension_digests.push(digest);
    }

    let fingerprint = setup_fingerprint(&extension_references, &extension_digests);
    let timestamp = unix_timestamp();
    if !setup_audit_exists(&root, &fingerprint) {
        match write_setup_audit(
            &root,
            &principal,
            &input.authority_basis,
            &extension_references,
            &extension_digests,
            &fingerprint,
            timestamp,
        ) {
            Ok(path) => changed_paths.push(path),
            Err(error) => {
                return QueryResult {
                    repository: Some(initialized_summary),
                    diagnostics: vec![Diagnostic::error("AOS-SETUP-AUDIT-WRITE-UNKNOWN", error)],
                    evidence: vec!["setup:audit-reconciliation-required".to_string()],
                    data,
                    plan,
                    operation: None,
                    exit_code: 8,
                    outcome: "unknown".to_string(),
                };
            }
        }
    }
    changed_paths.sort();
    changed_paths.dedup();
    diagnostics.push(Diagnostic::info(
        if changed_paths.is_empty() {
            "AOS-SETUP-ALREADY-COMPLETE"
        } else {
            "AOS-SETUP-COMPLETE"
        },
        "repository initialization and bundled reference extensions are verified",
    ));
    evidence.push("setup:bundled-manifest-digest-bound".to_string());
    evidence.push("setup:audit-recorded".to_string());
    QueryResult {
        repository: Some(initialized_summary),
        diagnostics,
        evidence,
        data: json!({
            "status": "complete",
            "principal_ref": principal,
            "authority_basis": input.authority_basis,
            "detected_project_types": if rust_detected { vec!["generic", "rust"] } else { vec!["generic"] },
            "extension_references": extension_references,
            "extension_digests": extension_digests,
            "setup_fingerprint": fingerprint,
        })
        .to_string(),
        plan,
        operation: Some(OperationSummary {
            id: format!("op-setup-{timestamp}"),
            result: "complete".to_string(),
            changed_paths,
            verification:
                "repository, bundled manifests, lifecycle, Governance, and Audit verified"
                    .to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec![format!("authority:{principal}")],
            timestamp: timestamp.to_string(),
        }),
        exit_code: 0,
        outcome: "success".to_string(),
    }
}

pub fn cancelled(path: Option<&Path>) -> QueryResult {
    let repository = repository::inspect(path)
        .ok()
        .map(|inspection| inspection.summary);
    QueryResult {
        repository,
        diagnostics: vec![Diagnostic::info(
            "AOS-SETUP-CANCELLED",
            "setup was cancelled before repository mutation",
        )],
        evidence: vec!["setup:user-cancelled".to_string()],
        data: json!({"status": "cancelled"}).to_string(),
        plan: None,
        operation: None,
        exit_code: 0,
        outcome: "cancelled".to_string(),
    }
}

fn setup_plan(init_plan: Option<PlanSummary>, extensions: &[&str]) -> Option<PlanSummary> {
    init_plan.map(|mut plan| {
        for reference in extensions {
            let id = reference.split('@').next().unwrap_or(reference);
            plan.affected_paths
                .push(format!(".aos/extensions/manifests/{reference}.json"));
            plan.affected_paths
                .push(format!(".aos/extensions/lifecycle/{id}.rN.json"));
        }
        plan.affected_paths.push(".aos/governance".to_string());
        plan.affected_paths.push(".aos/audit".to_string());
        plan.affected_paths.sort();
        plan.affected_paths.dedup();
        plan.ownership.push(OwnershipDecision {
            path: ".aos/extensions".to_string(),
            ownership: "aos".to_string(),
            decision: "write immutable bundled manifest and lifecycle revisions only".to_string(),
        });
        plan.recovery =
            "rerun setup idempotently; never roll back committed repository or extension history"
                .to_string();
        plan
    })
}

fn selected_extensions(rust_detected: bool) -> Vec<&'static str> {
    let mut selected = vec!["aos.reference.repository@1.0.0"];
    if rust_detected {
        selected.push("aos.reference.rust@1.0.0");
    }
    selected
}

fn bundled_manifests(rust_detected: bool) -> Vec<(&'static str, &'static str)> {
    let mut manifests = vec![("aos.reference.repository@1.0.0", GENERIC_MANIFEST)];
    if rust_detected {
        manifests.push(("aos.reference.rust@1.0.0", RUST_MANIFEST));
    }
    manifests
}

fn setup_data(
    principal: Option<&str>,
    authority_basis: &str,
    rust_detected: bool,
    extensions: &[&str],
) -> String {
    json!({
        "status": "planned",
        "principal_ref": principal,
        "authority_basis": authority_basis,
        "detected_project_types": if rust_detected { vec!["generic", "rust"] } else { vec!["generic"] },
        "reference_extensions": extensions,
        "confirmation_required": true,
    })
    .to_string()
}

fn resolve_principal(explicit: Option<&str>) -> Result<Option<String>, String> {
    if let Some(value) = explicit {
        if valid_principal(value) {
            return Ok(Some(value.to_string()));
        }
        return Err("explicit authority must be a non-empty safe reference".to_string());
    }
    let user = std::env::var(if cfg!(windows) { "USERNAME" } else { "USER" })
        .ok()
        .filter(|value| valid_local_user(value));
    match user {
        Some(value) => Ok(Some(format!("local-user:{value}"))),
        None => Err(
            "setup could not derive a safe OS user; provide --authority <PRINCIPAL>".to_string(),
        ),
    }
}

fn valid_local_user(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn valid_principal(value: &str) -> bool {
    !value.trim().is_empty()
        && value.len() <= 256
        && !value.chars().any(char::is_control)
        && !value.starts_with("runtime:")
        && !value.starts_with("provider:")
        && !value.starts_with("extension:")
        && value != "aos-cli"
        && value != "aos-runtime"
}

fn detects_rust(root: &Path) -> bool {
    let cargo = root.join("Cargo.toml");
    fs::symlink_metadata(cargo)
        .is_ok_and(|metadata| metadata.is_file() && !metadata.file_type().is_symlink())
}

fn display_root_path(value: &str) -> PathBuf {
    PathBuf::from(value.strip_prefix(r"\\?\").unwrap_or(value))
}

fn extension_digest(data: &str) -> Option<String> {
    let value: Value = serde_json::from_str(data).ok()?;
    value
        .pointer("/lifecycle/manifest_digest")
        .or_else(|| value.get("manifest_digest"))
        .and_then(Value::as_str)
        .map(str::to_string)
}

fn setup_fingerprint(references: &[String], digests: &[String]) -> String {
    let mut hasher = Sha256::new();
    for (reference, digest) in references.iter().zip(digests) {
        hasher.update(reference.as_bytes());
        hasher.update([0]);
        hasher.update(digest.as_bytes());
        hasher.update([0xff]);
    }
    format!("{:x}", hasher.finalize())
}

fn setup_audit_exists(root: &Path, fingerprint: &str) -> bool {
    fs::read_dir(root.join(".aos").join("audit"))
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .filter_map(|entry| fs::read_to_string(entry.path()).ok())
        .filter_map(|raw| serde_json::from_str::<Value>(&raw).ok())
        .any(|record| {
            record.get("event").and_then(Value::as_str) == Some("setup_completed")
                && record.get("setup_fingerprint").and_then(Value::as_str) == Some(fingerprint)
        })
}

#[allow(clippy::too_many_arguments)]
fn write_setup_audit(
    root: &Path,
    principal: &str,
    authority_basis: &str,
    references: &[String],
    digests: &[String],
    fingerprint: &str,
    timestamp: u64,
) -> Result<String, String> {
    let suffix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| error.to_string())?
        .as_nanos();
    let filename = format!(
        "{timestamp}-setup-completed-{}-{suffix}.json",
        std::process::id()
    );
    let relative = format!(".aos/audit/{filename}");
    let body = json!({
        "kind": "Audit",
        "id": filename,
        "revision": 1,
        "subject": "repository:setup",
        "event": "setup_completed",
        "principal": principal,
        "authority_basis": authority_basis,
        "timestamp_unix": timestamp,
        "outcome": "recorded",
        "extension_references": references,
        "extension_manifest_digests": digests,
        "setup_fingerprint": fingerprint,
        "secret_policy": "withheld",
    })
    .to_string();
    write_immutable(&root.join(&relative), &body, timestamp)?;
    Ok(relative)
}

fn write_immutable(path: &Path, content: &str, nonce: u64) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "target has no parent".to_string())?;
    fs::create_dir_all(parent).map_err(|error| format!("create directory: {error}"))?;
    if path.exists() {
        return Err("immutable target already exists".to_string());
    }
    let temporary = parent.join(format!(".tmp-setup-{nonce}-{}.json", std::process::id()));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(|error| format!("create temporary audit: {error}"))?;
    file.write_all(content.as_bytes())
        .map_err(|error| format!("write temporary audit: {error}"))?;
    file.sync_all()
        .map_err(|error| format!("sync temporary audit: {error}"))?;
    drop(file);
    fs::rename(&temporary, path).map_err(|error| format!("commit audit: {error}"))
}

fn init_failure(result: repository::InitResult) -> QueryResult {
    QueryResult {
        repository: result.repository,
        diagnostics: result.diagnostics,
        evidence: result.evidence,
        data: "null".to_string(),
        plan: result.plan,
        operation: result.operation,
        exit_code: result.exit_code,
        outcome: result.outcome,
    }
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}
