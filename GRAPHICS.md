# Graphics presets

Tertium Fixes provides four presets under **F4 → Tertium Fixes → Graphics presets**.
Turn on **Apply graphics preset**, then choose Ultra Performance, Performance,
Balanced or Quality. The option is off by default in the download, so installing
the client fixes does not immediately change the picture.

The presets target ambient occlusion, shadows, volumetric lighting, reflections
and post-processing. They keep resolution, DLSS/FSR/XeSS selection, frame
generation, field of view, textures, combat particles, outlines, object detail,
corpses and decals at their existing settings.

| Feature | Ultra Performance | Performance | Balanced | Quality |
| --- | --- | --- | --- | --- |
| Ambient occlusion | Off | Off | Low | Medium |
| Local and static shadows | Off | Off | Low | Medium |
| Dynamic sun shadows | Off | Off | Off | On |
| Fog volumes | Off | Low | Low | Medium |
| Light shafts and local fog lighting | Off | Off | Off | On |
| Baked illumination | Low | Low | Low | High |
| Ray tracing and screen-space reflections | Off | Off | Off | Off |
| Bloom, blur, depth of field, lens effects and skin scattering | Off | Off | Off | Off |

**Ultra Performance** makes the strongest cuts. Removing fog volumes changes
the atmosphere and can also change how toxic-gas areas look, because those areas
use the same volume system. It is a visible trade-off.

**Performance** removes AO and shadow passes while keeping the lowest stock fog
volumes. It is the better starting point when you want to reduce lighting cost
without removing those fog cues.

**Balanced** keeps low AO, local/static shadows and fog. **Quality** brings those
up to the stock medium levels and restores sun shadows, light shafts and local
volumetric lighting. Both keep ray tracing, reflections and the listed post
effects off.

Base baked illumination stays enabled so rooms remain readable. These are
lighting and effect presets, not a flat unlit rendering mode. Turning down a
feature that is already off cannot produce another saving. The gain also depends
on whether a particular scene is limited by graphics work, CPU work or something
else; no fixed FPS increase is promised.

## Applying and restoring

The preset uses the game's setting setters and applies changes in a batch. A
change can briefly pause rendering while the engine updates its settings and
shadow resources. There is no settings loop running every frame.

Before changing a setting, the mod records its saved value and its readable
effective renderer value. It restores values it still owns when you switch to a
preset that no longer controls them or turn the feature off. A later manual or
mod change is preserved. If a value has no readable original, it is left alone.
Where only the effective original is available, restoration may write that
captured value explicitly rather than removing the saved key.

Use **Apply graphics preset → Off** or `/tf_graphics restore` to restore captured
settings. `/tf_graphics` reports the selected preset and change counts.

The previous values are saved before changes begin. An interrupted change keeps
its recovery record. During shutdown or mod unload the saved values are restored
without trying to rebuild renderer resources in a closing world; a later safe
initialisation completes any native restoration still required.

## Other graphics mods

Disable **More Graphics Options** while using these presets, or leave Tertium's
graphics option off and manage the settings there. Both edit the same rendering
settings. Tertium does not continually overwrite values changed elsewhere, but
using two preset controllers makes the resulting configuration harder to predict.

DarkCache does not select graphics settings. Its icon cache must release its own
references when the renderer changes, while leaving normal UI ownership intact.
The combined build's verification record states which of those paths have been
tested in the engine.

## Checking a preset

Use the same location, direction of view, resolution and upscaler when comparing
presets. Let asset loading settle first. Check both the Mourningstar and a busy
gameplay scene; a hub measurement alone does not establish mission performance.
Pay attention to frame-time consistency as well as the FPS counter, and check
fog/gas visibility before keeping Ultra Performance enabled.

The values come from the installed 1.13.0 settings definitions and the supported
renderer flags. Source and controller tests check the four profiles, application,
restoration, failures and interaction with other settings writers. Native GPU
timing and the visual result still need a live test on the selected hardware.
