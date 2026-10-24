class_name PathWorld
extends Node3D
## The endless walking path.
##
## The path is a row of chunks along local -Z. You stay put (you're on a
## treadmill); the chunks slide towards you at your walking speed. When a chunk
## falls far enough behind, it jumps to the front and is refilled with new
## scenery, so the world never ends and only a few chunks exist at once.
## The sky and mountains don't scroll, so the horizon stays steady.

signal target_passed(target: GazeTarget)

const CHUNK_LENGTH := 30.0
const CHUNKS_BEHIND := 2
const CHUNKS_AHEAD := 5   # 150 m; fog hides anything further

## Walking speed (m/s), set every frame by the game.
var speed := 0.0
## Distance travelled along the path (m).
var distance := 0.0
var theme := ForestTheme.new()

var _scroll := Node3D.new()
var _chunks: Array[Node3D] = []
var _indices: Array[int] = []
var _targets := {}   # chunk -> Array[GazeTarget]


func _ready() -> void:
	theme.build_backdrop(self)
	add_child(_scroll)
	for k in CHUNKS_BEHIND + CHUNKS_AHEAD:
		var chunk := Node3D.new()
		chunk.position.z = (CHUNKS_BEHIND - k) * CHUNK_LENGTH
		_scroll.add_child(chunk)
		_chunks.append(chunk)
		_indices.append(k - CHUNKS_BEHIND)
		_fill(chunk, k - CHUNKS_BEHIND)


## Lines the path up with the treadmill: starts under the belt, runs the way you face.
func align(f: TreadmillFootprint) -> void:
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.forward.x, -f.forward.y)),
			Vector3(f.center.x, 0.0, f.center.y))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var ds := speed * delta
	distance += ds
	var count := _chunks.size()
	for i in count:
		var chunk := _chunks[i]
		chunk.position.z += ds
		if chunk.position.z > (CHUNKS_BEHIND + 1) * CHUNK_LENGTH:
			chunk.position.z -= count * CHUNK_LENGTH
			_indices[i] += count
			_fill(chunk, _indices[i])
		for t: GazeTarget in _targets.get(chunk, []):
			if not t.passed and chunk.position.z + t.position.z > 0.5:
				t.passed = true
				target_passed.emit(t)


func _fill(chunk: Node3D, index: int) -> void:
	for child in chunk.get_children():
		chunk.remove_child(child)   # leaves its groups at once
		child.queue_free()
	_targets[chunk] = theme.populate(chunk, index, CHUNK_LENGTH)
