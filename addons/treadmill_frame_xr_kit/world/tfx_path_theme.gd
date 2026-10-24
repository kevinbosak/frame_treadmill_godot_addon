class_name TFXPathTheme
extends RefCounted
## Treadmill Frame XR Kit: decides how a TFXPathWorld looks.
##
## Subclass it and override the three functions to make a new setting. This
## base class is a plain, usable look on its own: sky, grid ground, no scenery.
## The helpers at the bottom (sky dome, batched meshes) are for subclasses.
##
## Coordinates: the path runs along local -Z, centred on x = 0, ground at y = 0.

const GRID_SHADER := """shader_type spatial;
instance uniform float path_offset = 0.0;
uniform vec3 base_color : source_color = vec3(0.20, 0.33, 0.20);
uniform vec3 line_color : source_color = vec3(0.42, 0.62, 0.38);
varying vec2 p;

void vertex() { p = vec2(VERTEX.x, path_offset - VERTEX.z); }

void fragment() {
	vec2 g = abs(fract(p) - 0.5);
	ALBEDO = mix(base_color, line_color, step(0.47, max(g.x, g.y)));
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

var _grid_material: ShaderMaterial
var _ground_mesh := PlaneMesh.new()


## Things that don't scroll: sky, distant scenery, lights. Called once.
func build_backdrop(parent: Node3D) -> void:
	parent.add_child(make_sky_dome(Color(0.35, 0.55, 0.9), Color(0.75, 0.85, 0.95),
			Color(1, 0.95, 0.85), Vector3(0.3, 0.5, -0.8)))
	var sun := DirectionalLight3D.new()
	sun.transform.basis = Basis.looking_at(Vector3(-0.3, -0.7, -0.6), Vector3.UP)
	parent.add_child(sun)


## Called when World view turns on: fog, ambient light and so on.
func apply_environment(env: Environment) -> void:
	env.fog_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6


## Fills one stretch of path. The chunk covers local z from 0 (near end) to
## -length (far end); the same index must always give the same scenery.
## Return the chunk's gaze targets (if any) so the world can report them passing.
func populate(chunk: Node3D, index: int, length: float) -> Array[TFXGazeTarget]:
	if _grid_material == null:
		var shader := Shader.new()
		shader.code = GRID_SHADER
		_grid_material = ShaderMaterial.new()
		_grid_material.shader = shader
	chunk.add_child(make_ground(_grid_material, index, length, 160.0))
	return []


# --- Helpers for subclasses ------------------------------------------------------

## A ground strip for one chunk. Shaders can use `instance uniform float
## path_offset` (distance along the path) so patterns line up across chunks.
func make_ground(material: Material, index: int, length: float, width: float) -> MeshInstance3D:
	var ground := MeshInstance3D.new()
	_ground_mesh.size = Vector2(width, length)
	_ground_mesh.center_offset = Vector3(0, 0, -length / 2.0)
	ground.mesh = _ground_mesh
	ground.material_override = material
	# Wrapping keeps the shader's numbers small on long walks.
	ground.set_instance_shader_parameter("path_offset", fmod(index * length, 2400.0))
	return ground


## An opaque gradient sky with a sun. It has to be opaque: in the headset the
## background is passthrough, so without it the room would show in the sky.
func make_sky_dome(top: Color, horizon: Color, sun_color: Color, sun_dir: Vector3) -> MeshInstance3D:
	var sky := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 400.0
	dome.height = 800.0
	dome.radial_segments = 32
	dome.rings = 16
	var shader := Shader.new()
	shader.code = SKY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("horizon_color", horizon)
	mat.set_shader_parameter("sun_color", sun_color)
	mat.set_shader_parameter("sun_dir", sun_dir)
	dome.material = mat
	sky.mesh = dome
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sky


## Many copies of one mesh in a single draw call, each with its own transform
## and colour (the material should use vertex colour as albedo).
func add_multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D],
		colors: Array[Color], material: Material) -> void:
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
