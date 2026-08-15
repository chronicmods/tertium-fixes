UNSTABLE PREVIEW - DARKTIDE 1.12.4

This is a separate testing build. It does not replace the 0.5.1 Main file.

Compatibility requirement: disable SMOG, MemLeakFix, FPS Doctor, and any other
mod that performs automatic Lua memory cleaning or garbage collection, then
restart Darktide. Run only one cleanup controller at a time.

What changed:

- Updated the source-contract audit to Darktide 1.12.4.
- Preserved the new notification `start_callback` argument through the complete
  call, then added a separate repair for start/completion callbacks that 1.12.4
  drops while draining a full notification feed's overflow queue.
- Notification deduplication is now an optional, default-off behaviour. Calls
  with callbacks or timing always pass through, but even a callback-free repeat
  can still be useful feedback.
- Darktide fixed Redirect Fire upstream. This build detects that, reports
  `fixed upstream`, and does not pretend to patch it.
- The Path 09 fallback remains narrowly scoped because the 1.12.4 notes fix a
  matching general cutscene-fade symptom without naming that exact scene.
- Servo-Skull wheel isolation remains a separate stronger opt-in control
  preference, not a claim that the game's wheel-bound activation fix failed.
- I investigated reported ghost hits on Rashad and Atrox axes. There is no
  client-side damage patch in this build because Darktide's server owns damage
  and hit confirmation; changing local hitboxes could only create false impact
  feedback without making a rejected hit deal damage.
- Every one of the 25 modules has an executable behavior case that checks
  an actual state change or cleanup, plus its guarded/no-op path where relevant.
- Twenty-two module switches are on by default; the three tradeoff-bearing
  behaviours are opt-in. The complete source and behavior gates are repeated
  against the extracted archive before publication.

This still needs wider live-game soak, which is why it is an Optional File and
why the GitHub work stays on the `unstable` branch. If something acts up, run
`/tf_status`; the hit and action counters show whether a repair actually fired.

Install it by deleting the old `TertiumFixes` folder and replacing it with the
folder from this archive. Do not merge the two versions.
