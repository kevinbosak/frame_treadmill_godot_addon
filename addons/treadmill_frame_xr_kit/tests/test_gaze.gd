extends SceneTree
## Checks gaze target picking and dwell timing.
## Run from the project folder:  godot --headless --script res://addons/treadmill_frame_xr_kit/tests/test_gaze.gd

var failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	# Runs on the first frame, once the scene tree is up.
	if not _ran:
		_ran = true
		_run()
	return false


func _run() -> void:
	var near := _target(Vector3(0.3, 1.6, -3.0), 0.2)   # small, slightly right
	var big := _target(Vector3(-2.0, 1.6, -10.0), 1.0)  # large, left and further
	var far := _target(Vector3(0.0, 1.6, -60.0), 0.5)   # beyond max distance
	var all := [near, big, far]
	var eye := Vector3(0, 1.6, 0)

	_check("looking at small target", TFXGazeTracker.pick(eye, (near.position - eye).normalized(), all) == near)
	_check("just outside small target", TFXGazeTracker.pick(eye,
			(near.position - eye).normalized().rotated(Vector3.UP, deg_to_rad(4.8)), all) == near)
	_check("well off small target", TFXGazeTracker.pick(eye,
			(near.position - eye).normalized().rotated(Vector3.UP, deg_to_rad(-12.0)), all) == null)
	_check("big target easy to hit", TFXGazeTracker.pick(eye,
			(big.position - eye).normalized().rotated(Vector3.UP, deg_to_rad(6.0)), all) == big)
	_check("too far away ignored", TFXGazeTracker.pick(eye, (far.position - eye).normalized(), [far]) == null)

	# Dwell: 0.5 s of looking notices it; glances don't.
	var t := _target(Vector3.ZERO, 0.2)
	for i in 20:   # 0.2 s glance
		t.update_dwell(0.01, true)
	for i in 50:   # look away 0.5 s
		t.update_dwell(0.01, false)
	_check("glance not noticed", not t.noticed)
	var hits := 0
	for i in 60:
		if t.update_dwell(0.01, true):
			hits += 1
	_check("steady look noticed once", t.noticed and hits == 1)

	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _target(pos: Vector3, radius: float) -> TFXGazeTarget:
	var t := TFXGazeTarget.new()
	t.radius = radius
	root.add_child(t)
	t.position = pos
	return t


func _check(name: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print("%-28s %s" % [name, "ok" if ok else "FAIL"])
