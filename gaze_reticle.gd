class_name GazeReticle
extends MeshInstance3D
## Shows where you're looking without covering it: four short arcs around the
## gaze point with an empty middle. On a target it wraps around the object and an
## outer arc fills as you keep looking, turning gold once it's noticed.

## Size of the empty middle, as an angle (degrees). About the accuracy of eye tracking.
const MIN_RADIUS_DEG := 1.6
const SEGMENTS := 4
const ARC_DEG := 55.0
const IDLE_COLOR := Color(1, 1, 1, 0.55)
const FOCUS_COLOR := Color(0.55, 0.9, 1.0, 0.85)
const DONE_COLOR := Color(1.0, 0.8, 0.3, 0.9)

var tracker: GazeTracker

var _lines := ImmediateMesh.new()
var _radius := 0.1
var _center := Vector3.ZERO
var _have := false


func _ready() -> void:
	mesh = _lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.disable_fog = true
	mat.render_priority = 120
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if tracker == null or tracker.camera == null:
		return
	var t := tracker.current
	var dist := tracker.gaze_distance
	var center := tracker.gaze_origin + tracker.gaze_dir * dist
	var radius := dist * tan(deg_to_rad(MIN_RADIUS_DEG))
	if t:
		center = t.global_position
		radius = maxf(radius, t.radius * 1.35)
	var k := 1.0 - exp(-delta / 0.04)
	_center = center if not _have else _center.lerp(center, k)
	_radius = radius if not _have else lerpf(_radius, radius, k)
	_have = true

	var to_cam := tracker.camera.global_position - _center
	var up := Vector3.UP if absf(to_cam.normalized().y) < 0.98 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(to_cam, up), _center)
	_draw(t)


func _draw(t: GazeTarget) -> void:
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var color := IDLE_COLOR
	if t:
		color = DONE_COLOR if t.noticed else FOCUS_COLOR
	var thickness := _radius * 0.16
	var step := 360.0 / SEGMENTS
	for i in SEGMENTS:
		var start := i * step + (step - ARC_DEG) / 2.0 + 45.0
		_arc(_radius, thickness, start, ARC_DEG, color)
	if t and not t.noticed and t.progress() > 0.0:
		_arc(_radius * 1.3, thickness * 0.8, 90.0, -360.0 * t.progress(), FOCUS_COLOR)
	_lines.surface_end()


func _arc(r: float, thickness: float, start_deg: float, sweep_deg: float, color: Color) -> void:
	var steps := maxi(3, int(absf(sweep_deg) / 8.0))
	for s in steps:
		var a0 := deg_to_rad(start_deg + sweep_deg * s / steps)
		var a1 := deg_to_rad(start_deg + sweep_deg * (s + 1) / steps)
		var i0 := Vector3(cos(a0), sin(a0), 0) * r
		var o0 := Vector3(cos(a0), sin(a0), 0) * (r + thickness)
		var i1 := Vector3(cos(a1), sin(a1), 0) * r
		var o1 := Vector3(cos(a1), sin(a1), 0) * (r + thickness)
		for v in [i0, o0, o1, i0, o1, i1]:
			_lines.surface_set_color(color)
			_lines.surface_add_vertex(v)
