use std::fmt::Write as _;

pub const CLI_CONTRACT_VERSION: &str = "AOS-SPEC-004";
pub const CLI_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const RESULT_SCHEMA_VERSION: &str = "1";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum OutputFormat {
    Human,
    Json,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Severity {
    Info,
    Warning,
    Error,
}

impl Severity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub code: String,
    pub severity: Severity,
    pub message: String,
    pub path: Option<String>,
}

impl Diagnostic {
    pub fn info(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            severity: Severity::Info,
            message: message.into(),
            path: None,
        }
    }

    pub fn warning(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            severity: Severity::Warning,
            message: message.into(),
            path: None,
        }
    }

    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            severity: Severity::Error,
            message: message.into(),
            path: None,
        }
    }

    pub fn with_path(mut self, path: impl Into<String>) -> Self {
        self.path = Some(path.into());
        self
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RepositorySummary {
    pub root: String,
    pub status: String,
    pub compatibility: String,
    pub control_root: String,
    pub control_root_state: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OwnershipDecision {
    pub path: String,
    pub ownership: String,
    pub decision: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PlanSummary {
    pub id: String,
    pub snapshot: String,
    pub root: String,
    pub authority_required: bool,
    pub affected_paths: Vec<String>,
    pub preconditions: Vec<String>,
    pub ownership: Vec<OwnershipDecision>,
    pub recovery: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OperationSummary {
    pub id: String,
    pub result: String,
    pub changed_paths: Vec<String>,
    pub verification: String,
    pub reconciliation: String,
    pub audit_evidence: Vec<String>,
    pub timestamp: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResultEnvelope {
    pub command: String,
    pub outcome: String,
    pub repository: Option<RepositorySummary>,
    pub diagnostics: Vec<Diagnostic>,
    pub evidence: Vec<String>,
    pub data: Option<String>,
    pub plan: Option<PlanSummary>,
    pub operation: Option<OperationSummary>,
    pub error_category: Option<String>,
}

impl ResultEnvelope {
    pub fn success(command: impl Into<String>) -> Self {
        Self {
            command: command.into(),
            outcome: "success".to_string(),
            repository: None,
            diagnostics: Vec::new(),
            evidence: Vec::new(),
            data: None,
            plan: None,
            operation: None,
            error_category: None,
        }
    }

    pub fn findings(command: impl Into<String>) -> Self {
        Self {
            command: command.into(),
            outcome: "findings".to_string(),
            repository: None,
            diagnostics: Vec::new(),
            evidence: Vec::new(),
            data: None,
            plan: None,
            operation: None,
            error_category: None,
        }
    }

    pub fn error(command: impl Into<String>, category: impl Into<String>) -> Self {
        Self {
            command: command.into(),
            outcome: "error".to_string(),
            repository: None,
            diagnostics: Vec::new(),
            evidence: Vec::new(),
            data: None,
            plan: None,
            operation: None,
            error_category: Some(category.into()),
        }
    }

    pub fn to_json(&self) -> String {
        let mut output = String::from("{");
        write_json_field(&mut output, "schema_version", RESULT_SCHEMA_VERSION, true);
        write_json_field(&mut output, "command", &self.command, false);
        write_json_field(&mut output, "outcome", &self.outcome, false);

        output.push_str(",\"repository\":");
        match &self.repository {
            Some(repository) => output.push_str(&repository.to_json()),
            None => output.push_str("null"),
        }

        output.push_str(",\"diagnostics\":[");
        for (index, diagnostic) in self.diagnostics.iter().enumerate() {
            if index > 0 {
                output.push(',');
            }
            output.push_str(&diagnostic.to_json());
        }
        output.push(']');

        output.push_str(",\"evidence\":[");
        for (index, evidence) in self.evidence.iter().enumerate() {
            if index > 0 {
                output.push(',');
            }
            output.push('"');
            output.push_str(&escape_json(evidence));
            output.push('"');
        }
        output.push(']');

        output.push_str(",\"data\":");
        match &self.data {
            Some(data) => output.push_str(data),
            None => output.push_str("null"),
        }

        output.push_str(",\"plan\":");
        match &self.plan {
            Some(plan) => output.push_str(&plan.to_json()),
            None => output.push_str("null"),
        }

        output.push_str(",\"operation\":");
        match &self.operation {
            Some(operation) => output.push_str(&operation.to_json()),
            None => output.push_str("null"),
        }

        output.push_str(",\"error\":");
        match &self.error_category {
            Some(category) => {
                output.push_str("{\"category\":\"");
                output.push_str(&escape_json(category));
                output.push_str("\"}");
            }
            None => output.push_str("null"),
        }
        output.push('}');
        output
    }

    pub fn to_human(&self, quiet: bool) -> String {
        let mut output = String::new();
        writeln!(&mut output, "AOS {}", self.command).expect("writing to String cannot fail");
        writeln!(&mut output, "Outcome: {}", self.outcome).expect("writing to String cannot fail");

        if let Some(repository) = &self.repository {
            writeln!(&mut output, "Repository root: {}", repository.root)
                .expect("writing to String cannot fail");
            writeln!(&mut output, "Status: {}", repository.status)
                .expect("writing to String cannot fail");
            writeln!(&mut output, "Compatibility: {}", repository.compatibility)
                .expect("writing to String cannot fail");
            writeln!(
                &mut output,
                "Control root: {} ({})",
                repository.control_root, repository.control_root_state
            )
            .expect("writing to String cannot fail");
        }

        if let Some(data) = &self.data {
            writeln!(&mut output, "Data: {data}").expect("writing to String cannot fail");
        }

        if !quiet || self.outcome != "success" {
            for diagnostic in &self.diagnostics {
                let path = diagnostic
                    .path
                    .as_deref()
                    .map(|value| format!(" [{value}]"))
                    .unwrap_or_default();
                writeln!(
                    &mut output,
                    "[{}] {}{}: {}",
                    diagnostic.severity.as_str(),
                    diagnostic.code,
                    path,
                    diagnostic.message
                )
                .expect("writing to String cannot fail");
            }
        }

        if let Some(category) = &self.error_category {
            writeln!(&mut output, "Error category: {category}")
                .expect("writing to String cannot fail");
        }
        if let Some(plan) = &self.plan {
            writeln!(
                &mut output,
                "Plan: {} (snapshot {})",
                plan.id, plan.snapshot
            )
            .expect("writing to String cannot fail");
            writeln!(
                &mut output,
                "Authority required: {}",
                plan.authority_required
            )
            .expect("writing to String cannot fail");
            writeln!(
                &mut output,
                "Affected paths: {}",
                plan.affected_paths.join(", ")
            )
            .expect("writing to String cannot fail");
        }
        if let Some(operation) = &self.operation {
            writeln!(
                &mut output,
                "Operation: {} ({})",
                operation.id, operation.result
            )
            .expect("writing to String cannot fail");
            writeln!(
                &mut output,
                "Verification: {} ({})",
                operation.verification, operation.reconciliation
            )
            .expect("writing to String cannot fail");
        }
        output
    }
}

impl Diagnostic {
    fn to_json(&self) -> String {
        let mut output = String::from("{\"code\":\"");
        output.push_str(&escape_json(&self.code));
        output.push_str("\",\"severity\":\"");
        output.push_str(self.severity.as_str());
        output.push_str("\",\"message\":\"");
        output.push_str(&escape_json(&self.message));
        output.push_str("\",\"path\":");
        match &self.path {
            Some(path) => {
                output.push('"');
                output.push_str(&escape_json(path));
                output.push('"');
            }
            None => output.push_str("null"),
        }
        output.push('}');
        output
    }
}

impl RepositorySummary {
    fn to_json(&self) -> String {
        format!(
            "{{\"root\":\"{}\",\"status\":\"{}\",\"compatibility\":\"{}\",\"control_root\":\"{}\",\"control_root_state\":\"{}\"}}",
            escape_json(&self.root),
            escape_json(&self.status),
            escape_json(&self.compatibility),
            escape_json(&self.control_root),
            escape_json(&self.control_root_state),
        )
    }
}

impl OwnershipDecision {
    fn to_json(&self) -> String {
        format!(
            "{{\"path\":\"{}\",\"ownership\":\"{}\",\"decision\":\"{}\"}}",
            escape_json(&self.path),
            escape_json(&self.ownership),
            escape_json(&self.decision),
        )
    }
}

impl PlanSummary {
    fn to_json(&self) -> String {
        let mut output = format!(
            "{{\"id\":\"{}\",\"snapshot\":\"{}\",\"root\":\"{}\",\"authority_required\":{},\"affected_paths\":[",
            escape_json(&self.id),
            escape_json(&self.snapshot),
            escape_json(&self.root),
            self.authority_required,
        );
        write_json_strings(&mut output, &self.affected_paths);
        output.push_str("],\"preconditions\":[");
        write_json_strings(&mut output, &self.preconditions);
        output.push_str("],\"ownership\":[");
        for (index, ownership) in self.ownership.iter().enumerate() {
            if index > 0 {
                output.push(',');
            }
            output.push_str(&ownership.to_json());
        }
        output.push_str("],\"recovery\":\"");
        output.push_str(&escape_json(&self.recovery));
        output.push_str("\"}");
        output
    }
}

impl OperationSummary {
    fn to_json(&self) -> String {
        let mut output = format!(
            "{{\"id\":\"{}\",\"result\":\"{}\",\"changed_paths\":[",
            escape_json(&self.id),
            escape_json(&self.result),
        );
        write_json_strings(&mut output, &self.changed_paths);
        output.push_str("],\"verification\":\"");
        output.push_str(&escape_json(&self.verification));
        output.push_str("\",\"reconciliation\":\"");
        output.push_str(&escape_json(&self.reconciliation));
        output.push_str("\",\"audit_evidence\":[");
        write_json_strings(&mut output, &self.audit_evidence);
        output.push_str("],\"timestamp\":\"");
        output.push_str(&escape_json(&self.timestamp));
        output.push_str("\"}");
        output
    }
}

pub fn escape_json(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            character if character.is_control() => {
                write!(&mut escaped, "\\u{:04x}", character as u32)
                    .expect("writing to String cannot fail");
            }
            character => escaped.push(character),
        }
    }
    escaped
}

fn write_json_strings(output: &mut String, values: &[String]) {
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push('"');
        output.push_str(&escape_json(value));
        output.push('"');
    }
}

fn write_json_field(output: &mut String, name: &str, value: &str, first: bool) {
    if !first {
        output.push(',');
    }
    output.push('"');
    output.push_str(name);
    output.push_str("\":\"");
    output.push_str(&escape_json(value));
    output.push('"');
}

#[cfg(test)]
mod tests {
    use super::escape_json;

    #[test]
    fn json_escape_handles_control_characters() {
        assert_eq!(escape_json("a\"b\\c\n"), "a\\\"b\\\\c\\n");
    }
}
