class_name TFXPointer
extends Node3D
## Laser pointer for a controller. Shows a beam when aimed at a UI panel,
## and clicks the panel with the trigger.

const RANGE := 4.0

var hovered: TFXUiPanel3D = null

var _ray := RayCast3D.new()
var _beam := MeshInstance3D.new()
var _dot := MeshInstance3D.new()


func _ready() -> void:
	_ray.target_position = Vector3(0, 0, -RANGE)
	_ray.collide_with_areas = true
	_ray.collide_with_bodies = false
	_ray.collision_mask = TFXUiPanel3D.UI_LAYER
	add_child(_ray)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.85, 1.0)
	# Drawn after the see-through bubble (and over the settings panel), so the
	# beam stays visible where it passes in front of the real world.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = TFXPassthroughBubble.RENDER_PRIORITY + 18
	var beam := BoxMesh.new()
	beam.size = Vector3(0.002, 0.002, 1.0)
	beam.material = mat
	_beam.mesh = beam
	add_child(_beam)
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	dot.material = mat
	_dot.mesh = dot
	add_child(_dot)
	_beam.visible = false
	_dot.visible = false


func _process(_delta: float) -> void:
	_ray.force_raycast_update()
	var panel: TFXUiPanel3D = null
	if _ray.is_colliding():
		var collider := _ray.get_collider()
		if collider and collider.has_meta("ui_panel"):
			panel = collider.get_meta("ui_panel")
	if panel != hovered:
		if hovered:
			hovered.pointer_exit()
		hovered = panel
	if hovered:
		var hit := _ray.get_collision_point()
		hovered.pointer_move(hit)
		var dist := global_position.distance_to(hit)
		_beam.scale = Vector3(1, 1, dist)
		_beam.position = Vector3(0, 0, -dist / 2.0)
		_dot.global_position = hit
	_beam.visible = hovered != null
	_dot.visible = hovered != null


## The beam and dot meshes (used to warm them up before they're first shown).
func meshes() -> Array[Mesh]:
	return [_beam.mesh, _dot.mesh]


## Sends a trigger press or release to the panel being pointed at.
## Returns true if a panel took it.
func press(pressed: bool) -> bool:
	if hovered:
		hovered.pointer_button(pressed)
		return true
	return false
