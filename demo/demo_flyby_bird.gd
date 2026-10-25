class_name DemoFlybyBird
extends Node3D
## A small bird that flies across the sky in a straight line, flapping and
## chirping, then disappears.

var voice := TFXSpatialSound.new()
var _start := Vector3.ZERO
var _end := Vector3.ZERO
var _speed := 9.0
var _travelled := 0.0
var _chirp_wait := 0.3
var _time := 0.0
var _wings: Array[MeshInstance3D] = []


func fly(from: Vector3, to: Vector3, speed: float) -> void:
	_start = from
	_end = to
	_speed = speed
	global_position = from
	look_at(to, Vector3.UP)


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.13, 0.12)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.06
	body_mesh.height = 0.2
	body_mesh.radial_segments = 6
	body_mesh.rings = 3
	body_mesh.material = mat
	body.mesh = body_mesh
	body.rotation.x = PI / 2
	add_child(body)
	var wing_mesh := QuadMesh.new()
	wing_mesh.size = Vector2(0.22, 0.09)
	wing_mesh.material = mat
	for side in [-1.0, 1.0]:
		var pivot := MeshInstance3D.new()
		pivot.mesh = wing_mesh
		pivot.rotation.x = -PI / 2
		pivot.position.x = side * 0.11
		add_child(pivot)
		_wings.append(pivot)
	voice.unit_size = 9.0
	voice.max_distance = 90.0
	voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(voice)


func _process(delta: float) -> void:
	_time += delta
	_travelled += _speed * delta
	var length := _start.distance_to(_end)
	if _travelled >= length:
		queue_free()
		return
	global_position = _start.lerp(_end, _travelled / length)
	var flap := sin(_time * 14.0) * 0.6
	_wings[0].rotation.z = flap
	_wings[1].rotation.z = -flap
	_chirp_wait -= delta
	if _chirp_wait <= 0.0:
		voice.stream = DemoSounds.BIRD_CALLS[3 if randf() < 0.6 else 0]
		voice.pitch_scale = randf_range(1.05, 1.2)
		voice.play()
		_chirp_wait = randf_range(0.7, 1.6)
