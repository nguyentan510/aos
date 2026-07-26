use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};
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
