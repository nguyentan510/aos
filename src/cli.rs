use crate::intelligence::{self, RecordInput, RecordKind};
use crate::model::{CLI_CONTRACT_VERSION, CLI_VERSION, Diagnostic, OutputFormat, ResultEnvelope};
use crate::repository;
use std::path::PathBuf;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Command {
    Version,
    Inspect,
    Validate,
    Doctor,
    Init,
    Knowledge,
    State,
    Context,
    Help,
}

impl Command {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Version => "version",
            Self::Inspect => "inspect",
            Self::Validate => "validate",
            Self::Doctor => "doctor",
            Self::Init => "init",
            Self::Knowledge => "knowledge",
            Self::State => "state",
            Self::Context => "context",
            Self::Help => "help",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Options {
    pub command: Command,
    pub path: Option<PathBuf>,
    pub format: OutputFormat,
    pub quiet: bool,
    pub dry_run: bool,
    pub apply: bool,
    pub authority: Option<String>,
    pub record: bool,
    pub id: Option<String>,
    pub subject: Option<String>,
    pub content: Option<String>,
    pub value: Option<String>,
    pub source: Option<String>,
    pub classification: Option<String>,
    pub freshness: Option<String>,
    pub limit: usize,
}

#[derive(Debug)]
pub struct CommandResult {
    pub envelope: ResultEnvelope,
    pub format: OutputFormat,
    pub quiet: bool,
    pub exit_code: u8,
}

impl CommandResult {
    pub fn render(&self) {
        match self.format {
            OutputFormat::Human => print!("{}", self.envelope.to_human(self.quiet)),
            OutputFormat::Json => println!("{}", self.envelope.to_json()),
        }
    }
}

pub fn parse<I>(arguments: I) -> Result<Options, String>
where
    I: IntoIterator<Item = String>,
{
    let mut command = None;
    let mut path = None;
    let mut format = OutputFormat::Human;
    let mut quiet = false;
    let mut dry_run = false;
    let mut apply = false;
    let mut authority = None;
    let mut record = false;
    let mut id = None;
    let mut subject = None;
    let mut content = None;
    let mut state_value = None;
    let mut source = None;
    let mut classification = None;
    let mut freshness = None;
    let mut limit = 20usize;
    let mut iterator = arguments.into_iter();

    while let Some(argument) = iterator.next() {
        match argument.as_str() {
            "-h" | "--help" => {
                return Ok(Options {
                    command: Command::Help,
                    path: None,
                    format,
                    quiet,
                    dry_run,
                    apply,
                    authority,
                    record,
                    id,
                    subject,
                    content,
                    value: state_value,
                    source,
                    classification,
                    freshness,
                    limit,
                });
            }
            "-V" | "--version" => command = Some(Command::Version),
            "--quiet" => quiet = true,
            "--dry-run" => dry_run = true,
            "--apply" => apply = true,
            "--record" => record = true,
            "--id" => id = Some(next_value(&mut iterator, "--id")?),
            value if value.starts_with("--id=") => id = Some(value[5..].to_string()),
            "--subject" => subject = Some(next_value(&mut iterator, "--subject")?),
            value if value.starts_with("--subject=") => {
                subject = Some(value.trim_start_matches("--subject=").to_string())
            }
            "--content" => content = Some(next_value(&mut iterator, "--content")?),
            value if value.starts_with("--content=") => {
                content = Some(value.trim_start_matches("--content=").to_string())
            }
            "--value" => state_value = Some(next_value(&mut iterator, "--value")?),
            argument if argument.starts_with("--value=") => {
                state_value = Some(argument.trim_start_matches("--value=").to_string())
            }
            "--source" => source = Some(next_value(&mut iterator, "--source")?),
            value if value.starts_with("--source=") => {
                source = Some(value.trim_start_matches("--source=").to_string())
            }
            "--classification" => {
                classification = Some(next_value(&mut iterator, "--classification")?)
            }
            value if value.starts_with("--classification=") => {
                classification = Some(value.trim_start_matches("--classification=").to_string())
            }
            "--freshness" => freshness = Some(next_value(&mut iterator, "--freshness")?),
            value if value.starts_with("--freshness=") => {
                freshness = Some(value.trim_start_matches("--freshness=").to_string())
            }
            "--limit" => {
                limit = next_value(&mut iterator, "--limit")?
                    .parse()
                    .map_err(|_| "--limit requires a positive integer".to_string())?;
            }
            value if value.starts_with("--limit=") => {
                limit = value[8..]
                    .parse()
                    .map_err(|_| "--limit requires a positive integer".to_string())?;
            }
            "--authority" => {
                authority = Some(
                    iterator
                        .next()
                        .ok_or_else(|| "--authority requires a non-empty reference".to_string())?,
                );
            }
            value if value.starts_with("--authority=") => {
                authority = Some(value.trim_start_matches("--authority=").to_string());
            }
            "--format" => {
                let value = iterator
                    .next()
                    .ok_or_else(|| "--format requires human or json".to_string())?;
                format = parse_format(&value)?;
            }
            value if value.starts_with("--format=") => {
                format = parse_format(value.trim_start_matches("--format="))?;
            }
            value if value.starts_with('-') => {
                return Err(format!("unknown option '{value}'"));
            }
            value if command.is_none() => {
                command = Some(parse_command(value)?);
            }
            value => {
                if path.is_some() {
                    return Err(format!("unexpected argument '{value}'"));
                }
                path = Some(PathBuf::from(value));
            }
        }
    }

    let command = command.unwrap_or(Command::Help);
    if !matches!(command, Command::Init | Command::Knowledge | Command::State) && (dry_run || apply)
    {
        return Err("--dry-run and --apply are only valid for mutating commands".to_string());
    }
    if dry_run && apply {
        return Err("--dry-run and --apply are mutually exclusive".to_string());
    }
    if !matches!(command, Command::Init | Command::Knowledge | Command::State)
        && authority.is_some()
    {
        return Err("--authority is only valid for mutating commands".to_string());
    }
    if authority.as_deref().is_some_and(str::is_empty) {
        return Err("--authority requires a non-empty reference".to_string());
    }
    if limit == 0 {
        return Err("--limit requires a positive integer".to_string());
    }
    if !matches!(command, Command::Knowledge | Command::State) && record {
        return Err("--record is only valid for knowledge or state".to_string());
    }
    if !matches!(command, Command::Knowledge | Command::State)
        && (id.is_some()
            || subject.is_some()
            || content.is_some()
            || state_value.is_some()
            || source.is_some()
            || classification.is_some()
            || freshness.is_some())
    {
        return Err("record fields are only valid for knowledge or state".to_string());
    }
    if apply && !record && matches!(command, Command::Knowledge | Command::State) {
        return Err("--apply for knowledge or state requires --record".to_string());
    }
    if dry_run && !record && matches!(command, Command::Knowledge | Command::State) {
        return Err("--dry-run for knowledge or state requires --record".to_string());
    }
    if authority.is_some() && !record && matches!(command, Command::Knowledge | Command::State) {
        return Err("--authority for knowledge or state requires --record".to_string());
    }

    Ok(Options {
        command,
        path,
        format,
        quiet,
        dry_run,
        apply,
        authority,
        record,
        id,
        subject,
        content,
        value: state_value,
        source,
        classification,
        freshness,
        limit,
    })
}

fn parse_command(value: &str) -> Result<Command, String> {
    match value {
        "version" => Ok(Command::Version),
        "inspect" => Ok(Command::Inspect),
        "validate" => Ok(Command::Validate),
        "doctor" => Ok(Command::Doctor),
        "init" => Ok(Command::Init),
        "knowledge" => Ok(Command::Knowledge),
        "state" => Ok(Command::State),
        "context" => Ok(Command::Context),
        "help" => Ok(Command::Help),
        _ => Err(format!("unknown command '{value}'")),
    }
}

fn parse_format(value: &str) -> Result<OutputFormat, String> {
    match value {
        "human" => Ok(OutputFormat::Human),
        "json" => Ok(OutputFormat::Json),
        _ => Err(format!("unsupported format '{value}'; use human or json")),
    }
}

fn next_value<I>(iterator: &mut I, option: &str) -> Result<String, String>
where
    I: Iterator<Item = String>,
{
    iterator
        .next()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{option} requires a value"))
}

pub fn run(options: Options) -> CommandResult {
    match options.command {
        Command::Version => version_result(options),
        Command::Help => help_result(options),
        Command::Init => init_result(options),
        Command::Inspect | Command::Validate | Command::Doctor => repository_result(options),
        Command::Knowledge | Command::State | Command::Context => intelligence_result(options),
    }
}

pub fn usage_error(message: String) -> CommandResult {
    let mut envelope = ResultEnvelope::error("usage", "usage_error");
    envelope
        .diagnostics
        .push(Diagnostic::error("AOS-CLI-USAGE", message));
    envelope
        .diagnostics
        .push(Diagnostic::info("AOS-CLI-HELP", usage()));
    CommandResult {
        envelope,
        format: OutputFormat::Human,
        quiet: false,
        exit_code: 2,
    }
}

fn version_result(options: Options) -> CommandResult {
    let mut envelope = ResultEnvelope::success("version");
    envelope
        .evidence
        .push(format!("cli-contract:{CLI_CONTRACT_VERSION}"));
    envelope.diagnostics.push(Diagnostic::info(
        "AOS-CLI-VERSION",
        format!("aos {CLI_VERSION}"),
    ));
    envelope.diagnostics.push(Diagnostic::info(
        "AOS-CLI-CONTRACT",
        format!("contract {CLI_CONTRACT_VERSION}"),
    ));
    CommandResult {
        envelope,
        format: options.format,
        quiet: options.quiet,
        exit_code: 0,
    }
}

fn help_result(options: Options) -> CommandResult {
    let mut envelope = ResultEnvelope::success("help");
    envelope
        .diagnostics
        .push(Diagnostic::info("AOS-CLI-USAGE", usage()));
    CommandResult {
        envelope,
        format: options.format,
        quiet: options.quiet,
        exit_code: 0,
    }
}

fn init_result(options: Options) -> CommandResult {
    let result = repository::init(
        options.path.as_deref(),
        options.apply,
        options.authority.as_deref(),
    );
    let mut envelope = match result.outcome.as_str() {
        "success" => ResultEnvelope::success("init"),
        "plan_ready" => ResultEnvelope::success("init"),
        "authorization_required" => ResultEnvelope::error("init", "authorization_required"),
        "conflict" => ResultEnvelope::error("init", "ownership_conflict"),
        "stale" => ResultEnvelope::error("init", "stale_plan"),
        "unknown" => ResultEnvelope::error("init", "operation_unknown"),
        "error" => ResultEnvelope::error("init", "operation_failed"),
        _ => ResultEnvelope::error("init", "internal_error"),
    };
    envelope.outcome = result.outcome;
    envelope.repository = result.repository;
    envelope.diagnostics = result.diagnostics;
    envelope.evidence = result.evidence;
    envelope.plan = result.plan;
    envelope.operation = result.operation;
    CommandResult {
        envelope,
        format: options.format,
        quiet: options.quiet,
        exit_code: result.exit_code,
    }
}

fn repository_result(options: Options) -> CommandResult {
    let command_name = options.command.as_str();
    let inspection = match repository::inspect(options.path.as_deref()) {
        Ok(value) => value,
        Err(error) => {
            let mut envelope = ResultEnvelope::error(command_name, "root_error");
            envelope
                .diagnostics
                .push(Diagnostic::error(error.code, error.message));
            return CommandResult {
                envelope,
                format: options.format,
                quiet: options.quiet,
                exit_code: 3,
            };
        }
    };

    let has_errors = inspection
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == crate::model::Severity::Error);
    let mut envelope = if has_errors {
        ResultEnvelope::findings(command_name)
    } else {
        ResultEnvelope::success(command_name)
    };
    envelope.repository = Some(inspection.summary);
    envelope.diagnostics = inspection.diagnostics;
    envelope.evidence = inspection.evidence;

    let exit_code = if has_errors { 4 } else { 0 };
    CommandResult {
        envelope,
        format: options.format,
        quiet: options.quiet,
        exit_code,
    }
}

fn intelligence_result(options: Options) -> CommandResult {
    let command_name = options.command.as_str();
    let result = match options.command {
        Command::Knowledge if options.record => intelligence::record(RecordInput {
            kind: RecordKind::Knowledge,
            path: options.path.clone(),
            id: options.id.clone(),
            subject: options.subject.clone(),
            content: options.content.clone(),
            value: None,
            source: options.source.clone(),
            classification: options.classification.clone(),
            freshness: options.freshness.clone(),
            apply: options.apply,
            authority: options.authority.clone(),
        }),
        Command::State if options.record => intelligence::record(RecordInput {
            kind: RecordKind::State,
            path: options.path.clone(),
            id: options.id.clone(),
            subject: options.subject.clone(),
            content: None,
            source: options.source.clone(),
            classification: options.classification.clone(),
            freshness: options.freshness.clone(),
            apply: options.apply,
            authority: options.authority.clone(),
            value: options.value.clone(),
        }),
        Command::Knowledge => intelligence::query(
            RecordKind::Knowledge,
            options.path.as_deref(),
            options.limit,
        ),
        Command::State => {
            intelligence::query(RecordKind::State, options.path.as_deref(), options.limit)
        }
        Command::Context => intelligence::context(options.path.as_deref(), options.limit),
        _ => unreachable!("intelligence_result only handles intelligence commands"),
    };
    let mut envelope = if result.outcome == "success" || result.outcome == "plan_ready" {
        ResultEnvelope::success(command_name)
    } else {
        ResultEnvelope::error(
            command_name,
            match result.exit_code {
                2 => "usage_error",
                3 => "root_error",
                4 => "validation_findings",
                5 => "ownership_conflict",
                7 => "authorization_required",
                8 => "operation_unknown",
                _ => "internal_error",
            },
        )
    };
    envelope.outcome = result.outcome;
    envelope.repository = result.repository;
    envelope.diagnostics = result.diagnostics;
    envelope.evidence = result.evidence;
    envelope.data = Some(result.data);
    envelope.plan = result.plan;
    envelope.operation = result.operation;
    CommandResult {
        envelope,
        format: options.format,
        quiet: options.quiet,
        exit_code: result.exit_code,
    }
}

fn usage() -> String {
    "usage: aos <version|inspect|validate|doctor|init|knowledge|state|context> [PATH] [--format human|json] [--quiet]\n\
read-only commands: version, inspect, validate, doctor.\n\
init plans by default; use --dry-run to make the non-mutating intent explicit.\n\
init --apply requires --authority <REFERENCE> and performs transactional adoption.\n\
knowledge and state list records; use --record --apply with provenance fields to add proposed revisions.\n\
context selects authoritative active Knowledge and confirmed State deterministically."
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::{Command, parse};
    use crate::model::OutputFormat;

    fn parse_args(arguments: &[&str]) -> super::Options {
        parse(arguments.iter().map(|value| (*value).to_string())).expect("valid arguments")
    }

    #[test]
    fn parses_json_inspect_with_path() {
        let options = parse_args(&["inspect", ".", "--format=json"]);
        assert_eq!(options.command, Command::Inspect);
        assert_eq!(
            options.path.as_deref().and_then(|path| path.to_str()),
            Some(".")
        );
        assert_eq!(options.format, OutputFormat::Json);
    }

    #[test]
    fn rejects_mutation_flags_on_read_only_commands() {
        let result = parse(["validate".to_string(), "--apply".to_string()]);
        assert!(result.is_err());
    }

    #[test]
    fn init_parses_dry_run_command() {
        let options = parse_args(&["init", "--dry-run"]);
        assert_eq!(options.command, Command::Init);
        assert!(options.dry_run);
    }
}
