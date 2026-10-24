@tool
extends EditorPlugin
## Turning the plugin on sets the project settings the kit needs and prints a
## checklist for the things a plugin can't set (export presets).

const REQUIRED_SETTINGS := {
	"xr/openxr/enabled": true,
	"xr/shaders/enabled": true,
	"xr/openxr/extensions/eye_gaze_interaction": true,
	"xr/openxr/startup_alert": false,
	"rendering/renderer/rendering_method": "mobile",
	"rendering/textures/vram_compression/import_etc2_astc": true,
}


func _enable_plugin() -> void:
	var changed: PackedStringArray = []
	for key: String in REQUIRED_SETTINGS:
		if ProjectSettings.get_setting(key) != REQUIRED_SETTINGS[key]:
			ProjectSettings.set_setting(key, REQUIRED_SETTINGS[key])
			changed.append(key)
	if not changed.is_empty():
		ProjectSettings.save()
		print("Treadmill Frame XR Kit set: ", ", ".join(changed),
				". Restart the editor if the renderer changed.")
	print("""Treadmill Frame XR Kit checklist:
  - Instance res://addons/treadmill_frame_xr_kit/rig/tfx_rig.tscn in your main scene.
  - Android export preset for Steam Frame: Use Gradle Build on, XR Mode = OpenXR,
    architecture arm64-v8a only. Custom permissions for eye tracking:
    android.permission.EYE_TRACKING_FINE, android.permission.EYE_TRACKING_COARSE,
    com.oculus.permission.EYE_TRACKING
  - Or a Linux export preset with architecture arm64 (native SteamOS build).
  - See the kit's README.md for the rest.""")
