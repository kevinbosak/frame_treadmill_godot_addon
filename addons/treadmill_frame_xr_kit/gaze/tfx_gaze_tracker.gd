class_name TFXGazeTracker
extends Node3D
## Treadmill Frame XR Kit: works out where you're looking and which TFXGazeTarget (if any) you're looking at.
##
## Gaze source, best first: eye tracking -> head direction (headset without eye
## tracking) -> mouse (desktop preview). Instead of a thin ray, targets are picked
## by angle: anything within a couple of degrees of your gaze counts, allowing for
## the normal small inaccuracy of eye trackers and for tiny objects.

signal target_noticed(target: TFXGazeTarget)

## How far outside an object your gaze may land and still count (degrees).
const TOLERANCE_DEG := 2.0
## Pointing your head is coarser than looking, so head direction gets more leeway.
const HEAD_TOLERANCE_DEG := 4.0
## Physics layers used to judge how far away the thing you're looking at is.
const DEPTH_LAYERS := (1 << 1) | (1 << 3)

## Set by the scene.
var eye: XRController3D
var camera: XRCamera3D
var xr_active := false

## "eye tracking", "head direction" or "mouse".
var source := "none"
var gaze_origin := Vector3.ZERO
var gaze_dir := Vector3.FORWARD
## Best guess at how far away the gazed point is (m).
var gaze_distance := 10.0
var current: TFXGazeTarget = null

var _have_dir := false


func _process(delta: float) -> void:
	if camera == null:
		return
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	if eye and eye.get_has_tracking_data():
		origin = eye.global_position
		dir = -eye.global_transform.basis.z
		source = "eye tracking"
	elif xr_active:
		source = "head direction"
	else:
		var mouse := get_viewport().get_mouse_position()
		origin = camera.project_ray_origin(mouse)
		dir = camera.project_ray_normal(mouse)
		source = "mouse"
	gaze_origin = origin
	# A little smoothing takes out tracker jitter without feeling laggy.
	gaze_dir = dir if not _have_dir else gaze_dir.slerp(dir, 1.0 - exp(-delta / 0.025)).normalized()
	_have_dir = true

	var tolerance := HEAD_TOLERANCE_DEG if source == "head direction" else TOLERANCE_DEG
	var targets := get_tree().get_nodes_in_group(TFXGazeTarget.GROUP)
	current = pick(origin, gaze_dir, targets, tolerance)

	for node in targets:
		var t := node as TFXGazeTarget
		if t and t.update_dwell(delta, t == current):
			target_noticed.emit(t)

	gaze_distance = _estimate_distance()


## The target closest to the gaze direction, within the tolerance, or null.
static func pick(origin: Vector3, dir: Vector3, targets: Array,
		tolerance_deg: float = TOLERANCE_DEG) -> TFXGazeTarget:
	var best: TFXGazeTarget = null
	var best_score := tolerance_deg
	for node in targets:
		var t := node as TFXGazeTarget
		if t == null or not t.is_visible_in_tree():
			continue
		var to := t.global_position - origin
		var dist := to.length()
		if dist < 0.1 or dist > t.max_distance:
			continue
		# Angle from the gaze to the object's centre, minus the object's own angular size.
		var score := rad_to_deg(dir.angle_to(to)) - rad_to_deg(atan(t.radius / dist))
		if score < best_score:
			best = t
			best_score = score
	return best


func _estimate_distance() -> float:
	if current:
		return gaze_origin.distance_to(current.global_position)
	var query := PhysicsRayQueryParameters3D.create(gaze_origin, gaze_origin + gaze_dir * 30.0, DEPTH_LAYERS)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return gaze_origin.distance_to(hit.position)
	if gaze_dir.y < -0.05:
		return minf(gaze_origin.y / -gaze_dir.y, 30.0)   # where the gaze meets the floor
	return 15.0
