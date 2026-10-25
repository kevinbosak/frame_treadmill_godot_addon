class_name TFXAudio
extends Node
## Treadmill Frame XR Kit: audio buses, volumes and the binaural processors.
##
## Buses (all feed Master):
##   "TFX Ambience"  background beds (wind, distant chorus). Not positional.
##   "TFX World"     positional sounds in the world, with a light outdoor reverb.
##   "TFX Effects"   footsteps, chimes, interface sounds.
## Ambience and World are muted outside World view.
##
## Binaural cues: Godot's 3D audio already handles left/right loudness, distance
## and Doppler. On top of that, each nearby TFXSpatialSound borrows one of a small
## pool of "binaural" buses that delays the far ear (interaural time difference,
## up to about 0.65 ms) and muffles sounds behind your head. Those are the main
## cues for placing a sound. It isn't full HRTF (which needs a native library that
## doesn't exist for the Frame's Android build yet), but it's close in practice.

const AMBIENCE := &"TFX Ambience"
const WORLD := &"TFX World"
const EFFECTS := &"TFX Effects"
## Near-silent bus used to play sounds once during warm-up.
const WARMUP := &"TFX Warmup"
## How many sounds can have binaural cues at once; the rest play as plain 3D sound.
const POOL_SIZE := 12

## The active instance (the rig's). TFXSpatialSound finds it here.
static var instance: TFXAudio

## Turns binaural cues on or off for every sound (for comparing).
var binaural_enabled := true

var _free: Array[StringName] = []
var _effects := {}   # bus name -> [AudioEffectDelay, AudioEffectLowPassFilter]


func _enter_tree() -> void:
	instance = self
	_setup_buses()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _setup_buses() -> void:
	_ensure_bus(AMBIENCE, &"Master")
	var world := _ensure_bus(WORLD, &"Master")
	_ensure_bus(EFFECTS, &"Master")
	AudioServer.set_bus_volume_db(_ensure_bus(WARMUP, &"Master"), -80.0)
	if AudioServer.get_bus_effect_count(world) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.7
		reverb.damping = 0.6
		reverb.spread = 1.0
		reverb.hipass = 0.2
		reverb.dry = 1.0
		reverb.wet = 0.12
		AudioServer.add_bus_effect(world, reverb)
	_free.clear()
	for i in POOL_SIZE:
		var bus_name := StringName("TFX Binaural %d" % i)
		var idx := _ensure_bus(bus_name, WORLD)
		if AudioServer.get_bus_effect_count(idx) == 0:
			var delay := AudioEffectDelay.new()
			delay.dry = 0.0
			delay.tap1_active = true
			delay.tap1_pan = -1.0     # tap 1 = left ear
			delay.tap1_level_db = 0.0
			delay.tap2_active = true
			delay.tap2_pan = 1.0      # tap 2 = right ear
			delay.tap2_level_db = 0.0
			delay.feedback_active = false
			AudioServer.add_bus_effect(idx, delay)
			var shadow := AudioEffectLowPassFilter.new()
			shadow.cutoff_hz = 20000.0
			AudioServer.add_bus_effect(idx, shadow)
		_effects[bus_name] = [AudioServer.get_bus_effect(idx, 0), AudioServer.get_bus_effect(idx, 1)]
		_free.append(bus_name)


static func _ensure_bus(bus_name: StringName, send: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send)
	return idx


## Returns a free binaural bus name, or &"" if they're all in use.
func acquire_binaural_bus() -> StringName:
	return _free.pop_back() if not _free.is_empty() else &""


func release_binaural_bus(bus_name: StringName) -> void:
	if bus_name != &"" and not bus_name in _free:
		apply_cues(bus_name, 0.0, 0.0, 20000.0)
		_free.append(bus_name)


## Sets one binaural bus: per-ear delays (ms) and the head-shadow cutoff (Hz).
func apply_cues(bus_name: StringName, left_ms: float, right_ms: float, cutoff_hz: float) -> void:
	var fx: Array = _effects.get(bus_name, [])
	if fx.is_empty():
		return
	var delay := fx[0] as AudioEffectDelay
	var shadow := fx[1] as AudioEffectLowPassFilter
	delay.tap1_delay_ms = left_ms
	delay.tap2_delay_ms = right_ms
	shadow.cutoff_hz = cutoff_hz


## Volumes are linear, 0..1.
func set_volumes(master: float, ambience: float, world: float, effects: float) -> void:
	_set_volume(&"Master", master)
	_set_volume(AMBIENCE, ambience)
	_set_volume(WORLD, world)
	_set_volume(EFFECTS, effects)


## Ambience and world sounds belong to World view; they're silent otherwise.
func set_world_audible(on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(AMBIENCE), not on)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(WORLD), not on)


func free_binaural_buses() -> int:
	return _free.size()


static func _set_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
