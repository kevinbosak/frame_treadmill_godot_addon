# Frame Walking Game

A mixed reality treadmill game for Steam Frame.

Done so far: passthrough (alpha blend mode on the Frame), the step detector, a settings screen,
the see-through safety bubble, the walking environment (endless dusk forest road), and an
eye-tracking test. Next up: the story director and clues, then a combat encounter prototype.

## Running it on the Frame

1. Start **Lepton Development** on the Frame.
2. On the Mac: `~/Library/Android/sdk/platform-tools/adb connect <frame-ip>:5555`
   If you get "no route to host": run `adb kill-server`, connect again, and check
   **System Settings → Privacy & Security → Local Network** for Godot and Terminal.
3. In Godot: **Remote Deploy → Steam Frame Lepton**.

## Controls (either controller)

| Button | Does |
|---|---|
| **B / Y** | Open or close **Settings**. Also cancels measuring. |
| **Trigger** | Clicks when pointing at Settings. Records a point while measuring. Otherwise switches between **Passthrough** and **World** view. |
| **A / X** | Quick calibrate at the speed set in Settings. |

## First-time setup (do this before walking in World view)

1. Open **Settings → Measure treadmill**. Step off the treadmill and follow the prompts. Touch a
   controller tip to the belt's **front-left corner** and pull that controller's trigger, then the
   **front-right corner**, then **anywhere along the back end**. A yellow dot marks each recorded point.
2. Close Settings and pull the trigger to switch to **World view**. A placeholder world (grid, sky,
   pillars) appears, and the treadmill area stays see-through, showing the real belt, rails,
   console and your hands.
3. Stride calibration lives in **Settings → Stride calibration**: set the treadmill speed, walk
   steadily until it says "ready to calibrate", then press **Calibrate at this speed**. Repeat at a few speeds.

All settings are saved on the headset: the treadmill measurement, calibration, safety margins,
see-through height and step graph.

## The walking world and the eye-tracking test

In **World view** you walk an endless forest road at dusk. It moves at your measured walking speed
and starts at the treadmill, heading the way you face. The road is built from 30 m stretches that
are recycled as you pass them, so it never ends.

**Eye-tracking test:** each stretch has one rune-marked **waystone**. It might be a stone by the
road, a rune in the grass, or a charm hanging in a tree. Look at one for about half a second and
it turns gold with a chime. The walking panel shows **Waystones noticed X of Y passed** and the
**Gaze** source:

- `eye tracking`: the Frame's eye tracker is working.
- `head direction`: eye tracking isn't reaching the app, so it falls back to where your head points.
  See **Settings → Headset** for which step is failing (below).

The **reticle** is a broken ring around where you're looking, with an empty middle, so it never
covers what you're looking at. On a waystone it wraps the object, and an outer arc fills as you
keep looking. You can turn it off in **Settings → Display and sound**; noticing still works.

Also in Settings: **Footstep sounds** (a gravel crunch on each detected step, World view only).
The panel shows today's and all-time distance (saved) and the frame rate.

The eye gaze setting is on in `project.godot` (XR → OpenXR → Extensions → Eye Gaze Interaction).
The Android export preset asks for the eye-tracking permissions (`EYE_TRACKING_FINE`/`COARSE`, and
Meta's `EYE_TRACKING`), and the app requests them at startup.

### Settings → Headset

- **Display refresh rate:** step through the rates the headset offers. It's saved.
- **Eye tracking diagnostics**, in order. The first "NO" is where it breaks:
  1. **Runtime offers eye gaze:** the headset's OpenXR runtime supports `XR_EXT_eye_gaze_interaction` for this app.
  2. **Eye tracker registered:** Godot set up the eye input.
  3. **Eye tracker sending data:** gaze data is actually arriving.
  4. **Eye permissions granted** (Android build).

The same report is written to the log at startup: `adb logcat -s godot | grep headset`.

## What to check on the headset

- **Bubble position:** does the see-through area line up with the real treadmill and include the
  rails and console? If it's shifted, re-measure. If it's the right place but too small or too big,
  tell me which side.
- **See-through height** (Settings, default 1.10 m above the belt): you should look *down* into the
  real treadmill and *ahead* into the virtual world. Raise it if the console gets cut off; lower it
  if the room shows when you look ahead.
- **Settings screen:** is the text readable, and do the buttons respond reliably to the laser?
- **Edge warnings** (only while walking): the Sides, Back and Front distances are in Settings.
- **World view:** is it comfortable to walk in? Does the speed feel right? What frame rate does the panel show?
- **Gaze:** does the panel say `eye tracking`? Does the reticle follow your eyes closely? Is half a
  second of looking about right to count as noticing?
- **After a restart:** is the bubble still in the right place? If the headset's tracking origin
  changes between sessions, it won't be, and we'll add a quick re-align.

## Without the headset (F5 in Godot)

**Tab** settings (click with the mouse) · **F** pretend treadmill under you · **T** switch view ·
the **mouse is your gaze** (point at waystones) ·
**W** simulated walking · **[ / ]** simulated cadence · **Up/Down** look up/down · **C** quick calibrate.
On the Mac the see-through area shows as black.

## Tests

```bash
godot --headless --script res://tests/test_step_detector.gd
godot --headless --script res://tests/test_footprint.gd
godot --headless --script res://tests/test_gaze.gd
```

## Files

| File | Purpose |
|---|---|
| `main.gd` / `main.tscn` | Scene, views, controls, measuring flow, HUD |
| `treadmill.gd` | Treadmill service: steps, speed, edge warnings, all saved settings |
| `treadmill_footprint.gd` | Belt position and size from the three touched points |
| `passthrough_bubble.gd` | See-through box around the treadmill |
| `settings_menu.gd` | The Settings screen (Treadmill, Stride, Display, Headset tabs) |
| `ui_panel_3d.gd` / `xr_pointer.gd` | 2D UI on a 3D panel, and the laser pointer |
| `path_world.gd` | The endless path: moves and recycles 30 m stretches at your speed |
| `forest_theme.gd` | The dusk forest look: sky, fog, light, ground, trees, lanterns, waystones. A new setting = a new theme file. |
| `gaze_tracker.gd` / `gaze_target.gd` / `gaze_reticle.gd` | Where you're looking, what counts as noticed, the reticle |
| `sounds.gd` | Footstep and chime sounds, made in code |
| `test_world.gd` | No longer used (the old placeholder world); safe to delete |
| `step_detector.gd` / `stride_calibration.gd` / `bob_waveform.gd` | Step counting, stride learning, step graph |
| `tests/` | Headless tests |
