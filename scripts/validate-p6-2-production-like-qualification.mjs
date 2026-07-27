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
  "**Status:** ACTIVE",
  "AOS_P6_2_FILESYSTEM_FAULT_INJECTION_OK",
  "AOS_P6_2_RECONCILIATION_OK",
  "AOS_P6_2_QUALIFICATION_SAMPLE_OK",
  "AOS_P6_2_DURATION_GATE_ACTIVE",
  "Production-like-runtime-ready:     NOT CLAIMED",
];
const missing = requiredEvidence.filter((marker) => !evidence.includes(marker));
if (!roadmap.includes("### P6.2 production-like qualification")) {
  missing.push("ROADMAP P6.2 section");
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
