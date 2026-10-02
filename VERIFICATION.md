# Verification

Tertium Fixes **0.6.0-unstable.3** targets Darktide **1.13.0-b802981**, Steam
build **25492122**, content revision **138030**.

## Source and behaviour checks

The reviewed build passes **205 package/source checks** and **843
behaviour checks across 22 suites**, with no skipped suites or reported errors.
The package checks compile every production Lua file, execute the option and
translation definitions, compare the runtime defaults, check module registration,
and compare the game files with the recorded hashes.

`tests/source_manifest.json` pins 113 relevant game files. It includes both the
decompiled-source and extracted-bytecode hashes. The source gate verifies the
readable source used by the tests. A missing or changed file fails the gate.

The new source suites execute the installed game's class, input, action, UI and
effect methods. They keep reproductions of the stock faults beside the repaired
cases. Native rendering, audio, resource and network services are represented
inside the test environment; these cases establish Lua behaviour and ownership,
not a native-engine benchmark or a completed mission.

| Suite | Checks |
| --- | ---: |
| Deferred loading | 19 |
| Partial effect startup and cleanup | 21 |
| Effect enable, reload and disable | 13 |
| Effects using the installed source | 56 |
| Audio and event cleanup | 43 |
| Effect handler IDs and ownership | 25 |
| Lua memory and HUD | 77 |
| Graphics preset controller | 45 |
| Graphics profiles using the installed source | 36 |
| Hive Scum stimm cue | 45 |
| Existing input and buff fixes | 19 |
| Input buffering using the installed source | 65 |
| Initial Social heading and live party counts | 20 |
| Talent and HUD metadata | 18 |
| Notification callbacks and suppression | 15 |
| Psykhanium and Stimm Field guards | 56 |
| Other existing repairs | 17 |
| Runtime errors, reset and cleanup | 76 |
| Runtime update scheduling | 22 |
| Shooting-range selector using the installed source | 38 |
| UI cleanup and template replacement | 34 |
| UI using the installed source | 83 |

The input tests cover normal local capture and input RPC data, exact-slot swaps,
quick and aimed Blitz behaviour, queued weapon specials, menu/key locks,
interaction, death and disabled extensions, held/released inputs, cancellation,
and both predicted and authoritative action acknowledgement. A separate review
reproduced and checked the server-correction path: it can restore an accepted
action without calling `start_action`, so the module observes that path as well.

The grouped options were also checked with the installed Mod Framework options
validator. All seven groups and 55 setting widgets were accepted with their
defaults. A pre-existing setting value was retained in the compatibility check.

The input master switch and all five action switches now default to off in both
the options and runtime fallback. The source gate checks that they agree and
that the input group remains opt-in. Saved Mod Framework values still take
precedence over these new-install defaults.

The unstable.3 source archive passed the complete gate after extraction,
using the same locked test dependencies as the working tree. The earlier paired
DarkCache source archive passed its 165 checks against unstable.2. The input
retry implementation is unchanged; this release changes its defaults for new
installs.

Archive verification compares every entry with the source file and checks ZIP
integrity. Game scripts and test dependencies are not bundled in the downloads.

## Allocation measurement

A comparison with commit `e7922ce` ran 100,000 identical successful runtime
calls in Fengari 0.1.5 after warm-up. The old wrapper allocated 200,000 Lua tables
and 100,000 Lua closures; the revised supported path allocated none. A separate
100,000 idle input-capture check also allocated no Lua tables or closures.

This measures the test VM. It is evidence that the unnecessary allocations were
removed, not a claim about an FPS increase in Darktide. The runtime checks whether
the actual `xpcall` supports arguments and retains a compatible fallback.

## Local game check

The initial local run reached the Mourningstar with the previously saved mod
list. Tertium Fixes was absent from that list. The log showed the older swap and
ability guarantee mods failing to hook `PlayerUnitAbilityExtension.use_ability_charge`,
which is no longer present. After Alt+F4, the engine also reported an unreleased
package and render targets. That run is a baseline, not validation of this update.

The installed unstable.1 build subsequently reached the Mourningstar with
Tertium Fixes enabled. Its native log recorded zero Tertium runtime errors at
the hub snapshot, confirmed the direct protected-call path, and recorded actual
audio-source, rumble and HUD metadata actions. The run also exposed an unavailable
Psykhanium guard: the game now nests its difficulty array under `danger_levels`.
That guard is corrected in unstable.2 and is tested through the real selector.

A later run exposed the Social heading's missing initial count context. The
updated localisation guard repairs that call, and the source regression preserves
normal party updates and unrelated diagnostics. A separate missing skin reference
was traced to the game's current item catalogue and remains outside the repairs.

The mod loader is patched, and the three overlapping guarantee entries are
disabled in both the load order and Mod Framework. FPS Doctor and SMOG were
already disabled. Existing extra-cleanup and notification-suppression choices
have been retained. The prior mod folder, load order and user settings are
backed up.

The new graphics build and DarkCache combination still require their final live
check. The earlier hub success does not establish that the new presets, cache
transitions or every weapon effect work in the engine. No successful mission
or native GPU benchmark is claimed here.

There was no separate game run for unstable.3. The changed input defaults were
checked in the source gate and with the installed Mod Framework options validator.

## Repeating the checks

From the source package, install the locked test dependencies and provide the
extracted game source:

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
$env:DARKTIDE_SOURCE_ROOT = "C:\Darktide-source-1.13.0"
npm.cmd test
```

The recorded extraction used the limn 0.7.2 release and
luajit-decompiler-v2 `1443316` with `-m`. The game source is not included in this
mod archive. Tool documentation is available from
[limn](https://github.com/manshanko/limn) and
[the decompiler release](https://github.com/igromanru/luajit-decompiler-v2/releases/tag/2024-11-30).

The runner requires a successful completion line from every suite. It also
rejects timeouts, stderr errors and skipped source tests; the Lua CLI's exit code
alone is insufficient.

## Remaining limits

The relevant weapon audio and rendering transitions still need checking in the
native client with those weapons equipped. Party Finder tests establish a
specific retained-reference defect, not the cause of every reported menu crash.
The chain-smoke report requires multiplayer conditions and was not reproduced by
a hub load. Server hit registration, account progression, backend connectivity
and native shutdown faults are outside the changes claimed by this release.
