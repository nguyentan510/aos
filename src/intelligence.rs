use crate::model::{
    Diagnostic, OperationSummary, OwnershipDecision, PlanSummary, RepositorySummary,
};
use crate::repository;
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

const INFORMATION_CONTRACT_VERSION: &str = "AOS-SPEC-001";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RecordKind {
    Knowledge,
    State,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ContextProfile {
    Full,
    Compact,
}

impl ContextProfile {
    fn as_str(self) -> &'static str {
        match self {
            Self::Full => "full",
            Self::Compact => "compact",
        }
    }
}

impl RecordKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Knowledge => "Knowledge",
            Self::State => "State",
        }
    }

    fn directory(self) -> &'static str {
        match self {
            Self::Knowledge => "knowledge",
            Self::State => "state",
        }
    }

    fn other(self) -> Self {
        match self {
            Self::Knowledge => Self::State,
            Self::State => Self::Knowledge,
        }
    }
}

#[derive(Debug)]
pub struct RecordInput {
    pub kind: RecordKind,
    pub path: Option<PathBuf>,
    pub id: Option<String>,
    pub subject: Option<String>,
    pub content: Option<String>,
    pub value: Option<String>,
    pub source: Option<String>,
    pub classification: Option<String>,
    pub freshness: Option<String>,
    pub apply: bool,
    pub authority: Option<String>,
}

#[derive(Debug)]
pub struct QueryResult {
    pub repository: Option<RepositorySummary>,
    pub diagnostics: Vec<Diagnostic>,
    pub evidence: Vec<String>,
    pub data: String,
    pub plan: Option<PlanSummary>,
    pub operation: Option<OperationSummary>,
    pub exit_code: u8,
    pub outcome: String,
}

#[derive(Debug)]
struct StoredRecord {
    raw: String,
    kind: RecordKind,
    id: String,
    revision: u64,
    subject: String,
    source_reference: String,
    content: Option<String>,
    observed_value: Option<String>,
    authority: String,
    lifecycle: String,
    freshness: Option<String>,
}

struct RecordDocument<'a> {
    kind: RecordKind,
    id: &'a str,
    project_id: &'a str,
    revision: u64,
    subject: &'a str,
    content: &'a str,
    source: &'a str,
    freshness: &'a str,
    authority_reference: &'a str,
    timestamp: u64,
}

pub fn query(kind: RecordKind, path: Option<&Path>, limit: usize) -> QueryResult {
    let inspection = match repository::inspect(path) {
        Ok(value) => value,
        Err(error) => {
            return QueryResult {
                repository: None,
                diagnostics: vec![Diagnostic::error(error.code, error.message)],
                evidence: vec!["knowledge:root-resolution".to_string()],
                data: "null".to_string(),
                plan: None,
                operation: None,
                exit_code: 3,
                outcome: "error".to_string(),
            };
        }
    };

    if inspection.summary.status != "initialized" {
        return QueryResult {
            repository: Some(inspection.summary),
            diagnostics: vec![Diagnostic::error(
                "AOS-INTELLIGENCE-REPOSITORY-NOT-INITIALIZED",
                "Knowledge and State require a supported initialized repository",
            )],
            evidence: vec!["knowledge:repository-boundary".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        };
    }

    let root = PathBuf::from(
        inspection
            .summary
            .root
            .strip_prefix(r"\\?\")
            .unwrap_or(&inspection.summary.root),
    );
    let (records, mut diagnostics) = read_records(&root, kind);
    let mut items = Vec::new();
    for record in records.into_iter().take(limit) {
        items.push(record.raw);
    }
    diagnostics.push(Diagnostic::info(
        "AOS-INTELLIGENCE-QUERY",
        format!("returned {} {} record(s)", items.len(), kind.as_str()),
    ));
    let has_errors = diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == crate::model::Severity::Error);
    QueryResult {
        repository: Some(inspection.summary),
        diagnostics,
        evidence: vec![
            "knowledge:provider-independent-query".to_string(),
            format!("knowledge:kind:{}", kind.as_str()),
        ],
        data: format!("[{}]", items.join(",")),
        plan: None,
        operation: None,
        exit_code: if has_errors { 4 } else { 0 },
        outcome: if has_errors { "findings" } else { "success" }.to_string(),
    }
}

pub fn context(
    path: Option<&Path>,
    limit: usize,
    profile: ContextProfile,
    budget_bytes: Option<usize>,
) -> QueryResult {
    let inspection = match repository::inspect(path) {
        Ok(value) => value,
        Err(error) => {
            return QueryResult {
                repository: None,
                diagnostics: vec![Diagnostic::error(error.code, error.message)],
                evidence: vec!["context:root-resolution".to_string()],
                data: "null".to_string(),
                plan: None,
                operation: None,
                exit_code: 3,
                outcome: "error".to_string(),
            };
        }
    };
    if inspection.summary.status != "initialized" {
        return QueryResult {
            repository: Some(inspection.summary),
            diagnostics: vec![Diagnostic::error(
                "AOS-CONTEXT-REPOSITORY-NOT-INITIALIZED",
                "context retrieval requires a supported initialized repository",
            )],
            evidence: vec!["context:repository-boundary".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        };
    }

    let root = PathBuf::from(
        inspection
            .summary
            .root
            .strip_prefix(r"\\?\")
            .unwrap_or(&inspection.summary.root),
    );
    let (mut all_records, mut diagnostics) = read_records(&root, RecordKind::Knowledge);
    let (state_records, state_diagnostics) = read_records(&root, RecordKind::State);
    all_records.extend(state_records);
    diagnostics.extend(state_diagnostics);
    all_records.sort_by(|left, right| {
        left.id
            .cmp(&right.id)
            .then(left.revision.cmp(&right.revision))
    });

    let mut latest_by_id = BTreeMap::new();
    let mut withheld = Vec::new();
    for record in all_records {
        if let Some(previous) = latest_by_id.insert(record.id.clone(), record) {
            withheld.push(format!(
                "{{\"id\":\"{}\",\"subject\":\"{}\",\"reason\":\"superseded_by_higher_revision\"}}",
                escape_json(&previous.id),
                escape_json(&previous.subject),
            ));
        }
    }

    let mut selected = Vec::new();
    let mut selected_bytes = 0usize;
    for record in latest_by_id.into_values() {
        let reason = if record.lifecycle != "active" {
            Some(format!("lifecycle_{}", record.lifecycle))
        } else if record.authority != "authoritative" {
            Some("authority_proposed".to_string())
        } else if matches!(record.freshness.as_deref(), Some("stale") | Some("unknown")) {
            Some(format!(
                "freshness_{}",
                record.freshness.as_deref().unwrap_or("unknown")
            ))
        } else {
            None
        };

        if let Some(reason) = reason {
            withheld.push(format!(
                "{{\"id\":\"{}\",\"subject\":\"{}\",\"reason\":\"{}\"}}",
                escape_json(&record.id),
                escape_json(&record.subject),
                escape_json(&reason),
            ));
        } else if selected.len() >= limit {
            withheld.push(format!(
                "{{\"id\":\"{}\",\"subject\":\"{}\",\"reason\":\"selection_limit\"}}",
                escape_json(&record.id),
                escape_json(&record.subject),
            ));
        } else {
            let projected = match profile {
                ContextProfile::Full => record.raw,
                ContextProfile::Compact => compact_record(&record),
            };
            let separator_bytes = if selected.is_empty() { 0 } else { 1 };
            let projected_bytes = projected.len() + separator_bytes;
            if budget_bytes.is_some_and(|budget| selected_bytes + projected_bytes > budget) {
                withheld.push(format!(
                    "{{\"id\":\"{}\",\"subject\":\"{}\",\"reason\":\"context_budget\"}}",
                    escape_json(&record.id),
                    escape_json(&record.subject),
                ));
            } else {
                selected_bytes += projected_bytes;
                selected.push(projected);
            }
        }
    }

    let data = format!(
        "{{\"policy\":\"authoritative-active-knowledge-and-confirmed-state\",\"profile\":\"{}\",\"limit\":{},\"budget_bytes\":{},\"selected_bytes\":{},\"selected\":[{}],\"withheld\":[{}]}}",
        profile.as_str(),
        limit,
        budget_bytes
            .map(|value| value.to_string())
            .unwrap_or_else(|| "null".to_string()),
        selected_bytes,
        selected.join(","),
        withheld.join(","),
    );
    diagnostics.push(Diagnostic::info(
        "AOS-CONTEXT-DETERMINISTIC",
        "context selection uses authority, lifecycle, freshness, stable identity ordering, and an explicit limit",
    ));
    let has_errors = diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == crate::model::Severity::Error);
    QueryResult {
        repository: Some(inspection.summary),
        diagnostics,
        evidence: vec![
            "context:provider-independent-selection".to_string(),
            "context:withheld-items-explained".to_string(),
        ],
        data,
        plan: None,
        operation: None,
        exit_code: if has_errors { 4 } else { 0 },
        outcome: if has_errors { "findings" } else { "success" }.to_string(),
    }
}

pub fn record(input: RecordInput) -> QueryResult {
    let inspection = match repository::inspect(input.path.as_deref()) {
        Ok(value) => value,
        Err(error) => {
            return QueryResult {
                repository: None,
                diagnostics: vec![Diagnostic::error(error.code, error.message)],
                evidence: vec!["knowledge:root-resolution".to_string()],
                data: "null".to_string(),
                plan: None,
                operation: None,
                exit_code: 3,
                outcome: "error".to_string(),
            };
        }
    };
    let repository = inspection.summary.clone();
    if repository.status != "initialized" {
        return QueryResult {
            repository: Some(repository),
            diagnostics: vec![Diagnostic::error(
                "AOS-INTELLIGENCE-REPOSITORY-NOT-INITIALIZED",
                "Knowledge and State recording requires a supported initialized repository",
            )],
            evidence: vec!["knowledge:repository-boundary".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        };
    }
    if !input.apply {
        return plan_result(&repository, &input);
    }
    let authority = match input
        .authority
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        Some(value) => value,
        None => {
            return QueryResult {
                repository: Some(repository),
                diagnostics: vec![Diagnostic::error(
                    "AOS-INTELLIGENCE-AUTHORITY-REQUIRED",
                    "recording Knowledge or State requires --apply --authority <REFERENCE>",
                )],
                evidence: vec!["knowledge:authority-required".to_string()],
                data: "null".to_string(),
                plan: None,
                operation: None,
                exit_code: 7,
                outcome: "authorization_required".to_string(),
            };
        }
    };

    if input.classification.as_deref().unwrap_or("proposed") != "proposed" {
        return QueryResult {
            repository: Some(repository),
            diagnostics: vec![Diagnostic::error(
                "AOS-INTELLIGENCE-PROMOTION-DEFERRED",
                "P4 recording can create proposed objects only; authoritative promotion requires Governance",
            )],
            evidence: vec!["knowledge:promotion-deferred".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 7,
            outcome: "authorization_required".to_string(),
        };
    }

    let id = match input.id.as_deref() {
        Some(value) if valid_id(value) => value.to_string(),
        _ => {
            return invalid_input(
                "AOS-INTELLIGENCE-ID-REQUIRED",
                "recording requires a safe --id",
            );
        }
    };
    let subject = match input
        .subject
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        Some(value) => value,
        None => {
            return invalid_input(
                "AOS-INTELLIGENCE-SUBJECT-REQUIRED",
                "recording requires --subject",
            );
        }
    };
    let source = match input
        .source
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        Some(value) => value,
        None => {
            return invalid_input(
                "AOS-INTELLIGENCE-SOURCE-REQUIRED",
                "recording requires --source",
            );
        }
    };
    let (content_key, content) = match input.kind {
        RecordKind::Knowledge => (
            "content",
            input.content.as_deref().filter(|value| !value.is_empty()),
        ),
        RecordKind::State => (
            "observed_value",
            input.value.as_deref().filter(|value| !value.is_empty()),
        ),
    };
    let content = match content {
        Some(value) => value,
        None => {
            return invalid_input(
                "AOS-INTELLIGENCE-VALUE-REQUIRED",
                format!("recording requires --{content_key}"),
            );
        }
    };
    if contains_sensitive(content) {
        return QueryResult {
            repository: Some(repository),
            diagnostics: vec![Diagnostic::error(
                "AOS-INTELLIGENCE-SENSITIVE-CONTENT",
                "record content resembles a secret and is not accepted as ordinary project intelligence",
            )],
            evidence: vec!["knowledge:sensitive-content-rejected".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 4,
            outcome: "findings".to_string(),
        };
    }
    let freshness = input.freshness.as_deref().unwrap_or("unknown");
    if input.kind == RecordKind::State && !matches!(freshness, "confirmed" | "stale" | "unknown") {
        return invalid_input(
            "AOS-INTELLIGENCE-FRESHNESS-INVALID",
            "state freshness must be confirmed, stale, or unknown",
        );
    }

    let root = PathBuf::from(
        repository
            .root
            .strip_prefix(r"\\?\")
            .unwrap_or(&repository.root),
    );
    if read_records(&root, input.kind.other())
        .0
        .iter()
        .any(|record| record.id == id)
    {
        return QueryResult {
            repository: Some(repository),
            diagnostics: vec![Diagnostic::error(
                "AOS-INTELLIGENCE-ID-CONFLICT",
                "the Information Object id already belongs to another object kind",
            )],
            evidence: vec!["knowledge:identity-conflict".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 5,
            outcome: "conflict".to_string(),
        };
    }
    let revision = next_revision(&root, input.kind, &id);
    let timestamp = unix_timestamp();
    let project_id = repository::project_id(&root)
        .unwrap_or_else(|| format!("project-{:016x}", stable_hash(&repository.root)));
    let record = record_json(&RecordDocument {
        kind: input.kind,
        id: &id,
        project_id: &project_id,
        revision,
        subject,
        content,
        source,
        freshness,
        authority_reference: authority,
        timestamp,
    });
    let relative_path = format!(".aos/{}/{}.r{}.json", input.kind.directory(), id, revision);
    let target = root.join(&relative_path);
    if let Err(error) = atomic_create_record(&target, &record, timestamp) {
        return QueryResult {
            repository: Some(repository),
            diagnostics: vec![Diagnostic::error("AOS-INTELLIGENCE-RECORD-FAILED", error)],
            evidence: vec!["knowledge:record-failure".to_string()],
            data: "null".to_string(),
            plan: None,
            operation: None,
            exit_code: 8,
            outcome: "unknown".to_string(),
        };
    }
    let operation = OperationSummary {
        id: format!("op-knowledge-{timestamp}-{revision}"),
        result: "recorded_proposed".to_string(),
        changed_paths: vec![relative_path.clone()],
        verification: "immutable record file verified".to_string(),
        reconciliation: "not_required".to_string(),
        audit_evidence: vec![format!("authority:{authority}"), format!("source:{source}")],
        timestamp: timestamp.to_string(),
    };
    QueryResult {
        repository: Some(repository),
        diagnostics: vec![Diagnostic::info(
            "AOS-INTELLIGENCE-RECORDED",
            format!(
                "proposed {} revision {} recorded",
                input.kind.as_str(),
                revision
            ),
        )],
        evidence: vec![
            "knowledge:immutable-revision".to_string(),
            "knowledge:provenance-recorded".to_string(),
        ],
        data: record,
        plan: None,
        operation: Some(operation),
        exit_code: 0,
        outcome: "success".to_string(),
    }
}

fn plan_result(repository: &RepositorySummary, input: &RecordInput) -> QueryResult {
    let kind = input.kind.directory();
    let id = input.id.as_deref().unwrap_or("<required-id>");
    let plan = PlanSummary {
        id: format!("plan-{}-{}", kind, stable_hash(&format!("{kind}:{id}"))),
        snapshot: "initialized".to_string(),
        root: repository.root.clone(),
        authority_required: true,
        affected_paths: vec![format!(".aos/{kind}/{id}.rN.json")],
        preconditions: vec![
            "repository remains initialized with a supported manifest".to_string(),
            "the target revision path does not already exist".to_string(),
        ],
        ownership: vec![OwnershipDecision {
            path: format!(".aos/{kind}"),
            ownership: "aos".to_string(),
            decision: "append immutable proposed revision; never overwrite prior revisions"
                .to_string(),
        }],
        recovery: "preserve prior revisions and reconcile an unknown record write".to_string(),
    };
    QueryResult {
        repository: Some(repository.clone()),
        diagnostics: vec![Diagnostic::info(
            "AOS-INTELLIGENCE-PLAN-READY",
            "record plan created; add --apply --authority to write a proposed revision",
        )],
        evidence: vec!["knowledge:record-plan".to_string()],
        data: "null".to_string(),
        plan: Some(plan),
        operation: None,
        exit_code: 0,
        outcome: "plan_ready".to_string(),
    }
}

fn invalid_input(code: &'static str, message: impl Into<String>) -> QueryResult {
    QueryResult {
        repository: None,
        diagnostics: vec![Diagnostic::error(code, message)],
        evidence: vec!["knowledge:input-validation".to_string()],
        data: "null".to_string(),
        plan: None,
        operation: None,
        exit_code: 2,
        outcome: "error".to_string(),
    }
}

fn read_records(root: &Path, kind: RecordKind) -> (Vec<StoredRecord>, Vec<Diagnostic>) {
    let directory = root.join(".aos").join(kind.directory());
    let mut diagnostics = Vec::new();
    let mut paths = match fs::read_dir(&directory) {
        Ok(entries) => entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("json"))
            .collect::<Vec<_>>(),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(error) => {
            diagnostics.push(
                Diagnostic::error(
                    "AOS-INTELLIGENCE-DIRECTORY-READ",
                    format!("cannot read {} records: {error}", kind.as_str()),
                )
                .with_path(directory.to_string_lossy()),
            );
            Vec::new()
        }
    };
    paths.sort();
    let mut records = Vec::new();
    for path in paths {
        let raw = match fs::read_to_string(&path) {
            Ok(value) => value,
            Err(error) => {
                diagnostics.push(
                    Diagnostic::error(
                        "AOS-INTELLIGENCE-RECORD-READ",
                        format!("cannot read Information Object revision: {error}"),
                    )
                    .with_path(path.to_string_lossy()),
                );
                continue;
            }
        };
        let parsed = (|| {
            let stored_kind = extract_string(&raw, "kind")?;
            if stored_kind != kind.as_str() {
                return None;
            }
            Some(StoredRecord {
                id: extract_string(&raw, "id")?,
                kind,
                revision: extract_string(&raw, "revision")?.parse().ok()?,
                subject: extract_string(&raw, "subject")?,
                source_reference: extract_string(&raw, "source_reference")?,
                content: extract_string(&raw, "content"),
                observed_value: extract_string(&raw, "observed_value"),
                authority: extract_string(&raw, "authority")?,
                lifecycle: extract_string(&raw, "lifecycle")?,
                freshness: extract_string(&raw, "freshness"),
                raw,
            })
        })();
        match parsed {
            Some(record) => records.push(record),
            None => diagnostics.push(
                Diagnostic::error(
                    "AOS-INTELLIGENCE-RECORD-INVALID",
                    "Information Object revision has missing, invalid, or mismatched core fields",
                )
                .with_path(path.to_string_lossy()),
            ),
        }
    }
    (records, diagnostics)
}

fn compact_record(record: &StoredRecord) -> String {
    let mut output = format!(
        "{{\"kind\":\"{}\",\"id\":\"{}\",\"revision\":\"{}\",\"subject\":\"{}\",\"source_reference\":\"{}\",\"authority\":\"{}\",\"lifecycle\":\"{}\"",
        record.kind.as_str(),
        escape_json(&record.id),
        record.revision,
        escape_json(&record.subject),
        escape_json(&record.source_reference),
        escape_json(&record.authority),
        escape_json(&record.lifecycle),
    );
    if let Some(freshness) = &record.freshness {
        output.push_str(&format!(",\"freshness\":\"{}\"", escape_json(freshness)));
    }
    match record.kind {
        RecordKind::Knowledge => output.push_str(&format!(
            ",\"content\":\"{}\"",
            escape_json(record.content.as_deref().unwrap_or(""))
        )),
        RecordKind::State => output.push_str(&format!(
            ",\"observed_value\":\"{}\"",
            escape_json(record.observed_value.as_deref().unwrap_or(""))
        )),
    }
    output.push('}');
    output
}

fn next_revision(root: &Path, kind: RecordKind, id: &str) -> u64 {
    read_records(root, kind)
        .0
        .into_iter()
        .filter(|record| record.id == id)
        .map(|record| record.revision)
        .max()
        .unwrap_or(0)
        + 1
}

fn record_json(document: &RecordDocument<'_>) -> String {
    let common = format!(
        "\"kind\":\"{}\",\"id\":\"{}\",\"project_id\":\"{}\",\"contract_version\":\"{}\",\"revision\":\"{}\",\"previous_revision\":{},\"owner\":\"project-owner\",\"producer\":\"aos-cli\",\"created_at_unix\":\"{}\",\"last_produced_at_unix\":\"{}\",\"authority\":\"proposed\",\"lifecycle\":\"active\",\"subject\":\"{}\",\"source_reference\":\"{}\",\"derived\":\"false\",\"authority_basis\":\"pending-governance\",\"authority_reference\":\"{}\"",
        document.kind.as_str(),
        escape_json(document.id),
        escape_json(document.project_id),
        INFORMATION_CONTRACT_VERSION,
        document.revision,
        if document.revision > 1 {
            format!("\"{}@{}\"", escape_json(document.id), document.revision - 1)
        } else {
            "null".to_string()
        },
        document.timestamp,
        document.timestamp,
        escape_json(document.subject),
        escape_json(document.source),
        escape_json(document.authority_reference),
    );
    match document.kind {
        RecordKind::Knowledge => format!(
            "{{{common},\"content\":\"{}\"}}",
            escape_json(document.content)
        ),
        RecordKind::State => format!(
            "{{{common},\"observed_value\":\"{}\",\"observation_instant_unix\":\"{}\",\"observer\":\"aos-cli\",\"freshness\":\"{}\",\"freshness_policy\":\"caller-declared-observation\"}}",
            escape_json(document.content),
            document.timestamp,
            escape_json(document.freshness),
        ),
    }
}

fn atomic_create_record(target: &Path, content: &str, nonce: u64) -> Result<(), String> {
    let parent = target
        .parent()
        .ok_or_else(|| "record target has no parent".to_string())?;
    fs::create_dir_all(parent).map_err(|error| format!("create record directory: {error}"))?;
    if target.exists() {
        return Err("the target immutable revision already exists".to_string());
    }
    let temporary = parent.join(format!(
        ".tmp-{}-{nonce}.json",
        target.file_stem().unwrap().to_string_lossy()
    ));
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)
        .map_err(|error| format!("create temporary record: {error}"))?;
    file.write_all(content.as_bytes())
        .map_err(|error| format!("write record: {error}"))?;
    file.write_all(b"\n")
        .map_err(|error| format!("terminate record: {error}"))?;
    file.sync_all()
        .map_err(|error| format!("sync record: {error}"))?;
    drop(file);
    fs::rename(&temporary, target).map_err(|error| {
        let _ = fs::remove_file(&temporary);
        format!("commit immutable record: {error}")
    })
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

fn contains_sensitive(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    ["api_key=", "apikey=", "password=", "secret=", "token="]
        .iter()
        .any(|marker| normalized.contains(marker))
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

fn escape_json(value: &str) -> String {
    crate::model::escape_json(value)
}
