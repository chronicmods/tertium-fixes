# Verification status: 0.5.2-unstable.1

This page separates what I can prove from what still needs live-game soak. A
hook being installed is not counted as a repair firing. Tertium Fixes already
keeps separate hit and action counters, which are visible through `/tf_status`.

## Current target

- Darktide source snapshot: 1.12.4
- Source commit: `fffb2f1f8a38b42f61cc98610bda0dfdd2129914`
- Locally installed Steam build observed during the audit: `24611088`
- Preview version: `0.5.2-unstable.1`

The source gate checks the exact classes, methods, signatures, template keys,
and several stock defect shapes used by the mod. It is not allowed to skip the
source checks when building this preview.

## Test evidence

- 594 package, safety, and current-source contract checks pass with the 1.12.4
  source gate enabled and no source skips accepted.
- 404 executable Lua behavior checks pass across all 13 suites.
- The complete branch gate is 998 checks with zero failures.
- All 25 production modules have at least one behavior case that proves an
  observable mutation, cleanup, suppression, restoration, or guarded upstream
  no-op.
- The same 998-check gate also passes against the extracted release archive.
  All 34 production files in that archive hash-match the branch contents.
- Final archive: `TertiumFixes-v0.5.2-unstable.1.zip`, 71,809 bytes, SHA-256
  `12799321f347fe6c7578876e5e1c1c99a9feaa4bf873236f78da197c92c307a9`.
- Existing live Darktide 1.12.3 logs confirm that DMF loaded the mod and
  installed its immediate and deferred hook families without a Tertium Fixes
  runtime error. That is install-path evidence, not 1.12.4 soak evidence.

The pinned runtime for behavior tests is `fengari-node-cli@0.1.0` with
`fengari@0.1.5`. The exact versions and transitive dependencies are recorded in
`package-lock.json`.

From the repository root, the reproducible gate is:

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
$env:DARKTIDE_SOURCE_ROOT = "C:\path\to\Darktide-Source-Code"
npm.cmd test
```

The smoke gate resolves that source directory as a Git checkout and fails unless
`HEAD` is exactly `fffb2f1f8a38b42f61cc98610bda0dfdd2129914`.

To audit a real session log without counting hook installation as a repair hit:

```powershell
node tests/audit_live_log.mjs "C:\path\to\console.log"
```

## What the 1.12.4 audit found

Darktide changed
`ConstantElementNotificationFeed.event_add_notification_message` by adding a
new `start_callback` argument. Version 0.5.1 did not forward that eighth
argument. The preview forwards it in every path. The optional deduplicator also
excludes every call with callbacks or timing, and is now disabled by default
because a callback-free repeat can still carry useful information.

The same 1.12.4 source stores `start_callback` and `done_callback` when the
visible notification feed is full, but its overflow-drain path reads the old
`callback` field and calls `_add_notification_message` without the completion
callback. The new default-on queue repair restores only those two exact stored
callbacks while the matching queue head is being drained. Direct calls,
mismatched entries, disabled state, and failures pass through unchanged.

Darktide 1.12.4 also corrected Redirect Fire's `related_talents` metadata. The
preview recognizes the correct value, marks that module `fixed upstream`,
records no hit/action, and leaves the table identity untouched. Prime Target
and Power Overload still have the missing presentation metadata in the 1.12.4
source snapshot; behavior tests prove the exact fields added and restored.

The 1.12.4 notes say that a general cutscene fade-to-black that never clears was
fixed, but they do not name `path_of_trust_09`. The legacy Path 09 fallback is
therefore retained behind its exact scene, empty-queue, time-window, and HUD
state guards. This is deliberately not presented as proof that Path 09 remains
broken or that Fatshark fixed that exact scene.

## Module evidence map

| Module | Evidence in this preview |
| --- | --- |
| Cursor stack | Recounts truthy references, changes depth/visibility, and refreshes clipping only when needed. |
| Input-device handoff | Proves one same-frame selection update and no action for fixed, missing, or malformed state. |
| Rumble refresh | Proves an explicit `false` value survives and Wwise state refreshes after setting/suppression changes. |
| Redirect Fire | 1.12.4 source says fixed upstream; test proves zero mutation and zero action. Legacy broken shape is still repaired and restored. |
| Prime Target | Current source still lacks the talent link; test adds the exact link and restores `nil`. |
| Power Overload | Current source still lacks five HUD fields; test adds all five without touching buff strength, then restores them. |
| Chain smoke | Opt-in test proves stock end transition runs before the one captured particle tail is destroyed. |
| Servo-Skull wheel | Separate stronger opt-in control preference: removes exactly two wheel inputs from a private clone and restores the shared identity. This is not the game's 1.12.4 wheel-bound activation fix. |
| Notification overflow callbacks | Proves a matching full-feed queue drain restores the exact start/completion callbacks, while direct, mismatched, disabled, and failure paths preserve the original call. |
| Notification dedupe | Optional and default-off. Proves safe repetition can be suppressed, while all callbacks, delays, mission messages, and failures pass through with all eight arguments. |
| Localization guard | Proves invalid key/value fallbacks and removal of the temporary cache entry. |
| Lua heap controller | Exercises capacity detection, pressure thresholds, bounded steps, emergency collections, ownership conflicts, monitor-only mode, HUD, transitions, and exact tuning restoration. |
| Campaign vox cleanup | Stops and clears every owned hover handle before stock exit/destroy. |
| Player buff removal | Removes consecutive expired entries in reverse while keeping live order and malformed state fail-open. |
| Penances carousel | Reverses only the mouse-wheel Y axis seen by the stock handler. |
| Path of Trust fade | Narrow legacy fallback: arms only on `path_of_trust_09` and releases only the terminal fully-black state. The patch notes fix a matching general symptom but do not identify this scene. |
| Toxic-gas outlines | Preserves stock stop, restores visibility only for a dead local player, and restores original callbacks on disable. |
| Player FX lifecycle | Exercises moving particle/audio teardown, native failure retention, retry, and idempotence. |
| Partial-effect safety | Exercises all 17 wrappers, partial cleanup, retries, late stops, unload ownership, and same-session reload. |
| Event-listener cleanup | Proves six exact owner/event unregistrations after stock teardown with platform/server scoping. |
| Manual audio cleanup | Proves five exact owned sources are destroyed once; unrelated and failed handles remain owned for retry. |
| FX-handler integrity | Stress-tests generations, stale IDs, 300 ring allocations, local/network ownership, reentrancy, clear, and duplicate RPCs. |
| Stimm Field tombstone | Proves only the exact deleted-extension row is discarded without reading the destroyed extension. |
| Hive Scum chime | Proves a silent baseline and exactly one stock cue on a real zero-to-ready local stimm transition. This is a quality-of-life cue, not an upstream bug fix. |
| Psykhanium danger index | Proves scope, finite-number normalization, clamping, fallback, deleted parents, and no eager source load. |

## Limits

These checks demonstrate source compatibility and deterministic module behavior.
They cannot reproduce every rare engine timing condition or replace hours of
live sessions across hardware, missions, and mod combinations. The current
build is therefore published as a GitHub prerelease from `unstable` and as a
Nexus Optional File, leaving stable 0.5.1 untouched. Of the 25 module switches,
22 are on by default and the three tradeoff-bearing behaviours remain opt-in.

Reported Rashad and Atrox axe ghost hits were traced separately. The client can
predict a melee overlap and play its impact effect, but the server performs the
authoritative lag-compensated sweep, applies enemy damage, and returns the attack
report that drives hit confirmation. No deterministic zero-damage branch was
found in the current axe Lua templates. A local hitbox or damage-window edit
would therefore risk manufacturing more impact feedback without real damage, so
this preview deliberately does not advertise or include an axe hit-registration
fix.
