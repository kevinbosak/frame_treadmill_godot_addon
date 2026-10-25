class_name TFXUiPanel3D
extends Node3D
## Shows an ordinary 2D Godot UI (Controls) on a flat panel floating in 3D,
## and turns laser-pointer hits into mouse events so its buttons work.

const PIXELS_PER_METRE := 1400.0
const UI_LAYER := 1 << 1   # physics layer 2: what pointers look for

var viewport := SubViewport.new()
var size_m := Vector2.ONE

var _quad := MeshInstance3D.new()
var _area := Area3D.new()
var _last_pos := Vector2(-100, -100)
var _pressed := false


func setup(content: Control, size_px: Vector2i) -> void:
	viewport.size = size_px
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	content.custom_minimum_size = Vector2(size_px)
	viewport.add_child(content)

	size_m = Vector2(size_px) / PIXELS_PER_METRE
	var quad := QuadMesh.new()
	quad.size = size_m
	_quad.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = viewport.get_texture()
	# Draw on top of the see-through bubble, so the panel can be used in World view.
	mat.no_depth_test = true
	mat.render_priority = TFXPassthroughBubble.RENDER_PRIORITY + 15
	_quad.material_override = mat
	add_child(_quad)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_m.x, size_m.y, 0.02)
	shape.shape = box
	_area.add_child(shape)
	_area.monitoring = false
	_area.collision_mask = 0
	_area.set_meta("ui_panel", self)
	add_child(_area)
	_update_active()


## The panel's material (used to warm it up before it's first shown).
func panel_material() -> Material:
	return _quad.material_override


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_update_active()


## Hidden panels can't be pointed at and stop redrawing.
func _update_active() -> void:
	var active := is_visible_in_tree()
	_area.collision_layer = UI_LAYER if active else 0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active \
			else SubViewport.UPDATE_DISABLED
	if not active:
		pointer_exit()


func pointer_move(world_pos: Vector3) -> void:
	var local := to_local(world_pos)
	_last_pos = Vector2((local.x / size_m.x + 0.5) * viewport.size.x,
			(0.5 - local.y / size_m.y) * viewport.size.y)
	var ev := InputEventMouseMotion.new()
	ev.position = _last_pos
	ev.global_position = _last_pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	viewport.push_input(ev)


func pointer_button(pressed: bool) -> void:
	_pressed = pressed
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _last_pos
	ev.global_position = _last_pos
	viewport.push_input(ev)


func pointer_exit() -> void:
	if _pressed:
		pointer_button(false)
	_last_pos = Vector2(-100, -100)
	var ev := InputEventMouseMotion.new()
	ev.position = _last_pos
	ev.global_position = _last_pos
	viewport.push_input(ev)
