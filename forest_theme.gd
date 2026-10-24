class_name ForestTheme
extends RefCounted
## "Dusk forest road": the first look for the walking world.
##
## A theme decides the sky, fog, light, ground and what lines the path. PathWorld
## handles moving and recycling the path, so a new setting (coastline, colony
## highway...) is a new theme file with the same three functions:
## build_backdrop(), populate() and apply_environment().

const SKY_TOP := Color(0.16, 0.18, 0.40)
const SKY_HORIZON := Color(0.93, 0.60, 0.46)
const FOG_COLOR := Color(0.70, 0.50, 0.50)
const FOG_DENSITY := 0.022
const SUN_DIR := Vector3(-0.45, 0.16, -0.88)     # towards the sun: low, ahead-left
const SUN_COLOR := Color(1.0, 0.72, 0.5)
const AMBIENT := Color(0.42, 0.42, 0.62)

const ROAD_HALF_WIDTH := 1.5
const GROUND_WIDTH := 160.0

const GROUND_SHADER := """shader_type spatial;
render_mode specular_disabled;

instance uniform float path_offset = 0.0;
uniform vec3 grass_a : source_color = vec3(0.16, 0.26, 0.13);
uniform vec3 grass_b : source_color = vec3(0.27, 0.36, 0.17);
uniform vec3 dirt_a : source_color = vec3(0.36, 0.27, 0.19);
uniform vec3 dirt_b : source_color = vec3(0.50, 0.40, 0.28);
uniform float road_half_width = 1.5;

varying vec2 p;

float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// Path coordinates: x across the road, y = distance along it.
	p = vec2(VERTEX.x, path_offset - VERTEX.z);
}

void fragment() {
	float n = noise(p * 0.35) * 0.6 + noise(p * 1.7) * 0.3 + noise(p * 6.0) * 0.1;
	float edge = abs(p.x) + (noise(p * 0.8) - 0.5) * 0.5;
	float road = 1.0 - smoothstep(road_half_width - 0.2, road_half_width + 0.35, edge);
	vec3 grass = mix(grass_a, grass_b, n);
	vec3 dirt = mix(dirt_a, dirt_b, noise(p * 3.0) * 0.7 + n * 0.3);
	float rut = smoothstep(0.14, 0.0, abs(abs(p.x) - 0.65)) * 0.22;
	dirt *= 1.0 - rut;
	ALBEDO = mix(grass, dirt, road);
	ROUGHNESS = 1.0;
}
"""

const SKY_SHADER := """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 top_color : source_color;
uniform vec3 horizon_color : source_color;
uniform vec3 sun_color : source_color;
uniform vec3 sun_dir;

varying vec3 dir;

void vertex() { dir = normalize(VERTEX); }

void fragment() {
	vec3 d = normalize(dir);
	vec3 c = mix(horizon_color, top_color, smoothstep(0.0, 0.55, d.y));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	c += sun_color * (smoothstep(0.9985, 0.9995, s) * 1.5 + pow(s, 12.0) * 0.35);
	ALBEDO = c;
}
"""

var ground_mesh := PlaneMesh.new()
var ground_material := ShaderMaterial.new()
var plant_material := StandardMaterial3D.new()
var lantern_material := StandardMaterial3D.new()
var trunk_mesh := CylinderMesh.new()
var cone_mesh := CylinderMesh.new()
var round_mesh := SphereMesh.new()
var rock_mesh := SphereMesh.new()
var post_mesh := BoxMesh.new()
var lantern_mesh := BoxMesh.new()


func _init() -> void:
	var gs := Shader.new()
	gs.code = GROUND_SHADER
	ground_material.shader = gs
	ground_material.set_shader_parameter("road_half_width", ROAD_HALF_WIDTH)

	plant_material.vertex_color_use_as_albedo = true
	plant_material.roughness = 1.0
	lantern_material.albedo_color = Color(1.0, 0.75, 0.4)
	lantern_material.emission_enabled = true
	lantern_material.emission = Color(1.0, 0.65, 0.3)
	lantern_material.emission_energy_multiplier = 2.5

	trunk_mesh.top_radius = 0.1
	trunk_mesh.bottom_radius = 0.16
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 0
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 1.0
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 7
	cone_mesh.rings = 0
	round_mesh.radius = 1.0
	round_mesh.height = 2.0
	round_mesh.radial_segments = 7
	round_mesh.rings = 4
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 6
	rock_mesh.rings = 3
	post_mesh.size = Vector3(0.1, 1.5, 0.1)
	lantern_mesh.size = Vector3(0.2, 0.26, 0.2)


## Sky, distant mountains and the low sun. These don't scroll, so the horizon stays put.
func build_backdrop(parent: Node3D) -> void:
	var sky := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 400.0
	dome.height = 800.0
	dome.radial_segments = 32
	dome.rings = 16
	var ss := Shader.new()
	ss.code = SKY_SHADER
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = ss
	sky_mat.set_shader_parameter("top_color", SKY_TOP)
	sky_mat.set_shader_parameter("horizon_color", SKY_HORIZON)
	sky_mat.set_shader_parameter("sun_color", SUN_COLOR)
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR)
	dome.material = sky_mat
	sky.mesh = dome
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(sky)

	# Mountains: drawn without fog in a hazy colour, so their outlines stay visible.
	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.vertex_color_use_as_albedo = true
	mountain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mountain_mat.disable_fog = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in 46:
		var angle := TAU * i / 46.0 + rng.randf_range(-0.05, 0.05)
		var dist := rng.randf_range(200.0, 300.0)
		var h := rng.randf_range(25.0, 75.0)
		var w := rng.randf_range(35.0, 70.0)
		xforms.append(Transform3D(Basis.from_scale(Vector3(w, h, w)),
				Vector3(cos(angle) * dist, h / 2.0 - 2.0, sin(angle) * dist)))
		colors.append(SKY_TOP.lerp(SKY_HORIZON, rng.randf_range(0.35, 0.6)).darkened(0.25))
	_multi(parent, cone_mesh, xforms, colors, mountain_mat)

	var sun := DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	sun.transform.basis = Basis.looking_at(-SUN_DIR, Vector3.UP)
	parent.add_child(sun)


func apply_environment(env: Environment) -> void:
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.7


## Fills one stretch of path. The chunk covers local z from 0 (near end) to
## -length (far end). Same index -> same scenery. Returns its gaze targets.
func populate(chunk: Node3D, index: int, length: float) -> Array[GazeTarget]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919 + 13)

	var ground := MeshInstance3D.new()
	ground_mesh.size = Vector2(GROUND_WIDTH, length)
	ground_mesh.center_offset = Vector3(0, 0, -length / 2.0)
	ground.mesh = ground_mesh
	ground.material_override = ground_material
	# Wrapping keeps the shader's numbers small on long walks.
	ground.set_instance_shader_parameter("path_offset", fmod(index * length, 2400.0))
	chunk.add_child(ground)

	var trunks: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var leaves: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var rounds: Array[Transform3D] = []
	var round_colors: Array[Color] = []

	for i in 46:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (3.6 + pow(rng.randf(), 1.7) * 55.0)
		var z := -rng.randf() * length
		var h := rng.randf_range(2.5, 7.0)
		var trunk_h := h * 0.35
		trunks.append(Transform3D(Basis.from_scale(Vector3(1, trunk_h, 1) * (h / 5.0 + 0.4)),
				Vector3(x, trunk_h * (h / 5.0 + 0.4) / 2.0, z)))
		trunk_colors.append(Color(0.30, 0.21, 0.15).darkened(rng.randf() * 0.3))
		var green := Color(0.13, 0.30, 0.18).lerp(Color(0.25, 0.38, 0.16), rng.randf())
		if rng.randf() < 0.7:
			# Pine: stacked cones.
			for layer in 3:
				var w := h * (0.34 - layer * 0.08)
				var lh := h * 0.42
				leaves.append(Transform3D(Basis.from_scale(Vector3(w, lh, w)),
						Vector3(x, trunk_h + layer * h * 0.2 + lh / 2.0, z)))
				leaf_colors.append(green.lightened(layer * 0.05))
		else:
			var r := h * 0.3
			rounds.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.9, r)),
					Vector3(x, trunk_h + r * 0.7, z)))
			round_colors.append(green.lerp(Color(0.45, 0.35, 0.12), rng.randf() * 0.5))

	var rocks: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	for i in 14:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(0.15, 0.7)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.6, s)),
				Vector3(side * rng.randf_range(2.0, 14.0), s * 0.15, -rng.randf() * length)))
		rock_colors.append(Color(0.42, 0.40, 0.42).darkened(rng.randf() * 0.3))
	for i in 18:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(0.25, 0.6)
		rounds.append(Transform3D(Basis.from_scale(Vector3(s * 1.4, s, s * 1.4)),
				Vector3(side * rng.randf_range(2.2, 9.0), s * 0.5, -rng.randf() * length)))
		round_colors.append(Color(0.18, 0.32, 0.15).lerp(Color(0.3, 0.38, 0.18), rng.randf()))

	_multi(chunk, trunk_mesh, trunks, trunk_colors, plant_material)
	_multi(chunk, cone_mesh, leaves, leaf_colors, plant_material)
	_multi(chunk, round_mesh, rounds, round_colors, plant_material)
	_multi(chunk, rock_mesh, rocks, rock_colors, plant_material)

	# A lantern post every stretch, alternating sides: the "lantern road".
	var side := 1.0 if index % 2 == 0 else -1.0
	var post := MeshInstance3D.new()
	post.mesh = post_mesh
	post.material_override = plant_material
	post.position = Vector3(side * 2.1, 0.75, -length * 0.5)
	chunk.add_child(post)
	var lantern := MeshInstance3D.new()
	lantern.mesh = lantern_mesh
	lantern.material_override = lantern_material
	lantern.position = Vector3(side * 2.1, 1.6, -length * 0.5)
	chunk.add_child(lantern)

	return [_waystone(chunk, rng, length)]


## Eye-tracking test object: a rune-marked stone, sometimes obvious, sometimes hidden.
func _waystone(chunk: Node3D, rng: RandomNumberGenerator, length: float) -> GazeTarget:
	var target := GazeTarget.new()
	var mesh := MeshInstance3D.new()
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.45, 0.47, 0.55)
	glow.emission_enabled = true
	target.glow_material = glow
	mesh.material_override = glow
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var z := -rng.randf_range(0.2, 0.8) * length
	var kind := rng.randf()
	if kind < 0.45:
		target.label = "roadside stone"
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.9, 0.3)
		mesh.mesh = box
		target.radius = 0.45
		target.position = Vector3(side * rng.randf_range(2.6, 3.6), 0.45, z)
		target.rotation.y = rng.randf_range(-0.5, 0.5)
	elif kind < 0.75:
		target.label = "rune in the grass"
		var disc := CylinderMesh.new()
		disc.top_radius = 0.14
		disc.bottom_radius = 0.14
		disc.height = 0.04
		disc.radial_segments = 8
		mesh.mesh = disc
		target.radius = 0.16
		target.position = Vector3(side * rng.randf_range(4.0, 10.0), 0.05, z)
		target.rotation.x = 0.4
	else:
		target.label = "charm in a tree"
		var charm := BoxMesh.new()
		charm.size = Vector3(0.18, 0.24, 0.05)
		mesh.mesh = charm
		target.radius = 0.18
		target.position = Vector3(side * rng.randf_range(3.8, 7.0), rng.randf_range(2.6, 3.8), z)
	target.add_child(mesh)
	chunk.add_child(target)
	return target


func _multi(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color],
		material: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
