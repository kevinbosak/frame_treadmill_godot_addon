class_name DemoForestTheme
extends TFXPathTheme
## Demo theme: "dusk forest road". Rolling hills, textured ground, grass tufts,
## drifting clouds, ground mist, fireflies and pollen; rune-marked waystones for
## the gaze test; songbirds in the trees and crickets in the grass.
##
## An example TFXPathTheme subclass: overrides build_backdrop(),
## apply_environment(), populate() and update(), uses the base class helpers,
## and offers look options for the graphics test bench (Settings → Forest).
## Every texture is generated (Godot noise), so there are no image files.

const SKY_TOP := Color(0.16, 0.18, 0.40)
const SKY_HORIZON := Color(0.93, 0.60, 0.46)
const FOG_COLOR := Color(0.62, 0.52, 0.55)
const FOG_DENSITY := 0.016
const SUN_DIR := Vector3(-0.45, 0.16, -0.88)     # towards the sun: low, ahead-left
const SUN_COLOR := Color(1.0, 0.72, 0.5)
const AMBIENT := Color(0.42, 0.42, 0.62)

const ROAD_HALF_WIDTH := 1.5
const GROUND_WIDTH := 160.0
## How tall the hills get. The road and its verges stay flat.
const HILL_SCALE := 1.0

## Trees and rocks: colour from the instance, plus optional fake light (darker
## undersides and bases) and wind sway, both done per vertex so they're cheap.
const PLANT_SHADER := """shader_type spatial;
render_mode specular_disabled;

uniform float shading = 1.0;
uniform float wind = 1.0;
varying float shade;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 root = MODEL_MATRIX[3].xyz;
	// Height above the ground under this tree (passed per instance).
	float h = max(world.y - INSTANCE_CUSTOM.x, 0.0);
	float phase = root.x * 0.37 + root.z * 0.23;
	vec3 sway = vec3(sin(TIME * 1.3 + phase), 0.0, cos(TIME * 1.1 + phase * 1.3) * 0.6)
			* wind * 0.05 * h * h / 16.0;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * sway;
	vec3 n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float sky = 0.62 + 0.38 * (n.y * 0.5 + 0.5);
	float ground = mix(0.72, 1.0, smoothstep(0.0, 1.2, h));
	shade = mix(1.0, sky * ground * 1.08, shading);
}

void fragment() {
	ALBEDO = COLOR.rgb * shade;
	ROUGHNESS = 1.0;
}
"""

## Grass tufts: opaque blades (no see-through edges, which are costly on mobile
## GPUs), tips swaying in the wind.
const GRASS_SHADER := """shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform float wind = 1.0;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float t = clamp(VERTEX.y / 0.4, 0.0, 1.0);
	float phase = root.x * 0.5 + root.z * 0.3;
	VERTEX.x += sin(TIME * 2.1 + phase) * 0.05 * t * t * wind;
	VERTEX.z += cos(TIME * 1.7 + phase) * 0.03 * t * t * wind;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""

## Soft dark circles under trees: a cheap stand-in for real shadows.
const BLOB_SHADER := """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.02, 0.03, 0.02);
	ALPHA = 0.45 * (1.0 - smoothstep(0.3, 1.0, d));
}
"""

## Ground: hills shaped as it's drawn (the road stays flat), and either generated
## textures with surface detail or the older procedural colouring.
## height() must match ground_height() in GDScript, so scenery sits on the hills.
const GROUND_SHADER := """shader_type spatial;
render_mode specular_disabled;

instance uniform float path_offset = 0.0;
uniform vec3 grass_a : source_color = vec3(0.16, 0.26, 0.13);
uniform vec3 grass_b : source_color = vec3(0.27, 0.36, 0.17);
uniform vec3 dirt_a : source_color = vec3(0.36, 0.27, 0.19);
uniform vec3 dirt_b : source_color = vec3(0.50, 0.40, 0.28);
uniform float road_half_width = 1.5;
uniform float detail = 1.0;
uniform float hills = 1.0;
uniform float hill_scale = 1.0;
uniform float textured = 1.0;
// R = grass shade, G = dirt shade, B = grass blade streaks (see textures/generate_textures.py).
uniform sampler2D ground_mix : filter_linear_mipmap_anisotropic, repeat_enable;
// R,G = grass normal x,y; B,A = dirt normal x,y. Only read up close.
uniform sampler2D ground_normals : filter_linear_mipmap, repeat_enable;
uniform float normals_fade_start = 6.0;
uniform float normals_fade_end = 11.0;

varying vec2 p;
varying vec3 grass_tint;   // slow colour variation across the grass, worked out per vertex

float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// q.x = across the road, q.y = distance along it. Periods along the road divide
// 2400 m, where the distance wraps, so there's never a seam.
float height(vec2 q) {
	float m = smoothstep(5.0, 20.0, abs(q.x));
	float h = sin(q.x * 0.071 + TAU * q.y / 120.0) * 1.4
			+ sin(q.x * 0.137 - TAU * q.y / 60.0 + 1.3) * 0.8
			+ sin(q.x * 0.029 + TAU * q.y / 300.0 + 0.7) * 2.6;
	return (h + 2.0) * m * hill_scale * hills;
}

// Colour ramps, in sRGB like a colour picker; converted once at the end.
vec3 grass_ramp(float t) {
	vec3 c = mix(vec3(0.14, 0.25, 0.10), vec3(0.22, 0.36, 0.15), smoothstep(0.0, 0.35, t));
	c = mix(c, vec3(0.32, 0.45, 0.18), smoothstep(0.35, 0.7, t));
	return mix(c, vec3(0.46, 0.48, 0.24), smoothstep(0.7, 1.0, t));
}
vec3 dirt_ramp(float t) {
	vec3 c = mix(vec3(0.64, 0.55, 0.42), vec3(0.52, 0.41, 0.28), smoothstep(0.0, 0.45, t));
	c = mix(c, vec3(0.43, 0.33, 0.21), smoothstep(0.45, 0.8, t));
	return mix(c, vec3(0.36, 0.27, 0.17), smoothstep(0.8, 1.0, t));
}
vec3 to_linear(vec3 c) { return c * (c * (c * 0.305306 + 0.682171) + 0.012523); }

void vertex() {
	p = vec2(VERTEX.x, path_offset - VERTEX.z);
	VERTEX.y += height(p);
	float e = 0.5;
	float hx = height(p + vec2(e, 0.0)) - height(p - vec2(e, 0.0));
	float hs = height(p + vec2(0.0, e)) - height(p - vec2(0.0, e));
	NORMAL = normalize(vec3(-hx, 2.0 * e, hs));
	// Patches about 15-25 m across. The ground has a vertex every few metres, so
	// this costs almost nothing compared with doing it for every pixel.
	float v = 0.5 + 0.28 * sin(p.x * 0.31 + TAU * p.y / 24.0)
			+ 0.22 * sin(p.x * 0.19 - TAU * p.y / 16.0 + 2.1);
	grass_tint = vec3(0.54) + 0.68 * to_linear(grass_ramp(clamp(v, 0.0, 1.0)));
}

void fragment() {
	// Wavy road edge: a few sines along the road (periods divide 2400 m).
	float wobble = sin(TAU * p.y / 3.0 + 0.4) * 0.14 + sin(TAU * p.y / 1.25 + p.x * 2.0) * 0.08;
	float edge = abs(p.x) + wobble;
	float road = 1.0 - smoothstep(road_half_width - 0.2, road_half_width + 0.35, edge);
	float rut = smoothstep(0.14, 0.0, abs(abs(p.x) - 0.65)) * 0.22;
	vec3 col;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	if (textured > 0.5) {
		// Two texture reads in all: one for colour, one for surface detail.
		vec2 uv = p * 0.42;
		vec3 m = texture(ground_mix, uv).rgb;
		vec3 grass = grass_ramp(m.r) * (0.85 + 0.3 * m.b);
		vec3 dirt = dirt_ramp(m.g) * (1.0 - rut);
		col = to_linear(mix(grass, dirt, road)) * mix(grass_tint, vec3(1.0), road);
		float dist = length(VERTEX);
		if (dist < normals_fade_end) {
			// Far away the detail is too small to see, so it's skipped there.
			vec4 nm = texture(ground_normals, uv);
			NORMAL_MAP = vec3(mix(nm.rg, nm.ba, road), 1.0);
			NORMAL_MAP_DEPTH = 0.9 * (1.0 - smoothstep(normals_fade_start, normals_fade_end, dist));
		}
	} else {
		float n = noise(p * 0.35) * 0.6 + noise(p * 1.7) * 0.3 + noise(p * 6.0) * 0.1;
		vec3 grass = mix(grass_a, grass_b, n);
		vec3 dirt = mix(dirt_a, dirt_b, noise(p * 3.0) * 0.7 + n * 0.3) * (1.0 - rut);
		col = mix(grass, dirt, road);
		if (detail > 0.5) {
			// Fine detail for close up: grass streaks and pebbles. Extra work per pixel.
			float blades = noise(vec2(p.x * 40.0, p.y * 9.0)) * noise(p * 23.0);
			float pebbles = smoothstep(0.82, 0.9, noise(p * 14.0)) * road;
			col *= 0.85 + 0.3 * mix(blades, 0.5, road);
			col = mix(col, vec3(0.62, 0.58, 0.52), pebbles * 0.6);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
"""

var ground_material := ShaderMaterial.new()
var plant_material := ShaderMaterial.new()
var grass_material := ShaderMaterial.new()
var blob_material := ShaderMaterial.new()
var blob_mesh := QuadMesh.new()
var lantern_material := StandardMaterial3D.new()
var trunk_mesh := CylinderMesh.new()
var cone_mesh := CylinderMesh.new()
var round_mesh := SphereMesh.new()
var rock_mesh := SphereMesh.new()
var post_mesh := BoxMesh.new()
var lantern_mesh := BoxMesh.new()
var tuft_mesh: ArrayMesh
var cloud_texture: NoiseTexture2D

var _fireflies: GPUParticles3D
var _pollen: GPUParticles3D
var _env: Environment
var _particle_speed := -1.0


func _init() -> void:
	display_name = "Forest"
	var gs := Shader.new()
	gs.code = GROUND_SHADER
	ground_material.shader = gs
	ground_material.set_shader_parameter("road_half_width", ROAD_HALF_WIDTH)
	ground_material.set_shader_parameter("hill_scale", HILL_SCALE)
	_make_ground_textures()

	var ps := Shader.new()
	ps.code = PLANT_SHADER
	plant_material.shader = ps
	var grs := Shader.new()
	grs.code = GRASS_SHADER
	grass_material.shader = grs
	var bs := Shader.new()
	bs.code = BLOB_SHADER
	blob_material.shader = bs
	blob_mesh.size = Vector2(1, 1)
	blob_mesh.orientation = PlaneMesh.FACE_Y
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
	tuft_mesh = _make_tuft_mesh()

	var cloud_noise := FastNoiseLite.new()
	cloud_noise.seed = 11
	cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cloud_noise.frequency = 0.006
	cloud_noise.fractal_octaves = 5
	cloud_texture = _noise_texture(cloud_noise, null, false)
	_update_materials()


## Height of the ground at a point: x across the road, s along it. Matches the
## ground shader's height(), so scenery sits on the hills.
static func ground_height(x: float, s: float, hills_on: bool) -> float:
	if not hills_on:
		return 0.0
	var m := smoothstep(5.0, 20.0, absf(x))
	if m <= 0.0:
		return 0.0
	var h := sin(x * 0.071 + TAU * s / 120.0) * 1.4 \
			+ sin(x * 0.137 - TAU * s / 60.0 + 1.3) * 0.8 \
			+ sin(x * 0.029 + TAU * s / 300.0 + 0.7) * 2.6
	return (h + 2.0) * m * HILL_SCALE


## Sky with clouds, distant mountains, the low sun, and fireflies and pollen.
## These don't scroll, so the horizon stays put.
func build_backdrop(parent: Node3D) -> void:
	parent.add_child(make_sky_dome(SKY_TOP, SKY_HORIZON, SUN_COLOR, SUN_DIR, cloud_texture))

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
	add_multimesh(parent, cone_mesh, xforms, colors, mountain_mat)

	sun = DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	sun.transform.basis = Basis.looking_at(-SUN_DIR, Vector3.UP)
	parent.add_child(sun)

	# Fireflies: glowing specks that wander, flicker and drift past at your speed.
	var flicker := Gradient.new()
	flicker.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0])
	flicker.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.25),
			Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_fireflies = _make_particles(60, 7.0, Vector3(12, 1.0, 16), Vector3(0, 1.2, -10), 0.05,
			Color(0.85, 1.0, 0.45), true, 0.35, flicker)
	parent.add_child(_fireflies)
	# Pollen and seeds: tiny pale motes catching the light.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	_pollen = _make_particles(140, 9.0, Vector3(8, 1.5, 14), Vector3(0, 1.6, -8), 0.014,
			Color(1.0, 0.95, 0.85), false, 0.15, fade)
	parent.add_child(_pollen)
	_update_materials()


func apply_environment(env: Environment) -> void:
	_env = env
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.7
	_update_materials()


## Particles drift past at your walking speed, like everything else.
func update(_delta: float, speed: float) -> void:
	if absf(speed - _particle_speed) < 0.02:
		return
	_particle_speed = speed
	for p in [_fireflies, _pollen]:
		if p:
			var m := p.process_material as ParticleProcessMaterial
			m.initial_velocity_min = maxf(speed - 0.05, 0.0)
			m.initial_velocity_max = speed + 0.05


## Fills one stretch of path. The chunk covers local z from 0 (near end) to
## -length (far end). Same index -> same scenery. Returns its gaze targets.
func populate(chunk: Node3D, index: int, length: float) -> Array[TFXGazeTarget]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(index * 7919 + 13)
	var hills := option("hills")
	var s0 := fmod(index * length, 2400.0)   # path distance at the chunk's near end
	var ground_y := func(x: float, z: float) -> float: return ground_height(x, s0 - z, hills)

	chunk.add_child(make_ground(ground_material, index, length, GROUND_WIDTH))
	var ground := chunk.get_child(chunk.get_child_count() - 1) as MeshInstance3D
	var ground_mesh := PlaneMesh.new()   # finer, so the hills can be shaped
	ground_mesh.size = Vector2(GROUND_WIDTH, length)
	ground_mesh.center_offset = Vector3(0, 0, -length / 2.0)
	# Kept even without hills: the grass colour variation is worked out per vertex.
	ground_mesh.subdivide_width = 40
	ground_mesh.subdivide_depth = 8
	ground.mesh = ground_mesh

	var trunks: Array[Transform3D] = []
	var trunk_colors: Array[Color] = []
	var trunk_ground := PackedFloat32Array()
	var leaves: Array[Transform3D] = []
	var leaf_colors: Array[Color] = []
	var leaf_ground := PackedFloat32Array()
	var rounds: Array[Transform3D] = []
	var round_colors: Array[Color] = []
	var round_ground := PackedFloat32Array()
	var blobs: Array[Transform3D] = []
	for i in roundi(46 * density):
		if i % 24 == 23:
			await next_frame()   # a few dozen trees per frame keeps each frame light
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (3.6 + pow(rng.randf(), 1.7) * 55.0)
		var z := -rng.randf() * length
		var y: float = ground_y.call(x, z) - 0.15
		var h := rng.randf_range(2.5, 7.0)
		var trunk_h := h * 0.35
		trunks.append(Transform3D(Basis.from_scale(Vector3(1, trunk_h, 1) * (h / 5.0 + 0.4)),
				Vector3(x, y + trunk_h * (h / 5.0 + 0.4) / 2.0, z)))
		trunk_colors.append(Color(0.30, 0.21, 0.15).darkened(rng.randf() * 0.3))
		trunk_ground.append(y)
		if absf(x) < 30.0:
			var r := h * 0.45
			blobs.append(Transform3D(Basis.from_scale(Vector3(r, 1, r)), Vector3(x, y + 0.19, z)))
		var green := Color(0.13, 0.30, 0.18).lerp(Color(0.25, 0.38, 0.16), rng.randf())
		if rng.randf() < 0.7:
			# Pine: stacked cones.
			for layer in 3:
				var w := h * (0.34 - layer * 0.08)
				var lh := h * 0.42
				leaves.append(Transform3D(Basis.from_scale(Vector3(w, lh, w)),
						Vector3(x, y + trunk_h + layer * h * 0.2 + lh / 2.0, z)))
				leaf_colors.append(green.lightened(layer * 0.05))
				leaf_ground.append(y)
		else:
			var r := h * 0.3
			rounds.append(Transform3D(Basis.from_scale(Vector3(r, r * 0.9, r)),
					Vector3(x, y + trunk_h + r * 0.7, z)))
			round_colors.append(green.lerp(Color(0.45, 0.35, 0.12), rng.randf() * 0.5))
			round_ground.append(y)

	var rocks: Array[Transform3D] = []
	var rock_colors: Array[Color] = []
	var rock_ground := PackedFloat32Array()
	for i in roundi(14 * density):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(0.15, 0.7)
		var x := side * rng.randf_range(2.0, 14.0)
		var z := -rng.randf() * length
		var gy: float = ground_y.call(x, z)
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 1.3, s * 0.6, s)),
				Vector3(x, gy + s * 0.15, z)))
		rock_ground.append(gy)
		rock_colors.append(Color(0.42, 0.40, 0.42).darkened(rng.randf() * 0.3))
	for i in roundi(18 * density):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(0.25, 0.6)
		var x := side * rng.randf_range(2.2, 9.0)
		var z := -rng.randf() * length
		var gy: float = ground_y.call(x, z)
		rounds.append(Transform3D(Basis.from_scale(Vector3(s * 1.4, s, s * 1.4)),
				Vector3(x, gy + s * 0.5, z)))
		round_ground.append(gy)
		round_colors.append(Color(0.18, 0.32, 0.15).lerp(Color(0.3, 0.38, 0.18), rng.randf()))

	await next_frame()   # spread the work: trees, then the rest
	add_multimesh(chunk, trunk_mesh, trunks, trunk_colors, plant_material, trunk_ground)
	add_multimesh(chunk, cone_mesh, leaves, leaf_colors, plant_material, leaf_ground)
	add_multimesh(chunk, round_mesh, rounds, round_colors, plant_material, round_ground)
	add_multimesh(chunk, rock_mesh, rocks, rock_colors, plant_material, rock_ground)
	if option("blob_shadows") and not blobs.is_empty():
		var blob_colors: Array[Color] = []
		blob_colors.resize(blobs.size())
		blob_colors.fill(Color.WHITE)
		add_multimesh(chunk, blob_mesh, blobs, blob_colors, blob_material)
		chunk.get_child(chunk.get_child_count() - 1).set_meta("tfx_no_shadow", true)

	if option("grass"):
		await next_frame()
		_add_grass(chunk, rng, length, ground_y)

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
	if option("lantern_lights"):
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 1.5
		light.omni_range = 7.0
		light.position = lantern.position
		chunk.add_child(light)

	await next_frame()
	_add_sounds(chunk, rng, length, ground_y)
	return [_waystone(chunk, rng, length, ground_y)]


## Grass tufts, thickest along the road verges and thinning out further away.
func _add_grass(chunk: Node3D, rng: RandomNumberGenerator, length: float, ground_y: Callable) -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for i in roundi(380 * density):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * (ROAD_HALF_WIDTH + 0.25 + pow(rng.randf(), 1.8) * 11.0)
		var z := -rng.randf() * length
		var s := rng.randf_range(0.7, 1.35)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
				Vector3(x, ground_y.call(x, z), z)))
		colors.append(Color(1, 1, 1).lerp(Color(1.15, 1.05, 0.7), rng.randf() * 0.6))
	add_multimesh(chunk, tuft_mesh, xforms, colors, grass_material)
	chunk.get_child(chunk.get_child_count() - 1).set_meta("tfx_no_shadow", true)


## A cricket in the grass by the road, and usually a songbird up in a tree. They
## scroll past with the path, so you hear them go by on your left or right.
func _add_sounds(chunk: Node3D, rng: RandomNumberGenerator, length: float, ground_y: Callable) -> void:
	var cricket := TFXSpatialSound.new()
	cricket.stream = DemoSounds.CRICKET
	cricket.unit_size = 1.6
	cricket.max_distance = 30.0
	cricket.pitch_scale = rng.randf_range(0.94, 1.06)
	cricket.autoplay = true
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var cx := side * rng.randf_range(2.2, 5.0)
	var cz := -rng.randf() * length
	cricket.position = Vector3(cx, ground_y.call(cx, cz) + 0.1, cz)
	chunk.add_child(cricket)
	if rng.randf() < 0.75:
		var bird := DemoSongbird.new()
		bird.call_index = rng.randi()
		side = -1.0 if rng.randf() < 0.5 else 1.0
		var bx := side * rng.randf_range(5.0, 18.0)
		var bz := -rng.randf() * length
		bird.position = Vector3(bx, ground_y.call(bx, bz) + rng.randf_range(3.0, 6.0), bz)
		chunk.add_child(bird)


func get_options() -> Array[Dictionary]:
	return [
		{"key": "textured_ground", "label": "Textured ground (grass and dirt with surface detail)", "default": true},
		{"key": "hills", "label": "Rolling hills", "default": true, "rebuild": true},
		{"key": "grass", "label": "Grass tufts along the road", "default": true, "rebuild": true},
		{"key": "clouds", "label": "Drifting clouds", "default": true},
		{"key": "mist", "label": "Ground mist", "default": true},
		{"key": "fireflies", "label": "Fireflies", "default": true},
		{"key": "pollen", "label": "Floating pollen", "default": true},
		{"key": "tree_shading", "label": "Tree shading (darker undersides and bases)", "default": true},
		{"key": "wind", "label": "Trees and grass sway in the wind", "default": true},
		{"key": "blob_shadows", "label": "Soft shadows under trees (fake, cheap)", "default": true, "rebuild": true},
		{"key": "ground_detail", "label": "Procedural ground detail (when textures are off)", "default": true},
		{"key": "lantern_lights", "label": "Lanterns cast real light (costly)", "default": false, "rebuild": true},
	]


func set_option(key: String, value: bool) -> void:
	super(key, value)
	_update_materials()


func _update_materials() -> void:
	plant_material.set_shader_parameter("shading", 1.0 if option("tree_shading") else 0.0)
	plant_material.set_shader_parameter("wind", 1.0 if option("wind") else 0.0)
	grass_material.set_shader_parameter("wind", 1.0 if option("wind") else 0.0)
	ground_material.set_shader_parameter("detail", 1.0 if option("ground_detail") else 0.0)
	ground_material.set_shader_parameter("textured", 1.0 if option("textured_ground") else 0.0)
	ground_material.set_shader_parameter("hills", 1.0 if option("hills") else 0.0)
	if sky_material:
		sky_material.set_shader_parameter("clouds", 1.0 if option("clouds") else 0.0)
	if _fireflies:
		_fireflies.visible = option("fireflies")
	if _pollen:
		_pollen.visible = option("pollen")
	if _env:
		# Height fog: thicker below about knee height, so it pools in the dips.
		_env.fog_height = 0.5
		_env.fog_height_density = 0.035 if option("mist") else 0.0


## Eye-tracking test object: a rune-marked stone, sometimes obvious, sometimes hidden.
func _waystone(chunk: Node3D, rng: RandomNumberGenerator, length: float, ground_y: Callable) -> TFXGazeTarget:
	var target := TFXGazeTarget.new()
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
		var x := side * rng.randf_range(2.6, 3.6)
		target.position = Vector3(x, ground_y.call(x, z) + 0.45, z)
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
		var x := side * rng.randf_range(4.0, 10.0)
		target.position = Vector3(x, ground_y.call(x, z) + 0.05, z)
		target.rotation.x = 0.4
	else:
		target.label = "charm in a tree"
		var charm := BoxMesh.new()
		charm.size = Vector3(0.18, 0.24, 0.05)
		mesh.mesh = charm
		target.radius = 0.18
		var x := side * rng.randf_range(3.8, 7.0)
		target.position = Vector3(x, ground_y.call(x, z) + rng.randf_range(2.6, 3.8), z)
	target.add_child(mesh)
	chunk.add_child(target)
	return target


# --- Generated assets -------------------------------------------------------------

## Grass and dirt come from two small pre-made textures (see
## textures/generate_textures.py), compressed for the GPU.
func _make_ground_textures() -> void:
	ground_material.set_shader_parameter("ground_mix", load("res://demo/textures/ground_mix.png"))
	ground_material.set_shader_parameter("ground_normals", load("res://demo/textures/ground_normals.png"))


func _noise_texture(noise: FastNoiseLite, colors: Gradient, normal_map: bool,
		bump := 4.0) -> NoiseTexture2D:
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	if normal_map:
		tex.as_normal_map = true
		tex.bump_strength = bump
	elif colors:
		tex.color_ramp = colors
	return tex


static var _dot: GradientTexture2D


## A small round glow that fades to transparent at the edge, for particles.
static func _soft_dot() -> GradientTexture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	_dot = GradientTexture2D.new()
	_dot.gradient = g
	_dot.width = 64
	_dot.height = 64
	_dot.fill = GradientTexture2D.FILL_RADIAL
	_dot.fill_from = Vector2(0.5, 0.5)
	_dot.fill_to = Vector2(1.0, 0.5)
	return _dot


## One tuft: seven thin blades, dark at the base and lighter at the tip.
static func _make_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 7:
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.06)
		var across := Vector3(-sin(a), 0, cos(a)) * 0.018
		var tip := base + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.03, 0.1) \
				+ Vector3.UP * rng.randf_range(0.22, 0.42)
		var base_color := Color(0.10, 0.20, 0.07)
		var tip_color := Color(0.42, 0.52, 0.20).lerp(Color(0.55, 0.50, 0.25), rng.randf() * 0.5)
		for v in [[base - across, base_color], [base + across, base_color], [tip, tip_color]]:
			st.set_normal(Vector3.UP)
			st.set_color(v[1])
			st.add_vertex(v[0])
	return st.commit()


func _make_particles(amount: int, lifetime: float, extents: Vector3, center: Vector3,
		size: float, color: Color, glow: bool, turbulence: float, ramp: Gradient) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.position = center
	p.visibility_aabb = AABB(Vector3(-25, -4, -30), Vector3(50, 12, 60))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = extents
	m.direction = Vector3(0, 0, 1)   # towards you, like the scrolling world
	m.spread = 12.0
	m.gravity = Vector3.ZERO
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.0
	m.turbulence_noise_scale = 4.0
	m.turbulence_noise_speed = Vector3(0.1, 0.1, 0.1)
	m.turbulence_influence_min = turbulence * 0.5
	m.turbulence_influence_max = turbulence
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	m.color_ramp = ramp_tex
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if glow else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.albedo_texture = _soft_dot()   # round and soft, not a square
	mat.disable_fog = glow
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.set_meta("tfx_no_shadow", true)
	return p
