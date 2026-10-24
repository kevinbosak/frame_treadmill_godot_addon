extends Node3D
## Placeholder world for testing the see-through bubble: sky, grid ground and
## scattered pillars. The real walking environment replaces this next.

const GROUND_SHADER := """shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.20, 0.33, 0.20);
uniform vec3 line_color : source_color = vec3(0.42, 0.62, 0.38);

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 g = abs(fract(p) - 0.5);
	ALBEDO = mix(base_color, line_color, step(0.47, max(g.x, g.y)));
}
"""


func _ready() -> void:
	# Sky: an opaque dome, so the room only shows through the bubble.
	var sky := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 400.0
	dome.height = 800.0
	dome.flip_faces = true
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.albedo_color = Color(0.55, 0.72, 0.95)
	dome.material = sky_mat
	sky.mesh = dome
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = shader
	plane.material = ground_mat
	ground.mesh = plane
	add_child(ground)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var box := BoxMesh.new()
	for i in 140:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(4.0, 70.0)
		var h := rng.randf_range(0.5, 4.0)
		var pillar := MeshInstance3D.new()
		pillar.mesh = box
		pillar.scale = Vector3(rng.randf_range(0.3, 1.2), h, rng.randf_range(0.3, 1.2))
		pillar.position = Vector3(cos(angle) * dist, h / 2.0, sin(angle) * dist)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.from_hsv(rng.randf(), 0.45, 0.85)
		pillar.material_override = mat
		add_child(pillar)
