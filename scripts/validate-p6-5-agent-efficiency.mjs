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

requireText("scripts/run_p6_5_agent_efficiency_benchmark.ps1", [
  "AOS-P6-5-AGENT-CAPSULE-1",
  "mcp_servers={}",
  "total_input_reduction_at_least_25_percent",
  "AOS_P6_5_AGENT_EFFICIENCY_OK",
]);
requireText("scripts/evaluate_p6_5_agent_efficiency_repeats.ps1", [
  "AOS-P6-5-AGENT-EFFICIENCY-EVALUATION-1",
  "optimized_input_repeat_drift_at_most_5_percent",
  "uncached_regression_is_reported_but_not_a_provider_neutral_gate",
  "AOS_P6_5_AGENT_EFFICIENCY_OK",
]);
requireText("evidence/P6.5-AGENT-EFFICIENCY-QUALIFICATION.md", [
  "**Status:** PASS",
  "p6-5-evaluation-20260727T152757Z",
  "30280170417",
  "46.284%",
  "Uncached input",
  "AOS_P6_5_AGENT_EFFICIENCY_OK",
  "Production-ready:                   NOT CLAIMED",
]);
requireText(".github/workflows/ci.yml", [
  "P6.5 efficiency evaluator smoke",
  "evaluate_p6_5_agent_efficiency_repeats.ps1",
]);
requireText("ROADMAP.md", [
  "### P6.5 Agent efficiency qualification",
  "P6.5-AGENT-EFFICIENCY-QUALIFICATION.md",
]);
requireText("README.md", [
  "P6.5 Agent efficiency",
  "P6.5-AGENT-EFFICIENCY-QUALIFICATION.md",
]);

if (failures.length > 0) {
  console.error("AOS_P6_5_AGENT_EFFICIENCY_STATIC_VALIDATION_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_5_AGENT_EFFICIENCY_STATIC_VALIDATION_OK");
