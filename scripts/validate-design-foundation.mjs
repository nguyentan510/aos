import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";
import { TextDecoder } from "node:util";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const decoder = new TextDecoder("utf-8", { fatal: true });
const errors = [];

const requiredFiles = [
  ".gitignore",
  "LICENSE",
  "README.md",
  "VISION.md",
  "PRINCIPLES.md",
  "DESIGN.md",
  "ROADMAP.md",
  "Cargo.toml",
  "Cargo.lock",
  "rust-toolchain.toml",
  "src/main.rs",
  "src/cli.rs",
  "src/model.rs",
  "src/repository.rs",
  "src/intelligence.rs",
  "src/work.rs",
  "tests/cli_smoke.rs",
  "scripts/validate-aos.mjs",
  "scripts/run_p5_governed_work_smoke.ps1",
  "scripts/run_p5_hardening_gate.ps1",
  "scripts/run_p4_ai_facing_benchmark.ps1",
  "scripts/aggregate_p4_split_benchmark.ps1",
  "scripts/run_controlled_downstream_pilot.ps1",
  "evidence/P0-DESIGN-FOUNDATION-REVIEW.md",
  "evidence/P1-AOS-SPEC-001-REVIEW.md",
  "evidence/P1-AOS-SPEC-002-REVIEW.md",
  "evidence/P1-AOS-SPEC-003-REVIEW.md",
  "evidence/P1-AOS-SPEC-004-REVIEW.md",
  "evidence/P1-AOS-SPEC-005-REVIEW.md",
  "evidence/P1-AOS-SPEC-006-REVIEW.md",
  "evidence/P1-STANDARDS-CONTRACTS-REVIEW.md",
  "evidence/P2-READ-ONLY-CLI-REVIEW.md",
  "evidence/P3-TRANSACTIONAL-INIT-REVIEW.md",
  "evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md",
  "evidence/P4-VALUE-BENCHMARK.md",
  "evidence/P5-GOVERNED-WORK-REVIEW.md",
  "evidence/P5-CONTROLLED-DOWNSTREAM-PILOT.md",
  "specifications/README.md",
  "specifications/TEMPLATE.md",
  "specifications/001-information-model.md",
  "specifications/002-repository.md",
  "specifications/003-protocol.md",
  "specifications/004-cli.md",
  "specifications/005-runtime.md",
  "specifications/006-extension.md",
  "adr/README.md",
  "adr/TEMPLATE.md",
  "adr/0001-independent-product-boundary.md",
  "adr/0002-design-canonical-reference-model.md",
  "adr/0003-init-bootstrap-command.md",
  "adr/0004-domain-runtime-separation.md",
  "adr/0005-rust-native-binary-implementation.md",
  "adr/0006-p2-read-only-cli-boundary.md",
  "adr/0007-transactional-repository-initialization.md",
  "adr/0008-p4-knowledge-state-context-binding.md",
  "adr/0009-p5-governed-work-vertical-slice.md",
];

const requiredHeadings = new Map([
  [
    "README.md",
    [
      "Why AOS",
      "Product boundary",
      "Canonical design",
      "Current maturity",
      "License",
    ],
  ],
  [
    "VISION.md",
    [
      "Mission",
      "Vision",
      "Problem space",
      "Target users",
      "Product goals",
      "Non-goals",
      "Product strategy",
      "Qualitative success criteria",
    ],
  ],
  [
    "PRINCIPLES.md",
    ["How to use these principles", "P1 —", "P12 —", "Decision rule"],
  ],
  [
    "DESIGN.md",
    [
      "Purpose",
      "Design authority",
      "System context",
      "Artifact boundary",
      "Ubiquitous language",
      "Architectural mechanisms",
      "Canonical interaction flow",
      "System invariants",
      "Planned project lifecycle",
      "Trust and authority",
      "Extension conformance",
      "Feature conformance",
    ],
  ],
  [
    "ROADMAP.md",
    [
      "Roadmap rules",
      "Status vocabulary",
      "P0 — Design Foundation",
      "P1 — Standards and Contracts",
      "P2 — Read-only Project Intelligence CLI",
      "P3 — Transactional Repository Initialization",
      "P4 — Knowledge and Context",
      "P5 — Work, Protocol, and Governance",
      "P6 — Extension Ecosystem",
      "P7 — Scale and Distributed Runtime",
    ],
  ],
  [
    "evidence/P0-DESIGN-FOUNDATION-REVIEW.md",
    [
      "Review objective",
      "Scope boundaries",
      "Exit criteria",
      "Consistency review",
      "Representative traceability",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-001-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Boundary review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-002-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Boundary review",
      "Safety review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-003-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Safety review",
      "Boundary review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-004-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Safety review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-005-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Safety review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-AOS-SPEC-006-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Contract review",
      "Safety review",
      "Findings",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P1-STANDARDS-CONTRACTS-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Deliverable matrix",
      "Cross-contract review",
      "Conformance and verification",
      "Accepted limitations",
      "Decision",
    ],
  ],
  [
    "evidence/P2-READ-ONLY-CLI-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Deliverable matrix",
      "Safety review",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P3-TRANSACTIONAL-INIT-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Deliverable matrix",
      "Safety review",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md",
    [
      "Review objective",
      "Entry gate",
      "Deliverable matrix",
      "Safety review",
      "Verification",
      "Decision",
    ],
  ],
  [
    "evidence/P5-GOVERNED-WORK-REVIEW.md",
    [
      "Review objective",
      "Entry-gate truth",
      "Implemented vertical slice",
      "Safety evidence",
      "Verification",
      "Maturity decision",
    ],
  ],
  [
    "specifications/001-information-model.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "P4 Knowledge and State serialization",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/002-repository.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/003-protocol.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/004-cli.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "P4 Knowledge and Context commands",
      "P5 Work, Protocol, and Governance commands",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/005-runtime.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/006-extension.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "specifications/README.md",
    [
      "Authority",
      "Identifier",
      "Lifecycle",
      "Normative language",
      "Required structure",
      "Planned specification queue",
      "Acceptance process",
    ],
  ],
  [
    "specifications/TEMPLATE.md",
    [
      "Purpose",
      "Motivation",
      "Scope",
      "Non-goals",
      "Terminology",
      "Normative requirements",
      "Interfaces and data flow",
      "Lifecycle and state transitions",
      "Failure behavior",
      "Security and governance",
      "Compatibility and migration",
      "Conformance tests",
      "Unresolved questions",
      "Change history",
    ],
  ],
  [
    "adr/TEMPLATE.md",
    [
      "Context",
      "Decision",
      "Consequences",
      "Alternatives considered",
      "Compatibility and migration",
      "Conformance",
    ],
  ],
]);

function toRepositoryPath(absolutePath) {
  return relative(repositoryRoot, absolutePath).replaceAll("\\", "/");
}

function readUtf8(repositoryPath) {
  const absolutePath = join(repositoryRoot, repositoryPath);

  try {
    return decoder.decode(readFileSync(absolutePath));
  } catch (error) {
    errors.push(`${repositoryPath}: not valid UTF-8 (${error.message})`);
    return "";
  }
}

function collectMarkdownFiles(directory) {
  const files = [];

  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === ".codebase-memory") {
      continue;
    }

    const absolutePath = join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectMarkdownFiles(absolutePath));
    } else if (entry.isFile() && extname(entry.name).toLowerCase() === ".md") {
      files.push(absolutePath);
    }
  }

  return files;
}

for (const repositoryPath of requiredFiles) {
  const absolutePath = join(repositoryRoot, repositoryPath);
  if (!existsSync(absolutePath) || !statSync(absolutePath).isFile()) {
    errors.push(`${repositoryPath}: required file is missing`);
  }
}

for (const [repositoryPath, headings] of requiredHeadings) {
  const content = readUtf8(repositoryPath);

  for (const heading of headings) {
    if (!content.includes(`# ${heading}`) && !content.includes(`## ${heading}`)) {
      errors.push(`${repositoryPath}: required heading "${heading}" is missing`);
    }
  }
}

const markdownFiles = collectMarkdownFiles(repositoryRoot);

for (const absolutePath of markdownFiles) {
  const repositoryPath = toRepositoryPath(absolutePath);
  const content = readUtf8(repositoryPath);
  const linkPattern = /!?\[[^\]]*]\(([^)]+)\)/g;

  if (/[ \t]+$/m.test(content)) {
    errors.push(`${repositoryPath}: trailing whitespace is not allowed`);
  }
  if (!content.endsWith("\n")) {
    errors.push(`${repositoryPath}: file must end with a newline`);
  }

  for (const match of content.matchAll(linkPattern)) {
    let target = match[1].trim();

    if (
      target.startsWith("#") ||
      /^(?:https?:|mailto:)/i.test(target)
    ) {
      continue;
    }

    if (target.startsWith("<") && target.endsWith(">")) {
      target = target.slice(1, -1);
    }

    target = target.split("#", 1)[0];
    if (!target) {
      continue;
    }

    try {
      target = decodeURIComponent(target);
    } catch {
      errors.push(`${repositoryPath}: invalid link encoding "${match[1]}"`);
      continue;
    }

    const resolvedTarget = resolve(dirname(absolutePath), target);
    if (!existsSync(resolvedTarget)) {
      errors.push(`${repositoryPath}: broken local link "${match[1]}"`);
    }
  }
}

const canonicalDocuments = [
  "README.md",
  "VISION.md",
  "PRINCIPLES.md",
  "DESIGN.md",
  "ROADMAP.md",
];

const forbiddenCanonicalPatterns = [
  {
    pattern: /\bAI Operating System\b/i,
    message: 'must not expand AOS as "AI Operating System"',
  },
  {
    pattern: /\baos install\b/i,
    message: 'must use the planned canonical project command "aos init"',
  },
  {
    pattern: /\b(?:Oracle|Forge|Atlas|Sage)\b/,
    message: "must not name premature runtime components",
  },
];

for (const repositoryPath of canonicalDocuments) {
  const content = readUtf8(repositoryPath);

  for (const { pattern, message } of forbiddenCanonicalPatterns) {
    if (pattern.test(content)) {
      errors.push(`${repositoryPath}: ${message}`);
    }
  }
}

const officialDescriptor = "Project Intelligence Operating System";
for (const repositoryPath of ["README.md", "VISION.md", "DESIGN.md"]) {
  if (!readUtf8(repositoryPath).includes(officialDescriptor)) {
    errors.push(`${repositoryPath}: official product descriptor is missing`);
  }
}

const readme = readUtf8("README.md");
for (const target of [
  "VISION.md",
  "PRINCIPLES.md",
  "DESIGN.md",
  "ROADMAP.md",
  "specifications/README.md",
  "adr/README.md",
  "evidence/P0-DESIGN-FOUNDATION-REVIEW.md",
  "evidence/P1-AOS-SPEC-001-REVIEW.md",
  "evidence/P1-AOS-SPEC-002-REVIEW.md",
  "evidence/P1-AOS-SPEC-003-REVIEW.md",
  "evidence/P1-AOS-SPEC-004-REVIEW.md",
  "evidence/P1-AOS-SPEC-005-REVIEW.md",
  "evidence/P1-AOS-SPEC-006-REVIEW.md",
  "evidence/P1-STANDARDS-CONTRACTS-REVIEW.md",
  "evidence/P2-READ-ONLY-CLI-REVIEW.md",
  "evidence/P3-TRANSACTIONAL-INIT-REVIEW.md",
  "evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md",
  "evidence/P5-GOVERNED-WORK-REVIEW.md",
]) {
  if (!readme.includes(`](${target})`)) {
    errors.push(`README.md: missing navigation link to ${target}`);
  }
}

const roadmap = readUtf8("ROADMAP.md");
const p0Section = roadmap.match(
  /## P0 — Design Foundation([\s\S]*?)(?=\n## P1 — Standards and Contracts)/,
);
if (!p0Section) {
  errors.push("ROADMAP.md: P0 section is missing");
} else {
  if (!p0Section[1].includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P0 must be marked COMPLETE after closeout");
  }
  if (
    !p0Section[1].includes(
      "evidence/P0-DESIGN-FOUNDATION-REVIEW.md",
    )
  ) {
    errors.push("ROADMAP.md: P0 closeout evidence link is missing");
  }
}

const p0Review = readUtf8("evidence/P0-DESIGN-FOUNDATION-REVIEW.md");
if (!p0Review.includes("**Status:** PASS")) {
  errors.push("P0 review: status must be PASS");
}
if (!p0Review.includes("**Decision:** P0 exit gate satisfied")) {
  errors.push("P0 review: exit-gate decision is missing");
}

const p1Section = roadmap.match(
  /## P1 — Standards and Contracts([\s\S]*?)(?=\n## P2 — Read-only Project Intelligence CLI)/,
);
if (!p1Section) {
  errors.push("ROADMAP.md: P1 section is missing");
} else {
  if (!p1Section[1].includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P1 must be COMPLETE after all six specifications are accepted");
  }
  for (const specification of [
    "001-information-model.md",
    "002-repository.md",
    "003-protocol.md",
    "004-cli.md",
    "005-runtime.md",
    "006-extension.md",
  ]) {
    if (!p1Section[1].includes(`specifications/${specification}`)) {
      errors.push(`ROADMAP.md: P1 specification link ${specification} is missing`);
    }
  }
  if (!p1Section[1].includes("evidence/P1-STANDARDS-CONTRACTS-REVIEW.md")) {
    errors.push("ROADMAP.md: P1 closeout evidence link is missing");
  }
}

const gitignore = readUtf8(".gitignore");
if (!/^\.codebase-memory\/$/m.test(gitignore)) {
  errors.push(".gitignore: .codebase-memory/ must be ignored");
}

const license = readUtf8("LICENSE");
if (
  !license.includes("Apache License") ||
  !license.includes("Version 2.0, January 2004")
) {
  errors.push("LICENSE: standard Apache License 2.0 text is missing");
}

const adrDirectory = join(repositoryRoot, "adr");
const adrFiles = readdirSync(adrDirectory)
  .filter((name) => /^\d{4}-[a-z0-9-]+\.md$/.test(name))
  .sort();
const adrIds = new Set();

for (const filename of adrFiles) {
  const idFromFilename = filename.slice(0, 4);
  const repositoryPath = `adr/${filename}`;
  const content = readUtf8(repositoryPath);
  const headingMatch = content.match(/^# ADR-(\d{4}) — .+$/m);
  const statusMatch = content.match(/^\*\*Status:\*\* (.+)$/m);

  if (!headingMatch) {
    errors.push(`${repositoryPath}: ADR heading is invalid`);
  } else if (headingMatch[1] !== idFromFilename) {
    errors.push(`${repositoryPath}: heading ID does not match filename`);
  }

  if (adrIds.has(idFromFilename)) {
    errors.push(`${repositoryPath}: duplicate ADR identifier`);
  }
  adrIds.add(idFromFilename);

  if (!statusMatch) {
    errors.push(`${repositoryPath}: ADR status is missing`);
  } else {
    const status = statusMatch[1].trim();
    if (
      !["Proposed", "Accepted", "Deprecated", "Superseded", "Rejected"].includes(
        status,
      )
    ) {
      errors.push(`${repositoryPath}: ADR status "${status}" is invalid`);
    }
  }
}

const expectedFoundationAdrs = [
  "0001",
  "0002",
  "0003",
  "0004",
  "0005",
  "0006",
  "0007",
  "0008",
];
for (const id of expectedFoundationAdrs) {
  if (!adrIds.has(id)) {
    errors.push(`adr/: foundational ADR-${id} is missing`);
  }
}

const adrIndex = readUtf8("adr/README.md");
for (const filename of adrFiles) {
  if (!adrIndex.includes(`](${filename})`)) {
    errors.push(`adr/README.md: missing index link to ${filename}`);
  }
}

const specificationIndex = readUtf8("specifications/README.md");
for (const state of ["Draft", "Accepted", "Deprecated", "Superseded"]) {
  if (!specificationIndex.includes(`\`${state}\``)) {
    errors.push(`specifications/README.md: lifecycle state ${state} is missing`);
  }
}

for (const keyword of ["MUST", "MUST NOT", "SHOULD", "SHOULD NOT", "MAY"]) {
  if (!specificationIndex.includes(`**${keyword}**`)) {
    errors.push(
      `specifications/README.md: normative keyword ${keyword} is missing`,
    );
  }
}

for (let number = 1; number <= 6; number += 1) {
  const id = `AOS-SPEC-${String(number).padStart(3, "0")}`;
  if (!specificationIndex.includes(`\`${id}\``)) {
    errors.push(`specifications/README.md: planned identifier ${id} is missing`);
  }
}

const unexpectedSpecificationFiles = readdirSync(
  join(repositoryRoot, "specifications"),
).filter(
  (name) =>
    name.endsWith(".md") &&
    name !== "README.md" &&
    name !== "TEMPLATE.md" &&
    !/^\d{3}-[a-z0-9-]+\.md$/.test(name),
);

if (unexpectedSpecificationFiles.length > 0) {
  errors.push(
    `specifications/: invalid specification filenames: ${unexpectedSpecificationFiles.join(", ")}`,
  );
}

const informationModel = readUtf8("specifications/001-information-model.md");
if (!/^# AOS-SPEC-001 — Information Model$/m.test(informationModel)) {
  errors.push("AOS-SPEC-001: heading or identifier is invalid");
}
if (!/^\*\*Status:\*\* Accepted$/m.test(informationModel)) {
  errors.push("AOS-SPEC-001: status must be Accepted");
}
const unresolvedQuestions = informationModel.match(
  /## Unresolved questions([\s\S]*?)(?=\r?\n## Change history)/,
);
if (!unresolvedQuestions || unresolvedQuestions[1].trim() !== "") {
  errors.push("AOS-SPEC-001: unresolved questions must be empty when Accepted");
}
if (!/IM-C\d{3}/.test(informationModel)) {
  errors.push("AOS-SPEC-001: conformance cases are missing");
}
const informationModelReview = readUtf8(
  "evidence/P1-AOS-SPEC-001-REVIEW.md",
);
if (!informationModelReview.includes("**Status:** PASS")) {
  errors.push("P1 Information Model review: status must be PASS");
}
if (!informationModelReview.includes("**Decision:** Accepted")) {
  errors.push("P1 Information Model review: acceptance decision is missing");
}

const repositorySpecification = readUtf8(
  "specifications/002-repository.md",
);
if (!/^# AOS-SPEC-002 — Repository$/m.test(repositorySpecification)) {
  errors.push("AOS-SPEC-002: heading or identifier is invalid");
}
if (!/^\*\*Status:\*\* Accepted$/m.test(repositorySpecification)) {
  errors.push("AOS-SPEC-002: status must be Accepted");
}
const repositoryUnresolvedQuestions = repositorySpecification.match(
  /## Unresolved questions([\s\S]*?)(?=\r?\n## Change history)/,
);
if (
  !repositoryUnresolvedQuestions ||
  repositoryUnresolvedQuestions[1].trim() !== ""
) {
  errors.push("AOS-SPEC-002: unresolved questions must be empty when Accepted");
}
if (!/RM-C\d{3}/.test(repositorySpecification)) {
  errors.push("AOS-SPEC-002: conformance cases are missing");
}
const repositoryReview = readUtf8("evidence/P1-AOS-SPEC-002-REVIEW.md");
if (!repositoryReview.includes("**Status:** PASS")) {
  errors.push("P1 Repository review: status must be PASS");
}
if (!repositoryReview.includes("**Decision:** Accepted")) {
  errors.push("P1 Repository review: acceptance decision is missing");
}

const protocolSpecification = readUtf8("specifications/003-protocol.md");
if (!/^# AOS-SPEC-003 — Protocol$/m.test(protocolSpecification)) {
  errors.push("AOS-SPEC-003: heading or identifier is invalid");
}
if (!/^\*\*Status:\*\* Accepted$/m.test(protocolSpecification)) {
  errors.push("AOS-SPEC-003: status must be Accepted");
}
const protocolUnresolvedQuestions = protocolSpecification.match(
  /## Unresolved questions([\s\S]*?)(?=\r?\n## Change history)/,
);
if (
  !protocolUnresolvedQuestions ||
  protocolUnresolvedQuestions[1].trim() !== ""
) {
  errors.push("AOS-SPEC-003: unresolved questions must be empty when Accepted");
}
if (!/PR-C\d{3}/.test(protocolSpecification)) {
  errors.push("AOS-SPEC-003: conformance cases are missing");
}
const protocolReview = readUtf8("evidence/P1-AOS-SPEC-003-REVIEW.md");
if (!protocolReview.includes("**Status:** PASS")) {
  errors.push("P1 Protocol review: status must be PASS");
}
if (!protocolReview.includes("**Decision:** Accepted")) {
  errors.push("P1 Protocol review: acceptance decision is missing");
}

for (const specification of [
  {
    path: "specifications/004-cli.md",
    id: "AOS-SPEC-004",
    title: "CLI",
    conformancePrefix: "CLI",
    reviewPath: "evidence/P1-AOS-SPEC-004-REVIEW.md",
  },
  {
    path: "specifications/005-runtime.md",
    id: "AOS-SPEC-005",
    title: "Runtime",
    conformancePrefix: "RT",
    reviewPath: "evidence/P1-AOS-SPEC-005-REVIEW.md",
  },
  {
    path: "specifications/006-extension.md",
    id: "AOS-SPEC-006",
    title: "Extension",
    conformancePrefix: "EX",
    reviewPath: "evidence/P1-AOS-SPEC-006-REVIEW.md",
  },
]) {
  const content = readUtf8(specification.path);
  if (
    !content.includes(`# ${specification.id} — ${specification.title}`) ||
    !/^\*\*Status:\*\* Accepted$/m.test(content)
  ) {
    errors.push(`${specification.id}: heading or Accepted status is invalid`);
  }
  const unresolved = content.match(
    /## Unresolved questions([\s\S]*?)(?=\r?\n## Change history)/,
  );
  if (!unresolved || unresolved[1].trim() !== "") {
    errors.push(
      `${specification.id}: unresolved questions must be empty when Accepted`,
    );
  }
  if (!new RegExp(`${specification.conformancePrefix}-C\\d{3}`).test(content)) {
    errors.push(`${specification.id}: conformance cases are missing`);
  }

  const review = readUtf8(specification.reviewPath);
  if (
    !review.includes("**Status:** PASS") ||
    !review.includes("**Decision:** Accepted")
  ) {
    errors.push(`${specification.id}: review PASS/Accepted evidence is missing`);
  }
}

const p1Review = readUtf8("evidence/P1-STANDARDS-CONTRACTS-REVIEW.md");
if (!p1Review.includes("**Status:** PASS")) {
  errors.push("P1 review: status must be PASS");
}
if (!p1Review.includes("**Decision:** P1 exit gate satisfied")) {
  errors.push("P1 review: exit-gate decision is missing");
}

const p2Start = roadmap.indexOf("## P2 ");
const p3Start = roadmap.indexOf("## P3 ");
if (p2Start < 0 || p3Start < 0 || p3Start <= p2Start) {
  errors.push("ROADMAP.md: P2/P3 ordering is missing");
} else {
  const p2Section = roadmap.slice(p2Start, p3Start);
  const p3End = roadmap.indexOf("## P4 ", p3Start);
  const p3Section = roadmap.slice(p3Start, p3End < 0 ? roadmap.length : p3End);

  if (!p2Section.includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P2 must be COMPLETE after CLI closeout");
  }
  if (!p2Section.includes("evidence/P2-READ-ONLY-CLI-REVIEW.md")) {
    errors.push("ROADMAP.md: P2 closeout evidence link is missing");
  }
  if (!p3Section.includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P3 must be COMPLETE after transactional init closeout");
  }
  if (!p3Section.includes("evidence/P3-TRANSACTIONAL-INIT-REVIEW.md")) {
    errors.push("ROADMAP.md: P3 closeout evidence link is missing");
  }
}

if (!roadmap.includes("**Current maturity:** P6")) {
  errors.push("ROADMAP.md: current maturity must identify the active P6 slice");
}
if (
  !roadmap.includes(
    "**Next eligible phase:** P7 only after qualification evidence and a measured scale need",
  )
) {
  errors.push(
    "ROADMAP.md: P7 must remain gated by qualification evidence and a measured scale need",
  );
}

const p2Review = readUtf8("evidence/P2-READ-ONLY-CLI-REVIEW.md");
if (!p2Review.includes("**Status:** PASS")) {
  errors.push("P2 review: status must be PASS");
}
if (!p2Review.includes("**Decision:** P2 exit gate satisfied")) {
  errors.push("P2 review: exit-gate decision is missing");
}
if (!readUtf8("rust-toolchain.toml").includes('channel = "1.96.0"')) {
  errors.push("rust-toolchain.toml: Rust 1.96.0 must be pinned");
}
if (!readUtf8("Cargo.toml").includes('name = "aos-cli"')) {
  errors.push("Cargo.toml: package name must be aos-cli");
}
if (!readUtf8("Cargo.toml").includes('name = "aos"')) {
  errors.push("Cargo.toml: binary name must be aos");
}
for (const sourceFile of [
  "src/main.rs",
  "src/cli.rs",
  "src/model.rs",
  "src/repository.rs",
  "src/intelligence.rs",
  "src/work.rs",
  "src/extension.rs",
  "tests/cli_smoke.rs",
]) {
  if (readUtf8(sourceFile).trim().length === 0) {
    errors.push(`${sourceFile}: P2 implementation file is empty`);
  }
}

const p3Review = readUtf8("evidence/P3-TRANSACTIONAL-INIT-REVIEW.md");
if (!p3Review.includes("**Status:** PASS")) {
  errors.push("P3 review: status must be PASS");
}
if (!p3Review.includes("**Decision:** P3 exit gate satisfied")) {
  errors.push("P3 review: exit-gate decision is missing");
}
const p3RepositorySpecification = readUtf8("specifications/002-repository.md");
for (const requiredManifestField of [
  "schema_version",
  "contract_version",
  "project_id",
  "repository_id",
  "operation_id",
  "authority_reference",
]) {
  if (!p3RepositorySpecification.includes(requiredManifestField)) {
    errors.push(
      `AOS-SPEC-002: P3 manifest field ${requiredManifestField} is missing`,
    );
  }
}
if (!readUtf8("README.md").includes("P3 Transactional Initialization Review")) {
  errors.push("README.md: P3 review navigation is missing");
}

const p4Start = roadmap.indexOf("## P4 ");
const p5Start = roadmap.indexOf("## P5 ");
if (p4Start < 0 || p5Start < 0 || p5Start <= p4Start) {
  errors.push("ROADMAP.md: P4/P5 ordering is missing");
} else {
  const p4Section = roadmap.slice(p4Start, p5Start);
  const p5End = roadmap.indexOf("## P6 ", p5Start);
  const p5Section = roadmap.slice(p5Start, p5End < 0 ? roadmap.length : p5End);
  if (!p4Section.includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P4 must be COMPLETE after Knowledge/Context closeout");
  }
  if (!p4Section.includes("evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md")) {
    errors.push("ROADMAP.md: P4 closeout evidence link is missing");
  }
  if (!p5Section.includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P5 must be COMPLETE after hosted CI closeout");
  }
  if (!p5Section.includes("evidence/P5-GOVERNED-WORK-REVIEW.md")) {
    errors.push("ROADMAP.md: P5 implementation evidence link is missing");
  }
  if (!p5Section.includes("30246501837") ||
      !p5Section.includes("30246618788") ||
      !p5Section.includes("v0.1.0-rc.2")) {
    errors.push("ROADMAP.md: P5 closeout must record successful hosted CI evidence");
  }
}

const p6Start = roadmap.indexOf("## P6 ");
const p7Start = roadmap.indexOf("## P7 ");
if (p6Start < 0 || p7Start < 0 || p7Start <= p6Start) {
  errors.push("ROADMAP.md: P6/P7 ordering is missing");
} else {
  const p6Section = roadmap.slice(p6Start, p7Start);
  if (!p6Section.includes("**Status:** `COMPLETE`")) {
    errors.push("ROADMAP.md: P6 must be COMPLETE after hosted CI and RC3 closeout");
  }
  if (!p6Section.includes("30251035563") ||
      !p6Section.includes("30251174570") ||
      !p6Section.includes("v0.1.0-rc.3")) {
    errors.push("ROADMAP.md: P6 closeout must record hosted CI and RC3 provenance");
  }
}

const p6Review = readUtf8("evidence/P6-EXTENSION-ECOSYSTEM-REVIEW.md");
if (!p6Review.includes("**Status:** COMPLETE")) {
  errors.push("P6 review: status must be COMPLETE");
}
if (!p6Review.includes("AOS_RC3_CHECKSUMS_OK")) {
  errors.push("P6 review: RC3 checksum verification evidence is missing");
}

const p4Review = readUtf8("evidence/P4-KNOWLEDGE-CONTEXT-REVIEW.md");
if (!p4Review.includes("**Status:** PASS")) {
  errors.push("P4 review: status must be PASS");
}
if (!p4Review.includes("**Decision:** P4 exit gate satisfied")) {
  errors.push("P4 review: exit-gate decision is missing");
}
const p4InformationModel = readUtf8("specifications/001-information-model.md");
for (const requiredP4Field of [
  "previous_revision",
  "source_reference",
  "authority_reference",
  "freshness_policy",
]) {
  if (!p4InformationModel.includes(requiredP4Field)) {
    errors.push(`AOS-SPEC-001: P4 field ${requiredP4Field} is missing`);
  }
}
const p4CliSpecification = readUtf8("specifications/004-cli.md");
for (const command of ["aos knowledge", "aos state", "aos context"]) {
  if (!p4CliSpecification.includes(command)) {
    errors.push(`AOS-SPEC-004: P4 command ${command} is missing`);
  }
}

const p5Review = readUtf8("evidence/P5-GOVERNED-WORK-REVIEW.md");
if (!p5Review.includes("**Status:** COMPLETE") ||
    !p5Review.includes("P5 roadmap closeout:             PASS") ||
    !p5Review.includes("closeout commit run: 30246501837 PASS") ||
    !p5Review.includes("release workflow: 30246618788 PASS") ||
    !p5Review.includes("AOS_RC2_CHECKSUMS_OK")) {
  errors.push("P5 review: successful hosted CI closeout truth is missing");
}
for (const marker of [
  "AOS_P5_GOVERNED_WORK_CONTRACT_OK",
  "AOS_P5_GOVERNED_WORK_SMOKE_OK",
  "AOS_P5_GOVERNANCE_RECONCILIATION_OK",
  "AOS_P5_HARDENING_OK",
  "AOS_P4_VALUE_BENCHMARK_OK",
  "AOS_CONTROLLED_DOWNSTREAM_PILOT_OK",
]) {
  if (!p5Review.includes(marker)) {
    errors.push(`P5 review: expected marker ${marker} is missing`);
  }
}
const p4ValueReview = readUtf8("evidence/P4-VALUE-BENCHMARK.md");
if (!p4ValueReview.includes("**Status:** QUALIFIED PATCH/TEST VALUE GATE PASS") ||
    !p4ValueReview.includes("AOS_P4_VALUE_BENCHMARK_OK")) {
  errors.push("P4 value review: qualified value marker is missing");
}
const pilotReview = readUtf8("evidence/P5-CONTROLLED-DOWNSTREAM-PILOT.md");
if (!pilotReview.includes("**Status:** PASS") ||
    !pilotReview.includes("AOS_CONTROLLED_DOWNSTREAM_PILOT_OK")) {
  errors.push("P5 controlled pilot: pass marker is missing");
}
for (const action of ["create", "authorize", "run", "reconcile", "show"]) {
  if (!p4CliSpecification.includes(`\`aos work ${action}\``)) {
    errors.push(`AOS-SPEC-004: P5 work action ${action} is missing`);
  }
}

if (errors.length > 0) {
  console.error("AOS_DESIGN_FOUNDATION_FAILED");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exitCode = 1;
} else {
  console.log("AOS_DESIGN_FOUNDATION_OK");
}
