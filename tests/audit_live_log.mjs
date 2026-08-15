import fs from "node:fs";
import process from "node:process";

const logPath = process.argv[2] || process.env.DARKTIDE_CONSOLE_LOG;

if (!logPath) {
  process.stderr.write(
    "Usage: node tests/audit_live_log.mjs path/to/Darktide/console.log\n",
  );
  process.exit(2);
}

const lines = fs.readFileSync(logPath, "utf8").split(/\r?\n/u);
const initIndex = lines.findIndex((line) =>
  line.includes("Init DMF mod 'TertiumFixes'"),
);

if (initIndex < 0) {
  process.stderr.write("FAIL TertiumFixes DMF initialization was not found\n");
  process.exit(1);
}

const sessionLines = lines.slice(initIndex);
const modLines = sessionLines.filter(
  (line) =>
    line.includes("[MOD][TertiumFixes]") ||
    line.includes("Tertium Fixes module failed"),
);
const errors = modLines.filter(
  (line) => line.includes("[ERROR]") || line.includes("module failed"),
);
const hookLines = modLines.filter(
  (line) => line.includes("Hooking '") || line.includes("needs to be delayed"),
);
const installedMethods = [
  ...new Set(
    hookLines
      .map((line) => line.match(/(?:Hooking|\[)(?:\s*)?'([^']+)'/u)?.[1])
      .filter(Boolean),
  ),
].sort();
const teamcityLine = lines.find((line) => line.includes("teamcity_build_id ="));
const teamcityBuild = teamcityLine?.match(/teamcity_build_id = (\d+)/u)?.[1];

process.stdout.write(`Log: ${logPath}\n`);
process.stdout.write(`Engine build: ${teamcityBuild ?? "not recorded"}\n`);
process.stdout.write(`Tertium hook registrations: ${hookLines.length}\n`);
process.stdout.write(`Unique hooked methods: ${installedMethods.length}\n`);
process.stdout.write(`Tertium errors after initialization: ${errors.length}\n`);

if (installedMethods.length > 0) {
  process.stdout.write(`Methods: ${installedMethods.join(", ")}\n`);
}

if (errors.length > 0) {
  process.stderr.write(`${errors.join("\n")}\n`);
  process.exit(1);
}

if (hookLines.length < 10) {
  process.stderr.write(
    "FAIL fewer than ten Tertium hook registrations were observed; this session is not useful install-path evidence\n",
  );
  process.exit(1);
}

process.stdout.write("PASS live DMF initialization and hook-install path is clean\n");
