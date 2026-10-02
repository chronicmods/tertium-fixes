Tertium Fixes 0.6.0-unstable.3 for Darktide 1.13.0

Input retries now start off for new installs. Turn on Keep briefly blocked
inputs and the weapon-swap, ability, special, reload or quick Blitz actions you
want to retry. Updating keeps saved choices.

Adds four optional graphics presets: Ultra Performance, Performance, Balanced
and Quality. Performance removes AO and shadows while keeping low fog. Ultra
Performance also removes fog volumes, which can change gas visibility. Higher
tiers retain more lighting detail. Resolution, upscaling, FOV, textures and
combat particles keep their existing settings. Disable More Graphics Options
while using the new presets.

Includes independent buffering for briefly blocked weapon swaps, abilities, weapon
specials, reloads and supported quick Blitz actions. Disable the corresponding
Guarantee Weapon Swap, Guarantee Ability Activation and Guarantee Special Action
mods before using the new options.

Also fixes abandoned Party Finder portraits, Social roster frames reverting to
default, missing initial party-count text, repeated icon/view releases, portrait
and weapon-icon rendering resume, inspection sound loops, and false
force-greatsword charge cues. Existing effect
guards, Stimm Field cleanup, stimm-ready audio, update scheduling, reset and
quarantine handling have been corrected.

Extra Lua garbage collection is off by default for new settings. Previous saved
choices remain in place. If you enable it, disable other automatic Lua memory
cleaners. The current game already manages its own collection.

Replace the old TertiumFixes folder completely. This remains an Optional File;
see the included verification and research notes for the checks and limits.
