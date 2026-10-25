class_name DemoWildlife
extends Node3D
## The demo's moving and distant creatures: a bee that visits now and then, birds that
## fly across the sky, and an owl or woodpecker calling from far away, from any
## direction (including behind you).

var rig: TFXRig
var bee := DemoBee.new()

var _flyby_wait := randf_range(8.0, 15.0)
var _distant_wait := randf_range(10.0, 20.0)
var _distant := TFXSpatialSound.new()


func _ready() -> void:
	bee.rig = rig
	add_child(bee)
	_distant.unit_size = 22.0
	_distant.max_distance = 150.0
	add_child(_distant)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_flyby_wait -= delta
	if _flyby_wait <= 0.0:
		_spawn_flyby()
		_flyby_wait = randf_range(18.0, 35.0)
	_distant_wait -= delta
	if _distant_wait <= 0.0 and not _distant.playing:
		var head := rig.xr_camera.global_position
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		_distant.global_position = head + dir * randf_range(20.0, 40.0) + Vector3.UP * randf_range(3.0, 8.0)
		_distant.stream = DemoSounds.OWL if randf() < 0.5 else DemoSounds.WOODPECKER
		_distant.pitch_scale = randf_range(0.95, 1.05)
		_distant.play()
		_distant_wait = randf_range(15.0, 35.0)


func _spawn_flyby() -> void:
	var head := rig.xr_camera.global_position
	var toward := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var across := toward.cross(Vector3.UP).normalized()
	var mid := head + toward * randf_range(4.0, 14.0) + Vector3.UP * randf_range(5.0, 10.0)
	var bird := DemoFlybyBird.new()
	add_child(bird)
	bird.fly(mid - across * 45.0, mid + across * 45.0, randf_range(8.0, 11.0))
