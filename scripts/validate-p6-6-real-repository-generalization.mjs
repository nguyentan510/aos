import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const failures = [];

function read(relative) {
  try {
    return readFileSync(join(root, relative), "utf8");
  } catch (error) {
    failures.push(`${relative}: ${error.message}`);
    return "";
  }
}

function requireText(relative, values) {
  const content = read(relative);
  for (const value of values) {
    if (!content.includes(value)) {
      failures.push(`${relative}: missing ${value}`);
    }
  }
}

let manifest;
try {
  manifest = JSON.parse(read("benchmarks/p6-6/scenarios.json"));
} catch (error) {
  failures.push(`benchmarks/p6-6/scenarios.json: ${error.message}`);
  manifest = { scenarios: [] };
}

const expectedRepositories = new Map([
  ["AOS_REPO", "f7de2d56cf1b400b47cb316f429e8bc38b0b5c8c"],
  ["TRENUX_RUST_REPO", "3297389bd35ff3e8eb129dc74308ec3c8d165bf2"],
  ["TRENUX_REPO", "020b1ca41824bd0e13d7552136ec6fd1b8ba5f20"],
]);
const expectedTaskTypes = [
  "architecture-owner",
  "bugfix",
  "docs-consistency",
  "feature",
  "onboarding",
];

if (manifest.qualification_level !== "patch-and-test") {
  failures.push("P6.6 manifest must be patch-and-test");
}
if (manifest.scenarios.length !== 15) {
  failures.push(`P6.6 manifest scenario count is ${manifest.scenarios.length}`);
}
if (new Set(manifest.scenarios.map((scenario) => scenario.id)).size !== 15) {
  failures.push("P6.6 scenario IDs are not unique");
}

for (const [repositoryEnvironment, expectedCommit] of expectedRepositories) {
  const scenarios = manifest.scenarios.filter(
    (scenario) => scenario.repository_env === repositoryEnvironment,
  );
  const taskTypes = [...new Set(scenarios.map((scenario) => scenario.task_type))].sort();
  if (scenarios.length !== 5) {
    failures.push(`${repositoryEnvironment}: expected five scenarios`);
  }
  if (JSON.stringify(taskTypes) !== JSON.stringify(expectedTaskTypes)) {
    failures.push(`${repositoryEnvironment}: incomplete task-type matrix`);
  }
  if (scenarios.some((scenario) => scenario.expected_commit !== expectedCommit)) {
    failures.push(`${repositoryEnvironment}: fixed commit mismatch`);
  }
  if (
    scenarios.some(
      (scenario) =>
        !Array.isArray(scenario.expected_patch_files) ||
        scenario.expected_patch_files.length !== 1 ||
        typeof scenario.verification_command !== "string" ||
        scenario.verification_command.length === 0,
    )
  ) {
    failures.push(`${repositoryEnvironment}: mutation or verification scope missing`);
  }
}

requireText("scripts/run_p4_ai_facing_benchmark.ps1", [
  'ValidateSet("p4", "p6.5")',
  "Running $($scenario.id) baseline repeat",
  "consumer quota unavailable",
  "AOS_P6_6_CONSUMER_BATCH_OK",
]);
requireText("scripts/evaluate_p6_6_real_repository_generalization.ps1", [
  "AOS-P6-6-REAL-REPOSITORY-GENERALIZATION-1",
  "sixty_executions",
  "total_input_reduction_at_least_25_percent",
  "elapsed_reduction_at_least_20_percent",
  "command_reduction_at_least_20_percent",
  "optimized_repeat_drift_at_most_10_percent",
  "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_EVALUATOR_SMOKE_OK",
  "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_OK",
]);
requireText("scripts/run_p6_6_evaluator_smoke.ps1", [
  "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_EVALUATOR_SMOKE_OK",
  "AOS_P6_6_EVALUATOR_SMOKE_OK",
  "evaluate_p6_6_real_repository_generalization.ps1",
]);
requireText(".github/workflows/ci.yml", [
  "P6.6 real-repository evaluator smoke",
  "run_p6_6_evaluator_smoke.ps1",
]);
requireText("evidence/P6.6-REAL-REPOSITORY-GENERALIZATION.md", [
  "**Status:** `ACTIVE`",
  "p4-20260728T033336Z",
  "p4-ai-20260727T154640Z",
  "31.26%",
  "usage limit",
  "AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_OK",
  "Production-ready claim:",
]);
requireText("ROADMAP.md", [
  "### P6.6 real repository generalization",
  "**Status:** `ACTIVE`",
  "60 valid consumer executions",
]);
requireText("README.md", [
  "P6.6 real repository generalization is active",
  "P6.6-REAL-REPOSITORY-GENERALIZATION.md",
]);

if (failures.length > 0) {
  console.error("AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_STATIC_VALIDATION_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_6_REAL_REPOSITORY_GENERALIZATION_STATIC_VALIDATION_OK");
