# Tertium Fixes

Created and maintained by chronic.

Tertium Fixes puts a collection of client fixes in one place. It covers the
things that get in the way during play: a weapon swap that never happens, menus
holding onto old icons, sounds continuing after a weapon has been put away,
incorrect buff information, and effects trying to use objects that no longer
exist. Every fix has its own option, so you can turn off anything you do not
want or isolate a problem without removing the whole mod.

## The 1.13 update

This version was checked against the scripts from the installed Depths of the
Damned build. The update adds input buffering, several menu repairs and fixes
for weapon sounds after inspecting. It also fixes problems in Tertium Fixes'
own scheduling and cleanup, and recognises Prime Target's official correction.

### Four graphics presets

Ultra Performance, Performance, Balanced and Quality are available in the
Graphics presets group. Turn on Apply graphics preset to use them. They change
the renderer settings behind the effects, including AO, shadows, fog and
lighting additions, while retaining your resolution, upscaler, textures, FOV,
combat particles and existing geometry limits.

Performance switches off AO and shadow passes but keeps low fog volumes. Ultra
Performance removes those volumes too, so fog and gas areas can look different.
Balanced keeps low lighting detail, while Quality uses medium lighting and fog
with sun shadows and light shafts. Ray tracing, screen-space reflections and
costly post effects remain off in all four. Base baked illumination stays on;
this is not a flat unlit view.

Previous values are recorded before applying a preset. Turning the feature off,
or using `/tf_graphics restore`, restores values the preset still owns and keeps
later changes made elsewhere. Applying a preset can briefly pause rendering.
The graphics option is off by default in the download. Disable More Graphics
Options while using it so two preset controllers are not editing the same keys.

The improvement depends on the settings you started with and the scene. A pass
that is already disabled cannot provide another saving. The included graphics
notes list the controls and trade-offs for each preset.

### More reliable inputs

The new input handling keeps a weapon-swap, ability, special, reload or supported
quick Blitz press through a short block instead of immediately forgetting it.
It keeps the request for up to 0.75 seconds and clears it when the action starts
or is cancelled. A quick swap remembers the slot you wanted, rather than
repeatedly cycling weapons.

This uses the game's normal controls and action handling. It does not remove
cooldowns, change ability costs, force an invalid action or repeat an ability
after it has already started. The individual input options can be changed
separately.

Disable Guarantee Weapon Swap, Guarantee Ability Activation and Guarantee
Special Action when using the matching options here. They cover the same
inputs, and the older swap and ability mods call a method removed in 1.13.0.

### Menus that clean up properly

Party Finder now releases the portraits, frames and insignias left behind when
a member leaves or their profile disappears. The Social menu also keeps the
correct equipped frame after a profile refresh, instead of a late cleanup
callback changing it back to the default. Its initial party heading now receives
the missing count values, while normal party updates keep their real counts.

Repeated icon and view cleanup is handled without trying to release the same
reference twice. Portraits and weapon icons can also survive rendering being
disabled and resumed without repeatedly adding to their request names or
losing another widget's shared reference.

The existing cursor, input-device handoff, controller-rumble and Penances wheel
fixes remain. Queued notifications keep their start and completion actions,
and expired buff icons are removed properly. Power Overload's ally buff gets
the missing HUD information. Redirect Fire and Prime Target are already fixed
in the current game, so their older compatibility repairs stay inactive.

### Weapon sounds and effects

Chem-grenade and overheated power-weapon loops can be left at the old sound
source when the camera changes during inspection. The new repair stops the
displaced loop and lets the weapon continue through its normal effect handling.
A force greatsword also keeps its charge-tier bookkeeping when only visibility
has changed, preventing the false charge sound after picking up a stimm.

Other repairs cover affected moving player effects, manual sound sources,
campaign transmission audio, Servo-Skull and arc effects that did not finish
starting, outline recovery after dying in toxic gas, and Stimm Field entries
that still refer to destroyed buff extensions. The personal-stimm ready chime
stays silent on joining or spawning and no longer repeats during prediction
replay.

### Memory and performance

The client-repair work removes unnecessary allocations in regular callbacks and
releases specific resources when their owner is finished with them. The optional
graphics presets control the separate visual changes described above.

Lua memory monitoring stays enabled, but extra garbage collection is now off by
default for new settings. Darktide already manages collection, and adding full
cleanups can cause a pause. Existing saved settings are retained. If you enable
extra cleanup for troubleshooting, disable SMOG, MemLeakFix, FPS Doctor and
other automatic Lua memory cleaners first.

The memory meter marks a fallback capacity with `~`, so an estimate is not
presented as a detected heap limit. It measures Lua memory, not all of the
game's RAM or VRAM.

## Optional settings

Repeated basic notifications can be hidden, mouse-wheel weapon switching can
be blocked while holding the Servo-Skull, and chain-weapon smoke can be removed
aggressively. Those three settings remain off by default because they change
feedback, controls or the normal smoke tail. The experimental effect allocator
and network-effect options are also off by default.

## Installation

Install Darktide Mod Loader and Darktide Mod Framework, then place the complete
TertiumFixes folder in the game's mods folder and add TertiumFixes to
mod_load_order.txt. Close the game before updating and replace the old folder
completely. Saved Mod Framework settings are kept separately.

Use `/tf_status` to see which fixes are active and whether they have done
anything in that session. `/tf_reset module_id` resets a stopped fix; use
`/tf_reset all` for the whole mod. Repeated errors should be investigated before
turning the affected fix back on.

This build remains an Optional File while broader gameplay testing continues.
It addresses specific client faults; server hit registration, connection
outages, progression and native graphics problems still need fixes elsewhere.
The download includes the changes, test record and investigation notes.
