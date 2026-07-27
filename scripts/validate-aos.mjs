import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const validators = [
  "validate-design-foundation.mjs",
  "validate-specifications.mjs",
  "validate-p6-extension-ecosystem.mjs",
  "validate-extension-authoring-kit.mjs",
];

for (const validator of validators) {
  const result = spawnSync(process.execPath, [join(scriptDirectory, validator)], {
    encoding: "utf8",
    windowsHide: true,
  });

  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }

  if (result.error || result.status !== 0) {
    console.error("AOS_GOVERNANCE_FAILED");
    if (result.error) {
      console.error(`- ${validator}: ${result.error.message}`);
    }
    process.exitCode = result.status ?? 1;
    break;
  }
}

if (!process.exitCode) {
  console.log("AOS_GOVERNANCE_OK");
}
