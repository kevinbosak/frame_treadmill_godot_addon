extends SceneTree
## Checks the binaural cues: the maths, then Godot's real audio output.
## Run from the project folder:
##   godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_spatial_audio.gd

var failures := 0
var _frame := 0
var _audio: TFXAudio
var _sound: TFXSpatialSound
var _capture: AudioEffectCapture
var _results := {}
var _phase := ""
var _phase_start := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_check_maths()
		_setup_scene()
		_start_phase("right", Vector3(2, 0, 0))
	elif _frame == _phase_start + 40:
		_results[_phase] = _measure()
		match _phase:
			"right":
				_start_phase("front", Vector3(0, 0, -2))
			"front":
				_start_phase("behind", Vector3(0, 0, 2))
			"behind":
				_check_output()
				print("FAILURES: %d" % failures)
				quit(1 if failures > 0 else 0)
	return false


func _check_maths() -> void:
	var right := TFXSpatialSound.cues_for(Vector3(3, 0, 0))
	_check("right: left ear delayed ~0.65 ms", absf(right.x - 0.656) < 0.02 and right.y == 0.0)
	var left := TFXSpatialSound.cues_for(Vector3(-3, 0, 0))
	_check("left: right ear delayed", left.y > 0.6 and left.x == 0.0)
	var front := TFXSpatialSound.cues_for(Vector3(0, 0, -3))
	_check("ahead: no delay, bright", front.x == 0.0 and front.y == 0.0 and front.z > 17000.0)
	var behind := TFXSpatialSound.cues_for(Vector3(0, 0, 3))
	_check("behind: muffled", behind.z < 4000.0)
	var up := TFXSpatialSound.cues_for(Vector3(1, 3, 0))
	_check("above: smaller delay", up.x > 0.0 and up.x < right.x)


func _setup_scene() -> void:
	_audio = TFXAudio.new()
	root.add_child(_audio)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(0, _capture)
	_sound = TFXSpatialSound.new()
	_sound.stream = _noise()
	_sound.unit_size = 4.0
	root.add_child(_sound)


func _start_phase(phase_name: String, pos: Vector3) -> void:
	_phase = phase_name
	_phase_start = _frame
	_sound.stop()
	_sound.position = pos
	_sound.play()
	_capture.clear_buffer()


## Left/right loudness, the right ear's lead in samples, and brightness.
func _measure() -> Dictionary:
	var frames := _capture.get_buffer(_capture.get_frames_available())
	var l2 := 0.0
	var r2 := 0.0
	var diff2 := 0.0
	for i in range(1, frames.size()):
		l2 += frames[i].x * frames[i].x
		r2 += frames[i].y * frames[i].y
		var d := frames[i] - frames[i - 1]
		diff2 += d.x * d.x + d.y * d.y
	var best_lag := 0
	var best := -INF
	var n := mini(frames.size() - 64, 6000)
	for lag in range(-40, 41):
		var s := 0.0
		for i in range(64, n):
			s += frames[i].x * frames[i + lag].y if i + lag < frames.size() else 0.0
		if s > best:
			best = s
			best_lag = lag
	return {"left": sqrt(l2), "right": sqrt(r2), "lag": best_lag,
			"brightness": sqrt(diff2) / (sqrt(l2 + r2) + 1e-9), "frames": frames.size()}


func _check_output() -> void:
	var r: Dictionary = _results["right"]
	var f: Dictionary = _results["front"]
	var b: Dictionary = _results["behind"]
	print("right: %s" % r)
	print("front: %s" % f)
	print("behind: %s" % b)
	_check("audio was produced", r.frames > 1000 and r.right > 0.0)
	var ild_db: float = 20.0 * log(r.right / maxf(r.left, 1e-9)) / log(10.0)
	_check("right: %.1f dB louder in the right ear" % ild_db, ild_db > 5.0 and ild_db < 15.0)
	# lag > 0 means the left ear's signal matches the right ear's later samples,
	# i.e. the left ear hears it later.
	var lag_ms: float = -r.lag * 1000.0 / AudioServer.get_mix_rate()
	_check("right: left ear hears it %.2f ms later" % lag_ms, lag_ms > 0.45 and lag_ms < 0.8)
	_check("behind: duller than in front", b.brightness < f.brightness * 0.8)


func _noise() -> AudioStreamWAV:
	var rate := 44100
	var data := PackedByteArray()
	data.resize(rate * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in rate * 2:
		data.encode_s16(i * 2, int(rng.randf_range(-0.5, 0.5) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("%-44s %s" % [name, "ok" if ok else "FAIL"])
