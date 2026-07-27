use crate::intelligence::QueryResult;
use crate::model::{
    Diagnostic, OperationSummary, OwnershipDecision, PlanSummary, RepositorySummary,
};
use crate::repository;
use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const EXTENSION_CONTRACT_VERSION: &str = "AOS-SPEC-006";
pub const EXTENSION_PROTOCOL: &str = "aos.extension.readonly@1.0.0";
pub const EXTENSION_PROTOCOL_ID: &str = "aos.extension.readonly";
const EXTENSION_SCHEMA_VERSION: &str = "1";
const HOST_REPOSITORY_SUMMARY: &str = "repository.summary@1.0.0";
const HOST_RUST_CARGO_SUMMARY: &str = "rust.cargo_manifest.summary@1.0.0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExtensionAction {
    Discover,
    Validate,
    Inspect,
    Enable,
    Disable,
    Quarantine,
    Remove,
}

impl ExtensionAction {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "discover" => Ok(Self::Discover),
            "validate" => Ok(Self::Validate),
            "inspect" => Ok(Self::Inspect),
            "enable" => Ok(Self::Enable),
            "disable" => Ok(Self::Disable),
            "quarantine" => Ok(Self::Quarantine),
            "remove" => Ok(Self::Remove),
            _ => Err(format!("unknown extension action '{value}'")),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Discover => "discover",
            Self::Validate => "validate",
            Self::Inspect => "inspect",
            Self::Enable => "enable",
            Self::Disable => "disable",
            Self::Quarantine => "quarantine",
            Self::Remove => "remove",
        }
    }

    pub fn is_read_only(self) -> bool {
        matches!(self, Self::Discover | Self::Validate | Self::Inspect)
    }
}

#[derive(Debug)]
pub struct ExtensionInput {
    pub action: ExtensionAction,
    pub path: Option<PathBuf>,
    pub manifest_path: Option<PathBuf>,
    pub extension_id: Option<String>,
    pub extension_version: Option<String>,
    pub apply: bool,
    pub authority: Option<String>,
    pub evidence: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExtensionManifest {
    pub schema_version: String,
    pub contract_version: String,
    pub id: String,
    pub version: String,
    #[serde(rename = "type")]
    pub extension_type: String,
    pub owner: String,
    pub namespace: String,
    pub aos_compatibility: String,
    pub dependencies: Vec<ExtensionDependency>,
    pub capabilities: Vec<ExtensionCapability>,
    pub data_ownership: String,
    pub security: ExtensionSecurity,
    pub failure_behavior: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExtensionDependency {
    pub id: String,
    pub version_requirement: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExtensionCapability {
    pub name: String,
    pub host_operation: String,
    pub operation_class: String,
    pub resource_scopes: Vec<String>,
    pub idempotent: bool,
    pub retryable: bool,
    pub compensatable: bool,
    pub reconciliation_required: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ExtensionSecurity {
    pub network: bool,
    pub secrets: bool,
    pub process: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct LifecycleRecord {
    kind: String,
    id: String,
    version: String,
    revision: u64,
    previous_revision: Option<u64>,
    status: String,
    retired: bool,
    manifest_reference: String,
    manifest_digest: String,
    principal_ref: String,
    authority_basis_ref: String,
    timestamp_unix: u64,
    reason: String,
}

#[derive(Clone, Debug)]
struct ManifestBundle {
    manifest: ExtensionManifest,
    canonical_json: String,
    digest: String,
}

#[derive(Clone, Debug)]
pub struct WorkBinding {
    pub extension_reference: String,
    pub manifest_digest: String,
    pub capability_reference: String,
    pub resource_scope: String,
}

#[derive(Clone, Debug)]
pub struct ExtensionExecution {
    pub result_relative: String,
    pub result_json: String,
    pub evidence_reference: String,
}

#[derive(Clone, Debug)]
pub struct ExtensionError {
    pub code: &'static str,
    pub message: String,
    pub evidence: &'static str,
    pub exit_code: u8,
    pub quarantine: bool,
}

pub fn execute(input: ExtensionInput) -> QueryResult {
    let (summary, root) = match repository_context(input.path.as_deref()) {
        Ok(value) => value,
        Err(result) => return result,
    };

    match input.action {
        ExtensionAction::Discover => discover(&summary, &root, input.manifest_path.as_deref()),
        ExtensionAction::Validate => validate(&summary, &root, input.manifest_path.as_deref()),
        ExtensionAction::Inspect => inspect(
            &summary,
            &root,
            input.extension_id.as_deref(),
            input.extension_version.as_deref(),
        ),
        ExtensionAction::Enable => enable(&summary, &root, input),
        ExtensionAction::Disable | ExtensionAction::Quarantine | ExtensionAction::Remove => {
            transition(&summary, &root, input)
        }
    }
}

fn discover(summary: &RepositorySummary, root: &Path, path: Option<&Path>) -> QueryResult {
    let bundle = match load_candidate(root, path) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    if let Err(error) = validate_manifest_shape(&bundle.manifest) {
        return extension_failure(summary, error);
    }
    success(
        summary,
        "AOS-EXTENSION-DISCOVERED",
        "extension manifest discovered without execution or mutation",
        vec!["extension:read-only-discovery".to_string()],
        json!({
            "lifecycle": "discovered",
            "manifest": bundle.manifest,
            "manifest_digest": bundle.digest,
        }),
        None,
    )
}

fn validate(summary: &RepositorySummary, root: &Path, path: Option<&Path>) -> QueryResult {
    let bundle = match load_candidate(root, path) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    if let Err(error) = validate_bundle(root, &bundle) {
        return extension_failure(summary, error);
    }
    success(
        summary,
        "AOS-EXTENSION-VALIDATED",
        "extension manifest, compatibility, dependencies, namespace, and capabilities are valid",
        vec![
            "extension:contract-valid".to_string(),
            "extension:compatibility-valid".to_string(),
            "extension:capability-bounded".to_string(),
        ],
        json!({
            "lifecycle": "validated",
            "manifest": bundle.manifest,
            "manifest_digest": bundle.digest,
        }),
        None,
    )
}

fn inspect(
    summary: &RepositorySummary,
    root: &Path,
    extension_id: Option<&str>,
    extension_version: Option<&str>,
) -> QueryResult {
    let extension_id = match required(extension_id, "extension id") {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    let lifecycle = match latest_lifecycle(root, extension_id) {
        Some(value) => value,
        None => {
            return extension_failure(
                summary,
                error(
                    "AOS-EXTENSION-NOT-FOUND",
                    "no installed extension lifecycle matched the requested id",
                    "extension:reference-unresolved",
                    4,
                ),
            );
        }
    };
    let version = extension_version.unwrap_or(&lifecycle.version);
    let bundle = match load_snapshot(root, extension_id, version) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    success(
        summary,
        "AOS-EXTENSION-INSPECTED",
        "installed extension manifest and lifecycle inspected read-only",
        vec!["extension:inspect".to_string()],
        json!({
            "manifest": bundle.manifest,
            "manifest_digest": bundle.digest,
            "lifecycle": lifecycle,
        }),
        None,
    )
}

fn enable(summary: &RepositorySummary, root: &Path, input: ExtensionInput) -> QueryResult {
    let bundle = match load_candidate(root, input.manifest_path.as_deref()) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    if let Err(error) = validate_bundle(root, &bundle) {
        return extension_failure(summary, error);
    }
    let manifest_relative = manifest_relative(&bundle.manifest.id, &bundle.manifest.version);
    let lifecycle_relative = format!(
        ".aos/extensions/lifecycle/{}.r{}.json",
        bundle.manifest.id,
        next_lifecycle_revision(root, &bundle.manifest.id)
    );
    if !input.apply {
        return plan_result(
            summary,
            ExtensionAction::Enable,
            vec![manifest_relative, lifecycle_relative],
        );
    }
    let (principal, evidence) = match mutation_authority(&input) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };

    if let Some(current) = latest_lifecycle(root, &bundle.manifest.id)
        && current.status == "enabled"
        && !current.retired
    {
        if current.version != bundle.manifest.version {
            return extension_failure(
                summary,
                error(
                    "AOS-EXTENSION-VERSION-CONFLICT",
                    "disable the currently enabled version before enabling another version",
                    "extension:single-enabled-version",
                    5,
                ),
            );
        }
        if current.manifest_digest == bundle.digest {
            return success(
                summary,
                "AOS-EXTENSION-ALREADY-ENABLED",
                "extension is already enabled with the same immutable manifest digest",
                vec!["extension:idempotent-enable".to_string()],
                json!({"lifecycle": current, "manifest": bundle.manifest}),
                None,
            );
        }
    }

    let timestamp = unix_timestamp();
    let manifest_path = root.join(&manifest_relative);
    if manifest_path.exists() {
        let existing = match fs::read_to_string(&manifest_path) {
            Ok(value) => value,
            Err(read_error) => {
                return extension_failure(
                    summary,
                    error(
                        "AOS-EXTENSION-MANIFEST-READ-FAILED",
                        read_error.to_string(),
                        "extension:manifest-read",
                        8,
                    ),
                );
            }
        };
        if sha256(existing.as_bytes()) != bundle.digest {
            return extension_failure(
                summary,
                error(
                    "AOS-EXTENSION-MANIFEST-CONFLICT",
                    "an immutable manifest snapshot exists with different content",
                    "extension:immutable-manifest",
                    5,
                ),
            );
        }
    } else if let Err(write_error) =
        write_immutable(&manifest_path, &bundle.canonical_json, timestamp)
    {
        return extension_failure(
            summary,
            unknown_write_error(
                "AOS-EXTENSION-MANIFEST-WRITE-UNKNOWN",
                write_error,
                "extension:manifest-reconciliation-required",
            ),
        );
    }

    let mut changed_paths = vec![manifest_relative.clone()];
    let validated_revision = next_lifecycle_revision(root, &bundle.manifest.id);
    let validated = lifecycle_record(
        &bundle,
        validated_revision,
        "validated",
        false,
        principal,
        evidence,
        timestamp,
        "manifest and compatibility validated",
    );
    let validated_relative = lifecycle_relative_for(&bundle.manifest.id, validated_revision);
    if let Err(write_error) =
        write_json_immutable(&root.join(&validated_relative), &validated, timestamp)
    {
        return extension_failure(
            summary,
            unknown_write_error(
                "AOS-EXTENSION-LIFECYCLE-WRITE-UNKNOWN",
                write_error,
                "extension:lifecycle-reconciliation-required",
            ),
        );
    }
    changed_paths.push(validated_relative);

    let enabled_revision = validated_revision + 1;
    let enabled = lifecycle_record(
        &bundle,
        enabled_revision,
        "enabled",
        false,
        principal,
        evidence,
        timestamp + 1,
        "explicit Governance enablement",
    );
    let enabled_relative = lifecycle_relative_for(&bundle.manifest.id, enabled_revision);
    if let Err(write_error) =
        write_json_immutable(&root.join(&enabled_relative), &enabled, timestamp + 1)
    {
        return extension_failure(
            summary,
            unknown_write_error(
                "AOS-EXTENSION-LIFECYCLE-WRITE-UNKNOWN",
                write_error,
                "extension:lifecycle-reconciliation-required",
            ),
        );
    }
    changed_paths.push(enabled_relative);

    match governance_and_audit(
        root,
        &bundle.manifest.id,
        &bundle.manifest.version,
        "extension_enable",
        principal,
        evidence,
        "enabled",
        timestamp + 2,
    ) {
        Ok(paths) => changed_paths.extend(paths),
        Err(write_error) => {
            return extension_failure(
                summary,
                unknown_write_error(
                    "AOS-EXTENSION-AUDIT-WRITE-UNKNOWN",
                    write_error,
                    "extension:audit-reconciliation-required",
                ),
            );
        }
    }

    let operation = OperationSummary {
        id: format!("op-extension-enable-{timestamp}"),
        result: "enabled".to_string(),
        changed_paths,
        verification:
            "manifest, compatibility, dependencies, capability scope, and authority verified"
                .to_string(),
        reconciliation: "not_required".to_string(),
        audit_evidence: vec![format!("evidence:{evidence}")],
        timestamp: timestamp.to_string(),
    };
    success(
        summary,
        "AOS-EXTENSION-ENABLED",
        "extension enabled under explicit Governance authority",
        vec![
            "extension:manifest-snapshot".to_string(),
            "extension:lifecycle-enabled".to_string(),
            "extension:governance-recorded".to_string(),
        ],
        json!({"manifest": bundle.manifest, "lifecycle": enabled}),
        Some(operation),
    )
}

fn transition(summary: &RepositorySummary, root: &Path, input: ExtensionInput) -> QueryResult {
    let extension_id = match required(input.extension_id.as_deref(), "extension id") {
        Ok(value) => value.to_string(),
        Err(error) => return extension_failure(summary, error),
    };
    let action = input.action;
    if !input.apply {
        let next_revision = next_lifecycle_revision(root, &extension_id);
        return plan_result(
            summary,
            action,
            vec![lifecycle_relative_for(&extension_id, next_revision)],
        );
    }
    let (principal, evidence) = match mutation_authority(&input) {
        Ok(value) => value,
        Err(error) => return extension_failure(summary, error),
    };
    let current = match latest_lifecycle(root, &extension_id) {
        Some(value) => value,
        None => {
            return extension_failure(
                summary,
                error(
                    "AOS-EXTENSION-NOT-FOUND",
                    "extension lifecycle does not exist",
                    "extension:reference-unresolved",
                    4,
                ),
            );
        }
    };
    let (next_status, retired) = match action {
        ExtensionAction::Disable
            if matches!(current.status.as_str(), "enabled" | "quarantined") =>
        {
            ("disabled", false)
        }
        ExtensionAction::Quarantine if current.status == "enabled" => ("quarantined", false),
        ExtensionAction::Remove
            if matches!(current.status.as_str(), "disabled" | "quarantined") =>
        {
            ("disabled", true)
        }
        _ => {
            return extension_failure(
                summary,
                error(
                    "AOS-EXTENSION-TRANSITION-INVALID",
                    format!(
                        "cannot apply {} while extension lifecycle is {}",
                        action.as_str(),
                        current.status
                    ),
                    "extension:state-machine",
                    4,
                ),
            );
        }
    };
    let timestamp = unix_timestamp();
    let revision = current.revision + 1;
    let next = LifecycleRecord {
        kind: "ExtensionLifecycle".to_string(),
        id: current.id.clone(),
        version: current.version.clone(),
        revision,
        previous_revision: Some(current.revision),
        status: next_status.to_string(),
        retired,
        manifest_reference: current.manifest_reference.clone(),
        manifest_digest: current.manifest_digest.clone(),
        principal_ref: principal.to_string(),
        authority_basis_ref: format!("evidence:{evidence}"),
        timestamp_unix: timestamp,
        reason: format!("explicit extension {}", action.as_str()),
    };
    let relative = lifecycle_relative_for(&extension_id, revision);
    if let Err(write_error) = write_json_immutable(&root.join(&relative), &next, timestamp) {
        return extension_failure(
            summary,
            unknown_write_error(
                "AOS-EXTENSION-LIFECYCLE-WRITE-UNKNOWN",
                write_error,
                "extension:lifecycle-reconciliation-required",
            ),
        );
    }
    let mut paths = vec![relative];
    match governance_and_audit(
        root,
        &current.id,
        &current.version,
        &format!("extension_{}", action.as_str()),
        principal,
        evidence,
        if retired { "retired" } else { next_status },
        timestamp + 1,
    ) {
        Ok(audit_paths) => paths.extend(audit_paths),
        Err(write_error) => {
            return extension_failure(
                summary,
                unknown_write_error(
                    "AOS-EXTENSION-AUDIT-WRITE-UNKNOWN",
                    write_error,
                    "extension:audit-reconciliation-required",
                ),
            );
        }
    }
    success(
        summary,
        "AOS-EXTENSION-LIFECYCLE-UPDATED",
        format!("extension lifecycle changed to {next_status}"),
        vec![
            "extension:immutable-lifecycle".to_string(),
            "extension:governance-recorded".to_string(),
        ],
        json!({"lifecycle": next}),
        Some(OperationSummary {
            id: format!("op-extension-{}-{timestamp}", action.as_str()),
            result: if retired {
                "retired".to_string()
            } else {
                next_status.to_string()
            },
            changed_paths: paths,
            verification: "authority and lifecycle transition verified".to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec![format!("evidence:{evidence}")],
            timestamp: timestamp.to_string(),
        }),
    )
}

pub fn resolve_for_work(
    root: &Path,
    extension_reference: &str,
    capability_name: &str,
    requested_scope: &str,
) -> Result<WorkBinding, ExtensionError> {
    if requested_scope != "." {
        return Err(error(
            "AOS-EXTENSION-SCOPE-DENIED",
            "the declarative P6 runtime accepts only repository-local Work scope '.'",
            "extension:scope-denied",
            7,
        ));
    }
    let (extension_id, version) = parse_extension_reference(extension_reference)?;
    let lifecycle = latest_lifecycle(root, extension_id).ok_or_else(|| {
        error(
            "AOS-EXTENSION-NOT-ENABLED",
            "extension lifecycle does not exist",
            "extension:lifecycle-required",
            7,
        )
    })?;
    if lifecycle.version != version || lifecycle.status != "enabled" || lifecycle.retired {
        return Err(error(
            "AOS-EXTENSION-NOT-ENABLED",
            "the requested extension version is not enabled",
            "extension:lifecycle-denied",
            7,
        ));
    }
    let bundle = load_snapshot(root, extension_id, version)?;
    validate_manifest_shape(&bundle.manifest)?;
    if lifecycle.manifest_digest != bundle.digest {
        return Err(ExtensionError {
            code: "AOS-EXTENSION-INTEGRITY-MISMATCH",
            message: "enabled lifecycle digest does not match immutable manifest snapshot"
                .to_string(),
            evidence: "extension:integrity-mismatch",
            exit_code: 4,
            quarantine: true,
        });
    }
    let capability = bundle
        .manifest
        .capabilities
        .iter()
        .find(|candidate| candidate.name == capability_name)
        .ok_or_else(|| {
            error(
                "AOS-EXTENSION-CAPABILITY-DENIED",
                "capability is not declared by the enabled extension",
                "extension:capability-intersection",
                7,
            )
        })?;
    validate_capability(&bundle.manifest.namespace, capability)?;
    Ok(WorkBinding {
        extension_reference: format!("{}@{}", bundle.manifest.id, bundle.manifest.version),
        manifest_digest: bundle.digest,
        capability_reference: capability.name.clone(),
        resource_scope: capability.resource_scopes.join(","),
    })
}

#[allow(clippy::too_many_arguments)]
pub fn execute_for_work(
    root: &Path,
    extension_reference: &str,
    expected_digest: &str,
    capability_name: &str,
    expected_resource_scope: &str,
    governance_reference: &str,
    context_snapshot: &str,
    work_id: &str,
    work_revision: u64,
    run_revision: u64,
) -> Result<ExtensionExecution, ExtensionError> {
    let binding = resolve_for_work(root, extension_reference, capability_name, ".")?;
    if binding.manifest_digest != expected_digest {
        return Err(ExtensionError {
            code: "AOS-EXTENSION-INTEGRITY-MISMATCH",
            message: "Work manifest digest does not match the enabled immutable snapshot"
                .to_string(),
            evidence: "extension:integrity-mismatch",
            exit_code: 4,
            quarantine: true,
        });
    }
    if binding.resource_scope != expected_resource_scope {
        return Err(ExtensionError {
            code: "AOS-EXTENSION-SCOPE-DENIED",
            message: "Work resource scope does not match the enabled manifest capability"
                .to_string(),
            evidence: "extension:scope-denied",
            exit_code: 7,
            quarantine: true,
        });
    }
    let (extension_id, version) = parse_extension_reference(extension_reference)?;
    let bundle = load_snapshot(root, extension_id, version)?;
    let capability = bundle
        .manifest
        .capabilities
        .iter()
        .find(|candidate| candidate.name == capability_name)
        .ok_or_else(|| {
            error(
                "AOS-EXTENSION-CAPABILITY-DENIED",
                "capability is not declared by the extension manifest",
                "extension:capability-intersection",
                7,
            )
        })?;
    let (resource_reference, input_digest, output) = match capability.host_operation.as_str() {
        HOST_REPOSITORY_SUMMARY => execute_repository_summary(root)?,
        HOST_RUST_CARGO_SUMMARY => execute_rust_cargo_summary(root)?,
        _ => {
            return Err(error(
                "AOS-EXTENSION-HOST-OPERATION-UNSUPPORTED",
                "extension requested a host operation outside the P6 allowlist",
                "extension:host-operation-denied",
                6,
            ));
        }
    };
    let timestamp = unix_timestamp();
    let result = json!({
        "kind": "ExtensionResult",
        "contract_version": EXTENSION_CONTRACT_VERSION,
        "authority": "proposed",
        "lifecycle": "active",
        "extension_reference": extension_reference,
        "manifest_digest": expected_digest,
        "capability_reference": capability_name,
        "host_operation": capability.host_operation,
        "work_reference": format!("{work_id}@{work_revision}"),
        "run_reference": format!("{work_id}-run@{run_revision}"),
        "protocol_reference": EXTENSION_PROTOCOL,
        "governance_reference": governance_reference,
        "context_snapshot": context_snapshot,
        "resource_references": [resource_reference],
        "input_digest": input_digest,
        "status": "succeeded",
        "proposed_output": output,
        "verification_evidence": "aos:declarative-local-host-adapter",
        "timestamp_unix": timestamp,
    });
    let result_json = serde_json::to_string(&result).expect("serializable extension result");
    let relative = format!(".aos/extensions/results/{work_id}.r{run_revision}.json");
    write_immutable(&root.join(&relative), &result_json, timestamp).map_err(|write_error| {
        unknown_write_error(
            "AOS-EXTENSION-RESULT-WRITE-UNKNOWN",
            write_error,
            "extension:result-reconciliation-required",
        )
    })?;
    Ok(ExtensionExecution {
        result_relative: relative.clone(),
        result_json,
        evidence_reference: format!("extension-result:{relative}"),
    })
}

pub fn quarantine_for_safety(
    root: &Path,
    extension_reference: &str,
    reason: &str,
) -> Result<Vec<String>, String> {
    let (extension_id, version) =
        parse_extension_reference(extension_reference).map_err(|error| error.message)?;
    let current = latest_lifecycle(root, extension_id)
        .ok_or_else(|| "extension lifecycle not found for quarantine".to_string())?;
    if current.version != version || current.retired {
        return Err("extension version is not the active lifecycle subject".to_string());
    }
    if current.status == "quarantined" {
        return Ok(Vec::new());
    }
    let timestamp = unix_timestamp();
    let next = LifecycleRecord {
        kind: "ExtensionLifecycle".to_string(),
        id: current.id.clone(),
        version: current.version.clone(),
        revision: current.revision + 1,
        previous_revision: Some(current.revision),
        status: "quarantined".to_string(),
        retired: false,
        manifest_reference: current.manifest_reference,
        manifest_digest: current.manifest_digest,
        principal_ref: "aos-runtime".to_string(),
        authority_basis_ref: "policy:fail-closed".to_string(),
        timestamp_unix: timestamp,
        reason: reason.to_string(),
    };
    let relative = lifecycle_relative_for(extension_id, next.revision);
    write_json_immutable(&root.join(&relative), &next, timestamp)?;
    let audit = audit_event(
        root,
        extension_id,
        version,
        "extension_auto_quarantined",
        "aos-runtime",
        "policy:fail-closed",
        reason,
        timestamp + 1,
    )?;
    Ok(vec![relative, audit])
}

fn execute_repository_summary(root: &Path) -> Result<(String, String, Value), ExtensionError> {
    let relative = ".aos/repository.json";
    let path = root.join(relative);
    let bytes = fs::read(&path).map_err(|read_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            read_error.to_string(),
            "extension:repository-summary-input",
            4,
        )
    })?;
    let repository: Value = serde_json::from_slice(&bytes).map_err(|parse_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            parse_error.to_string(),
            "extension:repository-summary-input",
            4,
        )
    })?;
    let output = json!({
        "project_id": repository.get("project_id").and_then(Value::as_str),
        "repository_id": repository.get("repository_id").and_then(Value::as_str),
        "status": repository.get("status").and_then(Value::as_str),
        "contract_version": repository.get("contract_version").and_then(Value::as_str),
    });
    Ok((relative.to_string(), sha256(&bytes), output))
}

fn execute_rust_cargo_summary(root: &Path) -> Result<(String, String, Value), ExtensionError> {
    let relative = "Cargo.toml";
    let root = fs::canonicalize(root).map_err(|canonical_error| {
        error(
            "AOS-EXTENSION-ROOT-UNKNOWN",
            canonical_error.to_string(),
            "extension:repository-boundary",
            3,
        )
    })?;
    let path = root.join(relative);
    let canonical = fs::canonicalize(&path).map_err(|canonical_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            canonical_error.to_string(),
            "extension:rust-cargo-input",
            4,
        )
    })?;
    if !canonical.starts_with(&root) {
        return Err(error(
            "AOS-EXTENSION-SCOPE-DENIED",
            "Cargo.toml resolves outside the Repository Root",
            "extension:path-escape-denied",
            7,
        ));
    }
    let bytes = fs::read(&canonical).map_err(|read_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            read_error.to_string(),
            "extension:rust-cargo-input",
            4,
        )
    })?;
    let document = String::from_utf8(bytes.clone()).map_err(|utf8_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            utf8_error.to_string(),
            "extension:rust-cargo-input",
            4,
        )
    })?;
    let parsed: toml::Value = toml::from_str(&document).map_err(|parse_error| {
        error(
            "AOS-EXTENSION-ADAPTER-INPUT-INVALID",
            parse_error.to_string(),
            "extension:rust-cargo-input",
            4,
        )
    })?;
    let package = parsed.get("package").and_then(toml::Value::as_table);
    let workspace = parsed.get("workspace").and_then(toml::Value::as_table);
    let workspace_package = workspace
        .and_then(|table| table.get("package"))
        .and_then(toml::Value::as_table);
    let mut members = workspace
        .and_then(|table| table.get("members"))
        .and_then(toml::Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(toml::Value::as_str)
                .map(str::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    members.sort();
    let output = json!({
        "package_name": package.and_then(|table| table.get("name")).and_then(toml::Value::as_str),
        "package_version": package
            .and_then(|table| table.get("version"))
            .or_else(|| workspace_package.and_then(|table| table.get("version")))
            .and_then(toml::Value::as_str),
        "edition": package
            .and_then(|table| table.get("edition"))
            .or_else(|| workspace_package.and_then(|table| table.get("edition")))
            .and_then(toml::Value::as_str),
        "rust_version": package
            .and_then(|table| table.get("rust-version"))
            .or_else(|| workspace_package.and_then(|table| table.get("rust-version")))
            .and_then(toml::Value::as_str),
        "workspace_root": workspace.is_some(),
        "workspace_members": members,
        "workspace_member_count": members.len(),
    });
    Ok((relative.to_string(), sha256(&bytes), output))
}

fn load_candidate(root: &Path, path: Option<&Path>) -> Result<ManifestBundle, ExtensionError> {
    let path = path.ok_or_else(|| {
        error(
            "AOS-EXTENSION-MANIFEST-REQUIRED",
            "extension action requires --manifest <PATH>",
            "extension:manifest-required",
            2,
        )
    })?;
    let root = fs::canonicalize(root).map_err(|canonical_error| {
        error(
            "AOS-EXTENSION-ROOT-UNKNOWN",
            canonical_error.to_string(),
            "extension:repository-boundary",
            3,
        )
    })?;
    let candidate = if path.is_absolute() {
        path.to_path_buf()
    } else {
        root.join(path)
    };
    let candidate = fs::canonicalize(&candidate).map_err(|canonical_error| {
        error(
            "AOS-EXTENSION-MANIFEST-READ-FAILED",
            canonical_error.to_string(),
            "extension:manifest-read",
            4,
        )
    })?;
    if !candidate.starts_with(&root) {
        return Err(error(
            "AOS-EXTENSION-MANIFEST-SCOPE-DENIED",
            "extension manifest must be inside the selected Repository Root",
            "extension:path-escape-denied",
            7,
        ));
    }
    load_manifest_file(&candidate)
}

fn load_snapshot(root: &Path, id: &str, version: &str) -> Result<ManifestBundle, ExtensionError> {
    load_manifest_file(&root.join(manifest_relative(id, version)))
}

fn load_manifest_file(path: &Path) -> Result<ManifestBundle, ExtensionError> {
    let raw = fs::read_to_string(path).map_err(|read_error| {
        error(
            "AOS-EXTENSION-MANIFEST-READ-FAILED",
            read_error.to_string(),
            "extension:manifest-read",
            4,
        )
    })?;
    let manifest: ExtensionManifest = serde_json::from_str(&raw).map_err(|parse_error| {
        error(
            "AOS-EXTENSION-MANIFEST-INVALID",
            parse_error.to_string(),
            "extension:manifest-invalid",
            4,
        )
    })?;
    let canonical_json = serde_json::to_string(&manifest).expect("serializable extension manifest");
    let digest = sha256(canonical_json.as_bytes());
    Ok(ManifestBundle {
        manifest,
        canonical_json,
        digest,
    })
}

fn validate_bundle(root: &Path, bundle: &ManifestBundle) -> Result<(), ExtensionError> {
    validate_manifest_shape(&bundle.manifest)?;
    let enabled = enabled_manifests(root)?;
    for existing in &enabled {
        if existing.manifest.namespace == bundle.manifest.namespace
            && existing.manifest.id != bundle.manifest.id
        {
            return Err(error(
                "AOS-EXTENSION-NAMESPACE-CONFLICT",
                "extension namespace collides with an enabled extension",
                "extension:namespace-collision",
                4,
            ));
        }
    }
    let versions = enabled
        .iter()
        .map(|candidate| {
            (
                candidate.manifest.id.clone(),
                Version::parse(&candidate.manifest.version)
                    .expect("enabled manifests passed shape validation"),
            )
        })
        .collect::<BTreeMap<_, _>>();
    for dependency in &bundle.manifest.dependencies {
        let requirement = VersionReq::parse(&dependency.version_requirement).map_err(|_| {
            error(
                "AOS-EXTENSION-DEPENDENCY-INVALID",
                "dependency version requirement is not valid SemVer",
                "extension:dependency-invalid",
                4,
            )
        })?;
        match versions.get(&dependency.id) {
            Some(version) if requirement.matches(version) => {}
            Some(_) => {
                return Err(error(
                    "AOS-EXTENSION-DEPENDENCY-CONFLICT",
                    format!(
                        "dependency {} does not match the required version",
                        dependency.id
                    ),
                    "extension:dependency-conflict",
                    4,
                ));
            }
            None => {
                return Err(error(
                    "AOS-EXTENSION-DEPENDENCY-MISSING",
                    format!("dependency {} is not enabled", dependency.id),
                    "extension:dependency-missing",
                    4,
                ));
            }
        }
    }
    validate_dependency_graph(bundle, &enabled)
}

fn validate_manifest_shape(manifest: &ExtensionManifest) -> Result<(), ExtensionError> {
    if manifest.schema_version != EXTENSION_SCHEMA_VERSION
        || manifest.contract_version != EXTENSION_CONTRACT_VERSION
    {
        return Err(error(
            "AOS-EXTENSION-CONTRACT-UNSUPPORTED",
            "manifest schema or Extension contract version is unsupported",
            "extension:unsupported-contract",
            6,
        ));
    }
    if !valid_id(&manifest.id)
        || !valid_namespace(&manifest.namespace)
        || manifest.owner.trim().is_empty()
        || manifest.data_ownership != manifest.namespace
    {
        return Err(error(
            "AOS-EXTENSION-IDENTITY-INVALID",
            "extension identity, owner, namespace, or data ownership is invalid",
            "extension:identity-invalid",
            4,
        ));
    }
    if !matches!(
        manifest.extension_type.as_str(),
        "domain" | "language" | "framework" | "provider" | "tool" | "integration"
    ) {
        return Err(error(
            "AOS-EXTENSION-TYPE-INVALID",
            "extension type is unsupported",
            "extension:type-invalid",
            4,
        ));
    }
    Version::parse(&manifest.version).map_err(|_| {
        error(
            "AOS-EXTENSION-VERSION-INVALID",
            "extension version must be valid SemVer",
            "extension:version-invalid",
            4,
        )
    })?;
    let compatibility = VersionReq::parse(&manifest.aos_compatibility).map_err(|_| {
        error(
            "AOS-EXTENSION-COMPATIBILITY-INVALID",
            "AOS compatibility range must be valid SemVer",
            "extension:compatibility-invalid",
            4,
        )
    })?;
    let core_version = Version::parse(env!("CARGO_PKG_VERSION")).expect("Cargo package SemVer");
    if !compatibility.matches(&core_version) {
        return Err(error(
            "AOS-EXTENSION-CORE-INCOMPATIBLE",
            "extension compatibility range does not include this AOS version",
            "extension:core-incompatible",
            6,
        ));
    }
    if manifest.failure_behavior != "fail_closed"
        || manifest.security.network
        || manifest.security.secrets
        || manifest.security.process
    {
        return Err(error(
            "AOS-EXTENSION-SECURITY-INVALID",
            "P6 extensions must be fail-closed with network, secrets, and process access disabled",
            "extension:security-boundary",
            4,
        ));
    }
    if manifest.capabilities.is_empty() {
        return Err(error(
            "AOS-EXTENSION-CAPABILITY-REQUIRED",
            "extension must declare at least one bounded capability",
            "extension:capability-required",
            4,
        ));
    }
    let mut capability_names = BTreeSet::new();
    for capability in &manifest.capabilities {
        if !capability_names.insert(&capability.name) {
            return Err(error(
                "AOS-EXTENSION-CAPABILITY-DUPLICATE",
                "extension capability names must be unique",
                "extension:capability-duplicate",
                4,
            ));
        }
        validate_capability(&manifest.namespace, capability)?;
    }
    let mut dependencies = BTreeSet::new();
    for dependency in &manifest.dependencies {
        if !valid_id(&dependency.id)
            || dependency.id == manifest.id
            || !dependencies.insert(&dependency.id)
            || VersionReq::parse(&dependency.version_requirement).is_err()
        {
            return Err(error(
                "AOS-EXTENSION-DEPENDENCY-INVALID",
                "extension dependency identity or version requirement is invalid",
                "extension:dependency-invalid",
                4,
            ));
        }
    }
    Ok(())
}

fn validate_capability(
    namespace: &str,
    capability: &ExtensionCapability,
) -> Result<(), ExtensionError> {
    if !capability.name.starts_with(&format!("{namespace}."))
        || capability.operation_class != "read_only"
        || capability.compensatable
        || capability.resource_scopes.is_empty()
    {
        return Err(error(
            "AOS-EXTENSION-CAPABILITY-INVALID",
            "capability namespace, operation class, compensation, or scope is invalid",
            "extension:capability-invalid",
            4,
        ));
    }
    let expected_scope = match capability.host_operation.as_str() {
        HOST_REPOSITORY_SUMMARY => "repository:.",
        HOST_RUST_CARGO_SUMMARY => "file:Cargo.toml",
        _ => {
            return Err(error(
                "AOS-EXTENSION-HOST-OPERATION-UNSUPPORTED",
                "host operation is outside the declarative P6 allowlist",
                "extension:host-operation-denied",
                6,
            ));
        }
    };
    if capability.resource_scopes.len() != 1 || capability.resource_scopes[0] != expected_scope {
        return Err(error(
            "AOS-EXTENSION-SCOPE-DENIED",
            "capability resource scope does not match its allowlisted host operation",
            "extension:scope-denied",
            7,
        ));
    }
    Ok(())
}

fn validate_dependency_graph(
    candidate: &ManifestBundle,
    enabled: &[ManifestBundle],
) -> Result<(), ExtensionError> {
    let mut graph = enabled
        .iter()
        .map(|bundle| {
            (
                bundle.manifest.id.clone(),
                bundle
                    .manifest
                    .dependencies
                    .iter()
                    .map(|dependency| dependency.id.clone())
                    .collect::<Vec<_>>(),
            )
        })
        .collect::<BTreeMap<_, _>>();
    graph.insert(
        candidate.manifest.id.clone(),
        candidate
            .manifest
            .dependencies
            .iter()
            .map(|dependency| dependency.id.clone())
            .collect(),
    );
    let mut visiting = BTreeSet::new();
    let mut visited = BTreeSet::new();
    for node in graph.keys() {
        if dependency_cycle(node, &graph, &mut visiting, &mut visited) {
            return Err(error(
                "AOS-EXTENSION-DEPENDENCY-CYCLE",
                "extension dependency graph must be acyclic",
                "extension:dependency-cycle",
                4,
            ));
        }
    }
    Ok(())
}

fn dependency_cycle(
    node: &str,
    graph: &BTreeMap<String, Vec<String>>,
    visiting: &mut BTreeSet<String>,
    visited: &mut BTreeSet<String>,
) -> bool {
    if visiting.contains(node) {
        return true;
    }
    if visited.contains(node) {
        return false;
    }
    visiting.insert(node.to_string());
    if let Some(dependencies) = graph.get(node) {
        for dependency in dependencies {
            if graph.contains_key(dependency)
                && dependency_cycle(dependency, graph, visiting, visited)
            {
                return true;
            }
        }
    }
    visiting.remove(node);
    visited.insert(node.to_string());
    false
}

fn enabled_manifests(root: &Path) -> Result<Vec<ManifestBundle>, ExtensionError> {
    let mut latest = BTreeMap::<String, LifecycleRecord>::new();
    for record in read_lifecycle_records(root) {
        latest
            .entry(record.id.clone())
            .and_modify(|current| {
                if record.revision > current.revision {
                    *current = record.clone();
                }
            })
            .or_insert(record);
    }
    let mut manifests = Vec::new();
    for lifecycle in latest.values() {
        if lifecycle.status == "enabled" && !lifecycle.retired {
            let bundle = load_snapshot(root, &lifecycle.id, &lifecycle.version)?;
            validate_manifest_shape(&bundle.manifest)?;
            manifests.push(bundle);
        }
    }
    Ok(manifests)
}

#[allow(clippy::too_many_arguments)]
fn lifecycle_record(
    bundle: &ManifestBundle,
    revision: u64,
    status: &str,
    retired: bool,
    principal: &str,
    evidence: &str,
    timestamp: u64,
    reason: &str,
) -> LifecycleRecord {
    LifecycleRecord {
        kind: "ExtensionLifecycle".to_string(),
        id: bundle.manifest.id.clone(),
        version: bundle.manifest.version.clone(),
        revision,
        previous_revision: (revision > 1).then_some(revision - 1),
        status: status.to_string(),
        retired,
        manifest_reference: manifest_relative(&bundle.manifest.id, &bundle.manifest.version),
        manifest_digest: bundle.digest.clone(),
        principal_ref: principal.to_string(),
        authority_basis_ref: format!("evidence:{evidence}"),
        timestamp_unix: timestamp,
        reason: reason.to_string(),
    }
}

fn read_lifecycle_records(root: &Path) -> Vec<LifecycleRecord> {
    let directory = root.join(".aos").join("extensions").join("lifecycle");
    let entries = match fs::read_dir(directory) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };
    let mut records = Vec::new();
    for entry in entries.flatten() {
        if entry.path().extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let Ok(raw) = fs::read_to_string(entry.path()) else {
            continue;
        };
        if let Ok(record) = serde_json::from_str::<LifecycleRecord>(&raw) {
            records.push(record);
        }
    }
    records
}

fn latest_lifecycle(root: &Path, extension_id: &str) -> Option<LifecycleRecord> {
    read_lifecycle_records(root)
        .into_iter()
        .filter(|record| record.id == extension_id)
        .max_by_key(|record| record.revision)
}

fn next_lifecycle_revision(root: &Path, extension_id: &str) -> u64 {
    latest_lifecycle(root, extension_id)
        .map(|record| record.revision + 1)
        .unwrap_or(1)
}

fn parse_extension_reference(reference: &str) -> Result<(&str, &str), ExtensionError> {
    let (id, version) = reference.rsplit_once('@').ok_or_else(|| {
        error(
            "AOS-EXTENSION-REFERENCE-INVALID",
            "extension reference must use <id>@<version>",
            "extension:reference-invalid",
            2,
        )
    })?;
    if !valid_id(id) || Version::parse(version).is_err() {
        return Err(error(
            "AOS-EXTENSION-REFERENCE-INVALID",
            "extension reference identity or version is invalid",
            "extension:reference-invalid",
            2,
        ));
    }
    Ok((id, version))
}

fn manifest_relative(id: &str, version: &str) -> String {
    format!(".aos/extensions/manifests/{id}@{version}.json")
}

fn lifecycle_relative_for(id: &str, revision: u64) -> String {
    format!(".aos/extensions/lifecycle/{id}.r{revision}.json")
}

#[allow(clippy::too_many_arguments)]
fn governance_and_audit(
    root: &Path,
    extension_id: &str,
    version: &str,
    event: &str,
    principal: &str,
    evidence: &str,
    outcome: &str,
    timestamp: u64,
) -> Result<Vec<String>, String> {
    let decision_id = format!(
        "{event}-{extension_id}-{timestamp}-{}",
        unique_event_suffix()
    );
    let decision_relative = format!(".aos/governance/{decision_id}.r1.json");
    let decision = json!({
        "kind": "Governance",
        "id": decision_id,
        "revision": 1,
        "contract_version": EXTENSION_CONTRACT_VERSION,
        "subject": format!("extension:{extension_id}@{version}"),
        "decision_type": event,
        "responsible_principal": principal,
        "decision_instant_unix": timestamp,
        "outcome": outcome,
        "policy_basis": "AOS-SPEC-006 capability and lifecycle policy",
        "evidence_reference": evidence,
    });
    write_json_immutable(&root.join(&decision_relative), &decision, timestamp)?;
    let audit_relative = audit_event(
        root,
        extension_id,
        version,
        event,
        principal,
        &format!("governance:{decision_id}"),
        evidence,
        timestamp + 1,
    )?;
    Ok(vec![decision_relative, audit_relative])
}

#[allow(clippy::too_many_arguments)]
fn audit_event(
    root: &Path,
    extension_id: &str,
    version: &str,
    event: &str,
    principal: &str,
    authority_basis: &str,
    evidence: &str,
    timestamp: u64,
) -> Result<String, String> {
    let filename = format!(
        "{timestamp}-{event}-{extension_id}-{}.json",
        unique_event_suffix()
    );
    let relative = format!(".aos/audit/{filename}");
    let audit = json!({
        "kind": "Audit",
        "id": filename,
        "revision": 1,
        "subject": format!("extension:{extension_id}@{version}"),
        "event": event,
        "principal": principal,
        "authority_basis": authority_basis,
        "timestamp_unix": timestamp,
        "outcome": "recorded",
        "evidence_reference": evidence,
        "secret_policy": "withheld",
    });
    write_json_immutable(&root.join(&relative), &audit, timestamp)?;
    Ok(relative)
}

#[allow(clippy::result_large_err)]
fn repository_context(path: Option<&Path>) -> Result<(RepositorySummary, PathBuf), QueryResult> {
    let inspection = repository::inspect(path).map_err(|root_error| QueryResult {
        repository: None,
        diagnostics: vec![Diagnostic::error(root_error.code, root_error.message)],
        evidence: vec!["extension:root-resolution".to_string()],
        data: "null".to_string(),
        plan: None,
        operation: None,
        exit_code: 3,
        outcome: "error".to_string(),
    })?;
    if inspection.summary.status != "initialized" || inspection.summary.compatibility != "supported"
    {
        return Err(QueryResult {
            repository: Some(inspection.summary),
            diagnostics: vec![Diagnostic::error(
                "AOS-EXTENSION-REPOSITORY-NOT-INITIALIZED",
                "Extension operations require a supported initialized repository",
            )],
            evidence: vec!["extension:repository-boundary".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        });
    }
    let root = PathBuf::from(
        inspection
            .summary
            .root
            .strip_prefix(r"\\?\")
            .unwrap_or(&inspection.summary.root),
    );
    Ok((inspection.summary, root))
}

fn mutation_authority(input: &ExtensionInput) -> Result<(&str, &str), ExtensionError> {
    let principal = required(input.authority.as_deref(), "authority")?;
    if is_self_authority(principal) {
        return Err(error(
            "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED",
            "the AOS CLI, Runtime, provider, or extension cannot authorize itself",
            "governance:self-authority-denied",
            7,
        ));
    }
    let evidence = required(input.evidence.as_deref(), "evidence")?;
    if contains_sensitive_reference(evidence) {
        return Err(error(
            "AOS-EXTENSION-SENSITIVE-EVIDENCE",
            "extension Governance evidence must be a non-secret reference",
            "extension:sensitive-evidence-rejected",
            4,
        ));
    }
    Ok((principal, evidence))
}

fn required<'a>(value: Option<&'a str>, name: &str) -> Result<&'a str, ExtensionError> {
    value
        .filter(|candidate| !candidate.trim().is_empty())
        .ok_or_else(|| {
            error(
                "AOS-EXTENSION-INPUT-REQUIRED",
                format!("{name} is required"),
                "extension:input-validation",
                2,
            )
        })
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 128
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn valid_namespace(value: &str) -> bool {
    valid_id(value) && value.contains('.')
}

fn is_self_authority(value: &str) -> bool {
    value == "aos-cli"
        || value == "aos-runtime"
        || value.starts_with("runtime:")
        || value.starts_with("provider:")
        || value.starts_with("extension:")
}

fn contains_sensitive_reference(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    ["secret", "credential", "private-key", "token=", "password"]
        .iter()
        .any(|marker| lower.contains(marker))
}

fn sha256(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    let mut output = String::with_capacity(digest.len() * 2);
    for byte in digest {
        use std::fmt::Write as _;
        write!(&mut output, "{byte:02x}").expect("writing to String cannot fail");
    }
    output
}

fn write_json_immutable<T: Serialize>(
    path: &Path,
    value: &T,
    timestamp: u64,
) -> Result<(), String> {
    let content = serde_json::to_string(value).map_err(|error| error.to_string())?;
    write_immutable(path, &content, timestamp)
}

fn write_immutable(path: &Path, content: &str, timestamp: u64) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let temp = path.with_extension(format!("tmp-{timestamp}-{}", std::process::id()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temp)
        .map_err(|error| error.to_string())?;
    if let Err(write_error) = file
        .write_all(content.as_bytes())
        .and_then(|()| file.sync_all())
    {
        let _ = fs::remove_file(&temp);
        return Err(write_error.to_string());
    }
    if path.exists() {
        let _ = fs::remove_file(&temp);
        return Err(format!(
            "immutable revision already exists: {}",
            path.display()
        ));
    }
    fs::rename(&temp, path).map_err(|rename_error| {
        let _ = fs::remove_file(&temp);
        rename_error.to_string()
    })
}

fn plan_result(
    summary: &RepositorySummary,
    action: ExtensionAction,
    paths: Vec<String>,
) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics: vec![Diagnostic::info(
            "AOS-EXTENSION-PLAN-READY",
            format!(
                "extension {} plan created; add --apply and Governance evidence to mutate",
                action.as_str()
            ),
        )],
        evidence: vec!["extension:plan-only".to_string()],
        data: serde_json::to_string(&json!({
            "action": action.as_str(),
            "mutation": "not_applied",
            "authority_required": true,
        }))
        .expect("serializable plan data"),
        plan: Some(PlanSummary {
            id: format!("extension-{}-plan", action.as_str()),
            snapshot: "current-extension-catalog".to_string(),
            root: summary.root.clone(),
            authority_required: true,
            affected_paths: paths.clone(),
            preconditions: vec![
                "supported initialized repository".to_string(),
                "compatible immutable manifest".to_string(),
                "explicit Governance authority".to_string(),
            ],
            ownership: paths
                .into_iter()
                .map(|path| OwnershipDecision {
                    path,
                    ownership: "aos".to_string(),
                    decision: "create immutable revision only".to_string(),
                })
                .collect(),
            recovery: "no mutation occurred".to_string(),
        }),
        operation: None,
        exit_code: 0,
        outcome: "plan_ready".to_string(),
    }
}

fn success(
    summary: &RepositorySummary,
    code: impl Into<String>,
    message: impl Into<String>,
    evidence: Vec<String>,
    data: Value,
    operation: Option<OperationSummary>,
) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics: vec![Diagnostic::info(code, message)],
        evidence,
        data: serde_json::to_string(&data).expect("serializable extension result"),
        plan: None,
        operation,
        exit_code: 0,
        outcome: "success".to_string(),
    }
}

fn extension_failure(summary: &RepositorySummary, failure: ExtensionError) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics: vec![Diagnostic::error(failure.code, failure.message)],
        evidence: vec![failure.evidence.to_string()],
        data: "null".to_string(),
        plan: None,
        operation: None,
        exit_code: failure.exit_code,
        outcome: if failure.exit_code == 8 {
            "unknown".to_string()
        } else {
            "findings".to_string()
        },
    }
}

fn error(
    code: &'static str,
    message: impl Into<String>,
    evidence: &'static str,
    exit_code: u8,
) -> ExtensionError {
    ExtensionError {
        code,
        message: message.into(),
        evidence,
        exit_code,
        quarantine: false,
    }
}

fn unknown_write_error(
    code: &'static str,
    message: impl Into<String>,
    evidence: &'static str,
) -> ExtensionError {
    error(code, message, evidence, 8)
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn unique_event_suffix() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{}-{nanos}", std::process::id())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_manifest() -> ExtensionManifest {
        ExtensionManifest {
            schema_version: "1".to_string(),
            contract_version: EXTENSION_CONTRACT_VERSION.to_string(),
            id: "aos.reference.repository".to_string(),
            version: "1.0.0".to_string(),
            extension_type: "tool".to_string(),
            owner: "AOS project".to_string(),
            namespace: "aos.reference.repository".to_string(),
            aos_compatibility: ">=0.1.0, <0.2.0".to_string(),
            dependencies: Vec::new(),
            capabilities: vec![ExtensionCapability {
                name: "aos.reference.repository.summary".to_string(),
                host_operation: HOST_REPOSITORY_SUMMARY.to_string(),
                operation_class: "read_only".to_string(),
                resource_scopes: vec!["repository:.".to_string()],
                idempotent: true,
                retryable: true,
                compensatable: false,
                reconciliation_required: false,
            }],
            data_ownership: "aos.reference.repository".to_string(),
            security: ExtensionSecurity {
                network: false,
                secrets: false,
                process: false,
            },
            failure_behavior: "fail_closed".to_string(),
        }
    }

    #[test]
    fn valid_manifest_passes_contract_validation() {
        validate_manifest_shape(&valid_manifest()).expect("valid manifest");
    }

    #[test]
    fn manifest_digest_is_deterministic() {
        let manifest = valid_manifest();
        let first = serde_json::to_string(&manifest).unwrap();
        let second = serde_json::to_string(&manifest).unwrap();
        assert_eq!(sha256(first.as_bytes()), sha256(second.as_bytes()));
    }

    #[test]
    fn undeclared_host_operation_fails_closed() {
        let mut manifest = valid_manifest();
        manifest.capabilities[0].host_operation = "shell.exec@1.0.0".to_string();
        let failure = validate_manifest_shape(&manifest).expect_err("must fail");
        assert_eq!(failure.code, "AOS-EXTENSION-HOST-OPERATION-UNSUPPORTED");
    }

    #[test]
    fn unsupported_contract_uses_unsupported_exit_category() {
        let mut manifest = valid_manifest();
        manifest.contract_version = "AOS-SPEC-999".to_string();
        let failure = validate_manifest_shape(&manifest).expect_err("must fail");
        assert_eq!(failure.code, "AOS-EXTENSION-CONTRACT-UNSUPPORTED");
        assert_eq!(failure.exit_code, 6);
    }

    #[test]
    fn declared_scope_must_equal_the_host_operation_scope() {
        let mut manifest = valid_manifest();
        manifest.capabilities[0].resource_scopes = vec!["repository:../outside".to_string()];
        let failure = validate_manifest_shape(&manifest).expect_err("must fail");
        assert_eq!(failure.code, "AOS-EXTENSION-SCOPE-DENIED");
        assert_eq!(failure.exit_code, 7);
    }

    #[test]
    fn process_network_or_secret_access_is_rejected() {
        for security in [
            ExtensionSecurity {
                network: true,
                secrets: false,
                process: false,
            },
            ExtensionSecurity {
                network: false,
                secrets: true,
                process: false,
            },
            ExtensionSecurity {
                network: false,
                secrets: false,
                process: true,
            },
        ] {
            let mut manifest = valid_manifest();
            manifest.security = security;
            let failure = validate_manifest_shape(&manifest).expect_err("must fail");
            assert_eq!(failure.code, "AOS-EXTENSION-SECURITY-INVALID");
        }
    }

    #[test]
    fn dependency_cycle_is_rejected() {
        let mut first = valid_manifest();
        first.dependencies.push(ExtensionDependency {
            id: "aos.reference.rust".to_string(),
            version_requirement: "^1.0.0".to_string(),
        });
        let mut second = valid_manifest();
        second.id = "aos.reference.rust".to_string();
        second.namespace = "aos.reference.rust".to_string();
        second.data_ownership = second.namespace.clone();
        second.capabilities[0].name = "aos.reference.rust.summary".to_string();
        second.dependencies.push(ExtensionDependency {
            id: first.id.clone(),
            version_requirement: "^1.0.0".to_string(),
        });
        let first_json = serde_json::to_string(&first).unwrap();
        let second_json = serde_json::to_string(&second).unwrap();
        let first_bundle = ManifestBundle {
            manifest: first,
            digest: sha256(first_json.as_bytes()),
            canonical_json: first_json,
        };
        let second_bundle = ManifestBundle {
            manifest: second,
            digest: sha256(second_json.as_bytes()),
            canonical_json: second_json,
        };
        let failure =
            validate_dependency_graph(&first_bundle, &[second_bundle]).expect_err("cycle");
        assert_eq!(failure.code, "AOS-EXTENSION-DEPENDENCY-CYCLE");
    }
}
