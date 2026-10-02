import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const scripts = "scripts/mods/TertiumFixes";
const read = name => fs.readFileSync(path.join(root, name), "utf8");
const errors = [];
let checks = 0;

function check(ok, message) {
  checks++;
  if (!ok) errors.push(message);
}

function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const name = path.join(directory, entry.name);
    return entry.isDirectory() ? files(name) : [name];
  }).sort();
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function compile(name, text, execute = false) {
  const bytes = to_luastring(text);
  let result = lauxlib.luaL_loadbuffer(L, bytes, bytes.length, to_luastring("@" + name));
  if (result === lua.LUA_OK && execute) result = lua.lua_pcall(L, 0, 0, 0);
  const error = result === lua.LUA_OK ? "" : to_jsstring(lua.lua_tostring(L, -1));
  check(result === lua.LUA_OK, `${name}: ${error}`);
  lua.lua_settop(L, 0);
}

const productionFiles = [path.join(root, "TertiumFixes.mod"), ...files(path.join(root, "scripts"))];
for (const name of productionFiles) {
  if (/\.(lua|mod)$/.test(name)) compile(path.relative(root, name), fs.readFileSync(name, "utf8"));
}

const main = read(`${scripts}/TertiumFixes.lua`);
const core = read(`${scripts}/core.lua`);
const data = read(`${scripts}/TertiumFixes_data.lua`);
const localisation = read(`${scripts}/TertiumFixes_localization.lua`);
const packageData = JSON.parse(read("package.json"));
const modInfo = JSON.parse(read("info.json"));
const runtimeVersion = core.match(/Runtime\.version\s*=\s*["']([^"']+)["']/)?.[1];
check(runtimeVersion === packageData.version, "runtime and package versions differ");
check(modInfo.version === runtimeVersion && modInfo.author === "chronic", "mod menu version or author differs from the release");

const moduleNames = [...main.matchAll(/"TertiumFixes\/scripts\/mods\/TertiumFixes\/modules\/([^"\n]+)"/g)]
  .map(match => match[1]);
const actualModules = fs.readdirSync(path.join(root, scripts, "modules"))
  .filter(name => name.endsWith(".lua")).map(name => name.slice(0, -4));
check(moduleNames.length > 0 && new Set(moduleNames).size === moduleNames.length, "module registration is empty or duplicated");
check(actualModules.every(name => moduleNames.includes(name)) && moduleNames.every(name => actualModules.includes(name)),
  "registered modules do not match the files in the package");

const defaults = core.match(/Runtime\.defaults\s*=\s*({[\s\S]*?\n})/)?.[1];
check(Boolean(defaults), "runtime defaults are missing");
if (defaults) {
  compile("mod options", `
    function get_mod() return { localize = function(_, key) return key end } end
    local function options() ${data} end
    local function translations() ${localisation} end
    local config, words, defaults = options(), translations(), ${defaults}
    local seen = {}
    local function walk(widgets)
      for _, widget in ipairs(widgets) do
        local key = widget.setting_id
        assert(type(key) == "string" and not seen[key], "duplicate or unnamed option")
        seen[key] = true
        assert(words[key] and type(words[key].en) == "string", "missing option name: " .. key)
        if widget.type ~= "group" then
          assert(widget.default_value ~= nil, "missing default: " .. key)
          if defaults[key] ~= nil then
            assert(widget.default_value == defaults[key], "default differs from runtime: " .. key)
          end
        end
        if widget.options then
          for _, choice in ipairs(widget.options) do
            assert(words[choice.text] and words[choice.text].en, "missing choice text: " .. choice.text)
          end
        end
        if widget.sub_widgets then walk(widget.sub_widgets) end
      end
    end
    walk(config.options.widgets)
    for key in pairs(defaults) do assert(seen[key], "runtime setting has no option: " .. key) end
    assert(defaults.gc_cleaning_permitted == false, "extra garbage collection must be opt-in")
    assert(defaults.chain_smoke_cleanup_enabled == false, "smoke removal must be opt-in")
    assert(defaults.servo_skull_scroll_enabled == false, "wheel isolation must be opt-in")
    assert(defaults.notification_dedupe_enabled == false, "notification suppression must be opt-in")
    for _, key in ipairs({
      "input_retry_enabled", "input_retry_swap_enabled", "input_retry_ability_enabled",
      "input_retry_special_enabled", "input_retry_reload_enabled", "input_retry_blitz_enabled",
    }) do
      assert(defaults[key] == false, key .. " must be opt-in")
    end
  `, true);
}
lua.lua_close(L);

const sourceRoot = process.env.DARKTIDE_SOURCE_ROOT || process.argv[2];
const manifest = JSON.parse(read("tests/source_manifest.json"));
check(Boolean(sourceRoot), "provide the extracted game source through DARKTIDE_SOURCE_ROOT or the first argument");
if (sourceRoot) {
  for (const [name, expected] of Object.entries(manifest.files)) {
    const file = path.join(sourceRoot, name);
    if (!fs.existsSync(file)) {
      check(false, `missing game source: ${name}`);
      continue;
    }
    const hash = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
    check(hash === expected.source, `game source changed: ${name}`);
  }
  const requiredPaths = new Set();
  for (const name of productionFiles) {
    if (!name.endsWith(".lua")) continue;
    for (const match of fs.readFileSync(name, "utf8").matchAll(/["'](scripts\/[\w/.-]+)["']/g)) {
      if (!match[1].startsWith("scripts/mods/") && !match[1].endsWith("/")) {
        requiredPaths.add(match[1].endsWith(".lua") ? match[1] : match[1] + ".lua");
      }
    }
  }
  for (const name of requiredPaths) check(Boolean(manifest.files[name]), `game dependency is not pinned: ${name}`);
}

if (errors.length) {
  for (const error of errors) console.error(`FAIL ${error}`);
  console.error(`${checks - errors.length}/${checks} package and source checks passed`);
  process.exitCode = 1;
} else {
  console.log(`${checks} package and source checks passed for Darktide ${manifest.game_version}`);
  console.log(`${actualModules.length} modules; every production Lua file parsed; no source checks skipped`);
}
