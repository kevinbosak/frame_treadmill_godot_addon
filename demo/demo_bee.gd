class_name DemoBee
extends Node3D
## A bumblebee that visits now and then. Each visit is one of:
##   - a fly-by: a straight line passing just outside your personal space,
##   - a few laps around your head, then it flies off.
## In between it's gone (silent and hidden) for a while. Its buzz is a
## TFXSpatialSound, so you can place it by ear; looking at it for half a second
## counts as finding it (once per visit).

enum State { AWAY, FLYBY, APPROACH, CIRCLE, LEAVE }

const SPEED := 1.8              # m/s
## Never closer to your head than this (m).
const PERSONAL_SPACE := 0.6
## Closest approach on a fly-by (m).
const PASS_DISTANCE := 0.85
const ORBIT_RADIUS := 1.1
## Where visits start and end (m from your head); the buzz is faint out there.
const FAR := 12.0
## Seconds before the first visit, and between visits.
const FIRST_VISIT := Vector2(8.0, 15.0)
const BETWEEN_VISITS := Vector2(25.0, 60.0)

var rig: TFXRig
var state := State.AWAY
var velocity := Vector3.ZERO
var buzz := TFXSpatialSound.new()

var _target := TFXGazeTarget.new()
var _wait := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _progress := 0.0
var _length := 1.0
var _orbit_angle := 0.0
var _orbit_left := 0.0
var _orbit_dir := 1.0
var _time := 0.0
var _visual: Node3D
var _wings: Array[MeshInstance3D] = []


## The bee's body and wings (wings are named "Wing0" and "Wing1"). Static, so a
## copy can be handed to the rig's warm-up.
static func build_visual() -> Node3D:
	var visual := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.012
	body_mesh.height = 0.03
	body_mesh.radial_segments = 8
	body_mesh.rings = 4
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.95, 0.75, 0.15)
	body_mesh.material = fur
	body.mesh = body_mesh
	body.rotation.x = PI / 2
	visual.add_child(body)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.0125
	band_mesh.bottom_radius = 0.0125
	band_mesh.height = 0.008
	band_mesh.radial_segments = 8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.08, 0.05)
	band_mesh.material = dark
	band.mesh = band_mesh
	band.rotation.x = PI / 2
	band.position.z = 0.005
	visual.add_child(band)
	var wing_mesh := QuadMesh.new()
	wing_mesh.size = Vector2(0.022, 0.012)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.45)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_mesh.material = wing_mat
	for i in 2:
		var wing := MeshInstance3D.new()
		wing.name = "Wing%d" % i
		wing.mesh = wing_mesh
		wing.position = Vector3((-1.0 if i == 0 else 1.0) * 0.013, 0.008, -0.002)
		wing.rotation.x = -PI / 2
		visual.add_child(wing)
	return visual


func _ready() -> void:
	_visual = build_visual()
	add_child(_visual)
	for i in 2:
		_wings.append(_visual.get_node("Wing%d" % i) as MeshInstance3D)

	buzz.stream = DemoSounds.BEE
	buzz.unit_size = 1.2
	buzz.max_distance = 40.0
	add_child(buzz)

	_target.label = "bee"
	_target.radius = 0.08
	_target.max_distance = 8.0
	add_child(_target)
	_go_away(FIRST_VISIT)


func _process(delta: float) -> void:
	if rig == null or not is_visible_in_tree() or delta <= 0.0:
		return
	_time += delta
	var head := rig.xr_camera.global_position
	var before := global_position
	match state:
		State.AWAY:
			_wait -= delta
			if _wait <= 0.0:
				_start_visit(head)
			return
		State.FLYBY, State.LEAVE:
			_progress += SPEED * delta
			global_position = _from.lerp(_to, minf(_progress / _length, 1.0))
			if _progress >= _length:
				_go_away(BETWEEN_VISITS)
				return
		State.APPROACH:
			var entry := _orbit_point(head, _orbit_angle)
			var to := entry - global_position
			if to.length() < 0.15:
				state = State.CIRCLE
			else:
				global_position += to.normalized() * minf(SPEED * delta, to.length())
		State.CIRCLE:
			var step := SPEED / ORBIT_RADIUS * delta
			_orbit_angle += _orbit_dir * step
			_orbit_left -= step
			global_position = _orbit_point(head, _orbit_angle)
			if _orbit_left <= 0.0:
				_leave()

	var from_head := global_position - head
	if from_head.length() < PERSONAL_SPACE:
		global_position = head + from_head.normalized() * PERSONAL_SPACE
	global_position.y = maxf(global_position.y, _min_height())
	velocity = (global_position - before) / delta
	if velocity.length() > 0.05:
		look_at(global_position + velocity, Vector3.UP)
	# Bee-like wobble on the visual only, plus fluttering wings.
	_visual.position = Vector3(sin(_time * 7.3), sin(_time * 5.1) * 0.6, cos(_time * 6.7)) * 0.025
	for i in _wings.size():
		_wings[i].rotation.z = sin(_time * 55.0) * 0.7 * (1.0 if i == 0 else -1.0)
	buzz.pitch_scale = 0.92 + velocity.length() * 0.07


func _start_visit(head: Vector3) -> void:
	_set_present(true)
	TFXGraphics.note("bee visit")
	_target.noticed = false     # it can be found again on every visit
	_target.dwell = 0.0
	if randf() < 0.5:
		# Fly-by: pass beside you, just outside your personal space.
		var side := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		var along := side.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
		var closest := head + side * PASS_DISTANCE + Vector3.UP * randf_range(-0.15, 0.25)
		closest.y = maxf(closest.y, _min_height())
		_fly(closest - along * FAR, closest + along * FAR, State.FLYBY)
	else:
		# Circle: come in, do a few laps around your head, then leave.
		_orbit_angle = randf() * TAU
		_orbit_dir = 1.0 if randf() < 0.5 else -1.0
		_orbit_left = randi_range(2, 3) * TAU
		global_position = head + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)) * FAR + Vector3.UP * 0.8
		state = State.APPROACH


func _leave() -> void:
	var outward := Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle))
	var tangent := Vector3(-sin(_orbit_angle), 0.0, cos(_orbit_angle)) * _orbit_dir
	var away := (tangent + outward * 0.6).normalized() * (FAR + 3.0) + Vector3.UP * 1.5
	_fly(global_position, global_position + away, State.LEAVE)


func _fly(from: Vector3, to: Vector3, new_state: State) -> void:
	_from = from
	_to = to
	_progress = 0.0
	_length = maxf(from.distance_to(to), 0.01)
	global_position = from
	state = new_state


func _go_away(wait_range: Vector2) -> void:
	state = State.AWAY
	_wait = randf_range(wait_range.x, wait_range.y)
	_set_present(false)


func _set_present(on: bool) -> void:
	_visual.visible = on
	_target.visible = on
	if on:
		buzz.play()
	else:
		buzz.stop()


func _orbit_point(head: Vector3, angle: float) -> Vector3:
	var p := head + Vector3(cos(angle), 0.0, sin(angle)) * ORBIT_RADIUS
	p.y += -0.1 + 0.12 * sin(angle * 2.0)
	p.y = maxf(p.y, _min_height())
	return p


## Stay above the see-through area around the treadmill, so it stays visible.
func _min_height() -> float:
	var t := rig.treadmill
	return t.footprint.belt_height + t.bubble_height + 0.15
