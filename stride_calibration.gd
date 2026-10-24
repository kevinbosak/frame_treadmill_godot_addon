class_name StrideCalibration
extends RefCounted
## Learns your step length at different cadences, so pace = cadence x step length.
##
## Each calibration point pairs the cadence you were walking at with the
## treadmill speed you told the app. Step length grows as you speed up, so
## between points we interpolate. (Saved by Treadmill with the other settings.)

## Used until you calibrate: a typical walking step, in metres.
const DEFAULT_STEP_LENGTH := 0.7

## x = cadence (steps/min), y = step length (m), sorted by cadence.
var points: Array[Vector2] = []


## Records a point and returns the step length it implies (m).
func add_point(cadence_spm: float, speed_mps: float) -> float:
	var step_length := speed_mps / (cadence_spm / 60.0)
	# A new point replaces any old one at nearly the same cadence.
	for i in range(points.size() - 1, -1, -1):
		if absf(points[i].x - cadence_spm) < 5.0:
			points.remove_at(i)
	points.append(Vector2(cadence_spm, step_length))
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	return step_length


func step_length_for(cadence_spm: float) -> float:
	if points.is_empty():
		return DEFAULT_STEP_LENGTH
	if cadence_spm <= points[0].x:
		return points[0].y
	if cadence_spm >= points[-1].x:
		return points[-1].y
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if cadence_spm <= b.x:
			return lerpf(a.y, b.y, (cadence_spm - a.x) / (b.x - a.x))
	return points[-1].y


## Estimated speed in metres per second.
func speed_for(cadence_spm: float) -> float:
	return cadence_spm / 60.0 * step_length_for(cadence_spm)


func clear() -> void:
	points.clear()
