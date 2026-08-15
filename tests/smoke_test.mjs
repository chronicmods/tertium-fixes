import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const modRoot = path.resolve(testDir, "..");
const scriptRoot = path.join(modRoot, "scripts", "mods", "TertiumFixes");
const moduleRoot = path.join(scriptRoot, "modules");

let failures = 0;
let checks = 0;
let skips = 0;

function pass(message) {
  checks += 1;
  process.stdout.write(`PASS ${message}\n`);
}

function fail(message) {
  checks += 1;
  failures += 1;
  process.stderr.write(`FAIL ${message}\n`);
}

function check(condition, message) {
  if (condition) {
    pass(message);
  } else {
    fail(message);
  }
}

function read(relativePath) {
  return fs.readFileSync(path.join(modRoot, relativePath), "utf8");
}

function luaDefault(source, settingId) {
  const escaped = settingId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = source.match(
    new RegExp(`${escaped}\\s*=\\s*(true|false|[-\\d.]+|\"[^\"]*\")`),
  );

  return match?.[1];
}

function widgetDefault(source, settingId) {
  const marker = `setting_id = "${settingId}"`;
  const start = source.indexOf(marker);

  if (start < 0) {
    return undefined;
  }

  const match = source.slice(start, start + 260).match(
    /default_value\s*=\s*(true|false|[-\d.]+|"[^"]*")/,
  );

  return match?.[1];
}

const moduleNames = [
  "cursor_stack",
  "input_device_handoff",
  "rumble_apply",
  "veteran_redirect_tooltip",
  "zealot_prime_target_tooltip",
  "power_overload_hud",
  "chain_smoke_cleanup",
  "servo_skull_scroll",
  "notification_dedupe",
  "localization_guard",
  "gc_pressure",
  "campaign_vox_cleanup",
  "player_buff_removal",
  "penance_carousel_scroll",
  "path_of_trust_black_screen",
  "gas_outline_recovery",
  "player_fx_lifecycle",
  "effect_template_safety",
  "event_listener_cleanup",
  "audio_source_cleanup",
  "fx_handler_integrity",
  "stimm_field_deleted_extension_guard",
  "hive_scum_stimm_chime",
  "training_grounds_danger_index_guard",
];

const behaviorTestNames = [
  "deferred_loader_behavior.lua",
  "effect_template_safety_behavior.lua",
  "engine_cleanup_behavior.lua",
  "fx_handler_integrity_behavior.lua",
  "gc_pressure_behavior.lua",
  "input_and_buff_behavior.lua",
  "hive_scum_stimm_chime_behavior.lua",
  "psykhanium_source_guards_behavior.lua",
  "runtime_hardening_behavior.lua",
  "runtime_performance_behavior.lua",
];

const requiredFiles = [
  "TertiumFixes.mod",
  "README.md",
  "LICENSE",
  "scripts/mods/TertiumFixes/TertiumFixes.lua",
  "scripts/mods/TertiumFixes/TertiumFixes_data.lua",
  "scripts/mods/TertiumFixes/TertiumFixes_localization.lua",
  "scripts/mods/TertiumFixes/core.lua",
  ...behaviorTestNames.map((testName) => `tests/${testName}`),
  ...moduleNames.map(
    (moduleName) => `scripts/mods/TertiumFixes/modules/${moduleName}.lua`,
  ),
];

for (const relativePath of requiredFiles) {
  check(
    fs.existsSync(path.join(modRoot, relativePath)),
    `package contains ${relativePath}`,
  );
}

const discoveredModuleNames = fs
  .readdirSync(moduleRoot)
  .filter((fileName) => fileName.endsWith(".lua"))
  .map((fileName) => fileName.slice(0, -4))
  .sort();
const discoveredBehaviorTests = fs
  .readdirSync(path.join(modRoot, "tests"))
  .filter((fileName) => fileName.endsWith("_behavior.lua"))
  .sort();

check(
  moduleNames.length === 24 &&
    JSON.stringify(discoveredModuleNames) ===
      JSON.stringify([...moduleNames].sort()),
  "package module inventory is exactly all twenty-four production modules",
);
check(
  behaviorTestNames.length === 10 &&
    JSON.stringify(discoveredBehaviorTests) ===
      JSON.stringify([...behaviorTestNames].sort()),
  "package behavior inventory is exactly all ten Lua behavior suites",
);

const entrypoint = read("scripts/mods/TertiumFixes/TertiumFixes.lua");
const settings = read("scripts/mods/TertiumFixes/TertiumFixes_data.lua");
const localization = read(
  "scripts/mods/TertiumFixes/TertiumFixes_localization.lua",
);
const core = read("scripts/mods/TertiumFixes/core.lua");
const readme = read("README.md");
const license = read("LICENSE");
const modules = Object.fromEntries(
  moduleNames.map((moduleName) => [
    moduleName,
    read(`scripts/mods/TertiumFixes/modules/${moduleName}.lua`),
  ]),
);

const englishLocalizationValues = [
  ...localization.matchAll(/\ben\s*=\s*"((?:\\.|[^"\\])*)"/g),
].map((match) => match[1]);
const valuesWithUnsafePercent = englishLocalizationValues.filter((value) => {
  for (let index = 0; index < value.length; index += 1) {
    if (value[index] !== "%") continue;
    if (value[index + 1] === "%") {
      index += 1;
      continue;
    }
    return true;
  }
  return false;
});

check(
  valuesWithUnsafePercent.length === 0,
  "localization text escapes every literal percent sign for runtime formatting",
);

const entrypointModuleNames = [
  ...entrypoint.matchAll(
    /"TertiumFixes\/scripts\/mods\/TertiumFixes\/modules\/([a-z0-9_]+)"/g,
  ),
].map((match) => match[1]);

check(
  entrypointModuleNames.length === 24 &&
    new Set(entrypointModuleNames).size === 24 &&
    JSON.stringify([...entrypointModuleNames].sort()) ===
      JSON.stringify([...moduleNames].sort()),
  "entrypoint loads every production module exactly once and no others",
);

const moduleSettingIds = Object.fromEntries(
  moduleNames.map((moduleName) => [
    moduleName,
    moduleName === "gc_pressure" ? "gc_enabled" : `${moduleName}_enabled`,
  ]),
);

for (const moduleName of moduleNames) {
  const moduleSource = modules[moduleName];
  const settingId = moduleSettingIds[moduleName];

  check(
    entrypoint.includes(`modules/${moduleName}`),
    `entrypoint loads ${moduleName}`,
  );
  check(
    moduleSource.includes(`id = "${moduleName}"`) &&
      moduleSource.includes(`setting_id = "${settingId}"`),
    `${moduleName} declares the exact module and master-setting IDs`,
  );
}

const expectedHooks = [
  [
    "input_device_handoff",
    "scripts/managers/input/input_manager",
    "_update_devices",
    "same-frame input-device handoff hook",
  ],
  [
    "cursor_stack",
    "scripts/managers/input/input_manager",
    "push_cursor",
    "cursor push hook",
  ],
  [
    "cursor_stack",
    "scripts/managers/input/input_manager",
    "pop_cursor",
    "cursor pop hook",
  ],
  [
    "rumble_apply",
    "scripts/managers/input/input_manager",
    "_cb_update_rumble_enabled",
    "rumble-setting callback hook",
  ],
  [
    "rumble_apply",
    "scripts/managers/input/input_manager",
    "start_suppress_wwise_rumble",
    "rumble suppression hook",
  ],
  [
    "rumble_apply",
    "scripts/managers/input/input_manager",
    "stop_suppress_wwise_rumble",
    "rumble unsuppression hook",
  ],
  [
    "chain_smoke_cleanup",
    "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/chain_weapon_effects",
    "_update_active",
    "chain-weapon transition hook",
  ],
  [
    "localization_guard",
    "scripts/managers/localization/localization_manager",
    "localize",
    "localization hook",
  ],
  [
    "localization_guard",
    "scripts/managers/localization/localization_manager",
    "_process_string",
    "raw localization-value hook",
  ],
  [
    "notification_dedupe",
    "scripts/ui/constant_elements/elements/notification_feed/constant_element_notification_feed",
    "event_add_notification_message",
    "notification hook",
  ],
  [
    "campaign_vox_cleanup",
    "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list",
    "on_exit",
    "campaign-list exit hook",
  ],
  [
    "player_buff_removal",
    "scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling",
    "update",
    "player-buff removal repair hook",
  ],
  [
    "campaign_vox_cleanup",
    "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list",
    "destroy",
    "campaign-list destroy hook",
  ],
  [
    "penance_carousel_scroll",
    "scripts/ui/views/penance_overview_view/penance_overview_view",
    "_handle_carousel_scroll",
    "Penances carousel scroll hook",
  ],
  [
    "path_of_trust_black_screen",
    "scripts/managers/cinematic/cinematic_manager",
    "update",
    "Path of Trust completion hook",
  ],
  [
    "path_of_trust_black_screen",
    "scripts/ui/hud/elements/cutscene_fading/hud_element_cutscene_fading",
    "update",
    "cutscene fade-state hook",
  ],
  [
    "player_fx_lifecycle",
    "scripts/extension_systems/fx/player_unit_fx_extension",
    "_create_particles_wrapper",
    "player particle-world hook",
  ],
  [
    "player_fx_lifecycle",
    "scripts/extension_systems/fx/player_unit_fx_extension",
    "destroy",
    "player FX teardown hook",
  ],
  [
    "event_listener_cleanup",
    "scripts/managers/input/input_manager",
    "destroy",
    "input-manager listener teardown hook",
  ],
  [
    "event_listener_cleanup",
    "scripts/managers/game_mode/game_modes/game_mode_survival",
    "destroy",
    "Survival listener teardown hook",
  ],
  [
    "event_listener_cleanup",
    "scripts/utilities/expeditions/expedition_loot_handler",
    "destroy",
    "Expedition listener teardown hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/extension_systems/dialogue/dialogue_extension",
    "extensions_ready",
    "dialogue manual-source ownership hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/extension_systems/dialogue/dialogue_extension",
    "destroy",
    "dialogue manual-source teardown hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects",
    "destroy",
    "relic manual-source teardown hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/settings/fx/effect_templates/renegade_flamer_mutator_throw",
    "stop",
    "renegade flamer manual-source teardown hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/settings/fx/effect_templates/cultist_mutant_charge_foley",
    "stop",
    "mutant foley manual-source teardown hook",
  ],
  [
    "audio_source_cleanup",
    "scripts/settings/fx/effect_templates/chaos_poxwalker_bomber_foley",
    "stop",
    "poxwalker bomber manual-source teardown hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/fx_system",
    "init",
    "local FX-handler discovery hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "has_running_effect_with_global_id",
    "FX generation-query hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "add_template_effect",
    "local FX allocation hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "remove_template_effect",
    "FX removal hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "update",
    "local FX update hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "remove_effects_on_unit",
    "unit FX teardown hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "clear",
    "FX-handler clear hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "start_template_effect_from_rpc",
    "FX RPC-start containment hook",
  ],
  [
    "fx_handler_integrity",
    "scripts/extension_systems/fx/utilities/effect_templates_handler",
    "stop_template_effect_from_rpc",
    "FX RPC-stop containment hook",
  ],
  [
    "stimm_field_deleted_extension_guard",
    "scripts/extension_systems/proximity/side_relation_gameplay_logic/proximity_broker_stimm_field",
    "_make_linger",
    "Stimm Field deleted-extension hook",
  ],
  [
    "hive_scum_stimm_chime",
    "scripts/extension_systems/ability/player_unit_ability_extension",
    "fixed_update",
    "Hive Scum stimm charge-observation hook",
  ],
  [
    "training_grounds_danger_index_guard",
    "scripts/ui/view_elements/view_element_mission_board_difficulty_selector/view_element_mission_board_difficulty_selector",
    "initialize_data",
    "Psykhanium danger-index hook",
  ],
];

for (const [moduleName, classPath, methodName, label] of expectedHooks) {
  const source = modules[moduleName];

  check(
    source.includes(`"${classPath}"`) && source.includes(`"${methodName}"`),
    `${label} targets the pinned class and method`,
  );
}

const eventCleanup = modules.event_listener_cleanup;
for (const eventName of [
  "event_update_haptic_trigger_melee_resistance_strength",
  "event_update_haptic_trigger_ranged_resistance_strength",
  "event_update_haptic_trigger_melee_vibration_strength",
  "event_update_haptic_trigger_ranged_vibration_strength",
  "hordes_mode_on_mcguffin_picked_up",
  "event_hogtied_player_rescued",
]) {
  check(
    eventCleanup.includes(`"${eventName}"`),
    `listener cleanup owns exact omitted event ${eventName}`,
  );
}
check(
  eventCleanup.includes('local managers = rawget(_G, "Managers")') &&
    eventCleanup.includes("event_manager.unregister") &&
    eventCleanup.includes(
      "unregister(event_manager, owner, event_names[i])",
    ),
  "listener cleanup resolves the live event manager and unregisters exact owner/event pairs",
);
check(
  eventCleanup.includes('rawget(_G, "IS_PLAYSTATION") == true') &&
    eventCleanup.includes('rawget(loot_handler, "_is_server") == true') &&
    (eventCleanup.match(/"safe"/g) ?? []).length === 3,
  "listener cleanup preserves PlayStation/server scope and runs after all three stock destroy paths",
);

const audioCleanup = modules.audio_source_cleanup;
for (const [pathName, fieldName] of [
  ["scripts/extension_systems/dialogue/dialogue_extension", "_wwise_source_id"],
  [
    "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects",
    "_source_id",
  ],
  ["scripts/settings/fx/effect_templates/renegade_flamer_mutator_throw", "source_id"],
  ["scripts/settings/fx/effect_templates/cultist_mutant_charge_foley", "source_id"],
  ["scripts/settings/fx/effect_templates/chaos_poxwalker_bomber_foley", "source_id"],
]) {
  check(
    audioCleanup.includes(`path = "${pathName}"`) &&
      audioCleanup.includes(`field = "${fieldName}"`),
    `audio cleanup pins ${pathName} to owned handle ${fieldName}`,
  );
}
check(
  audioCleanup.includes('setmetatable({}, { __mode = "k" })') &&
    audioCleanup.includes("before_source == nil") &&
    audioCleanup.includes("created_source ~= nil") &&
    audioCleanup.includes("self._dialogue_manual_sources[owner] = created_source"),
  "audio cleanup weakly tracks only dialogue sources created by extensions_ready",
);
const audioDestroyBody = audioCleanup.slice(
  audioCleanup.indexOf("function module:_destroy_source"),
  audioCleanup.indexOf("function module:_after_stop"),
);
check(
  audioDestroyBody.includes("pcall(has_source, wwise_world, source_id)") &&
    audioDestroyBody.includes(
      "pcall(destroy_source, wwise_world, source_id)",
    ) &&
    audioDestroyBody.indexOf("pcall(has_source") <
      audioDestroyBody.indexOf("self:_clear_source_for_spec") &&
    audioDestroyBody.indexOf("pcall(destroy_source") <
      audioDestroyBody.lastIndexOf("self:_clear_source_for_spec"),
  "audio cleanup queries and destroys safely before clearing owned handles",
);
check(
  audioCleanup.includes('spec.method,\n\t\t"safe"') &&
    audioCleanup.includes('"extensions_ready",\n\t\t"normal"'),
  "audio cleanup observes stock source creation normally and tears sources down only after stop/destroy",
);

const fxIntegrity = modules.fx_handler_integrity;
check(
  fxIntegrity.includes("template_effect.is_running == true") &&
    fxIntegrity.includes("template_effect.template ~= nil") &&
    fxIntegrity.includes(
      "template_effect.global_effect_id == global_effect_id",
    ),
  "FX integrity validates the complete running-slot generation identity",
);
check(
  fxIntegrity.includes("rawget(handler, LOCAL_HANDLER_MARKER) == true") &&
    fxIntegrity.includes(
      "runtime:get(self.local_rewrite_setting_id) == true",
    ) &&
    fxIntegrity.includes(
      "runtime:get(self.rpc_containment_setting_id) == true",
    ),
  "FX allocator and RPC containment stay behind separate exact opt-in gates",
);
check(
  fxIntegrity.includes("value == math.floor(value)") &&
    fxIntegrity.includes("value >= 0") &&
    fxIntegrity.includes("buffer_index > max_num_template_effects") &&
    fxIntegrity.includes("template_effect.global_effect_id = nil"),
  "FX integrity rejects malformed IDs and buffer indices and clears stopped generations",
);
check(
  !fxIntegrity.includes("send_rpc") &&
    !fxIntegrity.includes("Managers.state.game_session") &&
    fxIntegrity.includes("_tertium_local_only"),
  "local FX rewrite contains no network-send path and is limited to marked handlers",
);
check(
  fxIntegrity.includes('FX_SYSTEM_PATH,\n\t\t"init",\n\t\t"safe"') &&
    fxIntegrity.includes('"clear",\n\t\t"safe"') &&
    fxIntegrity.includes(
      '"has_running_effect_with_global_id",\n\t\t"normal"',
    ),
  "FX integrity installs post-init/post-clear observation and normal generation-aware wrappers",
);

const stimmGuard = modules.stimm_field_deleted_extension_guard;
check(
  stimmGuard.includes(
    'type(value) == "table" and rawget(value, "__deleted") == true',
  ) &&
    stimmGuard.includes('rawget(_G, "DEDICATED_SERVER") == true'),
  "Stimm Field guard is client-only and matches only the exact deleted-extension tombstone",
);
check(
  stimmGuard.includes('"_make_linger",\n\t\t"normal"') &&
    stimmGuard.includes("rawset(units, unit, nil)") &&
    stimmGuard.includes("rawset(lingering, unit, nil)") &&
    stimmGuard.lastIndexOf("return func(broker, unit, t, linger_time)") <
      stimmGuard.indexOf("runtime:record_hit(self.id)"),
  "Stimm Field guard fails open except for the deleted row, which it removes without invoking stock linger",
);
check(
  !stimmGuard.includes("runtime:defer_file") &&
    !stimmGuard.includes("require(") &&
    !stimmGuard.includes("ScriptUnit"),
  "Stimm Field guard does not eagerly load game code or probe a destroyed ScriptUnit extension",
);

const hiveChime = modules.hive_scum_stimm_chime;
check(
  hiveChime.includes('local ABILITY_TYPE = "pocketable_ability"') &&
    hiveChime.includes('local ABILITY_NAME = "broker_ability_syringe"') &&
    !hiveChime.includes("broker_ability_stimm_field"),
  "Hive Scum chime matches only the personal pocketable syringe",
);
check(
  hiveChime.includes(
    'local READY_SOUND = "wwise/events/ui/play_hud_ability_off_cooldown"',
  ) &&
    hiveChime.includes('rawget(_G, "Managers")') &&
    hiveChime.includes("ui:play_2d_sound(READY_SOUND)"),
  "Hive Scum chime uses Darktide's stock local ability-ready cue",
);
check(
  hiveChime.includes('setmetatable({}, { __mode = "k" })') &&
    hiveChime.includes("if previous_charges == nil then") &&
    hiveChime.includes("if previous_charges > 0 or charges <= 0 then"),
  "Hive Scum chime seeds silently and detects only unavailable-to-available charge transitions",
);
check(
  hiveChime.includes('"fixed_update",\n\t\t"safe"') &&
    hiveChime.includes("charge_state[extension] = charges") &&
    hiveChime.indexOf("charge_state[extension] = charges", hiveChime.indexOf("previous_charges")) <
      hiveChime.indexOf("ui:play_2d_sound(READY_SOUND)"),
  "Hive Scum chime observes post-update charges and commits state before audio",
);
check(
  !hiveChime.includes("require(") &&
    !hiveChime.includes("remaining_ability_cooldown") &&
    !hiveChime.includes("charge_replenished") &&
    hiveChime.includes('rawget(_G, "DEDICATED_SERVER") == true'),
  "Hive Scum chime avoids eager loading and unreliable cooldown/event proxies",
);
for (const lifecycleMethod of [
  "on_game_state_changed",
  "on_setting_changed",
  "on_enabled",
  "on_disabled",
  "on_unload",
  "reset",
]) {
  check(
    hiveChime.includes(`function module:${lifecycleMethod}`) &&
      hiveChime.slice(hiveChime.indexOf(`function module:${lifecycleMethod}`)).includes(
        "self:_clear_state()",
      ),
    `Hive Scum chime clears observations during ${lifecycleMethod}`,
  );
}

const dangerGuard = modules.training_grounds_danger_index_guard;
check(
  dangerGuard.includes(
    'local TRAINING_GROUNDS_CLASS = "TrainingGroundsOptionsView"',
  ) &&
    dangerGuard.includes('local SHOOTING_RANGE = "shooting_range"') &&
    dangerGuard.includes("local DEFAULT_DANGER = 3"),
  "Psykhanium guard pins the exact view, mode, and stock fallback danger",
);
check(
  dangerGuard.includes('rawget(value, "__deleted") == true') &&
    dangerGuard.includes("number ~= number") &&
    dangerGuard.includes("number == math.huge") &&
    dangerGuard.includes("number == -math.huge") &&
    dangerGuard.includes("math.floor(number)") &&
    dangerGuard.includes("math.max(1, math.min(count, index))"),
  "Psykhanium guard rejects deleted parents and non-finite values before flooring and clamping",
);
check(
  dangerGuard.includes("runtime:defer_file") &&
    dangerGuard.includes('"initialize_data",\n\t\t"normal"') &&
    dangerGuard.includes("_raw_class_name(parent) == TRAINING_GROUNDS_CLASS") &&
    dangerGuard.includes(
      'rawget(parent, "training_grounds_settings") == SHOOTING_RANGE',
    ) &&
    dangerGuard.includes("if normalized ~= optional_difficulty_index then"),
  "Psykhanium normalization is deferred, shooting-range scoped, and records only changed values",
);
check(
  dangerGuard.includes('rawget(settings, DEFAULT_DANGER) ~= nil') &&
    dangerGuard.includes("return _first_existing_index(settings, count)") &&
    !dangerGuard.includes("require("),
  "Psykhanium guard falls back to an existing danger entry without eager source loading",
);

const cursor = modules.cursor_stack;
check(
  cursor.includes('"safe"') &&
    cursor.includes("stack_references") &&
    cursor.includes("actual_depth"),
  "cursor repair uses post-call safe hooks and recounts references",
);
check(
  cursor.includes("_update_clip_cursor") && !/\bWindow\s*\./.test(cursor),
  "cursor repair delegates clipping and does not call Window directly",
);
check(
  cursor.includes('rawget(_G, "IS_WINDOWS")') &&
    cursor.includes('rawget(_G, "IS_XBS")') &&
    /if is_windows then[\s\S]*elseif is_xbs then/.test(cursor),
  "cursor repair updates only the platform-appropriate visibility flag",
);

const inputHandoff = modules.input_device_handoff;
check(
  inputHandoff.includes('selection.logic ~= latest_logic') &&
    inputHandoff.includes("InputDevice.last_pressed_device") &&
    inputHandoff.includes("device == latest_device"),
  "input handoff reconciles only latest-device selection when the new device is absent",
);
check(
  inputHandoff.includes('"safe"') &&
    inputHandoff.includes("runtime:run(self.id, update_selection, input_manager)"),
  "input handoff performs the stock selection callback through the guarded runtime",
);
check(
  inputHandoff.includes("return device_count == highest_index, update_selection") &&
    inputHandoff.includes('type(index) ~= "number"'),
  "input handoff fails open on sparse or malformed device lists",
);

const rumble = modules.rumble_apply;
check(
  rumble.includes('rawget(_G, "DEDICATED_SERVER")') &&
    rumble.includes("_update_wwise_rumble"),
  "rumble repair is client-only and delegates state application to the game",
);
check(
  rumble.includes('type(explicit_value) == "boolean"') &&
    rumble.includes("_user_rumble_state = explicit_value"),
  "rumble repair accepts an explicit callback value without coercion",
);

const veteran = modules.veteran_redirect_tooltip;
for (const exactName of [
  "veteran_improved_tag_allied_buff",
  "veteran_improved_tag_allied_buff_increased_stacks",
  "veteran_improved_tag_dead_bonus",
  "veteran_improved_tag_dead_coherency_bonus",
]) {
  check(veteran.includes(`"${exactName}"`), `Redirect Fire patch pins ${exactName}`);
}
check(
  veteran.includes("#related ~= 1") &&
    veteran.includes("template.related_talents == patch.replacement"),
  "Redirect Fire patch validates exact metadata and restores identity-safely",
);

const zealotPrimeTarget = modules.zealot_prime_target_tooltip;
for (const exactName of [
  "zealot_elite_kills_empowers",
  "zealot_elite_kills_empowers_effect",
]) {
  check(
    zealotPrimeTarget.includes(`"${exactName}"`),
    `Prime Target patch pins ${exactName}`,
  );
}
check(
  zealotPrimeTarget.includes("template.related_talents ~= nil") &&
    zealotPrimeTarget.includes("template.class_name ~= \"buff\"") &&
    zealotPrimeTarget.includes(
      "self._template.related_talents == self._replacement",
    ),
  "Prime Target patch validates exact metadata and restores identity-safely",
);
check(
  zealotPrimeTarget.includes("talent.passive.buff_template_name ~= PARENT_KEY") &&
    zealotPrimeTarget.includes("TALENT_KEY"),
  "Prime Target patch validates the effect against its actual talent",
);

const power = modules.power_overload_hud;
for (const exactName of [
  "cryptic_overload_keystone_allies_buff",
  "cryptic_overload_keystone_stack",
  "cryptic_overload_keystone",
]) {
  check(power.includes(`"${exactName}"`), `Power Overload patch pins ${exactName}`);
}
check(
  power.includes("target.duration ~= 8") &&
    power.includes("target.predicted ~= false") &&
    power.includes("target.refresh_duration_on_stack ~= true"),
  "Power Overload patch validates the exact 8-second ally-buff shape",
);
check(
  power.includes('"always_show_in_hud"') &&
    power.includes('"hud_icon_gradient_map"') &&
    power.includes('"related_talents"'),
  "Power Overload patch is limited to presentation metadata",
);
check(
  power.includes("patch.target[field] == patch.applied[field]"),
  "Power Overload patch restores only values it still owns",
);

const chain = modules.chain_smoke_cleanup;
const chainHookStart = chain.indexOf("function (func, effects, ...)");
const chainHookBody = chain.slice(chainHookStart);
const originalTransitionIndex = chainHookBody.indexOf("func(effects, ...)");
const destroyCallIndex = chainHookBody.indexOf("_destroy_released_effect,");
check(
  originalTransitionIndex >= 0 &&
    destroyCallIndex > originalTransitionIndex,
  "chain cleanup runs the original transition and power-down sound first",
);
check(
  chain.includes("special_active ~= false") &&
    chain.includes("effects:_looping_effect_id() ~= nil") &&
    chain.includes("World.are_particles_playing") &&
    chain.includes("World.destroy_particles"),
  "chain cleanup hard-stops only the just-released active-loop handle",
);
check(
  !chain.includes("_pending") &&
    !chain.includes("cleanup_delay") &&
    chain.includes("normal particle tail"),
  "chain cleanup retains no recyclable particle IDs and declares its tail trade-off",
);

const servo = modules.servo_skull_scroll;
check(
  servo.includes(
    '"scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point"',
  ) &&
    servo.includes(
      '"scripts/settings/player_character/player_character_constants"',
    ),
  "Servo-Skull patch pins the exact template and constants table",
);
check(
  servo.includes('"wield_scroll_up"') &&
    servo.includes('"wield_scroll_down"') &&
    servo.includes("removed ~= 2"),
  "Servo-Skull patch removes exactly the two wheel inputs",
);
check(
  servo.includes("inputs ~= constants.wield_inputs") &&
    servo.includes("first_step.inputs = replacement") &&
    !servo.includes("constants.wield_inputs ="),
  "Servo-Skull patch clones privately and never mutates shared wield inputs",
);
check(
  servo.includes("current == self._replacement_inputs") &&
    servo.includes("first_step.inputs = self._original_inputs"),
  "Servo-Skull patch restores only its own replacement",
);

const notifications = modules.notification_dedupe;
check(
  notifications.includes("callback ~= nil") &&
    notifications.includes("done_callback ~= nil") &&
    notifications.includes("delay ~= nil"),
  "notification dedupe excludes calls with side effects or timing",
);
check(
  notifications.includes("<= 384") &&
    !/table\.clear\s*\(\s*notification/i.test(notifications) &&
    !/_notifications\s*=\s*\{\s*\}/.test(notifications),
  "notification cache is bounded and never clears the feed",
);
check(
  notifications.includes('return allow_nil and "z;" or nil') &&
    notifications.includes("tostring(#encoded)") &&
    notifications.includes('value_type == "string" and "s"'),
  "notification scalars are nil-distinct, typed, and length-prefixed",
);
check(
  notifications.includes("if not ok then") &&
    notifications.includes(
      "return func(notification_feed, message_type, data, callback, sound_event, done_callback, delay)",
    ),
  "notification guard fails open to the original game call",
);

function scalar(value, allowNil) {
  if (value === undefined) {
    return allowNil ? "z;" : undefined;
  }

  const valueType = typeof value;

  if (!["string", "number", "boolean"].includes(valueType)) {
    return undefined;
  }

  const encoded = String(value);
  const tag = valueType === "string" ? "s" : valueType === "number" ? "n" : "b";

  return `${tag}${encoded.length}:${encoded}`;
}

function fingerprint(messageType, data, soundEvent) {
  const messageTypePart = scalar(messageType, false);
  const soundPart = scalar(soundEvent, true);
  let dataPart;

  if (!messageTypePart || !soundPart) {
    return undefined;
  }

  if (messageType === "default" || messageType === "mission") {
    dataPart = scalar(data, false);
  } else if (
    messageType === "alert" &&
    data !== null &&
    typeof data === "object"
  ) {
    const textPart = scalar(data.text, false);
    const alertTypePart = scalar(data.type, true);

    if (textPart && alertTypePart) {
      dataPart = textPart + alertTypePart;
    }
  }

  return dataPart ? messageTypePart + dataPart + soundPart : undefined;
}

const notificationCollisionPairs = [
  [
    fingerprint("default", "true", undefined),
    fingerprint("default", true, undefined),
  ],
  [
    fingerprint("default", "1", undefined),
    fingerprint("default", 1, undefined),
  ],
  [
    fingerprint("default", "ab", "c"),
    fingerprint("default", "a", "bc"),
  ],
  [
    fingerprint("alert", { text: "x", type: undefined }, undefined),
    fingerprint("alert", { text: "x", type: "z;" }, undefined),
  ],
];

check(
  notificationCollisionPairs.every(([left, right]) => left !== right),
  "notification fingerprint mirror rejects type, nil, and field-boundary collisions",
);
check(
  fingerprint("default", { complex: true }, undefined) === undefined,
  "notification fingerprint mirror fails open for complex values",
);

const localizationGuard = modules.localization_guard;
check(
  localizationGuard.includes('type(key) ~= "string"') &&
    localizationGuard.includes('key == ""') &&
    localizationGuard.includes(
      "return func(localization_manager, key, no_cache, context)",
    ),
  "localization guard limits interception to invalid keys",
);
check(
  localizationGuard.includes('type(raw_str) ~= "string"') &&
    localizationGuard.includes("_invalid_value_fallback") &&
    localizationGuard.includes(
      "return func(localization_manager, key, raw_str, context)",
    ),
  "localization guard safely rejects non-string raw values only",
);
check(
  localizationGuard.includes("string_cache[key] == invalid_fallback") &&
    localizationGuard.includes("string_cache[key] = nil") &&
    localizationGuard.includes(
      "_mark_invalid_fallback(localization_manager, key, fallback)",
    ),
  "localization guard does not retain temporary fallbacks in the game string cache",
);
check(
  localizationGuard.includes("localize_states = setmetatable") &&
    localizationGuard.includes('__mode = "k"') &&
    localizationGuard.includes("state.keys[depth]") &&
    localizationGuard.includes("state.fallbacks[depth]") &&
    !localizationGuard.includes("local frame = {"),
  "localization guard reuses weak per-manager state instead of allocating per valid call",
);

const gc = modules.gc_pressure;
check(
  gc.includes('"count"') &&
    gc.includes('"step"') &&
    gc.includes('"collect"') &&
    gc.includes('"setpause"') &&
    gc.includes('"setstepmul"'),
  "GC controller exposes monitoring, incremental, full-clean, and tuning operations",
);
check(
  gc.includes("local PRESSURE_PERCENT = 80") &&
    gc.includes("local PRESSURE_DWELL_SECONDS = 5") &&
    gc.includes("local WARNING_PERCENT = 85") &&
    gc.includes("local CRITICAL_PERCENT = 90") &&
    gc.includes("local EMERGENCY_PERCENT = 95"),
  "GC controller declares the 80/85/90/95 pressure state machine",
);
check(
  gc.includes('"^%-+lua%-heap%-mb%-size=(%d+)$"') &&
    gc.includes('argument == "--lua-heap-mb-size"') &&
    gc.includes('self._capacity_source = "command line"') &&
    gc.includes('self._capacity_source = "fallback setting"'),
  "GC controller detects inline/split heap capacity argv with a fallback",
);
check(
  gc.indexOf('key = "cleanup_owner_primary"') <
      gc.indexOf('key = "cleanup_owner_legacy"') &&
    gc.includes("self._active_controllers[group.key] = true") &&
    gc.includes("self._conflict_id = self._conflict_id or group.key") &&
    gc.includes('return "cleanup-standby"') &&
    gc.includes("Lua heap cleanup is on standby"),
  "cleanup ownership has deterministic precedence and generic status reporting",
);
check(
  gc.includes("update_interval = 0.05") &&
    gc.includes("self._conflict_timer >= 1"),
  "GC controller runs at 20 Hz and rechecks external ownership every second",
);
const gcUpdateBody = gc.slice(
  gc.indexOf("function module:update(dt)"),
  gc.indexOf("function module:on_all_mods_loaded()"),
);
check(
  gcUpdateBody.indexOf("if self._conflict then") >= 0 &&
    gcUpdateBody.indexOf("if self._conflict then") <
      gcUpdateBody.indexOf("self._sample_timer = self._sample_timer + dt"),
  "GC fallback returns before heap sampling while an external controller owns collection",
);

const gcSampleBody = gc.slice(
  gc.indexOf("function module:_sample_heap()"),
  gc.indexOf("function module:_update_post_clean_warning(dt)"),
);
check(
  gcSampleBody.indexOf("self:_scan_conflicts()") >= 0 &&
    gcSampleBody.indexOf("self:_scan_conflicts()") <
      gcSampleBody.indexOf('"count"'),
  "GC monitoring rescans exact controller IDs immediately before heap count",
);

const incrementalBody = gc.slice(
  gc.indexOf("function module:_run_incremental_budget()"),
  gc.indexOf("function module:_notify(message, important)"),
);
check(
  incrementalBody.indexOf("self:_guard_mutation()") >= 0 &&
    incrementalBody.indexOf("self:_guard_mutation()") <
      incrementalBody.indexOf('"step"') &&
    gc.includes("local STEP_EFFORT_KB = 32") &&
    gc.includes("local MAX_STEPS_PER_UPDATE = 16") &&
    gc.includes("local STEP_BUDGET_MS = 1"),
  "GC incremental work is ownership-guarded and bounded by effort, count, and time",
);

const fullCollectBody = gc.slice(
  gc.indexOf("function module:_full_collect(reason, source, silent)"),
  gc.indexOf("function module:_queue_collect(reason, delay, source)"),
);
check(
  fullCollectBody.indexOf("self:_guard_mutation()") >= 0 &&
    fullCollectBody.indexOf("self:_guard_mutation()") <
      fullCollectBody.indexOf('"collect"') &&
    fullCollectBody.indexOf('"count"') <
      fullCollectBody.indexOf('"collect"'),
  "GC full collections are ownership-guarded and measure before cleanup",
);
check(
  gc.includes("Multiple Lua cleanup controllers are active") &&
    gc.includes("Enable only one automatic cleanup controller") &&
    !/candidate\s*:\s*set|candidate\s*\.\s*set/.test(gc),
  "cleanup-controller overlap warns once and never changes another controller",
);

const expectedControllerIds = [
  String.fromCharCode(83, 77, 79, 71),
  String.fromCharCode(77, 101, 109, 76, 101, 97, 107, 70, 105, 120),
  String.fromCharCode(70, 112, 115, 68, 111, 99, 116, 111, 114),
];

const detectedControllerIds = [
  ...gc.matchAll(/_name_from_bytes\(\{\s*([\d,\s]+)\}\)/g),
].map((match) => String.fromCharCode(
  ...[...match[1].matchAll(/\d+/g)].map((numberMatch) => Number(numberMatch[0])),
));

for (const [index, expectedControllerId] of expectedControllerIds.entries()) {
  check(
    detectedControllerIds.includes(expectedControllerId),
    `GC conflict detection includes exact private controller fixture ${index + 1}`,
  );
}

check(
  JSON.stringify(detectedControllerIds.sort()) ===
    JSON.stringify([...expectedControllerIds].sort()),
  "GC conflict detection contains only the verified exact mod IDs",
);

const campaignVox = modules.campaign_vox_cleanup;
check(
  campaignVox.includes('rawget(content, "hover_sound_id")') &&
    campaignVox.includes("content.hover_sound_id = nil") &&
    campaignVox.includes("content.hover_sound_played = nil"),
  "campaign audio cleanup clears both exact debrief-hover state fields",
);
check(
  campaignVox.includes('rawget(cell_data, "debrief_widget")') &&
    campaignVox.includes("stop_sound(ui_manager, sound_id)"),
  "campaign audio cleanup stops only stored debrief-widget sound handles",
);
check(
  campaignVox.includes('"on_exit"') &&
    campaignVox.includes('"destroy"') &&
    campaignVox.includes("return func(campaign_list, ...)"),
  "campaign audio cleanup covers both lifecycle paths and preserves originals",
);

const playerBuffRemoval = modules.player_buff_removal;
check(
  playerBuffRemoval.includes("for i = #active_buffs_data, 1, -1 do") &&
    playerBuffRemoval.includes('rawget(buff_data, "remove") == true') &&
    playerBuffRemoval.includes("table.remove(active_buffs_data, i)"),
  "player-buff repair removes only exact stale markers in a reverse pass",
);
check(
  playerBuffRemoval.includes('"safe"') &&
    playerBuffRemoval.includes("runtime:run(self.id, _remove_skipped_buffs, hud)"),
  "player-buff repair is post-call, guarded, and fail-open",
);

const penanceCarousel = modules.penance_carousel_scroll;
check(
  penanceCarousel.includes('action_name ~= "scroll_axis"') &&
    penanceCarousel.includes("-y"),
  "Penances carousel correction reverses only the mouse scroll axis",
);
check(
  penanceCarousel.includes('rawget(view, "_using_cursor_navigation") ~= true') &&
    penanceCarousel.includes("return func(view, input_service, dt, ...)"),
  "Penances carousel correction leaves non-mouse paths and failure cases original",
);
check(
  penanceCarousel.includes("original_null_service(input_service, ...)"),
  "Penances carousel correction preserves the view's null-input behavior",
);

const pathOfTrust = modules.path_of_trust_black_screen;
check(
  pathOfTrust.includes('"path_of_trust_09"') &&
    pathOfTrust.includes('rawget(cinematic_manager, "_active_story")') &&
    pathOfTrust.includes('rawget(queue, 1) == nil'),
  "Path of Trust repair arms only after the exact final cinematic and an empty queue",
);
check(
  pathOfTrust.includes('rawget(hud, "_fading_in") ~= true') &&
    pathOfTrust.includes('rawget(hud, "_fade_duration") ~= nil') &&
    pathOfTrust.includes('rawget(hud, "_fade_out_data") ~= nil'),
  "Path of Trust repair requires the exact stranded fully-black HUD state",
);
check(
  pathOfTrust.includes("REPAIR_FADE_SECONDS") &&
    pathOfTrust.includes("fade_out(") &&
    pathOfTrust.includes("COMPLETION_WINDOW_SECONDS"),
  "Path of Trust repair uses the HUD's own fade-out path inside a bounded window",
);

const gasOutline = modules.gas_outline_recovery;
for (const templateName of [
  "in_toxic_gas",
  "in_cultist_grenadier_gas",
  "in_twin_toxic_gas",
  "in_buildup_twin_toxic_gas",
]) {
  check(
    gasOutline.includes(`"${templateName}"`),
    `toxic-gas outline repair covers ${templateName}`,
  );
}
check(
  gasOutline.includes('rawget(_G, "HEALTH_ALIVE")') &&
    gasOutline.includes("not health_alive[unit]") &&
    gasOutline.includes("template_context.is_local_unit ~= true") &&
    gasOutline.includes("template_context.is_player ~= true"),
  "toxic-gas outline repair is limited to the dead local player",
);
check(
  gasOutline.includes('system("outline_system")') &&
    gasOutline.includes("set_global_visibility(true)") &&
    gasOutline.includes("local a, b, c, d = original("),
  "toxic-gas outline repair preserves original cleanup and restores global visibility",
);
check(
  gasOutline.includes("record.template.stop_func == record.wrapper") &&
    gasOutline.includes("record.template.stop_func = record.original"),
  "toxic-gas outline patch restores identity-safely",
);

const playerFx = modules.player_fx_lifecycle;
check(
  playerFx.includes('rawget(fx_extension, "_world")') &&
    playerFx.includes('"_create_particles_wrapper"') &&
    playerFx.includes("return func(fx_extension, world, ...)"),
  "player FX repair substitutes the extension world only when the call receives nil",
);
check(
  playerFx.includes('rawget(fx_extension, "_moving_sfx")') &&
    playerFx.includes("moving_sfx.buffer[i]") &&
    playerFx.includes("destroy_manual_source") &&
    playerFx.includes("moving_sfx.size = pending and size or 0"),
  "player FX teardown drains the actual moving-SFX ring buffer while retaining failed handles for retry",
);
check(
  playerFx.includes('rawget(fx_extension, "_moving_vfx")') &&
    playerFx.includes("moving_vfx.buffer[i]") &&
    playerFx.includes("destroy_particles") &&
    playerFx.includes("moving_vfx.size = pending and size or 0"),
  "player FX teardown drains the omitted moving-VFX ring buffer while retaining failed handles for retry",
);
check(
  playerFx.includes("self:_cleanup_before_destroy(fx_extension)") &&
    playerFx.includes("return func(fx_extension, ...)"),
  "player FX teardown drains invalid stock buffers before preserving the original destroy path",
);

const effectSafety = modules.effect_template_safety;
for (const templateName of [
  "companion_servo_skull_moving_effect",
  "companion_servo_skull_aim_on_ground_effect",
  "companion_servo_skull_flamer",
  "companion_servo_skull_empowered_effect",
  "companion_servo_skull_charged_shooting",
  "arc_chain_to_position",
]) {
  check(
    effectSafety.includes(`name = "${templateName}"`),
    `partial-effect guard covers ${templateName}`,
  );
}
check(
  effectSafety.includes("local PATCH_COUNT = 17") &&
    effectSafety.includes('template.name ~= spec.name') &&
    effectSafety.includes('type(template.resources) ~= "table"') &&
    effectSafety.includes('type(template.stop) ~= "function"'),
  "partial-effect guards require all seventeen exact 1.12.3 patch points",
);
check(
  effectSafety.includes('rawget(_G, "DEDICATED_SERVER") == true') &&
    effectSafety.includes("rawget(_G, lookup_name)") &&
    effectSafety.includes('_known_dead("ALIVE"') &&
    effectSafety.includes('_known_dead("HEALTH_ALIVE"'),
  "partial-effect guards are client-only and use the game liveness maps",
);
check(
  effectSafety.includes("record.template[record.field] == record.wrapper") &&
    effectSafety.includes("record.template[record.field] = record.original") &&
    effectSafety.includes("function module:on_unload()") &&
    effectSafety.includes("self:_restore()") &&
    effectSafety.includes('__mode = "k"'),
  "partial-effect patch restores on unload and weakly tracks one suppression per instance",
);
for (const handleName of [
  "playing_id",
  "_targeting_effect_id",
  "stream_effect_id",
  "source_id",
  "link_particle_id",
]) {
  check(
    effectSafety.includes(`"${handleName}"`),
    `partial-effect cleanup owns and clears ${handleName}`,
  );
}
check(
  effectSafety.includes("t >= effect_lifetime_end_t") &&
    effectSafety.includes("update_suppression_result = true"),
  "arc-chain client expiry is terminal and returns the handler-compatible signal",
);
check(
  effectSafety.includes("state.cleanup_attempted = true") &&
    effectSafety.includes("state.cleaned = true"),
  "partial-effect cleanup records idempotent lifecycle tombstones",
);

const moduleSettingDefaults = {
  cursor_stack_enabled: "true",
  input_device_handoff_enabled: "true",
  rumble_apply_enabled: "true",
  veteran_redirect_tooltip_enabled: "true",
  zealot_prime_target_tooltip_enabled: "true",
  power_overload_hud_enabled: "true",
  chain_smoke_cleanup_enabled: "false",
  servo_skull_scroll_enabled: "false",
  notification_dedupe_enabled: "true",
  localization_guard_enabled: "true",
  gc_enabled: "true",
  campaign_vox_cleanup_enabled: "true",
  player_buff_removal_enabled: "true",
  penance_carousel_scroll_enabled: "true",
  path_of_trust_black_screen_enabled: "true",
  gas_outline_recovery_enabled: "true",
  player_fx_lifecycle_enabled: "true",
  effect_template_safety_enabled: "true",
  event_listener_cleanup_enabled: "true",
  audio_source_cleanup_enabled: "true",
  fx_handler_integrity_enabled: "true",
  stimm_field_deleted_extension_guard_enabled: "true",
  hive_scum_stimm_chime_enabled: "true",
  training_grounds_danger_index_guard_enabled: "true",
};

const fxSubfeatureDefaults = {
  fx_handler_local_rewrite_enabled: "false",
  fx_handler_rpc_idempotence_enabled: "false",
};

check(
  moduleNames.length === 24 &&
    Object.keys(moduleSettingDefaults).length === 24 &&
    JSON.stringify(Object.keys(moduleSettingDefaults).sort()) ===
      JSON.stringify(Object.values(moduleSettingIds).sort()),
  "core, settings, and module inventory share all twenty-four master-setting IDs",
);

for (const [settingId, expectedDefault] of Object.entries(
  moduleSettingDefaults,
)) {
  check(
    luaDefault(core, settingId) === expectedDefault,
    `${settingId} core default is ${expectedDefault}`,
  );
  check(
    widgetDefault(settings, settingId) === expectedDefault,
    `${settingId} widget default is ${expectedDefault}`,
  );
}

for (const [settingId, expectedDefault] of Object.entries(
  fxSubfeatureDefaults,
)) {
  check(
    luaDefault(core, settingId) === expectedDefault,
    `${settingId} core default is ${expectedDefault}`,
  );
  check(
    widgetDefault(settings, settingId) === expectedDefault,
    `${settingId} widget default is ${expectedDefault}`,
  );
}

const disabledMasterSettingIds = Object.entries(moduleSettingDefaults)
  .filter(([, value]) => value === "false")
  .map(([settingId]) => settingId)
  .sort();

check(
  Object.values(moduleSettingDefaults).filter((value) => value === "true")
    .length === 22 &&
    Object.values(moduleSettingDefaults).filter((value) => value === "false")
      .length === 2 &&
    JSON.stringify(disabledMasterSettingIds) ===
      JSON.stringify([
        "chain_smoke_cleanup_enabled",
        "servo_skull_scroll_enabled",
      ]),
  "release defaults contain exactly twenty-two enabled modules and the two named opt-in prototypes",
);
check(
  luaDefault(core, "auto_quarantine_enabled") === "true" &&
    widgetDefault(settings, "auto_quarantine_enabled") === "true",
  "automatic module quarantine remains enabled in core and settings",
);

const settingIds = [
  ...Object.keys(moduleSettingDefaults),
  ...Object.keys(fxSubfeatureDefaults),
  "notification_dedupe_window_seconds",
  "notification_include_mission",
  "localization_fallback_mode",
  "gc_cleaning_permitted",
  "gc_capacity_fallback_mb",
  "gc_convenient_cleanup_enabled",
  "gc_periodic_cleanup_enabled",
  "gc_notifications_enabled",
  "gc_hud_enabled",
  "gc_hud_x_percent",
  "gc_hud_y_percent",
  "gc_shutdown_diagnostic_enabled",
  "gc_manual_clean_key",
  "gc_hud_toggle_key",
  "auto_quarantine_enabled",
  "auto_quarantine_threshold",
  "diagnostic_logging",
];

for (const settingId of settingIds) {
  check(
    settings.includes(`setting_id = "${settingId}"`),
    `${settingId} has a widget`,
  );
  check(
    localization.includes(`${settingId} = {`),
    `${settingId} has localization`,
  );
  check(
    localization.includes(`${settingId}_description = {`),
    `${settingId} has localized help text`,
  );
}

const configuredSettingIds = [
  ...settings.matchAll(/setting_id = "([^"]+)"/g),
].map((match) => match[1]);
check(
  new Set(configuredSettingIds).size === configuredSettingIds.length,
  "settings declares every setting ID exactly once",
);

check(
  core.includes("Runtime.version = \"0.5.1\""),
  "runtime reports release version 0.5.1",
);
check(
  core.includes("function Runtime:defer_file") &&
    core.includes("function Runtime:_register_deferred_paths") &&
    core.includes("mod.hook_require") &&
    core.includes("local registered_path = file_path"),
  "runtime aggregates post-load callbacks without eager game-file loading",
);
const productionLua = [core, ...Object.values(modules)].join("\n");
check(
  !/pcall\s*\(\s*require\b/u.test(productionLua),
  "production runtime contains no protected eager require calls",
);
for (const moduleName of [
  "effect_template_safety",
  "gas_outline_recovery",
  "input_device_handoff",
  "power_overload_hud",
  "servo_skull_scroll",
  "training_grounds_danger_index_guard",
  "veteran_redirect_tooltip",
  "zealot_prime_target_tooltip",
]) {
  check(
    modules[moduleName].includes("runtime:defer_file"),
    `${moduleName} defers game-file access until Darktide loads it`,
  );
}
check(
  core.includes("function Runtime:_protected_call") &&
    core.includes("xpcall(invoke, on_error)") &&
    core.includes("state.quarantined = true") &&
    core.includes("auto_quarantine_threshold"),
  "runtime contains protected execution and per-module quarantine",
);
check(
  core.includes("if not self._mod_enabled") &&
    core.includes("cleanup_event") &&
    core.includes("mod_enabled and module.state.available and not module.state.quarantined"),
  "runtime is inert while disabled but preserves cleanup dispatch",
);
check(
  core.includes("self._update_modules") &&
    core.includes("_rebuild_update_modules") &&
    core.includes("module.state.active") &&
    core.includes("type(module.update) == \"function\"") &&
    core.includes("module.update_interval"),
  "runtime schedules only active update modules and honors module intervals",
);
check(
  core.includes("self._settings_known") &&
    core.includes("self._settings_cache") &&
    core.includes("invalidate_setting") &&
    core.includes("setting_changed"),
  "runtime caches settings and invalidates them on explicit change events",
);

for (const phrase of [
  "Stuck or missing cursor",
  "Missed first input after changing devices",
  "Controller vibration changes not applying immediately",
  "Redirect Fire showing the wrong description",
  "Power Overload missing its ally-buff icon",
  "chain-weapon smoke cleanup",
  "Servo-Skull scroll isolation",
  "Repeated duplicate notifications",
  "Broken localization values",
  "Lua memory and long-session cleanup",
  "Expired buff icons remaining on the HUD",
  "Performance without reduced fidelity",
  "Player particles and moving effects",
  "Partly started effects",
  "Event listeners surviving",
  "Manually created sounds",
  "Client effect slots",
  "Destroyed Stimm Field state",
  "Hive Scum personal stimm ready chime",
  "Invalid Psykhanium danger setting",
]) {
  check(readme.toLowerCase().includes(phrase.toLowerCase()), `README covers ${phrase}`);
}
check(
  readme.includes("# Tertium Fixes 0.5.1") &&
    readme.toLowerCase().includes("twenty-two") &&
    readme.toLowerCase().includes("remaining two") &&
    readme.toLowerCase().includes("twenty-four") &&
    readme.includes("Created and maintained by chronic."),
  "README states v0.5.1, the 24/22/2 module split, and the author",
);

const compatibilityBlockStart = gc.indexOf("local CONTROLLER_GROUPS = {");
const compatibilityBlockEnd = gc.indexOf("local function _clamp", compatibilityBlockStart);
check(
  compatibilityBlockStart >= 0 && compatibilityBlockEnd > compatibilityBlockStart,
  "cleanup compatibility identifiers are isolated in one private declaration block",
);

const gcPublicSurface =
  compatibilityBlockStart >= 0 && compatibilityBlockEnd > compatibilityBlockStart
    ? gc.slice(0, compatibilityBlockStart) + gc.slice(compatibilityBlockEnd)
    : gc;
const publicDistributableCopy = [
  readme,
  license,
  localization,
  entrypoint,
  settings,
  core,
  ...Object.entries(modules).map(([moduleName, source]) =>
    moduleName === "gc_pressure" ? gcPublicSurface : source,
  ),
].join("\n");
const prohibitedPublicIdentityTerms = [
  ...expectedControllerIds,
  String.fromCharCode(79, 112, 101, 110, 65, 73),
  String.fromCharCode(67, 104, 97, 116, 71, 80, 84),
  String.fromCharCode(67, 111, 100, 101, 120),
  String.fromCharCode(108, 97, 110, 103, 117, 97, 103, 101, 32, 109, 111, 100, 101, 108),
  String.fromCharCode(65, 73, 45, 103, 101, 110, 101, 114, 97, 116, 101, 100),
  String.fromCharCode(103, 101, 110, 101, 114, 97, 116, 101, 100, 32, 98, 121),
  String.fromCharCode(105, 110, 115, 112, 105, 114, 101, 100, 32, 98, 121),
  String.fromCharCode(98, 111, 114, 114, 111, 119, 101, 100, 32, 102, 114, 111, 109),
  String.fromCharCode(99, 111, 112, 105, 101, 100, 32, 102, 114, 111, 109),
];
const foldedPublicCopy = publicDistributableCopy.toLowerCase();

for (let index = 0; index < prohibitedPublicIdentityTerms.length; index += 1) {
  check(
    !foldedPublicCopy.includes(prohibitedPublicIdentityTerms[index].toLowerCase()),
    `public distributable copy excludes unrelated identity or tooling marker ${index + 1}`,
  );
}
check(
  license.includes("Copyright (c) 2026 chronic") &&
    readme.includes("Created and maintained by chronic."),
  "public authorship is consistently chronic",
);

const sourceRootCandidates = [
  process.env.DARKTIDE_SOURCE_ROOT,
  path.resolve(modRoot, "..", "..", "vendor", "Darktide-Source-Code"),
].filter(Boolean);
const sourceRoot = sourceRootCandidates.find((candidate) =>
  fs.existsSync(path.join(candidate, "scripts")),
);

if (sourceRoot) {
  const sourceChecks = [
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.push_cursor = function (self, reference)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.pop_cursor = function (self, reference)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager._update_clip_cursor = function (self)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.update = function (self, dt, t)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager._update_selection = function (self)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager._update_devices = function (self, dt, t)",
    ],
    [
      "scripts/managers/input/input_device.lua",
      "InputDevice.update = function (self, dt, t)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager._cb_update_rumble_enabled = function (self)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager._update_wwise_rumble = function (self)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.start_suppress_wwise_rumble = function (self)",
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.stop_suppress_wwise_rumble = function (self)",
    ],
    [
      "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/chain_weapon_effects.lua",
      "ChainWeaponEffects._update_active = function (self)",
    ],
    [
      "scripts/managers/localization/localization_manager.lua",
      "LocalizationManager.localize = function (self, key, no_cache, context)",
    ],
    [
      "scripts/managers/localization/localization_manager.lua",
      "LocalizationManager._process_string = function (self, key, raw_str, context)",
    ],
    [
      "scripts/ui/constant_elements/elements/notification_feed/constant_element_notification_feed.lua",
      "ConstantElementNotificationFeed.event_add_notification_message = function (self, message_type, data, callback, sound_event, done_callback, delay)",
    ],
    [
      "scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling.lua",
      "HudElementPlayerBuffs.update = function (self, dt, t, ui_renderer, render_settings, input_service)",
    ],
    [
      "scripts/extension_systems/fx/player_unit_fx_extension.lua",
      "PlayerUnitFxExtension._create_particles_wrapper = function (self, world, particle_name, position, rotation, scale, create_network_index)",
    ],
    [
      "scripts/extension_systems/fx/player_unit_fx_extension.lua",
      "PlayerUnitFxExtension.destroy = function (self, unit)",
    ],
    [
      "scripts/extension_systems/fx/player_unit_fx_extension.lua",
      "local moving_sfx = self._moving_sfx",
    ],
    [
      "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list.lua",
      "ViewElementCampaignMissionList.on_exit = function (self)",
    ],
    [
      "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list.lua",
      "ViewElementCampaignMissionList.destroy = function (self, ui_renderer)",
    ],
    [
      "scripts/ui/view_elements/view_element_campaign_mission_list/view_element_campaign_mission_list_definitions.lua",
      "content.hover_sound_id = Managers.ui:play_2d_sound",
    ],
    [
      "scripts/settings/buff/archetype_buff_templates/veteran_buff_templates.lua",
      "templates.veteran_improved_tag_allied_buff = {",
    ],
    [
      "scripts/settings/buff/archetype_buff_templates/veteran_buff_templates.lua",
      "templates.veteran_improved_tag_allied_buff_increased_stacks = table.clone(templates.veteran_improved_tag_allied_buff)",
    ],
    [
      "scripts/settings/buff/archetype_buff_templates/cryptic_buff_templates.lua",
      "templates.cryptic_overload_keystone_stack = {",
    ],
    [
      "scripts/settings/buff/archetype_buff_templates/cryptic_buff_templates.lua",
      "templates.cryptic_overload_keystone_allies_buff = {",
    ],
    [
      "scripts/settings/talent/talent_settings_cryptic.lua",
      "allies_buff_duration = 8,",
    ],
    [
      "scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point.lua",
      "weapon_template.not_scroll_wieldable = true",
    ],
    [
      "scripts/settings/equipment/weapon_templates/grenades/cryptic_servo_skull_order_point.lua",
      "local wield_inputs = PlayerCharacterConstants.wield_inputs",
    ],
    [
      "scripts/settings/player_character/player_character_constants.lua",
      'input = "wield_scroll_down"',
    ],
    [
      "scripts/settings/player_character/player_character_constants.lua",
      'input = "wield_scroll_up"',
    ],
    [
      "scripts/settings/fx/effect_templates/companion_servo_skull_moving_effect.lua",
      'name = "companion_servo_skull_moving_effect"',
    ],
    [
      "scripts/settings/fx/effect_templates/companion_servo_skull_aim_on_ground_effect.lua",
      'name = "companion_servo_skull_aim_on_ground_effect"',
    ],
    [
      "scripts/settings/fx/effect_templates/companion_servo_skull_flamer.lua",
      'name = "companion_servo_skull_flamer"',
    ],
    [
      "scripts/settings/fx/effect_templates/companion_servo_skull_empowered_effect.lua",
      'name = "companion_servo_skull_empowered_effect"',
    ],
    [
      "scripts/settings/fx/effect_templates/companion_servo_skull_charged_shooting_effect.lua",
      'name = "companion_servo_skull_charged_shooting"',
    ],
    [
      "scripts/settings/fx/effect_templates/arc_chain_to_position.lua",
      'name = "arc_chain_to_position"',
    ],
    [
      "scripts/managers/input/input_manager.lua",
      "InputManager.destroy = function (self)",
    ],
    [
      "scripts/managers/game_mode/game_modes/game_mode_survival.lua",
      "GameModeSurvival.destroy = function (self)",
    ],
    [
      "scripts/utilities/expeditions/expedition_loot_handler.lua",
      "ExpeditionLootHandler.destroy = function (self)",
    ],
    [
      "scripts/extension_systems/dialogue/dialogue_extension.lua",
      "DialogueExtension.extensions_ready = function (self, world, unit)",
    ],
    [
      "scripts/extension_systems/dialogue/dialogue_extension.lua",
      "DialogueExtension.destroy = function (self)",
    ],
    [
      "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/zealot_relic_effects.lua",
      "ZealotRelicEffects.destroy = function (self)",
    ],
    [
      "scripts/settings/fx/effect_templates/renegade_flamer_mutator_throw.lua",
      "stop = function (template_data, template_context)",
    ],
    [
      "scripts/settings/fx/effect_templates/cultist_mutant_charge_foley.lua",
      "stop = function (template_data, template_context)",
    ],
    [
      "scripts/settings/fx/effect_templates/chaos_poxwalker_bomber_foley.lua",
      "stop = function (template_data, template_context)",
    ],
    [
      "scripts/extension_systems/fx/fx_system.lua",
      "FxSystem.init = function (self, extension_system_creation_context, ...)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.has_running_effect_with_global_id = function (self, global_effect_id)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.add_template_effect = function (self, unit_to_particle_group_lookup, template_context, template, optional_unit, optional_node, optional_position, optional_player_owner_unit)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.remove_template_effect = function (self, template_context, global_effect_id)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.update = function (self, template_context, dt, t)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.remove_effects_on_unit = function (self, template_context, unit)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.clear = function (self, template_context)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.start_template_effect_from_rpc = function (self, unit_to_particle_group_lookup, template_context, buffer_index, template, optional_unit, optional_node, optional_position, optional_player_owner_unit)",
    ],
    [
      "scripts/extension_systems/fx/utilities/effect_templates_handler.lua",
      "EffectTemplatesHandler.stop_template_effect_from_rpc = function (self, template_context, buffer_index)",
    ],
    [
      "scripts/extension_systems/proximity/side_relation_gameplay_logic/proximity_broker_stimm_field.lua",
      "ProximityBrokerStimmField._make_linger = function (self, unit, t, linger_time)",
    ],
    [
      "scripts/settings/ability/player_abilities/abilities/broker_abilities.lua",
      "broker_ability_syringe = {",
    ],
    [
      "scripts/extension_systems/ability/player_unit_ability_extension.lua",
      "PlayerUnitAbilityExtension.fixed_update = function (self, unit, dt, t, fixed_frame)",
    ],
    [
      "scripts/extension_systems/ability/player_unit_ability_extension.lua",
      "PlayerUnitAbilityExtension.remaining_ability_charges = function (self, ability_type)",
    ],
    [
      "scripts/settings/ui/ui_sound_events.lua",
      'ability_off_cooldown = "wwise/events/ui/play_hud_ability_off_cooldown"',
    ],
    [
      "scripts/ui/view_elements/view_element_mission_board_difficulty_selector/view_element_mission_board_difficulty_selector.lua",
      "ViewElementMissionBoardDifficultySelector.initialize_data = function (self, optional_difficulty_index)",
    ],
  ];

  for (const [relativePath, signature] of sourceChecks) {
    const source = fs.readFileSync(path.join(sourceRoot, relativePath), "utf8");
    check(
      source.includes(signature),
      `pinned source exposes ${signature.split(" = ")[0]}`,
    );
  }

  const chainSource = fs.readFileSync(
    path.join(
      sourceRoot,
      "scripts/extension_systems/visual_loadout/wieldable_slot_scripts/chain_weapon_effects.lua",
    ),
    "utf8",
  );
  const chainUpdateBody = chainSource.slice(
    chainSource.indexOf("ChainWeaponEffects._update_active ="),
    chainSource.indexOf("ChainWeaponEffects._update_sound"),
  );
  check(
    chainUpdateBody.indexOf("_stop_vfx_loop(false)") >= 0 &&
      chainUpdateBody.indexOf("_stop_vfx_loop(false)") <
        chainUpdateBody.indexOf("SPECIAL_OFF_SOUND_ALIAS"),
    "pinned chain transition stops its loop before playing the end sound",
  );

  const inputManagerSource = fs.readFileSync(
    path.join(sourceRoot, "scripts/managers/input/input_manager.lua"),
    "utf8",
  );
  const inputManagerUpdateBody = inputManagerSource.slice(
    inputManagerSource.indexOf("InputManager.update ="),
    inputManagerSource.indexOf("InputManager._update_devices ="),
  );
  const selectionIndex = inputManagerUpdateBody.indexOf("self:_update_selection()")
  const devicesIndex = inputManagerUpdateBody.indexOf("self:_update_devices(dt, t)")
  const servicesIndex = inputManagerUpdateBody.indexOf("self:_update_services(dt, t)")
  check(
    selectionIndex >= 0 &&
      selectionIndex < devicesIndex &&
      devicesIndex < servicesIndex,
    "pinned input update selects before polling devices and then updates services",
  );

  const inputDeviceSource = fs.readFileSync(
    path.join(sourceRoot, "scripts/managers/input/input_device.lua"),
    "utf8",
  );
  check(
    inputDeviceSource.includes("InputDevice.last_pressed_device = self"),
    "pinned input-device poll records the device that pressed during this frame",
  );

  const playerBuffSource = fs.readFileSync(
    path.join(
      sourceRoot,
      "scripts/ui/hud/elements/player_buffs/hud_element_player_buffs_polling.lua",
    ),
    "utf8",
  );
  const playerBuffUpdateBody = playerBuffSource.slice(
    playerBuffSource.indexOf("HudElementPlayerBuffs.update ="),
  );
  check(
    playerBuffUpdateBody.includes("for i = 1, #active_buffs_data do") &&
      playerBuffUpdateBody.includes("table.remove(active_buffs_data, i)"),
    "pinned player-buff update removes entries while traversing the array forwards",
  );
} else {
  skips += 1;
  process.stdout.write(
    "SKIP pinned source signature checks (set DARKTIDE_SOURCE_ROOT to enable)\n",
  );
}

check(
  fs.existsSync(moduleRoot) && fs.existsSync(scriptRoot),
  "resolved mod script directories exist",
);

process.stdout.write(
  `\n${failures === 0 ? "OK" : "FAILED"}: ${checks} checks, ${failures} failures, ${skips} skips\n`,
);

process.exitCode = failures === 0 ? 0 : 1;
