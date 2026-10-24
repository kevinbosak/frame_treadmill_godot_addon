extends SceneTree
## Feeds the step detector simulated head motion and checks the results.
## Run from the project folder:  godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_step_detector.gd

var failures := 0


func _init() -> void:
	# name, cadence (spm), bob (m), harmonic, noise (m), sway (m), seconds
	_case("slow walk", 80, 0.012, 0.0, 0.0015, 0.0, 30)
	_case("walk", 105, 0.025, 0.2, 0.002, 0.03, 30)
	_case("brisk walk, uneven bob", 125, 0.03, 0.45, 0.002, 0.03, 30)
	_case("jog", 160, 0.055, 0.3, 0.003, 0.03, 30)
	_case("run", 180, 0.07, 0.3, 0.003, 0.03, 30)
	_still("standing still with sway", 0.002, 0.015, 30)
	_still("looking around (slow up/down)", 0.002, 0.04, 30)
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _case(name: String, cadence: float, bob: float, harmonic: float,
		noise: float, sway: float, seconds: float) -> void:
	var d := TFXStepDetector.new()
	var t := 0.0
	var phase := 0.0
	while t < seconds:
		var dt := 1.0 / randf_range(72.0, 90.0)   # uneven frame times
		t += dt
		var rate := cadence * (1.0 + 0.03 * sin(t * 0.7))  # natural ±3% variation
		phase += dt * rate / 60.0 * TAU
		var y := 1.7 + bob * (cos(phase) + harmonic * cos(2.0 * phase + 0.8)) \
				+ sway * sin(t * 0.3) + randf_range(-noise, noise)
		d.add_sample(y, dt)
	var expected := cadence / 60.0 * seconds
	var count_err := absf(d.step_count - expected) / expected
	var cad_err := absf(d.cadence_spm - cadence) / cadence
	var ok := count_err < 0.04 and cad_err < 0.06
	if not ok:
		failures += 1
	print("%-28s %s  steps %d / ~%d  cadence %.0f / %.0f  bob %.1f cm"
			% [name, "ok  " if ok else "FAIL", d.step_count, roundi(expected),
			d.cadence_spm, cadence, d.amplitude * 100.0])


func _still(name: String, noise: float, sway: float, seconds: float) -> void:
	var d := TFXStepDetector.new()
	var t := 0.0
	while t < seconds:
		var dt := 1.0 / 90.0
		t += dt
		d.add_sample(1.7 + sway * sin(t * 1.2) + randf_range(-noise, noise), dt)
	var ok := d.step_count <= 2
	if not ok:
		failures += 1
	print("%-28s %s  false steps %d" % [name, "ok  " if ok else "FAIL", d.step_count])
