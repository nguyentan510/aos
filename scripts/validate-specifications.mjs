import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { TextDecoder } from "node:util";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const specificationDirectory = join(repositoryRoot, "specifications");
const decoder = new TextDecoder("utf-8", { fatal: true });
const errors = [];

const requiredSections = [
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
];

function repositoryPath(absolutePath) {
  return relative(repositoryRoot, absolutePath).replaceAll("\\", "/");
}

function readUtf8(absolutePath) {
  try {
    return decoder.decode(readFileSync(absolutePath));
  } catch (error) {
    errors.push(
      `${repositoryPath(absolutePath)}: invalid UTF-8 (${error.message})`,
    );
    return "";
  }
}

function sectionBody(content, heading, nextHeading) {
  const expression = new RegExp(
    `^## ${heading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*\\n([\\s\\S]*?)(?=^## ${nextHeading.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*$|(?![\\s\\S]))`,
    "m",
  );
  return content.match(expression)?.[1] ?? null;
}

if (!existsSync(specificationDirectory) || !statSync(specificationDirectory).isDirectory()) {
  errors.push("specifications/: directory is missing");
} else {
  const specificationFiles = readdirSync(specificationDirectory)
    .filter((name) => /^\d{3}-[a-z0-9-]+\.md$/.test(name))
    .sort();

  if (specificationFiles.length === 0) {
    errors.push("specifications/: no specification files found");
  }

  for (const filename of specificationFiles) {
    const absolutePath = join(specificationDirectory, filename);
    const path = repositoryPath(absolutePath);
    const content = readUtf8(absolutePath);
    const numericId = filename.slice(0, 3);
    const headingMatch = content.match(/^# (AOS-SPEC-\d{3}) — (.+)$/m);
    const statusMatch = content.match(/^\*\*Status:\*\* (.+)$/m);

    if (!headingMatch || headingMatch[1] !== `AOS-SPEC-${numericId}`) {
      errors.push(`${path}: heading or identifier does not match filename`);
    }

    if (!statusMatch) {
      errors.push(`${path}: status is missing`);
    } else if (
      !["Draft", "Accepted", "Deprecated", "Superseded"].includes(
        statusMatch[1].trim(),
      )
    ) {
      errors.push(`${path}: invalid status "${statusMatch[1].trim()}"`);
    }

    if (/[ \t]+$/m.test(content)) {
      errors.push(`${path}: trailing whitespace is not allowed`);
    }
    if (!content.endsWith("\n")) {
      errors.push(`${path}: file must end with a newline`);
    }

    for (const section of requiredSections) {
      if (!content.includes(`## ${section}`)) {
        errors.push(`${path}: required section "${section}" is missing`);
      }
    }

    const unresolved = sectionBody(
      content,
      "Unresolved questions",
      "Change history",
    );
    if (statusMatch?.[1].trim() === "Accepted" && unresolved?.trim()) {
      errors.push(`${path}: Accepted specification has unresolved questions`);
    }

    const requirementIds = [
      ...new Set(
        [...content.matchAll(/^\*\*([A-Z]{2,5}-\d{3})\./gm)].map(
          (match) => match[1],
        ),
      ),
    ];
    if (statusMatch?.[1].trim() === "Accepted" && requirementIds.length === 0) {
      errors.push(`${path}: Accepted specification has no numbered requirements`);
    }

    const conformance = sectionBody(
      content,
      "Conformance tests",
      "Unresolved questions",
    );
    if (statusMatch?.[1].trim() === "Accepted") {
      if (!conformance?.includes("Expected result")) {
        errors.push(`${path}: conformance table is missing expected results`);
      }
      if (!conformance?.match(/[A-Z]{2,5}-C\d{3}/)) {
        errors.push(`${path}: conformance cases are missing`);
      }

      const covered = new Set();
      for (const match of conformance.matchAll(
        /([A-Z]{2,5})-(\d{3})(?:\s*[–-]\s*\1-(\d{3}))?/g,
      )) {
        const prefix = match[1];
        const first = Number(match[2]);
        const last = match[3] ? Number(match[3]) : first;
        for (let number = first; number <= last; number += 1) {
          covered.add(`${prefix}-${String(number).padStart(3, "0")}`);
        }
      }

      for (const requirementId of requirementIds) {
        if (!covered.has(requirementId)) {
          errors.push(
            `${path}: ${requirementId} has no conformance coverage`,
          );
        }
      }
    }

    const linkPattern = /!?\[[^\]]*]\(([^)]+)\)/g;
    for (const match of content.matchAll(linkPattern)) {
      let target = match[1].trim();
      if (
        target.startsWith("#") ||
        /^(?:https?:|mailto:)/i.test(target)
      ) {
        continue;
      }
      target = target.replace(/^<|>$/g, "").split("#", 1)[0];
      if (!target) {
        continue;
      }
      const resolvedTarget = resolve(dirname(absolutePath), target);
      if (!existsSync(resolvedTarget)) {
        errors.push(`${path}: broken local link "${match[1]}"`);
      }
    }
  }

  const index = readUtf8(join(specificationDirectory, "README.md"));
  if (!index.includes("AOS-SPEC-001") || !index.includes("001-information-model.md")) {
    errors.push("specifications/README.md: AOS-SPEC-001 index entry is missing");
  }
  if (!index.includes("`Accepted`")) {
    errors.push("specifications/README.md: Accepted lifecycle is missing");
  }

  const informationModel = join(
    specificationDirectory,
    "001-information-model.md",
  );
  if (!existsSync(informationModel)) {
    errors.push("AOS-SPEC-001: specification file is missing");
  }
}

if (errors.length > 0) {
  console.error("AOS_SPECIFICATIONS_FAILED");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exitCode = 1;
} else {
  console.log("AOS_SPECIFICATIONS_OK");
}
