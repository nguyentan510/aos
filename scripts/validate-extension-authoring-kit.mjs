import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("..", import.meta.url));
const failures = [];

function parse(relative) {
  try {
    return JSON.parse(readFileSync(join(root, relative), "utf8"));
  } catch (error) {
    failures.push(`${relative}: ${error.message}`);
    return null;
  }
}

const schema = parse("extensions/schema/extension-manifest-v1.schema.json");
const template = parse("extensions/templates/repository-summary-extension.json");
const references = [
  parse("extensions/reference/aos.reference.repository/extension.json"),
  parse("extensions/reference/aos.reference.rust/extension.json"),
].filter(Boolean);

const requiredFields = [
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
];

if (schema) {
  if (schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
    failures.push("extension schema: draft 2020-12 declaration is missing");
  }
  for (const field of requiredFields) {
    if (!schema.required?.includes(field)) {
      failures.push(`extension schema: required field ${field} is missing`);
    }
  }
  const serialized = JSON.stringify(schema);
  for (const operation of [
    "repository.summary@1.0.0",
    "rust.cargo_manifest.summary@1.0.0",
  ]) {
    if (!serialized.includes(operation)) {
      failures.push(`extension schema: allowlisted operation ${operation} is missing`);
    }
  }
}

for (const [label, manifest] of [
  ["template", template],
  ...references.map((value, index) => [`reference-${index + 1}`, value]),
]) {
  if (!manifest) continue;
  for (const field of requiredFields) {
    if (!(field in manifest)) {
      failures.push(`${label}: required field ${field} is missing`);
    }
  }
  if (manifest.data_ownership !== manifest.namespace) {
    failures.push(`${label}: data_ownership must equal namespace`);
  }
  if (
    manifest.security?.network !== false ||
    manifest.security?.secrets !== false ||
    manifest.security?.process !== false
  ) {
    failures.push(`${label}: security boundary is not declarative-local`);
  }
  if (manifest.failure_behavior !== "fail_closed") {
    failures.push(`${label}: failure behavior is not fail_closed`);
  }
}

const authoringGuide = readFileSync(join(root, "extensions/README.md"), "utf8");
for (const text of [
  "aos extension validate",
  "aos extension enable",
  "Maximum manifest size: 256 KiB",
  "aos.extension.readonly@1.0.0",
]) {
  if (!authoringGuide.includes(text)) {
    failures.push(`extensions/README.md: missing ${text}`);
  }
}

if (failures.length > 0) {
  console.error("AOS_P6_1_AUTHORING_KIT_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_1_AUTHORING_KIT_OK");
