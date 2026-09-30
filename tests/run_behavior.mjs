import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fengariCli = path.join(
  repoRoot,
  "node_modules",
  "fengari-node-cli",
  "src",
  "lua-cli.js",
);

const sourceRoot = process.env.DARKTIDE_SOURCE_ROOT || process.argv[2];
if (!sourceRoot || !fs.existsSync(path.join(sourceRoot, "scripts"))) {
  console.error("Set DARKTIDE_SOURCE_ROOT or pass the extracted game source directory.");
  process.exit(2);
}
const suites = fs.readdirSync(path.join(repoRoot, "tests"))
  .filter(name => name.endsWith("_behavior.lua")).sort();

for (const suite of suites) {
  const args = [fengariCli, path.join("tests", suite)];
  if (suite.endsWith("_source_behavior.lua")) args.push(sourceRoot);
  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, DARKTIDE_SOURCE_ROOT: sourceRoot },
    timeout: 60000,
    maxBuffer: 4 * 1024 * 1024,
  });

  process.stdout.write(result.stdout || "");
  process.stderr.write(result.stderr || "");

  if (result.error) {
    console.error(`Unable to run ${suite}: ${result.error.message}`);
    process.exit(1);
  }

  const completed = /\b[1-9]\d* (?:checks, 0 failures|passed, 0 failed)\b/.test(result.stdout || "");
  if (result.status !== 0 || !completed || /^\s*SKIP\b/m.test(result.stdout || "") || (result.stderr || "").trim()) {
    console.error(`${suite} failed or did not complete all its checks.`);
    process.exit(result.status || 1);
  }
}

console.log(`behaviour gate: ${suites.length} suites passed without skips`);
