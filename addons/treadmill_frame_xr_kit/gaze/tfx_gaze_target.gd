class_name TFXGazeTarget
extends Node3D
## Treadmill Frame XR Kit: something the player can notice by looking at it: a clue, a waystone, an enemy.
## TFXGazeTracker decides what you're looking at; this node keeps the score.
## It counts as noticed once your gaze has rested on it for dwell_required seconds.

signal noticed_by_player

## Every target joins this group; TFXGazeTracker looks through it.
const GROUP := &"tfx_gaze_targets"

## Rough size of the object (m), so big things are easier to look at than small ones.
@export var radius := 0.2
## How long your gaze must rest on it to count as noticed (s).
@export var dwell_required := 0.5
## Too far away to count (m).
@export var max_distance := 40.0
## Optional: a material whose glow shows dwell progress and turns gold when noticed.
var glow_material: StandardMaterial3D
var label := "target"

var dwell := 0.0
var gazed := false
var noticed := false
## Set by the world once you've walked past it.
var passed := false
var noticed_at_msec := 0

const IDLE_GLOW := Color(0.35, 0.8, 1.0)
const NOTICED_GLOW := Color(1.0, 0.75, 0.25)


func _ready() -> void:
	add_to_group(GROUP)
	_update_glow()


func progress() -> float:
	return clampf(dwell / dwell_required, 0.0, 1.0)


## Called by TFXGazeTracker every frame.
func update_dwell(delta: float, looking: bool) -> bool:
	gazed = looking
	if looking:
		dwell += delta
	else:
		dwell = maxf(dwell - delta * 1.5, 0.0)
	var just_noticed := false
	if not noticed and dwell >= dwell_required:
		noticed = true
		noticed_at_msec = Time.get_ticks_msec()
		just_noticed = true
		noticed_by_player.emit()
	_update_glow()
	return just_noticed


func _update_glow() -> void:
	if glow_material == null:
		return
	if noticed:
		glow_material.emission = NOTICED_GLOW
		glow_material.emission_energy_multiplier = 3.0
	else:
		glow_material.emission = IDLE_GLOW
		glow_material.emission_energy_multiplier = 0.25 + 1.5 * progress()
