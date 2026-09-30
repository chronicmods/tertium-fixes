# Investigation notes

The update was checked against the scripts extracted from Darktide
**1.13.0-b802981**, Steam build **25492122**, content revision **138030**. The
public source repository had not yet reached this version when the work began.
The local extraction produced 10,550 readable Lua files. Two unrelated files
could not be decompiled: one expedition mission theme and the transonic
sword/knife damage profiles. Neither is used by these repairs.

The review screened 150 official bug topics created between 11 August and
29 September 2026, read 20 selected report threads, checked the current patch
notes, and followed the relevant calls through the installed scripts. Screening
a report title is not the same as reproducing its fault. The findings below
identify which problems were reproduced in Lua, which existing fixes still
apply, and which reports remain unresolved.

## New menu fixes

**Party Finder retained departed members' icons.**
`GroupFinderView._update_listed_group` marks an empty member slot as unfilled
without releasing its portrait, frame or insignia. `on_exit` releases only
filled slots, and a later member can overwrite the old IDs. The test loads a
member through the real game method, removes that member and exits; the three
old references remain. The repair calls the game's existing icon cleanup for
an explicitly empty slot that still owns those IDs. It also handles a temporarily
missing profile and a later return.

The [Party Finder memory report](https://forums.fatsharkgames.com/t/memory-leak-in-party-finder/125510)
describes hub crashes and slower menus after repeated use. The retained icon
owners are a demonstrated defect. This does not establish that they explain
every crash in that report or quantify how much native memory a session saves.

**The Social roster cleared its replacement frame.**
`SocialMenuRosterView._update_portrait_frame` queues the old icon for cleanup,
then loads a replacement. A cached icon resolves immediately. The old queued
callback subsequently writes the default frame over the new texture. The
repair runs that newly queued zero-delay frame cleanup before its replacement
can resolve. The item loader's two-frame package delay is retained.

This matches the ordering described in the acknowledged
[Social roster report](https://forums.fatsharkgames.com/t/social-menu-roster-shows-the-default-portrait-frame-instead-of-the-equipped-one/125142).
Tests cover a cached replacement, an uncached replacement, the same frame
package, closing during loading and another mod changing the unload delay.

**The Social menu's initial party heading lacked its count values.**
The later local game run logged missing `num_party_members` and
`max_num_party_members` values. The current roster definition calls
`Localize("loc_social_menu_party_header")` without context, even though it sets
the initial count and maximum in the widget content below that call. The existing
localisation guard now supplies the empty-party context only for that exact key
when context is absent, taking the maximum from the game's Social menu settings.

The current localisation manager writes a cache entry even when `no_cache` is
true. The repair therefore restores the previous cached value after building the
initial heading. Source tests reproduce both stock errors, then verify the
repaired definition and real roster updates from zero to four members and back.
Supplied context and unrelated localisation errors remain unchanged.

**Rendering resume could generate new icon requests while iterating them.**
The portrait and weapon-icon classes pass a complete request ID back into a
generator that appends its size suffix again. The resumed call can therefore
create another request in the table being traversed. The original source test
reaches its bounded reproduction limit; the fixed test keeps one request with
the correct owners and render job through repeated cycles. Existing IDs that
happen to contain size-like text and different render sizes are covered.

The same classes also lose a surviving shared owner if one reference is released
while rendering is disabled: the lookup retains owners, but the array used to
decide whether the request is empty has been drained. The repair reconciles
those owners before a real release. Suspension itself still uses the original
`keep_reference` behaviour.

These hooks target the actual portrait and weapon classes. Darktide copies base
methods into subclasses, so a late hook on the base class alone would miss them.

**Repeated cleanup could dereference missing data.**
Item-icon release retains an ID during its two-frame delay. A second normal
UIManager release passes `has_request`, queues the ID again, and later tries to
release data removed by the first entry. Rendered-icon cleanup has a similar
missing-reference case. View cleanup handles a missing view but not a missing
owner inside an existing view table. Tests reproduce all three cases through
the installed classes. The guards leave valid owners, callbacks and delays
with the original game methods.

## Weapon sounds and effect state

The [inspection audio report](https://forums.fatsharkgames.com/t/persistent-sounds-after-inspecting-certain-weapons/125174)
names chem grenades and overheated power blades. Their current source contains
two matching faults. Chem-grenade stop logic resolves a sound source that may
have moved since the looping sound started. Power-weapon lockout audio is not
stopped by its destroy method or camera callback. The repair tracks and stops
the affected playing IDs while leaving shared sound sources under game ownership.
Normal updates restart a still-needed loop on its current source.

The [force greatsword stimm report](https://forums.fatsharkgames.com/t/force-greatsword-misplays-charging-sound-when-picking-up-stimms/125507)
matches a separate bookkeeping fault. A visibility refresh resets the remembered
charge tier to low, making unchanged charges look like a new tier on the next
update. The repair retains the recognised tier when no charge count changed.
It does not add, remove or spend charges.

Source tests keep the stock counterexamples beside the repaired sequences.
Native sound and rendering functions are represented by test doubles, so those
tests establish the script ordering and resource ownership. Hearing the effects
with the relevant weapons still requires a live session. A native stop failure
during final destruction cannot be promised a later retry when the object will
no longer update.

The existing Servo-Skull and arc guards were checked against all six affected
templates. They now cover a missing movement extension before sound starts,
deleted cached extensions, and a changed game session or object ID. Cleanup
uses the world that owns the effect. A guard enabled before its game file loads
waits for that file instead of permanently marking itself unavailable.

Stimm Field cleanup now also covers normal departure and re-entry. Only a row
whose saved buff extension has the game's deleted flag is discarded. The current
source already passes the argument missing in the older
[Stimm Supply report](https://forums.fatsharkgames.com/t/stimm-supply-w-fast-acting-stimms-can-apply-cartel-stimm-buffs-while-cartel-stimm-is-on-cooldown/116779),
so no cooldown, stacking or talent-effect change was added for that report.

The ready chime ignores prediction replay and begins a silent baseline when an
ability is temporarily disabled. Dead-player gas cleanup also checks whether a
new local player unit already exists, preventing an old body's late stop from
changing the new player's outline state.

## Input handling

The local baseline log confirmed that the installed swap and ability guarantee
mods try to hook `PlayerUnitAbilityExtension.use_ability_charge`, which is absent
in 1.13.0. Their intended behaviour was checked from descriptions and settings;
their implementations were not used for the new code.

The replacement follows `HumanInputHandler`, the action-input parsers, the
visual-loadout slot helpers and `ActionHandler.start_action` in the current
game. Retries enter the normal local input cache before its ordinary network
update. The module does not call an ability, spend a charge or start an action
directly. It retains a short user intention, waits while the native parser
already holds that input, and stops on acknowledgement, cancellation or expiry.
Each action family has its own setting.

The later compatibility check found that ChatBlock can leave the gameplay input
service active while a HUD overlay owns input. Retry capture now also observes
the broader UI and ImGui input-ownership flags. Pending presses are discarded
while an overlay owns input and do not return when it closes.

## Graphics presets

The four profile definitions use the current game's renderer keys and the
stock Low/Medium lighting and fog payloads. They disable specific lighting and
effect passes rather than claiming an unsupported global unlit mode. Ultra
Performance turns off general fog volumes; the same volume system is used by
toxic gas, so that trade-off is stated in the options and [GRAPHICS.md](GRAPHICS.md).

The controller saves a recovery record before changing values. It distinguishes
saved values from effective renderer values, restores omitted keys on a profile
switch, and keeps later changes by another writer. The global renderer apply can
otherwise reset a live override even when that key was not part of the preset.
Temporary pass-through values preserve those overrides around the batch apply,
with their own recovery records if the operation is interrupted.

The graphics tests reproduce partial setting failures, failed saves, interrupted
restoration, false-valued settings, different saved/live originals, and reload
after a saved-only shutdown restoration. They verify the setter/apply/shadow-bake
event sequence against the installed helper functions. They do not measure GPU
performance or establish an FPS gain.

The local configuration already had most expensive passes disabled. Its clear
remaining reductions included AO and, in Ultra Performance, fog volumes. The
saved master fog label said off while its saved renderer volume flag was still
enabled. Profile labels alone were therefore not treated as proof of a disabled
rendering pass.

## Runtime and memory

The mod's update loop could skip the next module when quarantine rebuilt its
list during iteration. Interval remainders were also counted again as elapsed
time. The loop now finishes a stable list and tracks actual elapsed time
separately from its scheduling remainder.

Quarantine and unavailability release owned changes. Reset re-evaluates them;
a failed reset remains disabled. The affected HUD, talent and Servo-Skull input
repairs restore their old template edits before applying a replacement. Prime
Target recognises the 1.13.0 correction,
and Redirect Fire continues to recognise its earlier official fix.

The protected-call path avoids its old temporary argument/result tables when
the current `xpcall` supports arguments. It probes the actual callable because
Darktide may replace it with `Script.xpcall`. Nil arguments and multiple returns
are preserved, including on the fallback path.

Darktide configures its own garbage collector during boot. The inspected defaults
give it a 0.5–1 ms collection budget. Extra collection therefore starts disabled
for new mod settings. The optional controller now completes a partial tuning
restoration before taking ownership again, rejects nonfinite counts/capacities,
and avoids accumulating cleanup pressure while merely monitoring.

## Reports left without a new gameplay patch

The later local run also logged a missing
`content/items/weapons/player/skins/mo_1507_camo_38` item during remote-profile
loading. Fatshark's cached master-items catalogue for revision 138030 has no
definition for that path, but `stub_pistol_p1_deluxe01_ver01` and
`stub_pistol_p1_m1_ver01` reference it in their shared material attachments.
This is a catalogue inconsistency. Neither mod substitutes an invented item or
claims to repair that warning.

| Report | Finding and remaining limit |
| --- | --- |
| [Disrupt Destiny in the Psykhanium](https://forums.fatsharkgames.com/t/125981) | Target selection requires a qualifying breed, a forward cone and enemy perception line of sight. No change was made to the selected target or its buff rewards. |
| [Executioner's Stance highlights](https://forums.fatsharkgames.com/t/125927) | The buff takes a target list and reveals it over time. The report does not establish a safe intended rule for adding new enemies to it. |
| [Chordclaw and Plasma Gun charge feedback](https://forums.fatsharkgames.com/t/124992) | The visual/audio code reads a shared charge component. Resetting it from an effect hook would also change gameplay state. |
| [Huntsman reload and aiming](https://forums.fatsharkgames.com/t/125979) | The report involves coupled attack, reload and aim state. Input buffering is not presented as a fix for those weapon animation transitions. |
| [Chain-weapon sticky kills and audio](https://forums.fatsharkgames.com/t/125960) | The talent refresh and sticky-attack audio need their own verified cause. No damage or talent-refresh patch is claimed. |
| [Operative Stats movement modifiers](https://forums.fatsharkgames.com/t/125973) | Fatshark identified the current display as intended and took the request as UI feedback. |
| [Zealot talent reset](https://forums.fatsharkgames.com/t/125992) | Fatshark confirms partial loadout resets are expected after the tree changes. The mod does not reconstruct or spend talent points. |
| [Missing keystone allocation](https://forums.fatsharkgames.com/t/125971) | A saved-build migration report is insufficient evidence for a client account-data repair. |
| [Chat disappears](https://forums.fatsharkgames.com/t/125829) and [broken chat](https://forums.fatsharkgames.com/t/125532) | Service/channel failures were not reproduced as a local rendering fault. |
| [Backend sign-in error](https://forums.fatsharkgames.com/t/125994) | No client-side service or account repair is claimed. |
| [Advanced Combat Doctrines targeting allies](https://forums.fatsharkgames.com/t/125895) | This affects selected targets and shots. No local outline-only change is presented as a repair. |
| [Alt+F4 crash](https://forums.fatsharkgames.com/t/125417) | The local baseline had a package-unload exception and retained render targets at shutdown. It did not establish a causal link to a particular Lua callback. No blanket shutdown suppression was added. |

The current patch notes also list official corrections to outlines, heavy-attack
cancellation, several talent descriptions and other systems. Those notes were
checked alongside the code rather than treated as proof that every report with
a similar symptom was resolved. See
[Depths of the Damned patch notes](https://www.playdarktide.com/news/depths-of-the-damned-free-update-out-now).

The exact source hashes used by the checks are in `tests/source_manifest.json`.
The build checks reject missing or different source files and do not accept
skipped source suites. The live test record and remaining verification are in
[VERIFICATION.md](VERIFICATION.md).
