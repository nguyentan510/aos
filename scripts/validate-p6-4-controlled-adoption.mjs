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

requireText("scripts/run_p6_4_controlled_adoption_pilot.ps1", [
  "AOS-P6-4-CONTROLLED-ADOPTION-1",
  "published-release",
  "source_mutation_zero",
  "uninstall_preserved_downstream_data",
  "AOS_P6_4_CONTROLLED_ADOPTION_PILOT_OK",
]);
requireText("scripts/run_p6_4_agent_workflow_qualification.ps1", [
  "AOS-P6-4-AGENT-WORKFLOW-1",
  "installed RC4 provider-neutral Agent brief",
  "control_data_unchanged",
  "AOS_P6_4_AGENT_WORKFLOW_QUALIFICATION_OK",
]);
requireText(".github/workflows/ci.yml", [
  "P6.4 controlled adoption pilot",
  "run_p6_4_controlled_adoption_pilot.ps1",
]);
requireText("evidence/P6.4-CONTROLLED-ADOPTION-PILOT.md", [
  "p6-4-20260727T144515Z",
  "p6-4-agent-20260727T145003Z",
  "AOS_P6_4_CONTROLLED_ADOPTION_PILOT_OK",
  "AOS_P6_4_AGENT_WORKFLOW_QUALIFICATION_OK",
  "Production-ready:                   NOT CLAIMED",
]);
requireText("ROADMAP.md", [
  "### P6.4 controlled adoption pilot",
  "P6.4-CONTROLLED-ADOPTION-PILOT.md",
]);
requireText("README.md", [
  "P6.4 controlled adoption",
  "P6.4-CONTROLLED-ADOPTION-PILOT.md",
]);

if (failures.length > 0) {
  console.error("AOS_P6_4_CONTROLLED_ADOPTION_STATIC_VALIDATION_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_4_CONTROLLED_ADOPTION_STATIC_VALIDATION_OK");
