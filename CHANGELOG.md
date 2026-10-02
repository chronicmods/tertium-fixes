# Changes

## 0.6.0-unstable.3

- Input retries now start off for new installs, including the weapon-swap,
  ability and special-action replacements. Reload and quick Blitz retries also
  start off. Turn on **Keep briefly blocked inputs** and the actions you want
  to retry in Mod Options. Existing saved choices are kept.

## 0.6.0-unstable.2

- Added Ultra Performance, Performance, Balanced and Quality graphics presets,
  using the current engine settings. The graphics option is opt-in in the public
  download and preserves display, upscaling, textures and combat particles.
- Added saved-setting recovery and restoration for preset changes, disable,
  reload and partial failures. Later changes by other settings writers are kept.
- Stopped input retries while a HUD overlay or ImGui owns input, including when
  ChatBlock keeps the normal gameplay input service active.
- Updated the Psykhanium guard for the current nested `danger_levels` table.
- Fixed the Social menu's missing initial party-count context while preserving
  later live counts and unrelated localisation errors.

Ultra Performance removes fog volumes and can change gas visibility. Performance
retains those volumes. Neither preset substitutes a flat unlit rendering mode.

## 0.6.0-unstable.1

Updated for Darktide 1.13.0, using the scripts from the installed build.

- Added independent buffering for briefly blocked weapon swaps, combat
  abilities, weapon specials, reloads and supported quick Blitz actions. The
  options are separate and stop retrying on success, cancellation or expiry.
- Released portraits, frames and insignias left by empty Party Finder slots.
- Fixed Social roster frame cleanup overwriting a newly loaded frame.
- Fixed portrait and weapon-icon request handling when rendering resumes,
  including shared references released while rendering is disabled.
- Guarded duplicate or stale icon and view releases while preserving normal
  callbacks and package delays.
- Fixed displaced chem-grenade sound loops, power-weapon lockout audio left
  after camera changes or destruction, and false force-greatsword charge cues
  after visibility refreshes.
- Extended Servo-Skull and arc-effect guards to missing movement extensions,
  deleted cached extensions and stale game-session data.
- Extended Stimm Field cleanup to normal departure and re-entry, and prevented
  the stimm-ready cue replaying during prediction corrections.
- Kept an old player's late gas stop from changing a replacement player's
  outline state.
- Recognised Prime Target's official fix. Its older fallback and Redirect
  Fire's fallback leave the current correct metadata unchanged.
- Restored old template edits before applying a replacement, and corrected
  reset and early-enable behaviour for affected modules.
- Fixed skipped scheduled updates, time counted twice, and repeated cleanup
  during error handling. Quarantine now releases a fix's owned changes.
- Removed temporary allocations from supported protected calls while preserving
  nil arguments and all return values.
- Set extra Lua garbage collection to off for new settings. Corrected partial
  collector restoration, monitoring state and estimated-capacity display.
- Grouped the options by purpose and rewrote the descriptions and documentation.
- Added tests that execute the affected installed game classes, and pinned the
  source used by the checks. Test runs reject incomplete or skipped suites.

The existing smoke removal, notification suppression, Servo-Skull wheel
isolation and experimental effect options remain opt-in. Previously saved
settings are retained. The new input code replaces the matching guarantee
options; disable those older mods to avoid overlapping requests.
