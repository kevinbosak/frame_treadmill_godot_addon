class_name TFXPathWorld
extends Node3D
## Treadmill Frame XR Kit: an endless path that moves at the player's walking speed.
##
## The path is a row of chunks along local -Z. The player stays put (they're on
## a treadmill); the chunks slide towards them. When a chunk falls far enough
## behind, it jumps to the front and is refilled, so the world never ends and
## only a few chunks exist at once. The theme's backdrop (sky, mountains) doesn't
## scroll, so the horizon stays steady.
##
## Use: call setup(theme) once, then hand it to TFXRig as rig.world_root. The rig
## lines it up with the treadmill and feeds it the walking speed.

signal target_passed(target: TFXGazeTarget)

@export var chunk_length := 30.0
@export var chunks_behind := 2
## Keep (chunks_ahead x chunk_length) about where the theme's fog hides things.
@export var chunks_ahead := 5

## Walking speed (m/s). TFXRig sets this every frame.
var speed := 0.0
## Distance travelled along the path (m).
var distance := 0.0
var theme: TFXPathTheme
## Whether scenery casts shadows (set through set_shadows()).
var shadows := false

var _scroll := Node3D.new()
var _chunks: Array[Node3D] = []
var _indices: Array[int] = []
var _targets := {}   # chunk -> Array[TFXGazeTarget]
var _generation := {}   # chunk -> build number, so an outdated build is dropped


## Builds the path with the given look. Call once; uses the plain base look if null.
func setup(path_theme: TFXPathTheme = null) -> void:
	theme = path_theme if path_theme else TFXPathTheme.new()
	theme.build_backdrop(self)
	add_child(_scroll)
	for k in chunks_behind + chunks_ahead:
		var chunk := Node3D.new()
		chunk.position.z = (chunks_behind - k) * chunk_length
		_scroll.add_child(chunk)
		_chunks.append(chunk)
		_indices.append(k - chunks_behind)
		_fill(chunk, k - chunks_behind)


## Lines the path up with the treadmill: starts under the belt, runs the way you face.
func align(f: TFXFootprint) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.forward.x, -f.forward.y)),
			Vector3(f.center.x, 0.0, f.center.y))


func _process(delta: float) -> void:
	if theme == null or not is_visible_in_tree():
		return
	var ds := speed * delta
	distance += ds
	theme.update(delta, speed)
	var count := _chunks.size()
	for i in count:
		var chunk := _chunks[i]
		chunk.position.z += ds
		if chunk.position.z > (chunks_behind + 1) * chunk_length:
			chunk.position.z -= count * chunk_length
			_indices[i] += count
			_fill(chunk, _indices[i])
		for t: TFXGazeTarget in _targets.get(chunk, []):
			if not t.passed and chunk.position.z + t.position.z > 0.5:
				t.passed = true
				target_passed.emit(t)


## Rebuilds every chunk in place, e.g. after a density or option change.
func rebuild() -> void:
	for i in _chunks.size():
		_fill(_chunks[i], _indices[i])


## Turns shadow casting on or off for all scenery (the theme's sun must cast
## shadows too; TFXGraphics handles that).
func set_shadows(on: bool) -> void:
	shadows = on
	for chunk in _chunks:
		_apply_shadow_casting(chunk)


## Builds new scenery for a chunk outside the scene, then swaps it in. A theme
## may spread populate() over several frames (`await next_frame()`), which avoids
## a hitch every time a stretch is recycled; the old scenery stays until then
## (it's far ahead in the fog by that point).
func _fill(chunk: Node3D, index: int) -> void:
	var build: int = _generation.get(chunk, 0) + 1
	_generation[chunk] = build
	TFXGraphics.note("forest stretch build started")
	var content := Node3D.new()
	var targets: Array[TFXGazeTarget] = await theme.populate(content, index, chunk_length)
	if _generation.get(chunk) != build or not is_instance_valid(chunk):
		content.free()   # a newer build for this chunk has started
		return
	for child in chunk.get_children():
		chunk.remove_child(child)   # leaves its groups at once
		child.queue_free()
	_apply_shadow_casting(content)
	chunk.add_child(content)
	_targets[chunk] = targets
	TFXGraphics.note("forest stretch swapped in")


## Geometry casts shadows when they're on, except nodes tagged "tfx_no_shadow".
func _apply_shadow_casting(node: Node) -> void:
	for child in node.get_children():
		var g := child as GeometryInstance3D
		if g and not g.has_meta("tfx_no_shadow"):
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_apply_shadow_casting(child)
