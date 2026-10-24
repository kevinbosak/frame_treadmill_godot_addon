# Frame Walking Game

Treadmill VR games for Steam Frame, built on **Treadmill Frame XR Kit**
(`addons/treadmill_frame_xr_kit/`, MIT). This repo is both the kit's home and a starting template.

- **The kit:** everything reusable. See `addons/treadmill_frame_xr_kit/README.md`.
- **The demo:** `demo/forest_walk.tscn`, an endless dusk forest road with a waystone gaze test.
  It's the main scene, and a worked example of using the kit.

## Starting a new treadmill game from this template

1. Copy the repo (or use it as a GitHub template). Keep `addons/`, `project.godot`,
   `export_presets.cfg` and `openxr_action_map.tres`.
2. Make your main scene: instance `addons/treadmill_frame_xr_kit/rig/tfx_rig.tscn` and give it a
   world (see the kit README). Set it as the main scene in Project Settings.
3. Delete `demo/` when you no longer need the example. Rename the project in Project Settings and
   change the Android package name in the export preset.

To add treadmill support to another existing project, copy just `addons/treadmill_frame_xr_kit/`.

## Running on the Frame (from a Mac, Android build)

1. On the Frame: Developer Mode on, then start **Lepton Development** from the Steam library.
2. On the Mac: `~/Library/Android/sdk/platform-tools/adb connect <frame-ip>:5555`
   If you get "no route to host": run `adb kill-server`, connect again, and check
   **System Settings → Privacy & Security → Local Network** for Godot and Terminal.
3. In Godot: **Remote Deploy → Steam Frame Lepton**. The "SteamFrame" Android preset has Gradle build,
   OpenXR, arm64 and the eye-tracking permissions.

The "Steam Frame Arm64" Linux preset is for native builds, uploaded with Valve's SteamOS Devkit
Client (Windows/Linux).

## First run on the headset

1. **B/Y → Treadmill → Measure treadmill.** Step off and touch the belt's front-left corner, then
   front-right, then the back end, with a controller tip, pulling its trigger each time.
2. **Trigger** switches to World view; the treadmill area stays see-through.
3. **Stride:** set the treadmill speed, walk until it says ready, then Calibrate. Repeat at a few speeds.

## Still to check on the treadmill

- Step counting and speed against the treadmill's display (step graph on the walking panel).
- See-through area position and height; edge warning distances.
- Whether the treadmill measurement survives an app restart.
