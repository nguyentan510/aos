use crate::model::{
    Diagnostic, OperationSummary, OwnershipDecision, PlanSummary, RepositorySummary,
};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const REPOSITORY_SCHEMA_VERSION: &str = "1";
const REPOSITORY_CONTRACT_VERSION: &str = "AOS-SPEC-002";
const MANIFEST_FILE: &str = "repository.json";

#[derive(Debug)]
pub struct RootError {
    pub code: &'static str,
    pub message: String,
}

#[derive(Debug)]
pub struct Inspection {
    pub summary: RepositorySummary,
    pub diagnostics: Vec<Diagnostic>,
    pub evidence: Vec<String>,
}

#[derive(Debug)]
pub struct InitResult {
    pub outcome: String,
    pub repository: Option<RepositorySummary>,
    pub diagnostics: Vec<Diagnostic>,
    pub evidence: Vec<String>,
    pub plan: Option<PlanSummary>,
    pub operation: Option<OperationSummary>,
    pub exit_code: u8,
}

#[derive(Debug)]
struct InitPlan {
    root: PathBuf,
    control_root: PathBuf,
    snapshot: String,
    plan: PlanSummary,
}

pub fn inspect(path: Option<&Path>) -> Result<Inspection, RootError> {
    let root = resolve_root(path)?;
    Ok(inspect_root(&root))
}

pub fn init(path: Option<&Path>, apply: bool, authority: Option<&str>) -> InitResult {
    let root = match resolve_root(path) {
        Ok(root) => root,
        Err(error) => {
            return InitResult {
                outcome: "error".to_string(),
                repository: None,
                diagnostics: vec![Diagnostic::error(error.code, error.message)],
                evidence: vec!["repository:root-resolution".to_string()],
                plan: None,
                operation: None,
                exit_code: 3,
            };
        }
    };

    let inspection = inspect_root(&root);
    let summary = inspection.summary.clone();
    let mut evidence = inspection.evidence.clone();
    evidence.push("repository:adoption-plan".to_string());

    let plan = match build_plan(&root, &inspection) {
        Ok(plan) => plan,
        Err(error) => {
            let exit_code = if error.category == "ownership_conflict" {
                5
            } else {
                4
            };
            return InitResult {
                outcome: "conflict".to_string(),
                repository: Some(summary),
                diagnostics: vec![error.diagnostic],
                evidence,
                plan: None,
                operation: None,
                exit_code,
            };
        }
    };

    if !apply {
        let mut diagnostics = inspection.diagnostics;
        diagnostics.push(Diagnostic::info(
            "AOS-INIT-PLAN-READY",
            "adoption plan created; no repository mutation was requested",
        ));
        return InitResult {
            outcome: "plan_ready".to_string(),
            repository: Some(summary),
            diagnostics,
            evidence,
            plan: Some(plan.plan),
            operation: None,
            exit_code: 0,
        };
    }

    let authority = match authority.filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => {
            let mut diagnostics = inspection.diagnostics;
            diagnostics.push(Diagnostic::error(
                "AOS-INIT-AUTHORITY-REQUIRED",
                "init --apply requires a non-empty --authority reference",
            ));
            return InitResult {
                outcome: "authorization_required".to_string(),
                repository: Some(summary),
                diagnostics,
                evidence,
                plan: Some(plan.plan),
                operation: None,
                exit_code: 7,
            };
        }
    };

    let result = apply_plan(&plan, authority);
    let mut diagnostics = inspection.diagnostics;
    diagnostics.extend(result.diagnostics);
    evidence.extend(result.evidence);
    InitResult {
        outcome: result.outcome,
        repository: result.repository.or(Some(summary)),
        diagnostics,
        evidence,
        plan: Some(plan.plan),
        operation: result.operation,
        exit_code: result.exit_code,
    }
}

fn resolve_root(path: Option<&Path>) -> Result<PathBuf, RootError> {
    let requested_root = match path {
        Some(path) => path.to_path_buf(),
        None => std::env::current_dir().map_err(|error| RootError {
            code: "AOS-ROOT-CURRENT-DIR",
            message: format!("cannot resolve current directory: {error}"),
        })?,
    };

    let root = fs::canonicalize(&requested_root).map_err(|error| RootError {
        code: "AOS-ROOT-NOT_FOUND",
        message: format!(
            "repository root '{}' cannot be resolved: {error}",
            requested_root.display()
        ),
    })?;

    if !root.is_dir() {
        return Err(RootError {
            code: "AOS-ROOT-NOT_DIRECTORY",
            message: format!("repository root '{}' is not a directory", root.display()),
        });
    }
    Ok(root)
}

fn inspect_root(root: &Path) -> Inspection {
    let control_root = root.join(".aos");
    let control_root_display = control_root.to_string_lossy().into_owned();
    let mut diagnostics = Vec::new();
    let (control_root_state, status, compatibility) = match fs::symlink_metadata(&control_root) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            match fs::canonicalize(&control_root) {
                Ok(target) if target.starts_with(root) && target.is_dir() => {
                    diagnostics.push(Diagnostic::warning(
                            "AOS-REPO-CONTROL-LINK",
                            "the .aos control root is a link inside the selected repository; it is not an owned P3 control root",
                        ));
                    (
                        "link_inside_root",
                        "candidate",
                        "unrecognized_control_schema",
                    )
                }
                Ok(target) => {
                    diagnostics.push(
                        Diagnostic::error(
                            "AOS-REPO-CONTROL-BOUNDARY",
                            "the .aos control root resolves outside the selected repository",
                        )
                        .with_path(target.to_string_lossy()),
                    );
                    (
                        "link_outside_root",
                        "incompatible",
                        "invalid_control_boundary",
                    )
                }
                Err(error) => {
                    diagnostics.push(Diagnostic::error(
                        "AOS-REPO-CONTROL-LINK",
                        format!("the .aos control root cannot be resolved: {error}"),
                    ));
                    (
                        "unresolvable_link",
                        "incompatible",
                        "invalid_control_boundary",
                    )
                }
            }
        }
        Ok(metadata) if metadata.is_dir() => match read_manifest(&control_root, root) {
            Ok(()) => {
                diagnostics.push(Diagnostic::info(
                    "AOS-REPO-INITIALIZED",
                    "the repository has a supported AOS control root",
                ));
                ("directory", "initialized", "supported")
            }
            Err(ManifestError::Missing) => {
                diagnostics.push(Diagnostic::warning(
                    "AOS-REPO-CONTROL-UNRECOGNIZED",
                    "an .aos directory exists, but the P3 repository manifest is absent",
                ));
                ("directory", "candidate", "unrecognized_control_schema")
            }
            Err(error) => {
                diagnostics.push(Diagnostic::error(error.code(), error.message()));
                ("directory", "incompatible", "unsupported_control_schema")
            }
        },
        Ok(_) => {
            diagnostics.push(Diagnostic::error(
                "AOS-REPO-CONTROL-ROOT",
                "the .aos control root exists but is not a directory",
            ));
            ("not_directory", "incompatible", "invalid_control_root")
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            diagnostics.push(Diagnostic::info(
                "AOS-REPO-UNMANAGED",
                "no .aos control root exists; the repository is an unmanaged candidate",
            ));
            ("absent", "unmanaged", "not_initialized")
        }
        Err(error) => {
            diagnostics.push(Diagnostic::error(
                "AOS-REPO-CONTROL-READ",
                format!("the .aos control root cannot be inspected: {error}"),
            ));
            ("unreadable", "incompatible", "control_root_unreadable")
        }
    };

    Inspection {
        summary: RepositorySummary {
            root: root.to_string_lossy().into_owned(),
            status: status.to_string(),
            compatibility: compatibility.to_string(),
            control_root: control_root_display,
            control_root_state: control_root_state.to_string(),
        },
        diagnostics,
        evidence: vec!["repository:read-only-inspection".to_string()],
    }
}

#[derive(Debug)]
struct PlanError {
    category: &'static str,
    diagnostic: Diagnostic,
}

fn build_plan(root: &Path, inspection: &Inspection) -> Result<InitPlan, PlanError> {
    if inspection.summary.status != "unmanaged" && inspection.summary.status != "initialized" {
        return Err(PlanError {
            category: "ownership_conflict",
            diagnostic: Diagnostic::error(
                "AOS-INIT-CONTROL-ROOT-CONFLICT",
                "the existing .aos control root is not a supported AOS-owned repository; it is protected",
            ),
        });
    }

    let control_root = root.join(".aos");
    let snapshot = if inspection.summary.status == "initialized" {
        "initialized".to_string()
    } else {
        control_snapshot(&control_root)
    };
    let root_string = root.to_string_lossy().into_owned();
    let plan_id = format!(
        "plan-{:016x}",
        stable_hash(&format!(
            "{root_string}|{snapshot}|{REPOSITORY_CONTRACT_VERSION}"
        ))
    );
    let plan = PlanSummary {
        id: plan_id,
        snapshot: snapshot.clone(),
        root: root_string,
        authority_required: true,
        affected_paths: vec![".aos".to_string(), ".aos/repository.json".to_string()],
        preconditions: vec![
            "repository root remains canonical and accessible".to_string(),
            "the .aos control root remains absent or the compatible manifest remains unchanged"
                .to_string(),
        ],
        ownership: vec![
            OwnershipDecision {
                path: ".aos".to_string(),
                ownership: "aos".to_string(),
                decision: "create only when absent; protect any unknown existing root".to_string(),
            },
            OwnershipDecision {
                path: ".aos/repository.json".to_string(),
                ownership: "aos".to_string(),
                decision: "create or verify; never overwrite an unknown file".to_string(),
            },
        ],
        recovery: "atomic rename of a temporary control root; preserve user content and reconcile unknown apply results"
            .to_string(),
    };
    Ok(InitPlan {
        root: root.to_path_buf(),
        control_root,
        snapshot,
        plan,
    })
}

#[derive(Debug)]
struct ApplyResult {
    outcome: String,
    repository: Option<RepositorySummary>,
    diagnostics: Vec<Diagnostic>,
    evidence: Vec<String>,
    operation: Option<OperationSummary>,
    exit_code: u8,
}

fn apply_plan(plan: &InitPlan, authority: &str) -> ApplyResult {
    let current_snapshot = snapshot_for(&plan.root, &plan.control_root);
    if current_snapshot != plan.snapshot {
        return ApplyResult {
            outcome: "stale".to_string(),
            repository: None,
            diagnostics: vec![Diagnostic::error(
                "AOS-INIT-STALE-PLAN",
                "the repository control-root snapshot changed after planning; re-run aos init",
            )],
            evidence: vec!["repository:stale-plan-rejected".to_string()],
            operation: None,
            exit_code: 5,
        };
    }

    let timestamp = unix_timestamp();
    let operation_id = format!("op-{}-{}", stable_hash(&plan.plan.id), timestamp);
    if plan.snapshot == "initialized" {
        let operation = OperationSummary {
            id: operation_id,
            result: "already_initialized".to_string(),
            changed_paths: Vec::new(),
            verification: "supported manifest verified before apply".to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec![
                format!("authority:{authority}"),
                "operation:no-op".to_string(),
            ],
            timestamp: timestamp.to_string(),
        };
        return ApplyResult {
            outcome: "success".to_string(),
            repository: Some(inspect_root(&plan.root).summary),
            diagnostics: vec![Diagnostic::info(
                "AOS-INIT-IDEMPOTENT",
                "the repository is already initialized with a compatible AOS manifest",
            )],
            evidence: vec!["repository:idempotent-adoption".to_string()],
            operation: Some(operation),
            exit_code: 0,
        };
    }

    let temporary_root = plan.root.join(format!(".aos.tmp-{operation_id}"));
    if temporary_root.exists() {
        return ApplyResult {
            outcome: "conflict".to_string(),
            repository: None,
            diagnostics: vec![Diagnostic::error(
                "AOS-INIT-TEMPORARY-ROOT-CONFLICT",
                "the transactional temporary control root already exists; remove it only after inspection",
            )],
            evidence: vec!["repository:temporary-root-conflict".to_string()],
            operation: None,
            exit_code: 5,
        };
    }

    let write_result = (|| -> Result<(), String> {
        fs::create_dir(&temporary_root)
            .map_err(|error| format!("create temporary root: {error}"))?;
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(temporary_root.join(MANIFEST_FILE))
            .map_err(|error| format!("create repository manifest: {error}"))?;
        let manifest = manifest_json(plan, authority, &operation_id, timestamp);
        file.write_all(manifest.as_bytes())
            .map_err(|error| format!("write repository manifest: {error}"))?;
        file.sync_all()
            .map_err(|error| format!("sync repository manifest: {error}"))?;
        drop(file);
        fs::rename(&temporary_root, &plan.control_root)
            .map_err(|error| format!("commit control root atomically: {error}"))?;
        Ok(())
    })();

    if let Err(message) = write_result {
        let cleanup = if temporary_root.exists() {
            fs::remove_dir_all(&temporary_root).err()
        } else {
            None
        };
        let cleanup_note = cleanup
            .map(|error| format!(" temporary cleanup failed: {error}"))
            .unwrap_or_default();
        return ApplyResult {
            outcome: "unknown".to_string(),
            repository: None,
            diagnostics: vec![Diagnostic::error(
                "AOS-INIT-APPLY-FAILED",
                format!("{message}.{cleanup_note} inspect before retrying"),
            )],
            evidence: vec!["repository:apply-failure".to_string()],
            operation: Some(OperationSummary {
                id: operation_id,
                result: "unknown".to_string(),
                changed_paths: Vec::new(),
                verification: "not_verified".to_string(),
                reconciliation: "required".to_string(),
                audit_evidence: vec![format!("authority:{authority}")],
                timestamp: timestamp.to_string(),
            }),
            exit_code: 8,
        };
    }

    let verification = inspect_root(&plan.root);
    if verification.summary.status != "initialized" {
        return ApplyResult {
            outcome: "unknown".to_string(),
            repository: Some(verification.summary),
            diagnostics: vec![Diagnostic::error(
                "AOS-INIT-VERIFY-FAILED",
                "the control root was committed but the supported manifest could not be verified",
            )],
            evidence: vec!["repository:apply-reconciliation-required".to_string()],
            operation: Some(OperationSummary {
                id: operation_id,
                result: "unknown".to_string(),
                changed_paths: vec![".aos".to_string(), ".aos/repository.json".to_string()],
                verification: "failed".to_string(),
                reconciliation: "required".to_string(),
                audit_evidence: vec![format!("authority:{authority}")],
                timestamp: timestamp.to_string(),
            }),
            exit_code: 8,
        };
    }

    ApplyResult {
        outcome: "success".to_string(),
        repository: Some(verification.summary),
        diagnostics: vec![Diagnostic::info(
            "AOS-INIT-APPLIED",
            "the AOS control root was initialized transactionally",
        )],
        evidence: vec!["repository:atomic-adoption".to_string()],
        operation: Some(OperationSummary {
            id: operation_id,
            result: "initialized".to_string(),
            changed_paths: vec![".aos".to_string(), ".aos/repository.json".to_string()],
            verification: "supported manifest verified".to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec![
                format!("authority:{authority}"),
                "operation:atomic-rename".to_string(),
            ],
            timestamp: timestamp.to_string(),
        }),
        exit_code: 0,
    }
}

fn manifest_json(plan: &InitPlan, authority: &str, operation_id: &str, timestamp: u64) -> String {
    let project_id = format!("project-{:016x}", stable_hash(&plan.plan.root));
    let repository_id = format!("repository-{:016x}", stable_hash(&plan.plan.root));
    format!(
        "{{\"schema_version\":\"{REPOSITORY_SCHEMA_VERSION}\",\"contract_version\":\"{REPOSITORY_CONTRACT_VERSION}\",\"status\":\"initialized\",\"root\":\"{}\",\"project_id\":\"{project_id}\",\"repository_id\":\"{repository_id}\",\"ownership_policy\":\"user-by-default\",\"initialization_revision\":1,\"operation_id\":\"{operation_id}\",\"authority_reference\":\"{}\",\"initialized_at_unix\":{timestamp}}}\n",
        crate::model::escape_json(&plan.plan.root),
        crate::model::escape_json(authority),
        operation_id = crate::model::escape_json(operation_id),
    )
}

#[derive(Debug)]
enum ManifestError {
    Missing,
    NotRegular,
    Invalid(String),
}

impl ManifestError {
    fn code(&self) -> &'static str {
        match self {
            Self::Missing => "AOS-REPO-MANIFEST-MISSING",
            Self::NotRegular => "AOS-REPO-MANIFEST-NOT-REGULAR",
            Self::Invalid(_) => "AOS-REPO-MANIFEST-INVALID",
        }
    }

    fn message(&self) -> String {
        match self {
            Self::Missing => "the repository manifest is missing".to_string(),
            Self::NotRegular => "the repository manifest is not a regular file".to_string(),
            Self::Invalid(message) => format!("the repository manifest is invalid: {message}"),
        }
    }
}

fn read_manifest(control_root: &Path, root: &Path) -> Result<(), ManifestError> {
    let manifest = control_root.join(MANIFEST_FILE);
    let metadata = fs::symlink_metadata(&manifest).map_err(|error| {
        if error.kind() == std::io::ErrorKind::NotFound {
            ManifestError::Missing
        } else {
            ManifestError::Invalid(error.to_string())
        }
    })?;
    if !metadata.is_file() {
        return Err(ManifestError::NotRegular);
    }
    let content =
        fs::read_to_string(&manifest).map_err(|error| ManifestError::Invalid(error.to_string()))?;
    for (key, expected) in [
        ("schema_version", REPOSITORY_SCHEMA_VERSION),
        ("contract_version", REPOSITORY_CONTRACT_VERSION),
        ("status", "initialized"),
    ] {
        if extract_json_string(&content, key).as_deref() != Some(expected) {
            return Err(ManifestError::Invalid(format!(
                "{key} does not equal {expected}"
            )));
        }
    }
    if extract_json_string(&content, "root").as_deref() != Some(&root.to_string_lossy()) {
        return Err(ManifestError::Invalid(
            "manifest root does not match the selected canonical root".to_string(),
        ));
    }
    Ok(())
}

fn extract_json_string(content: &str, key: &str) -> Option<String> {
    let marker = format!("\"{key}\":\"");
    let start = content.find(&marker)? + marker.len();
    let remainder = &content[start..];
    let end = remainder.find('"')?;
    Some(remainder[..end].replace("\\\"", "\"").replace("\\\\", "\\"))
}

pub(crate) fn project_id(root: &Path) -> Option<String> {
    let content = fs::read_to_string(root.join(".aos").join(MANIFEST_FILE)).ok()?;
    extract_json_string(&content, "project_id")
}

fn control_snapshot(control_root: &Path) -> String {
    match fs::symlink_metadata(control_root) {
        Ok(metadata) if metadata.file_type().is_symlink() => "symlink".to_string(),
        Ok(metadata) if metadata.is_dir() => "directory".to_string(),
        Ok(_) => "file".to_string(),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => "absent".to_string(),
        Err(_) => "unreadable".to_string(),
    }
}

fn snapshot_for(root: &Path, control_root: &Path) -> String {
    if matches!(fs::symlink_metadata(control_root), Ok(metadata) if metadata.is_dir())
        && read_manifest(control_root, root).is_ok()
    {
        "initialized".to_string()
    } else {
        control_snapshot(control_root)
    }
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or(0)
}

fn stable_hash(value: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[cfg(test)]
mod tests {
    use super::{control_snapshot, stable_hash};

    #[test]
    fn stable_hash_is_repeatable() {
        assert_eq!(stable_hash("aos"), stable_hash("aos"));
        assert_ne!(stable_hash("aos"), stable_hash("other"));
    }

    #[test]
    fn absent_control_root_has_absent_snapshot() {
        let path = std::env::temp_dir().join(format!("aos-snapshot-{}", std::process::id()));
        assert_eq!(control_snapshot(&path), "absent");
    }
}
