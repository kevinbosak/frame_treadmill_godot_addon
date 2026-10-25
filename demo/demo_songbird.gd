class_name DemoSongbird
extends TFXSpatialSound
## A bird hidden in a tree that sings every few seconds. Placed by the theme,
## so it scrolls past with the path.

## Which of DemoSounds.BIRD_CALLS this bird sings.
var call_index := 0
var _wait := 0.0


func _ready() -> void:
	super()
	stream = DemoSounds.BIRD_CALLS[call_index % DemoSounds.BIRD_CALLS.size()]
	unit_size = 7.0
	max_distance = 80.0
	_wait = randf_range(0.5, 6.0)


func _process(delta: float) -> void:
	super(delta)
	_wait -= delta
	if _wait <= 0.0:
		pitch_scale = randf_range(0.95, 1.06)
		play()
		_wait = randf_range(4.0, 10.0)
