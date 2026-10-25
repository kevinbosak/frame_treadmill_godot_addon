class_name TFXSpatialSound
extends AudioStreamPlayer3D
## Treadmill Frame XR Kit: a positional sound you can place by ear.
##
## Use it like AudioStreamPlayer3D. While it's playing and within binaural_range,
## it borrows a binaural bus from TFXAudio and updates it every frame from where
## the sound is relative to your head:
##   - the far ear hears it later (up to ~0.65 ms, the Woodworth head model),
##   - sounds behind you are muffled, which tells front from back.
## Godot adds left/right loudness, distance falloff, air absorption and Doppler.
## Sounds go to the "TFX World" bus unless you set another.

const HEAD_RADIUS := 0.0875     # m
const SPEED_OF_SOUND := 343.0   # m/s

## Turn off for sounds that don't need placing.
@export var binaural := true
## Only nearby sounds borrow a binaural bus (m); farther ones play as plain 3D sound.
@export var binaural_range := 25.0

var _binaural_bus := &""
var _base_bus := &""
var _cues := Vector3(0.0, 0.0, 20000.0)   # left ms, right ms, cutoff Hz (smoothed)


func _init() -> void:
	# About 9 dB quieter in the far ear for a sound straight to the side, like a
	# real head. (Full panning would silence the far ear and lose the time cue.)
	panning_strength = 1.3
	attenuation_filter_cutoff_hz = 7000.0
	attenuation_filter_db = -18.0
	doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP


func _ready() -> void:
	if bus == &"Master":
		bus = TFXAudio.WORLD
	_base_bus = bus


func _process(delta: float) -> void:
	var audio := TFXAudio.instance
	var cam := get_viewport().get_camera_3d()
	var local := Vector3.ZERO
	var wanted := binaural and playing and audio != null and audio.binaural_enabled and cam != null
	if wanted:
		local = cam.global_transform.affine_inverse() * global_position
		wanted = local.length() <= binaural_range
	if wanted and _binaural_bus == &"":
		_binaural_bus = audio.acquire_binaural_bus()
		if _binaural_bus != &"":
			bus = _binaural_bus
			_cues = cues_for(local)   # start from the right place, no sweep
	elif not wanted and _binaural_bus != &"":
		_release()
	if _binaural_bus != &"":
		_cues = _cues.lerp(cues_for(local), 1.0 - exp(-delta / 0.03))
		audio.apply_cues(_binaural_bus, _cues.x, _cues.y, _cues.z)


func _exit_tree() -> void:
	_release()


func _release() -> void:
	if _binaural_bus == &"":
		return
	bus = _base_bus
	if TFXAudio.instance:
		TFXAudio.instance.release_binaural_bus(_binaural_bus)
	_binaural_bus = &""


## Binaural cues for a sound at `local` (relative to the head: -Z ahead, +X right,
## +Y up). Returns Vector3(left ear delay ms, right ear delay ms, muffle cutoff Hz).
static func cues_for(local: Vector3) -> Vector3:
	var dist := local.length()
	if dist < 0.01:
		return Vector3(0.0, 0.0, 20000.0)
	var dir := local / dist
	# Sideways angle (the same for front and back, as in real hearing).
	var theta := asin(clampf(absf(dir.x), 0.0, 1.0))
	var itd_ms := HEAD_RADIUS / SPEED_OF_SOUND * (theta + sin(theta)) * 1000.0
	var behind := clampf(dir.z, 0.0, 1.0)
	var cutoff := lerpf(18000.0, 3500.0, pow(behind, 0.8))
	if dir.x > 0.0:
		return Vector3(itd_ms, 0.0, cutoff)   # sound on the right: left ear hears it later
	return Vector3(0.0, itd_ms, cutoff)
