import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const fengariCli = path.join(
  repoRoot,
  "node_modules",
  "fengari-node-cli",
  "src",
  "lua-cli.js",
);

const suites = [
  "deferred_loader_behavior.lua",
  "effect_template_safety_behavior.lua",
  "engine_cleanup_behavior.lua",
  "fx_handler_integrity_behavior.lua",
  "gc_pressure_behavior.lua",
  "hive_scum_stimm_chime_behavior.lua",
  "input_and_buff_behavior.lua",
  "metadata_repairs_behavior.lua",
  "notification_dedupe_behavior.lua",
  "psykhanium_source_guards_behavior.lua",
  "remaining_repairs_behavior.lua",
  "runtime_hardening_behavior.lua",
  "runtime_performance_behavior.lua",
];

for (const suite of suites) {
  const result = spawnSync(process.execPath, [fengariCli, path.join("tests", suite)], {
    cwd: repoRoot,
    encoding: "utf8",
    stdio: "inherit",
  });

  if (result.error) {
    console.error(`Unable to run ${suite}: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

console.log(`behavior gate: ${suites.length} suites passed`);
