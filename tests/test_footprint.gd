extends SceneTree
## Checks the treadmill measurement maths.
## Run from the project folder:  godot --headless --script res://tests/test_footprint.gd

var failures := 0


func _init() -> void:
	# A 0.5 m x 1.4 m belt, 0.2 m high, facing -Z, centred at (1, -2).
	var fl := Vector3(0.75, 0.2, -2.7)
	var fr := Vector3(1.25, 0.2, -2.7)
	var back := Vector3(1.1, 0.21, -1.3)
	var f := TreadmillFootprint.from_points(fl, fr, back)
	_check("width", f.width, 0.5)
	_check("length", f.length, 1.4)
	_check("centre x", f.center.x, 1.0)
	_check("centre z", f.center.y, -2.0)
	_check("forward z", f.forward.y, -1.0)
	_check("right x", f.right.x, 1.0)
	_check("belt height", f.belt_height, 0.2033)
	_check("no problem", float(f.problem() == ""), 1.0)
	var local := f.to_local(Vector2(1.2, -2.3))  # 0.2 right, 0.3 ahead
	_check("local side", local.x, 0.2)
	_check("local ahead", local.y, 0.3)

	# Corners touched in the wrong order: still faces the front.
	var swapped := TreadmillFootprint.from_points(fr, fl, back)
	_check("swapped forward z", swapped.forward.y, -1.0)
	_check("swapped length", swapped.length, 1.4)

	# Same belt rotated 37 degrees around the vertical axis.
	var r := Basis(Vector3.UP, deg_to_rad(37.0))
	var rf := TreadmillFootprint.from_points(r * fl, r * fr, r * back)
	_check("rotated width", rf.width, 0.5)
	_check("rotated length", rf.length, 1.4)
	var expected_center := r * Vector3(1.0, 0.0, -2.0)
	_check("rotated centre x", rf.center.x, expected_center.x)
	_check("rotated centre z", rf.center.y, expected_center.z)

	# Nonsense measurements are rejected.
	var bad := TreadmillFootprint.from_points(fl, fl + Vector3(0.05, 0, 0), back)
	_check("tiny width rejected", float(bad.problem() != ""), 1.0)

	# Survives a save/load round trip.
	var copy := TreadmillFootprint.from_dict(f.to_dict())
	_check("round trip length", copy.length, 1.4)

	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func _check(name: String, got: float, want: float) -> void:
	var ok := absf(got - want) < 0.002
	if not ok:
		failures += 1
	print("%-22s %s  got %.4f want %.4f" % [name, "ok  " if ok else "FAIL", got, want])
