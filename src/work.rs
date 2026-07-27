use crate::intelligence::QueryResult;
use crate::model::{Diagnostic, OperationSummary, RepositorySummary, escape_json};
use crate::repository;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const VERIFY_PROTOCOL: &str = "aos.local.verify@1.0.0";
const VERIFY_PROTOCOL_ID: &str = "aos.local.verify";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum WorkAction {
    Create,
    Authorize,
    Run,
    Reconcile,
    Show,
}

impl WorkAction {
    pub fn parse(value: &str) -> Result<Self, String> {
        match value {
            "create" => Ok(Self::Create),
            "authorize" => Ok(Self::Authorize),
            "run" => Ok(Self::Run),
            "reconcile" => Ok(Self::Reconcile),
            "show" => Ok(Self::Show),
            _ => Err(format!(
                "unknown work action '{value}'; use create, authorize, run, reconcile, or show"
            )),
        }
    }
}

#[derive(Debug)]
pub struct WorkInput {
    pub action: WorkAction,
    pub path: Option<PathBuf>,
    pub apply: bool,
    pub authority: Option<String>,
    pub work_id: Option<String>,
    pub context_id: Option<String>,
    pub context_kind: Option<String>,
    pub intent: Option<String>,
    pub owner: Option<String>,
    pub scope: Option<String>,
    pub protocol: Option<String>,
    pub expected_output: Option<String>,
    pub verification: Option<String>,
    pub evidence: Option<String>,
    pub result: Option<String>,
    pub reason: Option<String>,
}

#[derive(Debug, Clone)]
struct Document {
    raw: String,
    kind: String,
    id: String,
    revision: u64,
    status: Option<String>,
    authority: Option<String>,
    lifecycle: Option<String>,
    freshness: Option<String>,
}

#[derive(Debug, Clone)]
struct ContextDocument {
    document: Document,
    subject: String,
    source_reference: String,
    content: Option<String>,
    observed_value: Option<String>,
    project_id: String,
    owner: String,
    producer: String,
}

pub fn execute(input: WorkInput) -> QueryResult {
    let (repository_summary, root) = match repository_context(input.path.as_deref()) {
        Ok(value) => value,
        Err(result) => return result,
    };

    if input.action != WorkAction::Show && !input.apply {
        return QueryResult {
            repository: Some(repository_summary),
            diagnostics: vec![Diagnostic::info(
                "AOS-WORK-PLAN-READY",
                "Work action plan created; add --apply and the required authority evidence to mutate",
            )],
            evidence: vec!["work:action-plan".to_string()],
            data: format!(
                "{{\"action\":\"{}\",\"mutation\":\"not_applied\",\"authority_required\":true}}",
                action_name(input.action)
            ),
            plan: None,
            operation: None,
            exit_code: 0,
            outcome: "plan_ready".to_string(),
        };
    }

    match input.action {
        WorkAction::Create => create(&repository_summary, &root, input),
        WorkAction::Authorize => authorize(&repository_summary, &root, input),
        WorkAction::Run => run(&repository_summary, &root, input),
        WorkAction::Reconcile => reconcile(&repository_summary, &root, input),
        WorkAction::Show => show(&repository_summary, &root, input),
    }
}

fn action_name(action: WorkAction) -> &'static str {
    match action {
        WorkAction::Create => "create",
        WorkAction::Authorize => "authorize",
        WorkAction::Run => "run",
        WorkAction::Reconcile => "reconcile",
        WorkAction::Show => "show",
    }
}

#[allow(clippy::result_large_err)]
fn repository_context(path: Option<&Path>) -> Result<(RepositorySummary, PathBuf), QueryResult> {
    let inspection = match repository::inspect(path) {
        Ok(value) => value,
        Err(error) => {
            return Err(QueryResult {
                repository: None,
                diagnostics: vec![Diagnostic::error(error.code, error.message)],
                evidence: vec!["work:root-resolution".to_string()],
                data: "null".to_string(),
                plan: None,
                operation: None,
                exit_code: 3,
                outcome: "error".to_string(),
            });
        }
    };
    if inspection.summary.status != "initialized" {
        return Err(QueryResult {
            repository: Some(inspection.summary),
            diagnostics: vec![Diagnostic::error(
                "AOS-WORK-REPOSITORY-NOT-INITIALIZED",
                "Work requires a supported initialized repository",
            )],
            evidence: vec!["work:repository-boundary".to_string()],
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

fn create(summary: &RepositorySummary, root: &Path, input: WorkInput) -> QueryResult {
    let work_id = match required_id(input.work_id.as_deref(), "work id") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let intent = match required(input.intent.as_deref(), "intent") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let owner = input.owner.as_deref().unwrap_or("project-owner");
    let scope = input.scope.as_deref().unwrap_or(".");
    let context_id = match required(input.context_id.as_deref(), "context id") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let protocol = input.protocol.as_deref().unwrap_or(VERIFY_PROTOCOL);
    if protocol != VERIFY_PROTOCOL {
        return failure(
            summary,
            4,
            "AOS-WORK-PROTOCOL-UNSUPPORTED",
            "only aos.local.verify@1.0.0 is accepted by the P5 vertical slice",
            "work:protocol-version",
        );
    }
    if !input.apply {
        return QueryResult {
            repository: Some(summary.clone()),
            diagnostics: vec![Diagnostic::info(
                "AOS-WORK-PLAN-READY",
                "Work proposal plan created; add --apply --authority to record it",
            )],
            evidence: vec!["work:proposal-plan".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 0,
            outcome: "plan_ready".to_string(),
        };
    }
    let authority = match non_empty(input.authority.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-WORK-AUTHORITY-REQUIRED",
                "recording Work requires --apply --authority <REFERENCE>",
                "work:authority-required",
            );
        }
    };
    if !valid_id(work_id) || !valid_id(context_id) {
        return failure(
            summary,
            2,
            "AOS-WORK-ID-INVALID",
            "work and context ids must contain only ASCII letters, digits, '.', '_' or '-'",
            "work:input-validation",
        );
    }
    if input
        .verification
        .as_deref()
        .is_some_and(|value| value.contains("secret") || value.contains("credential"))
    {
        return failure(
            summary,
            4,
            "AOS-WORK-SENSITIVE-VERIFICATION",
            "verification requirements must not contain secret-bearing content",
            "work:sensitive-output-rejected",
        );
    }

    let timestamp = unix_timestamp();
    let revision = next_revision(root, "work", work_id);
    let context_kind = input.context_kind.as_deref().unwrap_or("Knowledge");
    let content = format!(
        "{{\"kind\":\"Work\",\"id\":\"{}\",\"project_id\":\"{}\",\"contract_version\":\"AOS-SPEC-001\",\"revision\":\"{}\",\"previous_revision\":null,\"owner\":\"{}\",\"producer\":\"aos-cli\",\"created_at_unix\":\"{}\",\"last_produced_at_unix\":\"{}\",\"authority\":\"proposed\",\"lifecycle\":\"active\",\"intent\":\"{}\",\"scope\":\"{}\",\"context_reference\":\"{}:{}@latest\",\"expected_output\":\"{}\",\"verification_requirements\":\"{}\",\"protocol_id\":\"{}\",\"protocol_version\":\"1.0.0\",\"status\":\"proposed\",\"failure_reason\":null,\"unresolved_condition\":null,\"verification_evidence\":null,\"authority_basis\":\"pending-governance\",\"authority_reference\":\"{}\"}}",
        escape_json(work_id),
        escape_json(&format!(
            "project-{:016x}",
            stable_hash(&root.to_string_lossy())
        )),
        revision,
        escape_json(owner),
        timestamp,
        timestamp,
        escape_json(intent),
        escape_json(scope),
        escape_json(context_kind),
        escape_json(context_id),
        escape_json(
            input
                .expected_output
                .as_deref()
                .unwrap_or("declared output")
        ),
        escape_json(
            input
                .verification
                .as_deref()
                .unwrap_or("repository boundary and context integrity"),
        ),
        VERIFY_PROTOCOL_ID,
        escape_json(authority),
    );
    let relative = format!(".aos/work/{work_id}.r{revision}.json");
    if let Err(error) = write_immutable(&root.join(&relative), &content, timestamp) {
        return failure(
            summary,
            8,
            "AOS-WORK-RECORD-UNKNOWN",
            &error,
            "work:record-reconciliation-required",
        );
    }
    let audit = match audit_event(
        root,
        timestamp,
        work_id,
        "work_proposed",
        authority,
        "pending-governance",
        &format!("work:{work_id}@{revision}"),
    ) {
        Ok(value) => value,
        Err(error) => {
            return failure(
                summary,
                8,
                "AOS-AUDIT-WRITE-UNKNOWN",
                &error,
                "audit:reconciliation-required",
            );
        }
    };
    let diagnostics = vec![Diagnostic::info(
        "AOS-WORK-PROPOSED",
        format!("proposed Work {work_id} revision {revision} recorded"),
    )];
    success(
        summary,
        diagnostics,
        vec!["work:immutable-revision".to_string(), audit],
        content,
        OperationSummary {
            id: format!("op-work-create-{timestamp}"),
            result: "recorded_proposed".to_string(),
            changed_paths: vec![relative],
            verification: "immutable Work revision verified".to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec!["work:proposed".to_string()],
            timestamp: timestamp.to_string(),
        },
    )
}

fn authorize(summary: &RepositorySummary, root: &Path, input: WorkInput) -> QueryResult {
    let work_id = match required_id(input.work_id.as_deref(), "work id") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let authority = match non_empty(input.authority.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-WORK-AUTHORITY-REQUIRED",
                "authorization requires --authority <PRINCIPAL>",
                "governance:authority-required",
            );
        }
    };
    if is_self_authority(authority) {
        return failure(
            summary,
            7,
            "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED",
            "the AOS CLI, a Runtime, or a provider cannot grant itself authority",
            "governance:self-authority-denied",
        );
    }
    let evidence = match non_empty(input.evidence.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-GOVERNANCE-EVIDENCE-REQUIRED",
                "authorization requires --evidence <REFERENCE>",
                "governance:evidence-required",
            );
        }
    };
    if contains_sensitive_reference(evidence) {
        return failure(
            summary,
            4,
            "AOS-GOVERNANCE-SENSITIVE-EVIDENCE",
            "evidence must be a non-secret reference",
            "governance:sensitive-evidence-rejected",
        );
    }
    let work = match latest_document(root, "work", work_id) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                4,
                "AOS-WORK-NOT-FOUND",
                "the requested Work revision does not exist",
                "work:reference-unresolved",
            );
        }
    };
    if work.status.as_deref() != Some("proposed") {
        return failure(
            summary,
            4,
            "AOS-WORK-TRANSITION-INVALID",
            "only proposed Work can be authorized",
            "work:state-machine",
        );
    }
    if extract_string(&work.raw, "scope").as_deref() != Some(".") {
        return failure(
            summary,
            7,
            "AOS-GOVERNANCE-SCOPE-MISMATCH",
            "aos.local.verify@1.0.0 authorizes only the repository-local '.' scope",
            "governance:scope-denied",
        );
    }
    let decision_outcome = input.result.as_deref().unwrap_or("approved");
    if !matches!(decision_outcome, "approved" | "rejected") {
        return failure(
            summary,
            2,
            "AOS-GOVERNANCE-OUTCOME-INVALID",
            "authorization decision result must be approved or rejected",
            "governance:decision-validation",
        );
    }
    if decision_outcome == "rejected" {
        let timestamp = unix_timestamp();
        let decision_id = format!("decision-{work_id}-{timestamp}");
        let decision = format!(
            "{{\"kind\":\"Governance\",\"id\":\"{}\",\"contract_version\":\"AOS-SPEC-001\",\"revision\":\"1\",\"subject\":\"work:{}\",\"decision_type\":\"rejection\",\"responsible_principal\":\"{}\",\"decision_instant_unix\":\"{}\",\"outcome\":\"rejected\",\"policy_basis\":\"{}\",\"evidence_reference\":\"{}\",\"previous_decision\":null}}",
            decision_id,
            escape_json(work_id),
            escape_json(authority),
            timestamp,
            escape_json(input.reason.as_deref().unwrap_or("explicit rejection")),
            escape_json(evidence),
        );
        let relative = format!(".aos/governance/{decision_id}.r1.json");
        if let Err(error) = write_immutable(&root.join(&relative), &decision, timestamp) {
            return failure(
                summary,
                8,
                "AOS-GOVERNANCE-DECISION-UNKNOWN",
                &error,
                "governance:reconciliation-required",
            );
        }
        let audit = match audit_event(
            root,
            timestamp + 1,
            work_id,
            "work_rejected",
            authority,
            &format!("governance:{decision_id}"),
            &format!("work:{work_id}@{}", work.revision),
        ) {
            Ok(value) => value,
            Err(error) => {
                return failure(
                    summary,
                    8,
                    "AOS-AUDIT-WRITE-UNKNOWN",
                    &error,
                    "audit:reconciliation-required",
                );
            }
        };
        let diagnostics = vec![Diagnostic::info(
            "AOS-WORK-REJECTED",
            format!("Work {work_id} remains proposed; rejection decision was preserved"),
        )];
        return success(
            summary,
            diagnostics,
            vec!["governance:rejection-recorded".to_string(), audit],
            work.raw,
            OperationSummary {
                id: format!("op-work-reject-{timestamp}"),
                result: "rejected".to_string(),
                changed_paths: vec![relative],
                verification: "proposal retained and rejection recorded".to_string(),
                reconciliation: "not_required".to_string(),
                audit_evidence: vec![format!("evidence:{evidence}")],
                timestamp: timestamp.to_string(),
            },
        );
    }
    let context_reference = extract_string(&work.raw, "context_reference").unwrap_or_default();
    let (context_kind, context_id) = match context_reference
        .split_once(':')
        .and_then(|(kind, reference)| reference.split('@').next().map(|id| (kind, id)))
    {
        Some((kind, id)) if !kind.is_empty() && !id.is_empty() => {
            (kind.to_string(), id.to_string())
        }
        _ => {
            return failure(
                summary,
                4,
                "AOS-WORK-CONTEXT-UNRESOLVED",
                "Work has no resolvable context reference",
                "protocol:context-snapshot",
            );
        }
    };
    let context = match latest_context(root, &context_kind, &context_id) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                4,
                "AOS-WORK-CONTEXT-UNRESOLVED",
                "Work context reference cannot be resolved",
                "protocol:context-snapshot",
            );
        }
    };
    if extract_string(&work.raw, "project_id").as_deref() != Some(context.project_id.as_str()) {
        return failure(
            summary,
            4,
            "AOS-GOVERNANCE-CROSS-PROJECT-CONTEXT",
            "Work and context must belong to the same Project",
            "governance:cross-project-reference-denied",
        );
    }
    if context.document.lifecycle.as_deref() != Some("active")
        || context.document.freshness.as_deref() == Some("stale")
        || context.document.freshness.as_deref() == Some("unknown")
    {
        return failure(
            summary,
            4,
            "AOS-GOVERNANCE-CONTEXT-STALE",
            "stale, unknown, or inactive context cannot be authorized",
            "governance:stale-context-blocked",
        );
    }
    if let Err(result) = ensure_protocol(root) {
        return result;
    }
    let timestamp = unix_timestamp();
    let decision_id = format!("decision-{work_id}-{timestamp}");
    let decision = format!(
        "{{\"kind\":\"Governance\",\"id\":\"{}\",\"project_id\":\"{}\",\"contract_version\":\"AOS-SPEC-001\",\"revision\":\"1\",\"subject\":\"work:{}\",\"decision_type\":\"approval\",\"responsible_principal\":\"{}\",\"decision_instant_unix\":\"{}\",\"outcome\":\"approved\",\"policy_basis\":\"{}\",\"evidence_reference\":\"{}\",\"context_reference\":\"{}:{}@{}\",\"protocol_reference\":\"{}\",\"previous_decision\":null}}",
        decision_id,
        escape_json(&context.project_id),
        escape_json(work_id),
        escape_json(authority),
        timestamp,
        escape_json(
            input
                .reason
                .as_deref()
                .unwrap_or("explicit local governance approval")
        ),
        escape_json(evidence),
        escape_json(&context.document.kind),
        escape_json(&context.document.id),
        context.document.revision,
        VERIFY_PROTOCOL,
    );
    let decision_relative = format!(".aos/governance/{decision_id}.r1.json");
    if let Err(error) = write_immutable(&root.join(&decision_relative), &decision, timestamp) {
        return failure(
            summary,
            8,
            "AOS-GOVERNANCE-DECISION-UNKNOWN",
            &error,
            "governance:reconciliation-required",
        );
    }

    let mut context_relative = None;
    let context_revision = if context.document.authority.as_deref() == Some("proposed") {
        let next = context.document.revision + 1;
        let promoted = promoted_context(&context, next, timestamp, &decision_id);
        let relative = format!(
            ".aos/{}/{}.r{}.json",
            context.document.kind.to_lowercase(),
            context.document.id,
            next
        );
        if let Err(error) = write_immutable(&root.join(&relative), &promoted, timestamp) {
            return failure(
                summary,
                8,
                "AOS-GOVERNANCE-PROMOTION-UNKNOWN",
                &error,
                "governance:promotion-reconciliation-required",
            );
        }
        context_relative = Some(relative);
        next
    } else {
        context.document.revision
    };
    let work_revision = work.revision + 1;
    let authorized = replace_work(
        &work.raw,
        work_revision,
        timestamp,
        "authorized",
        "authoritative",
        &format!("governance:{decision_id}"),
        &format!("{}:{}@{}", context_kind, context_id, context_revision),
        None,
        None,
    );
    let work_relative = format!(".aos/work/{work_id}.r{work_revision}.json");
    if let Err(error) = write_immutable(&root.join(&work_relative), &authorized, timestamp) {
        return failure(
            summary,
            8,
            "AOS-WORK-AUTHORIZATION-UNKNOWN",
            &error,
            "work:authorization-reconciliation-required",
        );
    }
    let audit = match audit_event(
        root,
        timestamp + 1,
        work_id,
        "work_authorized",
        authority,
        &format!("governance:{decision_id}"),
        &format!("work:{work_id}@{work_revision}"),
    ) {
        Ok(value) => value,
        Err(error) => {
            return failure(
                summary,
                8,
                "AOS-AUDIT-WRITE-UNKNOWN",
                &error,
                "audit:reconciliation-required",
            );
        }
    };
    let mut paths = vec![decision_relative, work_relative];
    if let Some(relative) = context_relative {
        paths.push(relative);
    }
    let diagnostics = vec![Diagnostic::info(
        "AOS-WORK-AUTHORIZED",
        format!("Work {work_id} authorized under {VERIFY_PROTOCOL}"),
    )];
    success(
        summary,
        diagnostics,
        vec![
            "governance:approval-recorded".to_string(),
            "governance:promotion-or-validation".to_string(),
            audit,
        ],
        authorized,
        OperationSummary {
            id: format!("op-work-authorize-{timestamp}"),
            result: "authorized".to_string(),
            changed_paths: paths,
            verification: "authority, scope, context freshness, and protocol version verified"
                .to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec![format!("evidence:{evidence}")],
            timestamp: timestamp.to_string(),
        },
    )
}

fn run(summary: &RepositorySummary, root: &Path, input: WorkInput) -> QueryResult {
    let work_id = match required_id(input.work_id.as_deref(), "work id") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let executor = match non_empty(input.authority.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-WORK-EXECUTOR-REQUIRED",
                "running a Protocol requires --authority <EXECUTOR>",
                "protocol:executor-required",
            );
        }
    };
    let work = match latest_document(root, "work", work_id) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                4,
                "AOS-WORK-NOT-FOUND",
                "the requested Work revision does not exist",
                "work:reference-unresolved",
            );
        }
    };
    if work.status.as_deref() != Some("authorized") {
        return failure(
            summary,
            4,
            "AOS-WORK-TRANSITION-INVALID",
            "only authorized Work can start a Protocol Run",
            "work:state-machine",
        );
    }
    let protocol = extract_string(&work.raw, "protocol_id").map(|id| {
        format!(
            "{id}@{}",
            extract_string(&work.raw, "protocol_version").unwrap_or_default()
        )
    });
    if protocol.as_deref() != Some(VERIFY_PROTOCOL) {
        return failure(
            summary,
            4,
            "AOS-PROTOCOL-UNSUPPORTED",
            "Work is bound to an unsupported Protocol version",
            "protocol:unsupported-version",
        );
    }
    if let Err(result) = ensure_protocol(root) {
        return result;
    }
    let context_reference = extract_string(&work.raw, "context_reference").unwrap_or_default();
    let (context_kind, context_id, context_revision) =
        match parse_context_reference(&context_reference) {
            Some(value) => value,
            None => {
                return failure(
                    summary,
                    4,
                    "AOS-PROTOCOL-CONTEXT-UNRESOLVED",
                    "Work context snapshot is not a resolvable immutable revision",
                    "protocol:context-snapshot",
                );
            }
        };
    let context = match context_at_revision(root, context_kind, context_id, context_revision) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                4,
                "AOS-PROTOCOL-CONTEXT-UNRESOLVED",
                "the declared context snapshot revision does not exist",
                "protocol:context-snapshot",
            );
        }
    };
    if context.document.authority.as_deref() != Some("authoritative")
        || context.document.lifecycle.as_deref() != Some("active")
        || (context.document.kind == "State"
            && context.document.freshness.as_deref() != Some("confirmed"))
    {
        return failure(
            summary,
            4,
            "AOS-PROTOCOL-CONTEXT-INELIGIBLE",
            "Protocol Run requires authoritative, active, and confirmed context",
            "protocol:precondition-blocked",
        );
    }
    let result = input.result.as_deref().unwrap_or("succeeded");
    if !matches!(result, "succeeded" | "failed" | "partial" | "unknown") {
        return failure(
            summary,
            2,
            "AOS-PROTOCOL-RESULT-INVALID",
            "run result must be succeeded, failed, partial, or unknown",
            "protocol:result-validation",
        );
    }
    if input
        .evidence
        .as_deref()
        .is_some_and(contains_sensitive_reference)
    {
        return failure(
            summary,
            4,
            "AOS-PROTOCOL-SENSITIVE-EVIDENCE",
            "Run evidence must be a non-secret reference",
            "protocol:sensitive-evidence-rejected",
        );
    }
    let timestamp = unix_timestamp();
    let run_revision = next_revision(root, "runs", work_id);
    let run_status = match result {
        "succeeded" => "succeeded",
        "failed" => "failed",
        "partial" => "partial",
        _ => "unknown",
    };
    let reason = input.reason.as_deref().unwrap_or(if result == "succeeded" {
        "repository boundary and context snapshot checks passed"
    } else {
        "declared non-success result requires explicit recovery"
    });
    let run = format!(
        "{{\"kind\":\"Run\",\"id\":\"{}-run\",\"revision\":\"{}\",\"contract_version\":\"AOS-SPEC-003\",\"work_reference\":\"{}@{}\",\"protocol_reference\":\"{}\",\"context_snapshot\":\"{}\",\"executor\":\"{}\",\"started_at_unix\":\"{}\",\"finished_at_unix\":\"{}\",\"status\":\"{}\",\"step\":\"local-context-verification\",\"result\":\"{}\",\"evidence_reference\":\"{}\",\"reason\":\"{}\",\"reconciliation\":\"{}\"}}",
        work_id,
        run_revision,
        work_id,
        work.revision,
        VERIFY_PROTOCOL,
        escape_json(&context_reference),
        escape_json(executor),
        timestamp,
        timestamp,
        run_status,
        result,
        escape_json(
            input
                .evidence
                .as_deref()
                .unwrap_or("aos:local-context-verification")
        ),
        escape_json(reason),
        if matches!(result, "partial" | "unknown") {
            "required"
        } else {
            "not_required"
        },
    );
    let run_relative = format!(".aos/runs/{work_id}.r{run_revision}.json");
    if let Err(error) = write_immutable(&root.join(&run_relative), &run, timestamp) {
        return failure(
            summary,
            8,
            "AOS-PROTOCOL-RUN-UNKNOWN",
            &error,
            "protocol:run-reconciliation-required",
        );
    }
    let in_progress = replace_work(
        &work.raw,
        work.revision + 1,
        timestamp + 1,
        "in_progress",
        "authoritative",
        &extract_string(&work.raw, "authority_basis")
            .unwrap_or_else(|| "governance:unknown".to_string()),
        &context_reference,
        None,
        None,
    );
    let progress_relative = format!(".aos/work/{work_id}.r{}.json", work.revision + 1);
    if let Err(error) = write_immutable(&root.join(&progress_relative), &in_progress, timestamp + 1)
    {
        return failure(
            summary,
            8,
            "AOS-WORK-START-UNKNOWN",
            &error,
            "work:start-reconciliation-required",
        );
    }
    let (work_status, outcome) = match result {
        "succeeded" => ("completed", "completed"),
        "failed" => ("failed", "failed"),
        _ => ("blocked", "blocked"),
    };
    let completed = replace_work(
        &in_progress,
        work.revision + 2,
        timestamp + 2,
        work_status,
        "authoritative",
        &extract_string(&work.raw, "authority_basis")
            .unwrap_or_else(|| "governance:unknown".to_string()),
        &context_reference,
        if work_status == "completed" {
            Some(
                input
                    .evidence
                    .as_deref()
                    .unwrap_or("aos:local-context-verification"),
            )
        } else {
            None
        },
        Some(reason),
    );
    let work_relative = format!(".aos/work/{work_id}.r{}.json", work.revision + 2);
    if let Err(error) = write_immutable(&root.join(&work_relative), &completed, timestamp + 2) {
        return failure(
            summary,
            8,
            "AOS-WORK-COMPLETION-UNKNOWN",
            &error,
            "work:completion-reconciliation-required",
        );
    }
    let audit = match audit_event(
        root,
        timestamp + 3,
        work_id,
        &format!("protocol_run_{result}"),
        executor,
        &extract_string(&work.raw, "authority_basis")
            .unwrap_or_else(|| "governance:unknown".to_string()),
        &format!("run:{work_id}@{run_revision}"),
    ) {
        Ok(value) => value,
        Err(error) => {
            return failure(
                summary,
                8,
                "AOS-AUDIT-WRITE-UNKNOWN",
                &error,
                "audit:reconciliation-required",
            );
        }
    };
    let diagnostics = vec![Diagnostic::info(
        "AOS-PROTOCOL-RUN-RECORDED",
        format!("Protocol Run recorded with result {result}"),
    )];
    let evidence = vec![
        "protocol:context-snapshot-bound".to_string(),
        "protocol:local-only-verification".to_string(),
        audit,
    ];
    let operation = OperationSummary {
        id: format!("op-work-run-{timestamp}"),
        result: outcome.to_string(),
        changed_paths: vec![run_relative, progress_relative, work_relative],
        verification: reason.to_string(),
        reconciliation: if matches!(result, "partial" | "unknown") {
            "required".to_string()
        } else {
            "not_required".to_string()
        },
        audit_evidence: vec![
            format!("protocol:{VERIFY_PROTOCOL}"),
            format!("executor:{executor}"),
        ],
        timestamp: timestamp.to_string(),
    };
    if result == "succeeded" {
        success(summary, diagnostics, evidence, completed, operation)
    } else {
        recorded_findings(summary, diagnostics, evidence, completed, operation)
    }
}

fn reconcile(summary: &RepositorySummary, root: &Path, input: WorkInput) -> QueryResult {
    let work_id = match required_id(input.work_id.as_deref(), "work id") {
        Ok(value) => value,
        Err(result) => return result,
    };
    let principal = match non_empty(input.authority.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-RECONCILIATION-AUTHORITY-REQUIRED",
                "reconciliation requires --authority <PRINCIPAL>",
                "governance:reconciliation-authority",
            );
        }
    };
    if is_self_authority(principal) {
        return failure(
            summary,
            7,
            "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED",
            "a Runtime or provider cannot reconcile its own uncertain result",
            "governance:self-authority-denied",
        );
    }
    let result = match input.result.as_deref() {
        Some("resolved") | Some("unresolved") => input.result.as_deref().unwrap(),
        _ => {
            return failure(
                summary,
                2,
                "AOS-RECONCILIATION-RESULT-REQUIRED",
                "reconciliation requires --result resolved|unresolved",
                "governance:reconciliation-input",
            );
        }
    };
    let evidence = match non_empty(input.evidence.as_deref()) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                7,
                "AOS-RECONCILIATION-EVIDENCE-REQUIRED",
                "reconciliation requires --evidence <REFERENCE>",
                "governance:reconciliation-evidence",
            );
        }
    };
    if contains_sensitive_reference(evidence) {
        return failure(
            summary,
            4,
            "AOS-RECONCILIATION-SENSITIVE-EVIDENCE",
            "reconciliation evidence must be a non-secret reference",
            "governance:sensitive-evidence-rejected",
        );
    }
    let work = match latest_document(root, "work", work_id) {
        Some(value) => value,
        None => {
            return failure(
                summary,
                4,
                "AOS-WORK-NOT-FOUND",
                "the requested Work revision does not exist",
                "work:reference-unresolved",
            );
        }
    };
    if work.status.as_deref() != Some("blocked") {
        return failure(
            summary,
            4,
            "AOS-RECONCILIATION-NOT-BLOCKED",
            "only blocked Work requires reconciliation",
            "governance:reconciliation-state",
        );
    }
    let timestamp = unix_timestamp();
    let decision_id = format!("reconcile-{work_id}-{timestamp}");
    let decision = format!(
        "{{\"kind\":\"Governance\",\"id\":\"{}\",\"revision\":\"1\",\"contract_version\":\"AOS-SPEC-001\",\"subject\":\"work:{}\",\"decision_type\":\"reconciliation\",\"responsible_principal\":\"{}\",\"decision_instant_unix\":\"{}\",\"outcome\":\"{}\",\"evidence_reference\":\"{}\",\"prior_status\":\"blocked\",\"next_status\":\"{}\"}}",
        decision_id,
        work_id,
        escape_json(principal),
        timestamp,
        result,
        escape_json(evidence),
        if result == "resolved" {
            "authorized"
        } else {
            "blocked"
        },
    );
    let decision_relative = format!(".aos/governance/{decision_id}.r1.json");
    if let Err(error) = write_immutable(&root.join(&decision_relative), &decision, timestamp) {
        return failure(
            summary,
            8,
            "AOS-RECONCILIATION-UNKNOWN",
            &error,
            "governance:reconciliation-required",
        );
    }
    let next_status = if result == "resolved" {
        "authorized"
    } else {
        "blocked"
    };
    let updated = replace_work(
        &work.raw,
        work.revision + 1,
        timestamp + 1,
        next_status,
        "authoritative",
        &format!("governance:{decision_id}"),
        &extract_string(&work.raw, "context_reference").unwrap_or_default(),
        None,
        if result == "resolved" {
            None
        } else {
            Some("reconciliation unresolved")
        },
    );
    let work_relative = format!(".aos/work/{work_id}.r{}.json", work.revision + 1);
    if let Err(error) = write_immutable(&root.join(&work_relative), &updated, timestamp + 1) {
        return failure(
            summary,
            8,
            "AOS-RECONCILIATION-WORK-UNKNOWN",
            &error,
            "governance:reconciliation-required",
        );
    }
    let audit = match audit_event(
        root,
        timestamp + 2,
        work_id,
        &format!("reconciliation_{result}"),
        principal,
        &format!("governance:{decision_id}"),
        &format!("work:{work_id}@{}", work.revision + 1),
    ) {
        Ok(value) => value,
        Err(error) => {
            return failure(
                summary,
                8,
                "AOS-AUDIT-WRITE-UNKNOWN",
                &error,
                "audit:reconciliation-required",
            );
        }
    };
    let diagnostics = vec![Diagnostic::info(
        "AOS-RECONCILIATION-RECORDED",
        format!("reconciliation result {result} recorded"),
    )];
    success(
        summary,
        diagnostics,
        vec!["governance:reconciliation-recorded".to_string(), audit],
        updated,
        OperationSummary {
            id: format!("op-work-reconcile-{timestamp}"),
            result: result.to_string(),
            changed_paths: vec![decision_relative, work_relative],
            verification: format!("reconciliation evidence {evidence} retained"),
            reconciliation: result.to_string(),
            audit_evidence: vec![format!("evidence:{evidence}")],
            timestamp: timestamp.to_string(),
        },
    )
}

fn show(summary: &RepositorySummary, root: &Path, input: WorkInput) -> QueryResult {
    let mut documents = read_documents(&root.join(".aos").join("work"));
    documents.sort_by(|left, right| {
        left.id
            .cmp(&right.id)
            .then(left.revision.cmp(&right.revision))
    });
    if let Some(work_id) = input.work_id.as_deref() {
        documents.retain(|document| document.id == work_id);
    }
    if documents.is_empty() {
        return failure(
            summary,
            4,
            "AOS-WORK-NOT-FOUND",
            "no Work revision matched the query",
            "work:query",
        );
    }
    let selected = documents
        .iter()
        .filter(|document| {
            documents
                .iter()
                .filter(|candidate| candidate.id == document.id)
                .map(|candidate| candidate.revision)
                .max()
                == Some(document.revision)
        })
        .map(|document| document.raw.clone())
        .collect::<Vec<_>>();
    let work_ids = selected
        .iter()
        .filter_map(|raw| extract_string(raw, "id"))
        .collect::<Vec<_>>();
    let governance = read_matching(&root.join(".aos").join("governance"), &work_ids);
    let runs = read_matching(&root.join(".aos").join("runs"), &work_ids);
    let audit = read_matching(&root.join(".aos").join("audit"), &work_ids);
    let data = format!(
        "{{\"work\":[{}],\"governance\":[{}],\"runs\":[{}],\"audit\":[{}]}}",
        selected.join(","),
        governance.join(","),
        runs.join(","),
        audit.join(","),
    );
    success(
        summary,
        vec![Diagnostic::info(
            "AOS-WORK-QUERY",
            format!("returned {} current Work object(s)", selected.len()),
        )],
        vec!["work:traceable-query".to_string()],
        data,
        OperationSummary {
            id: format!("op-work-show-{}", unix_timestamp()),
            result: "queried".to_string(),
            changed_paths: Vec::new(),
            verification: "Work, Governance, Run, and Audit references collected".to_string(),
            reconciliation: "not_required".to_string(),
            audit_evidence: vec!["work:audit-trace".to_string()],
            timestamp: unix_timestamp().to_string(),
        },
    )
}

#[allow(clippy::too_many_arguments)]
fn replace_work(
    raw: &str,
    revision: u64,
    timestamp: u64,
    status: &str,
    authority: &str,
    authority_basis: &str,
    context_reference: &str,
    verification_evidence: Option<&str>,
    reason: Option<&str>,
) -> String {
    let id = extract_string(raw, "id").unwrap_or_default();
    let project_id = extract_string(raw, "project_id").unwrap_or_default();
    let owner = extract_string(raw, "owner").unwrap_or_else(|| "project-owner".to_string());
    let intent = extract_string(raw, "intent").unwrap_or_default();
    let scope = extract_string(raw, "scope").unwrap_or_else(|| ".".to_string());
    let expected = extract_string(raw, "expected_output").unwrap_or_default();
    let verification = extract_string(raw, "verification_requirements").unwrap_or_default();
    let protocol_id =
        extract_string(raw, "protocol_id").unwrap_or_else(|| "aos.local.verify".to_string());
    let protocol_version =
        extract_string(raw, "protocol_version").unwrap_or_else(|| "1.0.0".to_string());
    format!(
        "{{\"kind\":\"Work\",\"id\":\"{}\",\"project_id\":\"{}\",\"contract_version\":\"AOS-SPEC-001\",\"revision\":\"{}\",\"previous_revision\":\"{}@{}\",\"owner\":\"{}\",\"producer\":\"aos-cli\",\"created_at_unix\":\"{}\",\"last_produced_at_unix\":\"{}\",\"authority\":\"{}\",\"lifecycle\":\"active\",\"intent\":\"{}\",\"scope\":\"{}\",\"context_reference\":\"{}\",\"expected_output\":\"{}\",\"verification_requirements\":\"{}\",\"protocol_id\":\"{}\",\"protocol_version\":\"{}\",\"status\":\"{}\",\"failure_reason\":{},\"unresolved_condition\":{},\"verification_evidence\":{},\"authority_basis\":\"{}\",\"authority_reference\":\"{}\"}}",
        escape_json(&id),
        escape_json(&project_id),
        revision,
        escape_json(&id),
        revision - 1,
        escape_json(&owner),
        extract_string(raw, "created_at_unix").unwrap_or_else(|| timestamp.to_string()),
        timestamp,
        escape_json(authority),
        escape_json(&intent),
        escape_json(&scope),
        escape_json(context_reference),
        escape_json(&expected),
        escape_json(&verification),
        escape_json(&protocol_id),
        escape_json(&protocol_version),
        escape_json(status),
        optional_json_string(if matches!(status, "failed" | "blocked") {
            reason
        } else {
            None
        }),
        optional_json_string(if status == "blocked" { reason } else { None }),
        optional_json_string(verification_evidence),
        escape_json(authority_basis),
        escape_json(authority_basis),
    )
}

fn promoted_context(
    context: &ContextDocument,
    revision: u64,
    timestamp: u64,
    decision_id: &str,
) -> String {
    let common = format!(
        "\"kind\":\"{}\",\"id\":\"{}\",\"project_id\":\"{}\",\"contract_version\":\"AOS-SPEC-001\",\"revision\":\"{}\",\"previous_revision\":\"{}@{}\",\"owner\":\"{}\",\"producer\":\"{}\",\"created_at_unix\":\"{}\",\"last_produced_at_unix\":\"{}\",\"authority\":\"authoritative\",\"lifecycle\":\"active\",\"subject\":\"{}\",\"source_reference\":\"{}\",\"derived\":\"false\",\"authority_basis\":\"governance:{}\",\"authority_reference\":\"governance:{}\"",
        context.document.kind,
        escape_json(&context.document.id),
        escape_json(&context.project_id),
        revision,
        escape_json(&context.document.id),
        revision - 1,
        escape_json(&context.owner),
        escape_json(&context.producer),
        extract_string(&context.document.raw, "created_at_unix")
            .unwrap_or_else(|| timestamp.to_string()),
        timestamp,
        escape_json(&context.subject),
        escape_json(&context.source_reference),
        escape_json(decision_id),
        escape_json(decision_id),
    );
    if context.document.kind == "State" {
        format!(
            "{{{common},\"observed_value\":\"{}\",\"observation_instant_unix\":\"{}\",\"observer\":\"{}\",\"freshness\":\"{}\",\"freshness_policy\":\"governance-confirmed\"}}",
            escape_json(context.observed_value.as_deref().unwrap_or("")),
            extract_string(&context.document.raw, "observation_instant_unix")
                .unwrap_or_else(|| timestamp.to_string()),
            escape_json(&context.producer),
            escape_json(context.document.freshness.as_deref().unwrap_or("confirmed")),
        )
    } else {
        format!(
            "{{{common},\"content\":\"{}\"}}",
            escape_json(context.content.as_deref().unwrap_or("")),
        )
    }
}

#[allow(clippy::result_large_err)]
fn ensure_protocol(root: &Path) -> Result<(), QueryResult> {
    let path = root
        .join(".aos")
        .join("protocol")
        .join("aos.local.verify@1.0.0.json");
    if path.exists() {
        let raw = fs::read_to_string(&path).map_err(|error| QueryResult {
            repository: None,
            diagnostics: vec![Diagnostic::error(
                "AOS-PROTOCOL-READ-FAILED",
                error.to_string(),
            )],
            evidence: vec!["protocol:read-failure".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        })?;
        if extract_string(&raw, "id").as_deref() != Some("aos.local.verify")
            || extract_string(&raw, "version").as_deref() != Some("1.0.0")
            || extract_string(&raw, "status").as_deref() != Some("accepted")
        {
            return Err(failure(
                &RepositorySummary {
                    root: root.to_string_lossy().into_owned(),
                    status: "initialized".to_string(),
                    compatibility: "supported".to_string(),
                    control_root: root.join(".aos").to_string_lossy().into_owned(),
                    control_root_state: "directory".to_string(),
                },
                4,
                "AOS-PROTOCOL-CONTRACT-INVALID",
                "aos.local.verify@1.0.0 is not an accepted immutable Protocol",
                "protocol:contract-invalid",
            ));
        }
        return Ok(());
    }
    let timestamp = unix_timestamp();
    let content = "{\"kind\":\"Protocol\",\"id\":\"aos.local.verify\",\"version\":\"1.0.0\",\"status\":\"accepted\",\"purpose\":\"deterministic local-only context and repository verification\",\"inputs\":\"Work revision and Context Snapshot\",\"outputs\":\"verification evidence\",\"steps\":\"repository-boundary, context-authority, context-freshness\",\"governance_points\":\"authorization before run\",\"execution_mode\":\"read_only\",\"failure_behavior\":\"fail_closed_and_reconcile\"}";
    write_immutable(&path, content, timestamp).map_err(|error| {
        failure(
            &RepositorySummary {
                root: root.to_string_lossy().into_owned(),
                status: "initialized".to_string(),
                compatibility: "supported".to_string(),
                control_root: root.join(".aos").to_string_lossy().into_owned(),
                control_root_state: "directory".to_string(),
            },
            8,
            "AOS-PROTOCOL-RECORD-UNKNOWN",
            &error,
            "protocol:record-reconciliation-required",
        )
    })?;
    Ok(())
}

fn audit_event(
    root: &Path,
    timestamp: u64,
    work_id: &str,
    event: &str,
    principal: &str,
    authority_basis: &str,
    subject: &str,
) -> Result<String, String> {
    let filename = format!("{timestamp}-{event}-{work_id}.json");
    let relative = format!(".aos/audit/{filename}");
    let content = format!(
        "{{\"kind\":\"Audit\",\"id\":\"{}\",\"revision\":\"1\",\"subject\":\"{}\",\"event\":\"{}\",\"principal\":\"{}\",\"authority_basis\":\"{}\",\"timestamp_unix\":\"{}\",\"outcome\":\"recorded\",\"evidence_reference\":\"{}\",\"secret_policy\":\"withheld\"}}",
        escape_json(&filename),
        escape_json(subject),
        escape_json(event),
        escape_json(principal),
        escape_json(authority_basis),
        timestamp,
        escape_json(subject),
    );
    write_immutable(&root.join(&relative), &content, timestamp)
        .map(|()| format!("audit:{filename}"))
        .map_err(|error| format!("audit evidence requires reconciliation: {error}"))
}

fn read_matching(directory: &Path, ids: &[String]) -> Vec<String> {
    let mut values = fs::read_dir(directory)
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .map(|entry| entry.path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("json"))
        .filter_map(|path| fs::read_to_string(path).ok())
        .filter(|raw| ids.iter().any(|id| raw.contains(id)))
        .collect::<Vec<_>>();
    values.sort();
    values
}

fn latest_context(root: &Path, kind: &str, id: &str) -> Option<ContextDocument> {
    let directory = root.join(".aos").join(kind.to_lowercase());
    let mut documents = read_documents(&directory)
        .into_iter()
        .filter(|document| document.id == id && document.kind == kind)
        .collect::<Vec<_>>();
    documents.sort_by_key(|document| document.revision);
    context_document(root, documents.pop()?)
}

fn context_at_revision(
    root: &Path,
    kind: &str,
    id: &str,
    revision: u64,
) -> Option<ContextDocument> {
    let document = read_documents(&root.join(".aos").join(kind.to_lowercase()))
        .into_iter()
        .find(|document| {
            document.id == id && document.kind == kind && document.revision == revision
        })?;
    context_document(root, document)
}

fn context_document(root: &Path, document: Document) -> Option<ContextDocument> {
    Some(ContextDocument {
        subject: extract_string(&document.raw, "subject")?,
        source_reference: extract_string(&document.raw, "source_reference")?,
        content: extract_string(&document.raw, "content"),
        observed_value: extract_string(&document.raw, "observed_value"),
        project_id: extract_string(&document.raw, "project_id")
            .unwrap_or_else(|| format!("project-{:016x}", stable_hash(&root.to_string_lossy()))),
        owner: extract_string(&document.raw, "owner")
            .unwrap_or_else(|| "project-owner".to_string()),
        producer: extract_string(&document.raw, "producer")
            .unwrap_or_else(|| "aos-cli".to_string()),
        document,
    })
}

fn parse_context_reference(value: &str) -> Option<(&str, &str, u64)> {
    let (kind, reference) = value.split_once(':')?;
    let (id, revision) = reference.split_once('@')?;
    Some((kind, id, revision.parse().ok()?))
}

fn latest_document(root: &Path, directory: &str, id: &str) -> Option<Document> {
    let mut documents = read_documents(&root.join(".aos").join(directory))
        .into_iter()
        .filter(|document| document.id == id)
        .collect::<Vec<_>>();
    documents.sort_by_key(|document| document.revision);
    documents.pop()
}

fn read_documents(directory: &Path) -> Vec<Document> {
    let mut paths = fs::read_dir(directory)
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .map(|entry| entry.path())
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("json"))
        .collect::<Vec<_>>();
    paths.sort();
    paths
        .into_iter()
        .filter_map(|path| {
            let raw = fs::read_to_string(path).ok()?;
            Some(Document {
                kind: extract_string(&raw, "kind")?,
                id: extract_string(&raw, "id")?,
                revision: extract_string(&raw, "revision")?.parse().ok()?,
                status: extract_string(&raw, "status"),
                authority: extract_string(&raw, "authority"),
                lifecycle: extract_string(&raw, "lifecycle"),
                freshness: extract_string(&raw, "freshness"),
                raw,
            })
        })
        .collect()
}

fn next_revision(root: &Path, directory: &str, id: &str) -> u64 {
    read_documents(&root.join(".aos").join(directory))
        .into_iter()
        .filter(|document| document.id == id)
        .map(|document| document.revision)
        .max()
        .unwrap_or(0)
        + 1
}

fn write_immutable(target: &Path, content: &str, nonce: u64) -> Result<(), String> {
    let parent = target
        .parent()
        .ok_or_else(|| "target has no parent".to_string())?;
    fs::create_dir_all(parent).map_err(|error| format!("create directory: {error}"))?;
    if target.exists() {
        return Err("immutable target already exists".to_string());
    }
    let temporary = parent.join(format!(
        ".tmp-{}-{nonce}.json",
        target
            .file_stem()
            .map(|value| value.to_string_lossy())
            .unwrap_or_default()
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(|error| format!("create temporary file: {error}"))?;
    file.write_all(content.as_bytes())
        .map_err(|error| format!("write file: {error}"))?;
    file.write_all(b"\n")
        .map_err(|error| format!("terminate file: {error}"))?;
    file.sync_all()
        .map_err(|error| format!("sync file: {error}"))?;
    drop(file);
    fs::rename(&temporary, target).map_err(|error| {
        let _ = fs::remove_file(&temporary);
        format!("commit immutable file: {error}")
    })
}

#[allow(clippy::result_large_err)]
fn required<'a>(value: Option<&'a str>, field: &str) -> Result<&'a str, QueryResult> {
    non_empty(value).ok_or_else(|| {
        failure(
            &RepositorySummary {
                root: String::new(),
                status: "unknown".to_string(),
                compatibility: "unknown".to_string(),
                control_root: String::new(),
                control_root_state: "unknown".to_string(),
            },
            2,
            "AOS-WORK-FIELD-REQUIRED",
            &format!("{field} is required"),
            "work:input-validation",
        )
    })
}

#[allow(clippy::result_large_err)]
fn required_id<'a>(value: Option<&'a str>, field: &str) -> Result<&'a str, QueryResult> {
    let value = required(value, field)?;
    if valid_id(value) {
        Ok(value)
    } else {
        Err(failure(
            &RepositorySummary {
                root: String::new(),
                status: "unknown".to_string(),
                compatibility: "unknown".to_string(),
                control_root: String::new(),
                control_root_state: "unknown".to_string(),
            },
            2,
            "AOS-WORK-ID-INVALID",
            "identifier is not safe",
            "work:input-validation",
        ))
    }
}

fn non_empty(value: Option<&str>) -> Option<&str> {
    value.filter(|value| !value.trim().is_empty())
}

fn success(
    summary: &RepositorySummary,
    diagnostics: Vec<Diagnostic>,
    evidence: Vec<String>,
    data: String,
    operation: OperationSummary,
) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics,
        evidence,
        data,
        plan: None,
        operation: Some(operation),
        exit_code: 0,
        outcome: "success".to_string(),
    }
}

fn recorded_findings(
    summary: &RepositorySummary,
    diagnostics: Vec<Diagnostic>,
    evidence: Vec<String>,
    data: String,
    operation: OperationSummary,
) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics,
        evidence,
        data,
        plan: None,
        operation: Some(operation),
        exit_code: 4,
        outcome: "findings".to_string(),
    }
}

fn failure(
    summary: &RepositorySummary,
    exit_code: u8,
    code: &'static str,
    message: &str,
    evidence: &str,
) -> QueryResult {
    QueryResult {
        repository: Some(summary.clone()),
        diagnostics: vec![Diagnostic::error(code, message)],
        evidence: vec![evidence.to_string()],
        data: "null".to_string(),
        plan: None,
        operation: None,
        exit_code,
        outcome: if exit_code == 7 {
            "authorization_required".to_string()
        } else {
            "findings".to_string()
        },
    }
}

fn optional_json_string(value: Option<&str>) -> String {
    value
        .map(|value| format!("\"{}\"", escape_json(value)))
        .unwrap_or_else(|| "null".to_string())
}

fn extract_string(content: &str, key: &str) -> Option<String> {
    let marker = format!("\"{key}\":\"");
    let start = content.find(&marker)? + marker.len();
    let mut value = String::new();
    let mut escaped = false;
    for character in content[start..].chars() {
        if escaped {
            match character {
                '"' => value.push('"'),
                '\\' => value.push('\\'),
                'n' => value.push('\n'),
                'r' => value.push('\r'),
                't' => value.push('\t'),
                other => {
                    value.push('\\');
                    value.push(other);
                }
            }
            escaped = false;
        } else if character == '\\' {
            escaped = true;
        } else if character == '"' {
            return Some(value);
        } else {
            value.push(character);
        }
    }
    None
}

fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.')
        })
}

fn is_self_authority(value: &str) -> bool {
    value == "aos-cli"
        || value == "local-runtime"
        || value.starts_with("runtime:")
        || value.starts_with("provider:")
}

fn contains_sensitive_reference(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    ["api_key=", "apikey=", "password=", "secret=", "token="]
        .iter()
        .any(|marker| lower.contains(marker))
}

fn stable_hash(value: &str) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in value.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs())
        .unwrap_or(0)
}
