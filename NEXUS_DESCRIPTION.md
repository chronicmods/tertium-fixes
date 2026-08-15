# Tertium Fixes 0.5.2-unstable.1

Created and maintained by chronic.

This is the separate unstable preview for Darktide 1.12.4. It does not replace the 0.5.1 Main file. I put Tertium Fixes together to deal with the client-side problems that kept getting in the way: stuck menus, missed inputs, incorrect talent and buff information, stale HUD entries, looping audio, effects that are not released properly, and avoidable Lua memory pressure during long sessions. It keeps all of those repairs in one place and only touches problems that can be handled safely on the player's side.

I've set the defaults up so it should work without any adjustment. Twenty-two of the twenty-five module switches are enabled immediately. On Darktide 1.12.4 the Redirect Fire module sees the official correction and stays inert. I left the remaining three disabled because they are optional behaviours with visible, control-related, or information-suppression tradeoffs. Every repair can still be switched on or off separately.

The mod does not change weapon statistics, talents, enemies, rewards, difficulty, damage, movement, cooldowns, progression, or mission rules. It does not lower texture quality, lighting, resolution, animation quality, normal particle quality, or audio quality.

Version 0.5.2-unstable.1 updates the game-source contracts to Darktide 1.12.4 and preserves the new start callback added to the notification path. It also repairs a separate 1.12.4 overflow-queue bug that stores start and completion callbacks but drops both when the queued notification is finally shown. Duplicate suppression remains available as an opt-in and is disabled by default. Darktide fixed the Redirect Fire presentation link upstream, so this preview detects that and reports it instead of applying a fake patch.

## Main fixes

### Input and menus

**Repair cursor reference stack**

Repairs the cursor state after menus request or release it. This addresses cases where the cursor remains visible during gameplay, disappears inside a menu, or becomes trapped after moving between overlapping screens. It does not change normal mouse movement or menu navigation.

**Use newly pressed input devices immediately**

Updates the active input device as soon as a controller, keyboard, or mouse is used. This helps prevent the first press after changing devices from being ignored. It does not alter bindings, sensitivity, aim assistance, or input priority after the handoff has completed.

**Apply controller-rumble setting immediately**

Refreshes controller vibration after its setting changes or after the game temporarily suppresses it. It does not increase vibration strength or add new vibration effects.

**Correct Penances carousel wheel direction**

Corrects the mouse-wheel direction in the Penances overview so it matches the surrounding menus. Keyboard and controller navigation remain unchanged.

### Talents, buffs, and HUD

**Correct Redirect Fire talent description**

The guarded repair remains for the older broken metadata, but Darktide 1.12.4 now has the correct presentation link. On the current game this module reports `fixed upstream` and makes no change. It never changes the talent's effect or balance.

**Correct Prime Target tactical-overlay text**

Restores the correct name and description for the Prime Target effect where the tactical overlay would otherwise show only an icon. The Zealot talent itself is unchanged.

**Show the Power Overload ally-buff icon**

Restores the intended icon and presentation information for the eight-second Power Overload ally buff. Buff strength, duration, stacking, and damage are not changed.

**Preserve notification overflow callbacks**

Restores the exact start and completion callbacks that Darktide 1.12.4 stores when the visible feed is full but fails to pass back when the overflow queue drains. Normal direct notifications and mismatched queue entries pass through unchanged.

**Deduplicate safe notifications (optional)**

Suppresses identical basic notifications repeated within a short period. Messages that contain actions, delays, or special behaviour are left alone. This is disabled by default because even a callback-free repeat can still be useful feedback. Mission notifications remain excluded unless separately enabled.

**Guard invalid localization keys**

Prevents invalid or missing text values from entering the normal interface text path. A broken value can be replaced by a visible diagnostic placeholder or by blank text, depending on the selected fallback option.

**Remove stale consecutive buff HUD entries**

Removes expired buff entries that can be skipped when several are cleared in sequence. Live buffs and their order are not changed.

**Legacy Path 09 black-screen fallback**

Watches only the exact `path_of_trust_09` terminal black state. Darktide 1.12.4 says a matching general cutscene-fade problem was fixed, but the notes do not identify this exact scene. The narrow guarded fallback therefore remains without claiming that Path 09 itself is still broken or was fixed upstream.

**Restore outlines after dying in toxic gas**

Restores outlines when the relevant toxic-gas effect ends while the local player is dead. Living players, remote players, unrelated effects, and normal gas behaviour are not changed.

**Repair invalid Psykhanium danger settings**

Validates the saved danger setting used by the Training Grounds shooting range. Valid choices are preserved. Missing, malformed, or out-of-range values fall back to a safe normal choice instead of breaking the selector.

**Play a chime when the Hive Scum stimm is ready**

Plays Darktide's normal ability-ready sound once when the local Hive Scum personal stimm changes from empty to usable.

The first ready state after joining, spawning, reconnecting, equipping the ability, or enabling the setting is deliberately silent. This prevents false alerts. Natural recharge, cooldown reduction, and direct charge restoration use the same ready check.

### Audio and visual effects

**Stop leaked Campaign Data Transmission audio**

Stops the stored transmission-hover sound when leaving or closing the affected campaign screen. Only the sound owned by that screen is touched.

**Repair player particle and moving-effect lifecycle**

Releases affected moving particles and sounds when the player effect that owns them is destroyed. It also supplies missing effect state where the game already has the correct value available. This reduces effects and sound handles remaining active after they should have ended.

**Guard partially initialized client effects**

Stops affected Servo-Skull, flamer, empowered, charged, and arc-chain effects from continuing when startup did not create all the state they require. Any resources that did start are released safely.

**Release leaked event listeners**

Unregisters affected controller-haptic, Survival objective, and Expedition rescue listeners when the related client object is destroyed. This prevents old listeners continuing to receive events after their owner has gone.

**Release leaked manual audio sources**

Releases affected dialogue, relic, flamer, mutant, and bomber sound sources when the object that created them ends. Unrelated and automatically managed audio is not touched.

**Guard client effect-handler state**

Adds safer cleanup around reused local effect slots. This prevents the shutdown of an older effect from clearing a newer effect that has reused the same position, and makes repeated cleanup harmless.

**Discard destroyed Stimm Field cache rows**

Removes a Stimm Field entry from the local proximity cache only after its stored buff connection has already been destroyed. Valid field entries and normal Stimm Field behaviour remain unchanged.

## Lua memory and long-session cleanup

Tertium Fixes includes a Lua heap controller intended to reduce avoidable memory pressure over longer sessions. The heap reading covers memory used by Darktide's Lua scripting. It is not total system RAM, video memory, or the complete game memory shown by Task Manager.

The controller checks the heap once per second. It uses the Lua heap capacity supplied through Darktide's launch settings when available. If the game does not provide a usable value, it uses the fallback capacity selected in the mod options.

Cleanup is gradual by design:

- Heap use must remain at or above 80 percent for five seconds before pressure handling begins.
- Small, limited cleanup steps are attempted before a full cleanup.
- At 85 percent, a warning can be shown and the heap meter can be temporarily forced visible.
- At 90 percent, one full cleanup is allowed for that pressure episode.
- At 95 percent, one additional emergency cleanup is allowed.
- The pressure episode ends when heap use falls below 80 percent.
- A sharp increase over a short period can request an earlier cleanup.

Cleanup can also run shortly after selected transitions between the Mourningstar, missions, and supported activities. These actions are delayed so loading allocations have time to settle.

The optional ten-minute cleanup is disabled by default. A full Lua cleanup can produce a brief frame-time hitch, particularly when a large amount of memory has accumulated. The manual cleanup key can cause the same type of hitch.

### Required compatibility step: disable other memory-cleaning mods

Before using Tertium Fixes' Lua cleanup controller, disable **SMOG**, **MemLeakFix**, **FPS Doctor**, and any other mod or option that performs automatic Lua memory cleaning, garbage collection, or collector tuning. Do not run two cleanup controllers together. Restart Darktide after disabling them so no old collector state remains in the session.

Tertium Fixes has a standby check for the known controllers above, but that is a last safety barrier rather than support for running them together. If you want to keep another memory-cleaning mod, turn off **Permit automatic and manual cleanup** in Tertium Fixes and use only its monitoring/status features.

### Heap meter

The meter shows current Lua heap use in megabytes, the detected or fallback capacity, the current percentage, and the pressure level. It can be positioned horizontally and vertically through the options menu.

The default controls are:

- **F5:** request one guarded full cleanup.
- **F8:** show or hide the heap meter for the current session.

Both keys can be rebound or cleared. A successful manual cleanup reports the heap before and after cleaning and the amount reclaimed. Manual cleanup has a three-second cooldown.

## Performance without reduced fidelity

With the default settings, the mod improves client housekeeping without lowering visual or audio quality. It removes expired HUD entries, abandoned listeners, finished audio handles, stranded particles, and stale effect state that would otherwise remain active longer than necessary. It also caches settings and active repair state so the same unchanged information is not looked up over and over again.

The normal configuration does not reduce:

- Texture quality
- Lighting
- Resolution or render scale
- Animation quality
- Audio quality
- Normal particle quality
- Visibility
- Simulation detail

The optional chain-weapon smoke workaround is the single deliberate visual exception because its purpose is to remove a visible smoke tail. It is disabled by default.

These changes are intended to improve consistency and reduce avoidable client work, particularly during longer sessions. Results still depend on hardware, drivers, graphics settings, mission conditions, and the current game version. The mod cannot remove online delay or guarantee a particular frame-rate increase.

## Optional behaviours

I left the following three behaviours disabled by default because each has a noticeable tradeoff.

**Deduplicate repeated safe notifications**

Suppresses identical callback-free default and alert messages inside the selected window. Anything with callbacks or timing passes through unchanged. Repetition can still be meaningful feedback, so this stays opt-in.

**Aggressively stop chain-weapon smoke**

Stops the affected smoke effect during chain-weapon power-down. This can prevent smoke remaining far longer than intended, but it also removes the normal short smoke tail. The power-down sound is preserved.

**Prevent Servo-Skull mouse-wheel toggles**

This is a stronger control preference, separate from Darktide 1.12.4's fix for wheel-bound Servo-Skull activation interruption. It removes mouse-wheel weapon switching while the skull is held, so the wheel cannot cycle weapons until the skull is put away. Keyboard and controller selection remain available.

## Complete options guide

Every main repair described above has its own checkbox. The following settings control timing, display, safety, and advanced behaviour.

### Notification options

**Deduplicate repeated safe notifications**
Default: Disabled.

Enables the optional duplicate-suppression window for callback-free default and alert messages. It does not control the separate overflow-callback repair.

**Notification duplicate window**  
Default: 2 seconds. Range: 1 to 10 seconds.

Sets how long an identical safe notification is treated as a duplicate while optional deduplication is enabled. A longer window removes repeats that arrive further apart, while a shorter window allows the same message to appear again sooner.

**Include mission notifications**  
Default: Disabled.

Also applies duplicate suppression to matching mission and objective messages. This remains disabled by default so repeated objective updates are preserved.

### Localization options

**Localization fallback**  
Default: Diagnostic placeholder.

Diagnostic placeholder makes an invalid text value visible so the affected interface element can be identified. Blank text hides the invalid value and keeps the affected area less distracting. This option is used only while the invalid-localization guard is enabled.

### Lua heap options

**Lua heap controller**  
Default: Enabled.

Enables heap monitoring, pressure detection, and the related options. Disabling it turns off this complete section of the mod.

**Permit automatic and manual cleanup**  
Default: Enabled.

Allows Tertium Fixes to adjust or invoke Lua cleanup. Disabling it retains monitoring, status information, and the heap meter without allowing any cleanup action.

**Fallback Lua heap capacity**  
Default: 1,024 MB. Range: 128 to 65,536 MB.

Used only when a valid capacity cannot be read from Darktide's launch settings. This value should represent the configured Lua heap limit. It should not be set to total system RAM or video memory.

**Clean at safe state transitions**  
Default: Enabled.

Allows delayed cleanup after selected entries and exits. Mourningstar entry receives a longer delay than most supported transitions so loading activity can settle first.

**Optional ten-minute cleanup**  
Default: Disabled.

Requests a full cleanup every ten minutes while enabled. It remains disabled by default because a periodic full cleanup can create a visible hitch even when the heap is not under immediate pressure.

**Heap-pressure notifications**  
Default: Enabled.

Shows warnings when the heap reaches high pressure and reports emergency cleanup results. This setting does not control the meter or diagnostic log.

**Show Lua heap meter**  
Default: Enabled.

Displays current Lua heap use, capacity, percentage, and pressure state. High pressure can temporarily force the meter visible until use returns below 80 percent.

**Heap meter horizontal position**  
Default: 5 percent. Range: 0 to 100 percent.

Moves the meter across the active HUD area from left to right.

**Heap meter vertical position**  
Default: 65 percent. Range: 0 to 100 percent.

Moves the meter down the active HUD area from top to bottom.

**Record abnormal-exit heap context**  
Default: Enabled.

Stores only the previous session's broad pressure level and whether the mod recorded a clean shutdown. If the previous session ended unexpectedly while heap pressure was high, a warning can be shown on the next launch. This is context only and does not claim that memory caused the crash.

**Manual full-cleanup key**  
Default: F5.

Requests one immediate guarded cleanup. It has a three-second cooldown and can produce a brief frame-time spike. The action remains blocked when cleanup permission is disabled or Tertium Fixes does not currently own cleanup.

**Show or hide heap meter key**  
Default: F8.

Toggles the meter for the current session. A high-pressure warning can temporarily force it visible until pressure clears.

### Advanced effect options

**Experimental local effect allocator**  
Default: Disabled.

Replaces allocation and expiry handling for client-local effects. The normal effect-handler repair does not require it. This setting remains disabled until it has broader live-game coverage and should be used only when diagnosing a specific effect problem.

**Experimental network effect containment**  
Default: Disabled.

Rejects some malformed, repeated, or already-stopped client effect messages. Delayed messages cannot always be identified with certainty after a slot is reused, so this setting remains disabled unless it is needed for a specific problem.

### Runtime safety options

**Auto-quarantine failing modules**  
Default: Enabled.

Stops one individual repair after repeated unexpected errors while leaving the remaining repairs active. This prevents a changed game function from causing the whole package to fail.

**Errors before quarantine**  
Default: 3. Range: 1 to 10.

Sets how many caught errors one repair can produce before it is quarantined. Lower values stop a failing repair sooner. Higher values allow more repeated attempts before it is stopped.

**Diagnostic log messages**  
Default: Enabled.

Records useful feature state changes and caught errors in the Darktide Mod Framework log. It does not add an on-screen performance overlay or change gameplay.

## Commands

**/tf_status**

Shows which repairs are available, active, disabled, or quarantined, together with their activity and error counters.

**/tf_reset module_id**

Clears errors, quarantine, and temporary state for one repair. Use `/tf_status` to find the required module ID.

**/tf_reset all**

Resets every repair without requiring a game restart.

**/tf_gc** or **/tf_gc status**

Shows heap capacity, current pressure, cleanup availability, recent actions, and controller state.

**/tf_gc clean**

Requests one guarded full cleanup and reports the result.

**/tf_gc step**

Requests one small incremental cleanup step.

Cleanup commands remain blocked when cleanup permission is disabled or the feature does not currently own cleanup.

## Requirements

- Darktide Mod Loader
- Darktide Mod Framework

## Installation

1. Install Darktide Mod Loader and Darktide Mod Framework.
2. Open Darktide's `mods` folder.
3. Copy the complete `TertiumFixes` folder into it.
4. Add `TertiumFixes` on its own line in `mods/mod_load_order.txt`.
5. Launch Darktide.
6. Open the Darktide Mod Framework options menu if you want to change any settings.

The finished folder should be:

`Darktide/mods/TertiumFixes/`

Do not add an extra folder level between `mods` and `TertiumFixes`.

## Updating

Delete the existing `TertiumFixes` folder and replace it with the complete folder from the new release. Do not merge releases together. Old files left behind can cause errors even when the current files are correct. Saved settings should remain available through Darktide Mod Framework.

Version 0.3.0 was withdrawn because it could cause a startup script error. If that version was ever installed, completely remove the old folder before installing the current release.

## Compatibility and limits

Tertium Fixes is client-side. The host and the rest of the team do not need it installed.

Each repair is separated from the others. If a Darktide update changes an affected system, the repair is designed to leave the game's original behaviour in place instead of guessing. Automatic quarantine can stop one failing repair without disabling the rest of the package.

There are still some things a client-side Lua mod simply cannot repair. Tertium Fixes cannot directly change:

- Server-side combat results or hit validation
- Authoritative enemy or mission state
- Matchmaking or service outages
- Account, reward, inventory, or progression records
- Packet loss, routing problems, or unstable internet connections
- Native engine, renderer, graphics-driver, operating-system, or platform faults
- Missing game content that requires an official update

The mod provides targeted local repairs and workarounds. It cannot guarantee a solution for every possible crash, disconnect, stutter, or black screen.

## Troubleshooting

**The game reports a loop or previous error while loading a module**

Delete the existing `TertiumFixes` folder completely and install the current release into a fresh folder. Do not merge the new release into an old copy.

**Tertium Fixes does not appear in the options menu**

Confirm that the loader and framework are installed, the folder is exactly `Darktide/mods/TertiumFixes/`, `TertiumFixes` is on its own line in `mods/mod_load_order.txt`, and there is no second nested `TertiumFixes` folder inside the first one.

**One repair has stopped working**

Run `/tf_status`. If the repair was quarantined, use `/tf_reset module_id` after the immediate problem has passed. If it repeatedly stops itself, leave only that setting disabled until a compatible update is available.

**The heap percentage looks wrong**

Check the fallback Lua heap capacity. It should match the configured Lua heap limit when Darktide does not provide that value automatically. Do not enter total system RAM or video memory.

**Manual cleanup is blocked**

Confirm that the Lua heap controller and cleanup permission are enabled. Also disable SMOG, MemLeakFix, FPS Doctor, and any other automatic Lua memory-cleaning mod, then restart the game. `/tf_gc status` shows whether cleanup is currently available.

**The Hive Scum stimm chime is silent after spawning**

This is intentional. The first ready state after joining, spawning, reconnecting, equipping, or enabling the setting is silent. The chime plays when the personal stimm later changes from empty to usable.

**A setting causes an unwanted visual or control change**

Check the three optional behaviours first. All are disabled by default. Turning off the affected setting restores normal behaviour.

## Uninstalling

Remove `TertiumFixes` from `mods/mod_load_order.txt`, then delete the `Darktide/mods/TertiumFixes` folder.
