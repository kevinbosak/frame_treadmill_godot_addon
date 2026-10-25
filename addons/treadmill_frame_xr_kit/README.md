# Treadmill Frame XR Kit

Building blocks for treadmill VR games on **Steam Frame**, for **Godot 4.7** (OpenXR, Mobile renderer).

You walk on a real treadmill; the kit turns your head bob into steps and speed, keeps you safe
(a see-through window onto the real treadmill, plus edge warnings), and moves a virtual world past
you at your real walking speed. Your game supplies the world and the gameplay.

License: MIT (see `LICENSE`).

## What's in it

| Piece | Class / file | What it does |
|---|---|---|
| Rig | `TFXRig` · `rig/tfx_rig.tscn` | Drop-in scene: headset, controllers, passthrough, views, walking panel (HUD), settings, measuring, warnings, gaze, footsteps |
| Treadmill service | `TFXTreadmill` · `core/` | Steps, cadence, smoothed speed, distances, edge warnings, all kit settings (saved) |
| Step detector | `TFXStepDetector` | Head bob to steps and cadence; ignores swaying and looking around |
| Stride calibration | `TFXStrideCalibration` | Learns step length per cadence from known treadmill speeds |
| Treadmill footprint | `TFXFootprint` | Belt position and size from three touched points |
| Safety bubble | `TFXPassthroughBubble` · `rig/` | See-through box around the treadmill in World view |
| Settings screen | `TFXSettingsMenu` · `ui/` | Tabs: Treadmill, Stride, Display, Sound, Headset, plus your own |
| 3D UI + pointer | `TFXUiPanel3D`, `TFXPointer` | Any Control UI on a panel in 3D, with laser pointers |
| Step graph | `TFXBobWaveform` | Live head bob graph on the walking panel |
| Gaze | `TFXGazeTracker`, `TFXGazeTarget`, `TFXGazeReticle` · `gaze/` | What you're looking at (eyes, then head direction, then mouse), noticing by dwell, a reticle that never covers the target |
| Path world | `TFXPathWorld`, `TFXPathTheme` · `world/` | Endless recycled path that moves at your speed; themes decide the look |
| Audio | `TFXAudio` · `audio/` | Buses (Ambience, World, Effects), volumes, muting outside World view, pool of binaural processors |
| Spatial sound | `TFXSpatialSound` · `audio/` | A positional sound you can place by ear: per-ear delay and behind-the-head muffling on top of Godot's 3D audio |
| Sounds | `TFXSounds` · `audio/` | Footstep and chime sounds made in code |

## Quick start

1. Copy `addons/treadmill_frame_xr_kit/` into your project and enable it in
   **Project Settings → Plugins**. It sets the OpenXR settings it needs and prints a checklist.
   Make sure the default `openxr_action_map.tres` exists; Godot creates it when OpenXR is on.
2. Instance `rig/tfx_rig.tscn` in your main scene. The rig owns the `WorldEnvironment`, so don't add another.
3. Give it a world:

```gdscript
extends Node3D

@onready var rig: TFXRig = $TFXRig

func _ready() -> void:
	var world := TFXPathWorld.new()
	add_child(world)
	world.setup(MyTheme.new())      # or world.setup() for the plain built-in look
	rig.world_root = world
	rig.treadmill.step_taken.connect(func() -> void: print("step"))

func _process(_delta: float) -> void:
	rig.hud_extra_lines = ["Score %d" % score]
```

See `res://demo/forest_walk.gd` in the template for a complete example.

## Player controls

| Button | Does |
|---|---|
| B / Y | Settings (also cancels measuring) |
| Trigger | Click a panel · record a point while measuring · otherwise switch Passthrough / World view |
| A / X | Quick calibrate at the speed set in Settings → Stride |

Change them with the rig's `settings_button`, `view_button` and `calibrate_button` exports
(OpenXR action names). World view only turns on once the treadmill is measured
(Settings → Treadmill → Measure treadmill).

Desktop preview keys: **Tab** settings, **T** view, **F** pretend treadmill, **W** simulated
walking, **[ / ]** simulated cadence, **Up/Down** look, **C** calibrate. The mouse is the gaze.

## Reference

### TFXRig
- `world_root: Node3D`: shown in World view. A `TFXPathWorld` is lined up with the treadmill,
  gets its theme's environment, and is fed the walking speed automatically.
- `hud_extra_lines: PackedStringArray`: your lines on the walking panel.
- `treadmill`, `gaze`, `settings_menu`, `xr_camera`, `controllers`, `world_env`: the parts.
- `set_world_view(on)`, `open_settings()`, `close_settings()`, `start_measuring()`, `toast(text)`.
- Signals: `view_changed(world_view)`, `treadmill_measured(footprint)`.

### TFXTreadmill
- Live: `speed_mps` (smoothed), `speed_mph()`, `detector.cadence_spm`, `detector.step_count`,
  `stepped_this_frame`, `head`, `edge_warning`, `session_distance`, `lifetime_distance`, `footprint`.
- Signals: `step_taken`, `edge_warning_changed(message)`, `settings_changed`.
- Settings are saved to `user://treadmill_frame_xr_kit.cfg`. Game settings belong in your own file.

### TFXPathWorld and TFXPathTheme
- The path runs along local −Z; chunks (`chunk_length`, `chunks_behind`, `chunks_ahead`) are
  recycled as you pass them. Signal `target_passed(target)` fires for gaze targets you walk past.
- Subclass `TFXPathTheme` and override:
  - `build_backdrop(parent)`: sky, far scenery, lights (doesn't scroll). The sky must be opaque;
    use `make_sky_dome()`.
  - `apply_environment(env)`: fog, ambient light.
  - `populate(chunk, index, length) -> Array[TFXGazeTarget]`: one stretch of path, local z from 0
    to −length. The same index must give the same scenery.
  - Helpers: `make_ground()` (shaders can use `instance uniform float path_offset`),
    `make_sky_dome()`, `add_multimesh()`.

### Gaze
- Add a `TFXGazeTarget` node (set `radius`, `dwell_required`, `max_distance`, optional
  `glow_material`) anywhere in the scene. It counts as noticed after its dwell time.
- `rig.gaze.target_noticed(target)`; `rig.gaze.source` is "eye tracking", "head direction" or "mouse".
  Head direction gets a wider tolerance (4° instead of 2°).

### Sound
- **Buses:** `TFXAudio.AMBIENCE` for background beds (not positional), `TFXAudio.WORLD` for
  positional sounds (with a light outdoor reverb), and `TFXAudio.EFFECTS` for footsteps and
  interface sounds. Ambience and World are muted outside World view. Volumes and the binaural
  switch are in Settings → Sound and saved.
- **Positional sounds:** use `TFXSpatialSound` instead of `AudioStreamPlayer3D`. It routes to the
  World bus and, while playing within `binaural_range` (25 m), borrows one of 12 binaural
  processors. Each one:
  - delays the far ear by up to ~0.65 ms (Woodworth head model): the time difference between ears,
  - muffles sounds behind you (low-pass down to 3.5 kHz): front versus back,
  - with Godot's own panning (set to about 9 dB between ears for a sound at the side), distance
    falloff, air absorption and Doppler.
  It's an approximation, not full HRTF: elevation cues are weak. A Steam Audio GDExtension doesn't
  exist yet for Android arm64, the Frame's build target. `TFXSpatialSound.cues_for()` is the model
  if you want to tune it.

```gdscript
var buzz := TFXSpatialSound.new()
buzz.stream = preload("res://sounds/bee.wav")   # a looping mono sound
buzz.unit_size = 1.2                             # loudness: about 0 dB at this distance
buzz.autoplay = true
bee.add_child(buzz)
```

Use mono sound files for positional sounds; a stereo file can't be placed.

### Settings screen
```gdscript
var tab := rig.settings_menu.add_tab("My game")
rig.settings_menu.add_heading(tab, "Difficulty")
rig.settings_menu.add_toggle(tab, "Hard mode", hard, func(on: bool) -> void: hard = on)
rig.settings_menu.add_stepper(tab, "Enemies", 1, 1, 10, func() -> float: return count,
		func(v: float) -> void: count = int(v), func(v: float) -> String: return str(int(v)))
rig.settings_menu.add_button(tab, "Reset", reset)
```

## Rendering order (if you add transparent things)

The bubble draws at render priority 100, after the world, so it can erase it. The walking panel
(110–116), reticle (120) and prompts (127) draw on top of it with depth testing off. Keep your own
always-visible overlays above 100.

## Tests

```bash
godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_step_detector.gd
godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_footprint.gd
godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_gaze.gd
godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_spatial_audio.gd
```
The spatial audio test captures Godot's actual output for a sound at your right: about 9 dB louder
in the right ear and 0.63 ms later in the left; behind you it comes out duller.

## Known limits

- Eye tracking isn't offered to Android (Lepton) builds on Steam Frame as of SteamOS 0.3/0.4.
  Gaze falls back to head direction; a native Linux arm64 build is untested.
- Passthrough uses the alpha blend mode; it's grayscale unless the Arcturus colour camera is fitted.
- If the headset's tracking origin changes between sessions, re-measure the treadmill.
