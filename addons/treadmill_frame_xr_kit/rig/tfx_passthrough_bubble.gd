class_name TFXPassthroughBubble
extends MeshInstance3D
## A see-through box around the treadmill. Wherever it's drawn, the virtual
## world is erased and the real room (passthrough) shows instead, so you can
## always see the belt, the rails, the console and your hands.
##
## How: the box multiplies the screen's colour and alpha by zero (blend_mul),
## leaving a fully transparent hole that the headset fills with the camera view.
## The top of the box sits below your eyes, so you look down into the real room
## and straight ahead into the virtual one.

## Extra room around the belt that also stays see-through (m).
const SIDE_MARGIN := 0.30    # rails and side decks
const BACK_MARGIN := 0.40    # where you'd step off
const FRONT_MARGIN := 0.35   # console base

const HOLE_SHADER := """shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_draw_always, shadows_disabled, fog_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""

## Saves GPU time: an ordinary solid box, a little smaller than the hole, drawn
## before the world. Anything behind it (the ground, grass and rocks under the
## see-through area) then fails the depth test and is never shaded, instead of
## being fully drawn and erased a moment later. The hole box still makes it
## transparent.
const OCCLUDER_SHADER := """shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
}
"""
const OCCLUDER_INSET := 0.01   # m, keeps it just behind the hole's faces

const RENDER_PRIORITY := 100

var _box := BoxMesh.new()
var _occluder_box := BoxMesh.new()


func _ready() -> void:
	mesh = _box
	var shader := Shader.new()
	shader.code = HOLE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Drawn after the world (so it can erase it) but before the HUD, reticle and
	# prompts, which draw on top so the see-through area can never hide them.
	mat.render_priority = RENDER_PRIORITY
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Solid boxes are drawn nearest first, and this one is right in front of
	# you, so it's drawn before the world without any extra setup.
	var occluder := MeshInstance3D.new()
	occluder.name = "Occluder"
	occluder.mesh = _occluder_box
	var occ_shader := Shader.new()
	occ_shader.code = OCCLUDER_SHADER
	var occ_mat := ShaderMaterial.new()
	occ_mat.shader = occ_shader
	occluder.material_override = occ_mat
	occluder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(occluder)


## Sizes and places the box around the measured belt.
func fit(f: TFXFootprint, height_above_belt: float) -> void:
	var bottom := minf(0.0, f.belt_height) - 0.5
	var top := f.belt_height + height_above_belt
	_box.size = Vector3(f.width + 2.0 * SIDE_MARGIN, top - bottom,
			f.length + FRONT_MARGIN + BACK_MARGIN)
	_occluder_box.size = (_box.size - Vector3.ONE * 2.0 * OCCLUDER_INSET).max(Vector3.ONE * 0.01)
	var mid := f.center + f.forward * (FRONT_MARGIN - BACK_MARGIN) / 2.0
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.forward.x, -f.forward.y)),
			Vector3(mid.x, (top + bottom) / 2.0, mid.y))
