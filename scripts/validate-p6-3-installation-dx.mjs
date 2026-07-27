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

requireText("src/cli.rs", [
  "Command::Setup",
  '"--yes"',
  "setup_result",
  "Continue? [y/N]",
]);
requireText("src/setup.rs", [
  "include_str!",
  "extension::enable_bundled",
  "AOS-SETUP-PLAN-READY",
  "AOS-SETUP-COMPLETE",
  "AOS-SETUP-ALREADY-COMPLETE",
  "local-user:",
]);
requireText("install.ps1", [
  "ArchivePath",
  "ChecksumPath",
  "Get-FileHash",
  "install.json",
  "AOS_P6_3_INSTALL_WINDOWS_OK",
]);
requireText("install.sh", [
  "archive-path",
  "checksum-path",
  "sha256sum",
  "install.json",
  "AOS_P6_3_INSTALL_LINUX_OK",
]);
requireText("adr/0011-p6-3-one-command-installation-and-setup.md", [
  "**Status:** Accepted",
  "does not fabricate",
  "never search for or remove downstream `.aos`",
]);
requireText("specifications/004-cli.md", [
  "**CLI-062.**",
  "**CLI-068.**",
  "`aos setup`",
]);
requireText(".github/workflows/ci.yml", [
  "run_p6_3_windows_installer_smoke.ps1",
  "run_p6_3_linux_installer_smoke.sh",
]);
requireText(".github/workflows/release.yml", [
  "install.ps1",
  "install.sh",
  "actions/attest-build-provenance@v2",
  "Hosted install smoke",
]);
requireText("evidence/P6.3-INSTALLATION-DEVELOPER-EXPERIENCE.md", [
  "**Status:** PASS",
  "AOS_P6_3_SETUP_CONTRACT_OK",
  "AOS_P6_3_INSTALL_WINDOWS_OK",
  "AOS_P6_3_INSTALL_LINUX_OK",
  "AOS_P6_3_FRESH_PROJECT_SMOKE_OK",
  "AOS_P6_3_INSTALLATION_DX_OK",
  "30274793870",
  "30274942709",
  "v0.1.0-rc.4",
]);

if (failures.length > 0) {
  console.error("AOS_P6_3_INSTALLATION_DX_STATIC_VALIDATION_FAILED");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("AOS_P6_3_INSTALLATION_DX_STATIC_VALIDATION_OK");
console.log("AOS_P6_3_INSTALLATION_DX_OK");
