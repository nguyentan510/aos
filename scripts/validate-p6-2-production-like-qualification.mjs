import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const evidence = readFileSync(
  join(root, "evidence", "P6.2-PRODUCTION-LIKE-QUALIFICATION.md"),
  "utf8",
);
const roadmap = readFileSync(join(root, "ROADMAP.md"), "utf8");
const ci = readFileSync(join(root, ".github", "workflows", "ci.yml"), "utf8");

const requiredEvidence = [
  "**Status:** COMPLETE",
  "AOS_P6_2_FILESYSTEM_FAULT_INJECTION_OK",
  "AOS_P6_2_RECONCILIATION_OK",
  "AOS_P6_2_QUALIFICATION_SAMPLE_OK",
  "AOS_P6_2_DURATION_GATE_ACTIVE",
  "AOS_P6_2_ACCELERATED_QUALIFICATION_OK",
  "samples: 8/8 PASS",
  "governed Extension Runs: 96",
  "observed duration: 0.000379 days",
  "30327707481",
  "Production-like-runtime-ready:     BOUNDED PASS",
  "Seven-day runtime resilience:      NOT CLAIMED",
];
const missing = requiredEvidence.filter((marker) => !evidence.includes(marker));
if (!roadmap.includes("### P6.2 production-like qualification")) {
  missing.push("ROADMAP P6.2 section");
}
for (const [relative, values] of [
  ["adr/0012-p6-2-accelerated-qualification.md", [
    "**Status:** Accepted",
    "samples >= 8",
    "governed Extension Runs >= 96",
  ]],
  ["scripts/run_p6_2_accelerated_qualification.ps1", [
    "AOS_P6_2_ACCELERATED_QUALIFICATION_OK",
    "TargetSamples = 8",
    "MinimumDurationDays 0",
    "total_extension_runs",
  ]],
]) {
  const content = readFileSync(join(root, relative), "utf8");
  for (const value of values) {
    if (!content.includes(value)) {
      missing.push(`${relative}: ${value}`);
    }
  }
}
for (const step of [
  "P6.2 filesystem fault-injection gate",
  "P6.2 installed-pilot harness smoke",
]) {
  if (!ci.includes(step)) {
    missing.push(`CI step: ${step}`);
  }
}

if (missing.length > 0) {
  console.error("AOS_P6_2_QUALIFICATION_GOVERNANCE_FAILED");
  for (const item of missing) {
    console.error(`- missing ${item}`);
  }
  process.exit(1);
}

console.log("AOS_P6_2_QUALIFICATION_GOVERNANCE_OK");
