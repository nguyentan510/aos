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

const manifests = [
  "extensions/reference/aos.reference.repository/extension.json",
  "extensions/reference/aos.reference.rust/extension.json",
];
for (const relative of manifests) {
  const content = read(relative);
  if (!content) continue;
  try {
    const manifest = JSON.parse(content);
    for (const key of [
      "schema_version",
      "contract_version",
      "id",
      "version",
      "type",
      "owner",
      "namespace",
      "aos_compatibility",
      "dependencies",
      "capabilities",
      "data_ownership",
      "security",
      "failure_behavior",
    ]) {
      if (!(key in manifest)) {
        failures.push(`${relative}: missing ${key}`);
      }
    }
    if (manifest.contract_version !== "AOS-SPEC-006") {
      failures.push(`${relative}: unsupported contract_version`);
    }
    if (
      manifest.security?.network !== false ||
      manifest.security?.secrets !== false ||
      manifest.security?.process !== false
    ) {
      failures.push(`${relative}: declarative-local security boundary is not closed`);
    }
  } catch (error) {
    failures.push(`${relative}: invalid JSON: ${error.message}`);
  }
}

requireText("src/extension.rs", [
  "repository.summary@1.0.0",
  "rust.cargo_manifest.summary@1.0.0",
  "aos.extension.readonly@1.0.0",
  "AOS-EXTENSION-INTEGRITY-MISMATCH",
  "AOS-GOVERNANCE-SELF-AUTHORITY-DENIED",
]);
requireText("src/work.rs", [
  "extension::resolve_for_work",
  "extension::execute_for_work",
  "extension::quarantine_for_safety",
  "AOS-EXTENSION-GOVERNANCE-BINDING-MISMATCH",
]);
requireText("adr/0010-p6-governed-declarative-extension-ecosystem.md", [
  "**Status:** Accepted",
  "Direct `aos extension invoke`",
]);
requireText("extensions/README.md", [
  "extension-manifest-v1.schema.json",
  "aos extension validate",
  "aos.extension.readonly@1.0.0",
]);
requireText("evidence/P6-EXTENSION-ECOSYSTEM-REVIEW.md", [
  "AOS_P6_EXTENSION_CONTRACT_OK",
  "AOS_P6_EXTENSION_LIFECYCLE_OK",
  "AOS_P6_EXTENSION_ISOLATION_OK",
  "AOS_P6_REFERENCE_EXTENSION_SMOKE_OK",
  "AOS_P6_EXTENSION_ECOSYSTEM_OK",
]);
requireText("evidence/P6.1-ADOPTION-HARDENING-REVIEW.md", [
  "AOS_P6_1_AUTHORING_KIT_OK",
  "AOS_P6_1_MULTI_REPOSITORY_PILOT_OK",
  "normalized replay drift: 0",
  "30252296890 PASS",
]);
requireText(".github/workflows/ci.yml", [
  "run_p6_extension_ecosystem_smoke.ps1",
  "run_p6_1_multi_repository_pilot.ps1",
]);
requireText(".github/workflows/release.yml", [
  "cp -R extensions",
  'Copy-Item "extensions"',
]);

if (failures.length > 0) {
  console.error("AOS_P6_EXTENSION_STATIC_VALIDATION_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_EXTENSION_STATIC_VALIDATION_OK");
