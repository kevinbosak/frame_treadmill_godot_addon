class_name TFXBobWaveform
extends MeshInstance3D
## Draws the last few seconds of head bob as a line graph, for tuning.
## White: filtered bob. Yellow: detection threshold. Green ticks: counted steps.

const WIDTH := 0.7         # metres across
const HISTORY := 3.0       # seconds shown
## Graph is drawn this many times larger than the real bob.
const VERTICAL_SCALE := 2.5
## Redraws per second, and the most line segments drawn (keeps it cheap).
const REDRAW_RATE := 20.0
const MAX_SEGMENTS := 120

var _samples: Array[Vector3] = []  # x = time, y = bob, z = threshold
var _steps: Array[float] = []
var _time := 0.0
var _lines := ImmediateMesh.new()
var _redraw_wait := 0.0


func _ready() -> void:
	mesh = _lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 116
	material_override = mat


func add_sample(value: float, threshold: float, dt: float, stepped: bool) -> void:
	_time += dt
	_samples.append(Vector3(_time, value, threshold))
	if stepped:
		_steps.append(_time)
	while not _samples.is_empty() and _time - _samples[0].x > HISTORY:
		_samples.pop_front()
	while not _steps.is_empty() and _time - _steps[0] > HISTORY:
		_steps.pop_front()


func _process(delta: float) -> void:
	_redraw_wait -= delta
	if _redraw_wait > 0.0 or not is_visible_in_tree():
		return
	_redraw_wait = 1.0 / REDRAW_RATE
	_lines.clear_surfaces()
	if _samples.size() < 2:
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	_line(Vector3(-WIDTH / 2, 0, 0), Vector3(WIDTH / 2, 0, 0), Color(1, 1, 1, 0.3))
	var stride := maxi(1, ceili(float(_samples.size()) / MAX_SEGMENTS))
	for i in range(stride, _samples.size(), stride):
		var a := _samples[i - stride]
		var b := _samples[i]
		_line(_point(a.x, a.z), _point(b.x, b.z), Color(1, 0.85, 0.2))
		_line(_point(a.x, a.y), _point(b.x, b.y), Color.WHITE)
	for t in _steps:
		_line(_point(t, -0.03), _point(t, 0.03), Color(0.3, 1, 0.4))
	_lines.surface_end()


func _point(t: float, value: float) -> Vector3:
	return Vector3((t - _time) / HISTORY * WIDTH + WIDTH / 2, value * VERTICAL_SCALE, 0)


func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)
