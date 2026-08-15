import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = process.env.DARKTIDE_SOURCE_ROOT || process.argv[2];

if (!sourceRoot) {
  console.error(
    "Set DARKTIDE_SOURCE_ROOT or pass the Darktide 1.12.4 source directory as the first argument.",
  );
  process.exit(2);
}

const run = (label, args, extraEnv = {}) => {
  console.log(`\n== ${label} ==`);
  const result = spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, ...extraEnv },
    stdio: "inherit",
  });

  if (result.error) {
    console.error(`${label} could not start: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
};

run("package and 1.12.4 source contracts", ["tests/smoke_test.mjs", sourceRoot], {
  DARKTIDE_SOURCE_ROOT: sourceRoot,
});
run("Lua behavior suites", ["tests/run_behavior.mjs"]);

console.log("\ncomplete release gate: PASS");
