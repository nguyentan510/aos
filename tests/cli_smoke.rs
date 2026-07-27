use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn temp_repository(label: &str) -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after epoch")
        .as_nanos();
    let path = std::env::temp_dir().join(format!("aos-{label}-{}-{nonce}", std::process::id()));
    fs::create_dir_all(&path).expect("temporary repository should be created");
    path
}

fn run_aos(arguments: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_aos"))
        .args(arguments)
        .output()
        .expect("aos binary should run")
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("stdout should be UTF-8")
}

fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("stderr should be UTF-8")
}

fn assert_no_control_directory(path: &Path) {
    assert!(
        !path.join(".aos").exists(),
        "read-only command must not create .aos"
    );
}

fn initialize_repository(repository: &Path) {
    let output = run_aos(&[
        "init",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=test-initializer",
        "--format=json",
    ]);
    assert!(
        output.status.success(),
        "init stderr: {}\ninit stdout: {}",
        stderr(&output),
        stdout(&output)
    );
}

fn record_knowledge(repository: &Path, id: &str) {
    let output = run_aos(&[
        "knowledge",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--apply",
        "--authority=producer",
        &format!("--id={id}"),
        &format!("--subject={id}"),
        "--content=verified-local-context",
        "--source=DESIGN.md",
        "--format=json",
    ]);
    assert!(
        output.status.success(),
        "knowledge stderr: {}\nknowledge stdout: {}",
        stderr(&output),
        stdout(&output)
    );
}

fn create_work(repository: &Path, work_id: &str, context_id: &str, context_kind: &str) {
    let output = run_aos(&[
        "work",
        "create",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=producer",
        &format!("--work-id={work_id}"),
        &format!("--context-id={context_id}"),
        &format!("--context-kind={context_kind}"),
        "--intent=verify-governed-context",
        "--expected-output=verified-result",
        "--verification=local-context-integrity",
        "--format=json",
    ]);
    assert!(
        output.status.success(),
        "work create stderr: {}\nwork create stdout: {}",
        stderr(&output),
        stdout(&output)
    );
}

fn authorize_work(repository: &Path, work_id: &str) -> Output {
    run_aos(&[
        "work",
        "authorize",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=project-reviewer",
        &format!("--work-id={work_id}"),
        "--evidence=review-evidence",
        "--format=json",
    ])
}

#[test]
fn inspect_reports_unmanaged_repository_without_mutation() {
    let repository = temp_repository("inspect");
    let output = run_aos(&[
        "inspect",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format",
        "json",
    ]);

    assert!(
        output.status.success(),
        "stderr: {}\nstdout: {}",
        stderr(&output),
        stdout(&output)
    );
    let body = stdout(&output);
    assert!(body.contains("\"command\":\"inspect\""));
    assert!(body.contains("\"outcome\":\"success\""));
    assert!(body.contains("\"status\":\"unmanaged\""));
    assert!(body.contains("AOS-REPO-UNMANAGED"));
    assert_no_control_directory(&repository);

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn validate_and_doctor_are_read_only_diagnostics() {
    let repository = temp_repository("diagnostics");
    for command in ["validate", "doctor"] {
        let output = run_aos(&[
            command,
            repository.to_str().expect("temporary path should be UTF-8"),
            "--format=json",
        ]);

        assert!(
            output.status.success(),
            "{command} stderr: {}",
            stderr(&output)
        );
        let body = stdout(&output);
        assert!(body.contains(&format!("\"command\":\"{command}\"")));
        assert!(body.contains("\"outcome\":\"success\""));
        assert_no_control_directory(&repository);
    }

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn inspect_reports_candidate_control_directory_without_mutation() {
    let repository = temp_repository("candidate");
    fs::create_dir(repository.join(".aos")).expect("candidate control directory should be created");
    let output = run_aos(&[
        "inspect",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
    ]);

    assert!(
        output.status.success(),
        "stderr: {}\nstdout: {}",
        stderr(&output),
        stdout(&output)
    );
    let body = stdout(&output);
    assert!(body.contains("\"status\":\"candidate\""));
    assert!(body.contains("AOS-REPO-CONTROL-UNRECOGNIZED"));
    assert!(body.contains("\"severity\":\"warning\""));
    assert!(repository.join(".aos").is_dir());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn inspect_reports_incompatible_control_root() {
    let repository = temp_repository("incompatible");
    fs::write(repository.join(".aos"), b"not a directory")
        .expect("control root file should be created");
    let output = run_aos(&[
        "inspect",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
    ]);

    assert_eq!(output.status.code(), Some(4), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"outcome\":\"findings\""));
    assert!(body.contains("\"status\":\"incompatible\""));
    assert!(body.contains("AOS-REPO-CONTROL-ROOT"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn init_default_and_dry_run_are_non_mutating_plans() {
    let repository = temp_repository("init-plan");
    let output = run_aos(&[
        "init",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
        "--dry-run",
    ]);

    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"command\":\"init\""));
    assert!(body.contains("\"outcome\":\"plan_ready\""));
    assert!(body.contains("\"authority_required\":true"));
    assert!(body.contains("\"affected_paths\":[\".aos\",\".aos/repository.json\"]"));
    assert_no_control_directory(&repository);

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn init_apply_requires_authority() {
    let repository = temp_repository("init-authority");
    let output = run_aos(&[
        "init",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
        "--apply",
    ]);

    assert_eq!(output.status.code(), Some(7), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"outcome\":\"authorization_required\""));
    assert!(body.contains("\"category\":\"authorization_required\""));
    assert!(body.contains("AOS-INIT-AUTHORITY-REQUIRED"));
    assert_no_control_directory(&repository);

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn init_apply_is_transactional_and_idempotent() {
    let repository = temp_repository("init-apply");
    let repository_string = repository.to_str().expect("temporary path should be UTF-8");
    let output = run_aos(&[
        "init",
        repository_string,
        "--format=json",
        "--apply",
        "--authority=local-test",
    ]);

    assert!(
        output.status.success(),
        "stderr: {}\nstdout: {}",
        stderr(&output),
        stdout(&output)
    );
    let body = stdout(&output);
    assert!(body.contains("\"outcome\":\"success\""));
    assert!(body.contains("\"status\":\"initialized\""));
    assert!(body.contains("\"result\":\"initialized\""));
    assert!(repository.join(".aos").is_dir());
    assert!(repository.join(".aos/repository.json").is_file());

    let repeat = run_aos(&[
        "init",
        repository_string,
        "--format=json",
        "--apply",
        "--authority",
        "local-test",
    ]);
    assert!(
        repeat.status.success(),
        "stderr: {}\nstdout: {}",
        stderr(&repeat),
        stdout(&repeat)
    );
    let repeat_body = stdout(&repeat);
    assert!(repeat_body.contains("\"result\":\"already_initialized\""));

    let inspect = run_aos(&["inspect", repository_string, "--format=json"]);
    assert!(inspect.status.success(), "stderr: {}", stderr(&inspect));
    assert!(stdout(&inspect).contains("\"compatibility\":\"supported\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn init_rejects_unknown_control_root_without_overwrite() {
    let repository = temp_repository("init-conflict");
    let control_root = repository.join(".aos");
    fs::create_dir(&control_root).expect("unknown control root should be created");
    fs::write(control_root.join("user-file.txt"), b"preserve me")
        .expect("user artifact should be created");

    let output = run_aos(&[
        "init",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
        "--apply",
        "--authority=local-test",
    ]);
    assert_eq!(output.status.code(), Some(5), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"category\":\"ownership_conflict\""));
    assert!(body.contains("AOS-INIT-CONTROL-ROOT-CONFLICT"));
    assert_eq!(
        fs::read(control_root.join("user-file.txt")).expect("user artifact should remain"),
        b"preserve me"
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn invalid_repository_root_returns_root_error() {
    let path = std::env::temp_dir().join(format!("aos-missing-{}", std::process::id()));
    let output = run_aos(&[
        "inspect",
        path.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
    ]);

    assert_eq!(output.status.code(), Some(3), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"outcome\":\"error\""));
    assert!(body.contains("\"category\":\"root_error\""));
}

#[test]
fn knowledge_dry_run_returns_plan_without_recording() {
    let repository = temp_repository("knowledge-plan");
    initialize_repository(&repository);
    let output = run_aos(&[
        "knowledge",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--dry-run",
        "--id=architecture",
        "--subject=architecture",
        "--content=modular",
        "--source=DESIGN.md",
        "--format=json",
    ]);

    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"outcome\":\"plan_ready\""));
    assert!(body.contains("\"authority_required\":true"));
    assert!(!repository.join(".aos/knowledge").exists());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn knowledge_record_requires_authority() {
    let repository = temp_repository("knowledge-authority");
    initialize_repository(&repository);
    let output = run_aos(&[
        "knowledge",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--apply",
        "--id=architecture",
        "--subject=architecture",
        "--content=modular",
        "--source=DESIGN.md",
        "--format=json",
    ]);

    assert_eq!(output.status.code(), Some(7), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("AOS-INTELLIGENCE-AUTHORITY-REQUIRED"));
    assert!(!repository.join(".aos/knowledge").exists());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn knowledge_revisions_are_immutable_and_provenance_is_retained() {
    let repository = temp_repository("knowledge-revision");
    initialize_repository(&repository);
    let repository_string = repository.to_str().expect("temporary path should be UTF-8");
    for content in ["modular", "modular-and-transactional"] {
        let output = run_aos(&[
            "knowledge",
            repository_string,
            "--record",
            "--apply",
            "--authority=project-owner",
            "--id=architecture",
            "--subject=architecture",
            &format!("--content={content}"),
            "--source=DESIGN.md",
            "--format=json",
        ]);
        assert!(
            output.status.success(),
            "stderr: {}\nstdout: {}",
            stderr(&output),
            stdout(&output)
        );
    }

    let first = fs::read_to_string(repository.join(".aos/knowledge/architecture.r1.json"))
        .expect("first immutable revision should exist");
    let second = fs::read_to_string(repository.join(".aos/knowledge/architecture.r2.json"))
        .expect("second immutable revision should exist");
    assert!(first.contains("\"revision\":\"1\""));
    assert!(first.contains("\"content\":\"modular\""));
    assert!(second.contains("\"revision\":\"2\""));
    assert!(second.contains("\"previous_revision\":\"architecture@1\""));
    assert!(second.contains("\"source_reference\":\"DESIGN.md\""));
    assert!(second.contains("\"authority\":\"proposed\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn knowledge_rejects_sensitive_content_without_writing() {
    let repository = temp_repository("knowledge-secret");
    initialize_repository(&repository);
    let output = run_aos(&[
        "knowledge",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--apply",
        "--authority=project-owner",
        "--id=credential",
        "--subject=credential",
        "--content=api_key=do-not-store",
        "--source=local-input",
        "--format=json",
    ]);

    assert_eq!(output.status.code(), Some(4), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("AOS-INTELLIGENCE-SENSITIVE-CONTENT"));
    assert!(
        !repository
            .join(".aos/knowledge/credential.r1.json")
            .exists()
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn context_is_deterministic_and_explains_withheld_records() {
    let repository = temp_repository("context");
    initialize_repository(&repository);
    let knowledge = repository.join(".aos/knowledge");
    let state = repository.join(".aos/state");
    fs::create_dir_all(&knowledge).expect("knowledge fixture directory should exist");
    fs::create_dir_all(&state).expect("state fixture directory should exist");
    fs::write(
        knowledge.join("architecture.r1.json"),
        r#"{"kind":"Knowledge","id":"architecture","revision":"1","subject":"architecture","authority":"authoritative","lifecycle":"active","source_reference":"DESIGN.md","content":"modular"}"#,
    )
    .expect("authoritative knowledge fixture should be written");
    fs::write(
        state.join("build.r1.json"),
        r#"{"kind":"State","id":"build","revision":"1","subject":"build","authority":"authoritative","lifecycle":"active","freshness":"stale","source_reference":"ci","observed_value":"passing"}"#,
    )
    .expect("stale state fixture should be written");
    fs::write(
        knowledge.join("proposal.r1.json"),
        r#"{"kind":"Knowledge","id":"proposal","revision":"1","subject":"proposal","authority":"proposed","lifecycle":"active","source_reference":"notes","content":"candidate"}"#,
    )
    .expect("proposed knowledge fixture should be written");

    let arguments = [
        "context",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--limit=10",
        "--format=json",
    ];
    let first = run_aos(&arguments);
    let second = run_aos(&arguments);
    assert!(first.status.success(), "stderr: {}", stderr(&first));
    assert_eq!(stdout(&first), stdout(&second));
    let body = stdout(&first);
    assert!(body.contains("\"selected\":[{\"kind\":\"Knowledge\",\"id\":\"architecture\""));
    assert!(body.contains("\"id\":\"build\",\"subject\":\"build\",\"reason\":\"freshness_stale\""));
    assert!(body.contains(
        "\"id\":\"proposal\",\"subject\":\"proposal\",\"reason\":\"authority_proposed\""
    ));
    assert!(body.contains("context:provider-independent-selection"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn compact_context_preserves_provenance_and_enforces_budget() {
    let repository = temp_repository("context-compact");
    initialize_repository(&repository);
    let knowledge = repository.join(".aos/knowledge");
    fs::create_dir_all(&knowledge).expect("knowledge fixture directory should exist");
    fs::write(
        knowledge.join("architecture.r1.json"),
        r#"{"kind":"Knowledge","id":"architecture","revision":"1","subject":"architecture","authority":"authoritative","lifecycle":"active","source_reference":"DESIGN.md","content":"modular"}"#,
    )
    .expect("compact knowledge fixture should be written");
    fs::write(
        knowledge.join("large.r1.json"),
        format!(
            r#"{{"kind":"Knowledge","id":"large","revision":"1","subject":"large","authority":"authoritative","lifecycle":"active","source_reference":"large.md","content":"{}"}}"#,
            "x".repeat(800)
        ),
    )
    .expect("large knowledge fixture should be written");

    let output = run_aos(&[
        "context",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--limit=10",
        "--profile=compact",
        "--budget-bytes=300",
        "--format=json",
    ]);
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let body = stdout(&output);
    assert!(body.contains("\"profile\":\"compact\""));
    assert!(body.contains("\"budget_bytes\":300"));
    assert!(body.contains("\"source_reference\":\"DESIGN.md\""));
    assert!(!body.contains("\"project_id\":\"project-"));
    assert!(body.contains("\"reason\":\"context_budget\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn state_record_preserves_declared_freshness_and_remains_proposed() {
    let repository = temp_repository("state");
    initialize_repository(&repository);
    let output = run_aos(&[
        "state",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--apply",
        "--authority=observer",
        "--id=build",
        "--subject=build",
        "--value=passing",
        "--freshness=confirmed",
        "--source=local-test",
        "--format=json",
    ]);

    assert!(output.status.success(), "stderr: {}", stderr(&output));
    let record = fs::read_to_string(repository.join(".aos/state/build.r1.json"))
        .expect("state record should exist");
    assert!(record.contains("\"freshness\":\"confirmed\""));
    assert!(record.contains("\"authority\":\"proposed\""));
    assert!(record.contains("\"source_reference\":\"local-test\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn context_reports_invalid_records_instead_of_silently_dropping_them() {
    let repository = temp_repository("context-invalid");
    initialize_repository(&repository);
    let knowledge = repository.join(".aos/knowledge");
    fs::create_dir_all(&knowledge).expect("knowledge directory should exist");
    fs::write(
        knowledge.join("broken.r1.json"),
        b"{\"kind\":\"Knowledge\"}",
    )
    .expect("invalid fixture should be written");

    let output = run_aos(&[
        "context",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--format=json",
    ]);
    assert_eq!(output.status.code(), Some(4), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("AOS-INTELLIGENCE-RECORD-INVALID"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn governed_work_vertical_slice_is_traceable_end_to_end() {
    let repository = temp_repository("p5-governed-work");
    initialize_repository(&repository);
    record_knowledge(&repository, "architecture");
    create_work(
        &repository,
        "verify-architecture",
        "architecture",
        "Knowledge",
    );

    let authorize = authorize_work(&repository, "verify-architecture");
    assert!(
        authorize.status.success(),
        "authorize stderr: {}\nauthorize stdout: {}",
        stderr(&authorize),
        stdout(&authorize)
    );
    assert!(stdout(&authorize).contains("AOS-WORK-AUTHORIZED"));
    assert!(
        repository
            .join(".aos/knowledge/architecture.r2.json")
            .is_file()
    );

    let run = run_aos(&[
        "work",
        "run",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=local-runtime",
        "--work-id=verify-architecture",
        "--evidence=verification-evidence",
        "--format=json",
    ]);
    assert!(
        run.status.success(),
        "run stderr: {}\nrun stdout: {}",
        stderr(&run),
        stdout(&run)
    );
    let run_body = stdout(&run);
    assert!(run_body.contains("\"result\":\"completed\""));
    assert!(run_body.contains("\"status\":\"completed\""));
    assert!(
        repository
            .join(".aos/work/verify-architecture.r3.json")
            .is_file(),
        "in_progress revision must be retained"
    );
    assert!(
        repository
            .join(".aos/work/verify-architecture.r4.json")
            .is_file(),
        "completed revision must be retained"
    );

    let show = run_aos(&[
        "work",
        "show",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--work-id=verify-architecture",
        "--format=json",
    ]);
    assert!(show.status.success(), "show stderr: {}", stderr(&show));
    let body = stdout(&show);
    assert!(body.contains("\"governance\":[{"));
    assert!(body.contains("\"runs\":[{"));
    assert!(body.contains("\"audit\":[{"));
    assert!(body.contains("\"context_snapshot\":\"Knowledge:architecture@2\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn work_mutation_plans_without_apply_and_creates_no_work_state() {
    let repository = temp_repository("p5-work-plan");
    initialize_repository(&repository);
    record_knowledge(&repository, "planning-context");

    let output = run_aos(&[
        "work",
        "create",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--work-id=planned-work",
        "--context-id=planning-context",
        "--context-kind=Knowledge",
        "--intent=plan-only",
        "--format=json",
    ]);
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("\"outcome\":\"plan_ready\""));
    assert!(stdout(&output).contains("\"mutation\":\"not_applied\""));
    assert!(!repository.join(".aos/work").exists());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn governance_denies_self_authority_and_preserves_proposal() {
    let repository = temp_repository("p5-self-authority");
    initialize_repository(&repository);
    record_knowledge(&repository, "boundary");
    create_work(&repository, "self-authorize", "boundary", "Knowledge");

    let output = run_aos(&[
        "work",
        "authorize",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=aos-cli",
        "--work-id=self-authorize",
        "--evidence=self-claim",
        "--format=json",
    ]);
    assert_eq!(output.status.code(), Some(7), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("AOS-GOVERNANCE-SELF-AUTHORITY-DENIED"));
    assert!(!repository.join(".aos/work/self-authorize.r2.json").exists());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn governance_rejection_is_audited_without_mutating_proposal() {
    let repository = temp_repository("p5-rejection");
    initialize_repository(&repository);
    record_knowledge(&repository, "candidate");
    create_work(&repository, "reject-me", "candidate", "Knowledge");

    let output = run_aos(&[
        "work",
        "authorize",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=project-reviewer",
        "--work-id=reject-me",
        "--evidence=review-evidence",
        "--result=rejected",
        "--reason=scope-not-approved",
        "--format=json",
    ]);
    assert!(output.status.success(), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("AOS-WORK-REJECTED"));
    assert!(
        !repository.join(".aos/work/reject-me.r2.json").exists(),
        "rejection must keep the proposal immutable"
    );
    let governance = fs::read_dir(repository.join(".aos/governance"))
        .expect("governance records should exist")
        .filter_map(Result::ok)
        .map(|entry| fs::read_to_string(entry.path()).expect("decision should be readable"))
        .collect::<String>();
    assert!(governance.contains("\"outcome\":\"rejected\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn stale_state_cannot_be_authorized_for_work() {
    let repository = temp_repository("p5-stale-state");
    initialize_repository(&repository);
    let state = run_aos(&[
        "state",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--record",
        "--apply",
        "--authority=observer",
        "--id=build",
        "--subject=build",
        "--value=passing",
        "--freshness=stale",
        "--source=ci",
        "--format=json",
    ]);
    assert!(state.status.success(), "state stderr: {}", stderr(&state));
    create_work(&repository, "use-build-state", "build", "State");

    let authorize = authorize_work(&repository, "use-build-state");
    assert_eq!(
        authorize.status.code(),
        Some(4),
        "stderr: {}",
        stderr(&authorize)
    );
    assert!(stdout(&authorize).contains("AOS-GOVERNANCE-CONTEXT-STALE"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn unknown_run_blocks_work_until_attributable_reconciliation() {
    let repository = temp_repository("p5-reconciliation");
    initialize_repository(&repository);
    record_knowledge(&repository, "runtime-boundary");
    create_work(
        &repository,
        "reconcile-run",
        "runtime-boundary",
        "Knowledge",
    );
    let authorize = authorize_work(&repository, "reconcile-run");
    assert!(authorize.status.success(), "stderr: {}", stderr(&authorize));

    let run = run_aos(&[
        "work",
        "run",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=local-runtime",
        "--work-id=reconcile-run",
        "--result=unknown",
        "--reason=verification-interrupted",
        "--format=json",
    ]);
    assert_eq!(run.status.code(), Some(4), "stderr: {}", stderr(&run));
    assert!(stdout(&run).contains("\"reconciliation\":\"required\""));
    assert!(stdout(&run).contains("\"status\":\"blocked\""));

    let duplicate = run_aos(&[
        "work",
        "run",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=local-runtime",
        "--work-id=reconcile-run",
        "--format=json",
    ]);
    assert_eq!(duplicate.status.code(), Some(4));
    assert!(stdout(&duplicate).contains("AOS-WORK-TRANSITION-INVALID"));

    let reconcile = run_aos(&[
        "work",
        "reconcile",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=project-reviewer",
        "--work-id=reconcile-run",
        "--result=resolved",
        "--evidence=current-observation",
        "--format=json",
    ]);
    assert!(reconcile.status.success(), "stderr: {}", stderr(&reconcile));
    assert!(stdout(&reconcile).contains("AOS-RECONCILIATION-RECORDED"));
    assert!(stdout(&reconcile).contains("\"status\":\"authorized\""));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn failed_run_is_recorded_as_non_success_and_never_completes_work() {
    let repository = temp_repository("p5-failed-run");
    initialize_repository(&repository);
    record_knowledge(&repository, "verification-policy");
    create_work(
        &repository,
        "failed-verification",
        "verification-policy",
        "Knowledge",
    );
    let authorize = authorize_work(&repository, "failed-verification");
    assert!(authorize.status.success(), "stderr: {}", stderr(&authorize));

    let run = run_aos(&[
        "work",
        "run",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=local-runtime",
        "--work-id=failed-verification",
        "--result=failed",
        "--reason=required-check-failed",
        "--evidence=failed-check",
        "--format=json",
    ]);
    assert_eq!(run.status.code(), Some(4), "stderr: {}", stderr(&run));
    let body = stdout(&run);
    assert!(body.contains("\"outcome\":\"findings\""));
    assert!(body.contains("\"status\":\"failed\""));
    assert!(!body.contains("\"status\":\"completed\""));
    assert!(body.contains("\"verification_evidence\":null"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn governance_denies_scope_mismatch_before_promotion() {
    let repository = temp_repository("p5-scope-mismatch");
    initialize_repository(&repository);
    record_knowledge(&repository, "scope-context");
    let create = run_aos(&[
        "work",
        "create",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=producer",
        "--work-id=wrong-scope",
        "--context-id=scope-context",
        "--context-kind=Knowledge",
        "--intent=verify-scope",
        "--scope=outside-repository",
        "--format=json",
    ]);
    assert!(create.status.success(), "stderr: {}", stderr(&create));

    let authorize = authorize_work(&repository, "wrong-scope");
    assert_eq!(authorize.status.code(), Some(7));
    assert!(stdout(&authorize).contains("AOS-GOVERNANCE-SCOPE-MISMATCH"));
    assert!(
        !repository
            .join(".aos/knowledge/scope-context.r2.json")
            .exists()
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn governance_denies_cross_project_context_reference() {
    let repository = temp_repository("p5-cross-project");
    initialize_repository(&repository);
    record_knowledge(&repository, "foreign-context");
    let context_path = repository.join(".aos/knowledge/foreign-context.r1.json");
    let original = fs::read_to_string(&context_path).expect("context should be readable");
    let project_marker = original
        .split("\"project_id\":\"")
        .nth(1)
        .and_then(|value| value.split('"').next())
        .expect("project id should exist");
    fs::write(
        &context_path,
        original.replace(project_marker, "project-foreign"),
    )
    .expect("cross-project fixture should be written");
    create_work(
        &repository,
        "cross-project-work",
        "foreign-context",
        "Knowledge",
    );

    let authorize = authorize_work(&repository, "cross-project-work");
    assert_eq!(authorize.status.code(), Some(4));
    assert!(stdout(&authorize).contains("AOS-GOVERNANCE-CROSS-PROJECT-CONTEXT"));

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn unsupported_protocol_record_fails_closed() {
    let repository = temp_repository("p5-unsupported-protocol");
    initialize_repository(&repository);
    record_knowledge(&repository, "protocol-context");
    create_work(
        &repository,
        "unsupported-protocol-work",
        "protocol-context",
        "Knowledge",
    );
    let protocol = repository.join(".aos/protocol");
    fs::create_dir_all(&protocol).expect("protocol directory should be created");
    fs::write(
        protocol.join("aos.local.verify@1.0.0.json"),
        r#"{"kind":"Protocol","id":"aos.local.verify","version":"9.0.0","status":"accepted"}"#,
    )
    .expect("unsupported protocol fixture should be written");

    let authorize = authorize_work(&repository, "unsupported-protocol-work");
    assert_eq!(authorize.status.code(), Some(4));
    assert!(stdout(&authorize).contains("AOS-PROTOCOL-CONTRACT-INVALID"));
    assert!(
        !repository
            .join(".aos/work/unsupported-protocol-work.r2.json")
            .exists()
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn secret_like_governance_evidence_is_rejected_without_decision() {
    let repository = temp_repository("p5-secret-evidence");
    initialize_repository(&repository);
    record_knowledge(&repository, "safe-context");
    create_work(&repository, "secret-evidence", "safe-context", "Knowledge");

    let authorize = run_aos(&[
        "work",
        "authorize",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=project-reviewer",
        "--work-id=secret-evidence",
        "--evidence=token=do-not-store",
        "--format=json",
    ]);
    assert_eq!(authorize.status.code(), Some(4));
    assert!(stdout(&authorize).contains("AOS-GOVERNANCE-SENSITIVE-EVIDENCE"));
    assert!(!repository.join(".aos/governance").exists());

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn audit_write_failure_reports_unknown_and_preserves_reconcilable_work() {
    let repository = temp_repository("p5-audit-failure");
    initialize_repository(&repository);
    record_knowledge(&repository, "audit-context");
    fs::write(repository.join(".aos/audit"), b"blocks audit directory")
        .expect("audit conflict fixture should be written");

    let create = run_aos(&[
        "work",
        "create",
        repository.to_str().expect("temporary path should be UTF-8"),
        "--apply",
        "--authority=producer",
        "--work-id=audit-unknown",
        "--context-id=audit-context",
        "--context-kind=Knowledge",
        "--intent=verify-audit-failure",
        "--format=json",
    ]);
    assert_eq!(create.status.code(), Some(8));
    assert!(stdout(&create).contains("AOS-AUDIT-WRITE-UNKNOWN"));
    assert!(stdout(&create).contains("audit:reconciliation-required"));
    assert!(
        repository.join(".aos/work/audit-unknown.r1.json").is_file(),
        "the immutable Work write must remain available for reconciliation"
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}

#[test]
fn concurrent_work_writes_never_overwrite_an_immutable_revision() {
    let repository = temp_repository("p5-concurrent-work");
    initialize_repository(&repository);
    record_knowledge(&repository, "concurrent-context");
    let repository_string = repository.to_str().expect("temporary path should be UTF-8");
    let arguments = [
        "work",
        "create",
        repository_string,
        "--apply",
        "--authority=producer",
        "--work-id=concurrent-work",
        "--context-id=concurrent-context",
        "--context-kind=Knowledge",
        "--intent=verify-concurrency",
        "--format=json",
    ];
    let mut first = Command::new(env!("CARGO_BIN_EXE_aos"))
        .args(arguments)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("first concurrent writer should start");
    let mut second = Command::new(env!("CARGO_BIN_EXE_aos"))
        .args(arguments)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("second concurrent writer should start");
    let first_status = first.wait().expect("first writer should finish");
    let second_status = second.wait().expect("second writer should finish");
    assert!(
        first_status.success() || second_status.success(),
        "at least one immutable writer must succeed"
    );
    let revisions = fs::read_dir(repository.join(".aos/work"))
        .expect("work directory should exist")
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with("concurrent-work.r")
        })
        .collect::<Vec<_>>();
    assert!(!revisions.is_empty());
    assert!(revisions.len() <= 2);
    for revision in revisions {
        let body = fs::read_to_string(revision.path()).expect("revision must remain readable");
        assert!(body.contains("\"id\":\"concurrent-work\""));
        assert!(body.contains("\"intent\":\"verify-concurrency\""));
    }
    assert!(
        fs::read_dir(repository.join(".aos/work"))
            .expect("work directory should remain readable")
            .filter_map(Result::ok)
            .all(|entry| !entry.file_name().to_string_lossy().starts_with(".tmp-")),
        "no temporary revision may remain"
    );

    fs::remove_dir_all(repository).expect("temporary repository should be removable");
}
