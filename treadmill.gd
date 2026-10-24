class_name Treadmill
extends Node
## The treadmill "service". It follows your head, counts steps, estimates your
## speed, knows where the treadmill is, warns when you drift towards an edge,
## and stores the app's settings and walking totals. The rest of the game reads from it.

signal settings_changed

const SAVE_PATH := "user://treadmill.cfg"
const OLD_CALIBRATION_PATH := "user://stride_calibration.cfg"
const MPS_PER_MPH := 0.44704

# --- Settings (saved on the headset) ------------------------------------------
## Treadmill speed you're walking at when you press Calibrate.
var calib_speed_mph := 3.0
## How close your head may come to each edge of the belt before a warning (m).
var margin_side := 0.12
var margin_back := 0.45
var margin_front := 0.15
## How high above the belt the see-through area reaches (m). Keep below your eyes.
var bubble_height := 1.1
var show_step_graph := true
var show_reticle := true
var footstep_sounds := true
## Display refresh rate chosen in Settings (Hz); 0 = headset default.
var refresh_rate := 0.0
## Everything you've ever walked in the app (m). Saved.
var lifetime_distance := 0.0
var footprint := TreadmillFootprint.new()
var calibration := StrideCalibration.new()

# --- Live readings ----------------------------------------------------------------
var detector := StepDetector.new()
## Set by the scene: the headset camera.
var camera: Node3D
var head := Vector3.ZERO
## Head position on the floor (x, z), smoothed so normal sway doesn't trigger warnings.
var head_floor := Vector2.ZERO
var stepped_this_frame := false
## Estimated walking speed (m/s), smoothed so the world won't surge.
var speed_mps := 0.0
## Empty when you're safely on the belt.
var edge_warning := ""
## Distance walked since the app started (m).
var session_distance := 0.0
var _unsaved_distance := 0.0

# Desktop simulation (no headset).
var sim_walking := false
var sim_cadence := 110.0
var _sim_phase := 0.0
var _have_head := false


func _ready() -> void:
	load_settings()


func _process(delta: float) -> void:
	if camera == null:
		return
	if sim_walking:
		_sim_phase += delta * sim_cadence / 60.0 * TAU
		camera.position.y = 1.6 + 0.02 * cos(_sim_phase) + randf_range(-0.002, 0.002)

	head = camera.global_position
	var floor_pos := Vector2(head.x, head.z)
	if not _have_head:
		head_floor = floor_pos
		_have_head = true
	head_floor = head_floor.lerp(floor_pos, 1.0 - exp(-delta / 0.3))

	stepped_this_frame = detector.add_sample(head.y, delta)
	var target := calibration.speed_for(detector.cadence_spm)
	speed_mps = lerpf(speed_mps, target, 1.0 - exp(-delta / 1.0))
	if target == 0.0 and speed_mps < 0.05:
		speed_mps = 0.0
	session_distance += speed_mps * delta
	lifetime_distance += speed_mps * delta
	_unsaved_distance += speed_mps * delta
	if _unsaved_distance > 50.0:   # save progress every 50 m
		save_settings()
	edge_warning = _check_edges()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()


## Only warns while you're walking, so stepping off the treadmill is quiet.
func _check_edges() -> String:
	if not footprint.is_valid() or detector.cadence_spm <= 0.0:
		return ""
	var p := footprint.to_local(head_floor)
	var half_w := footprint.width / 2.0
	var half_l := footprint.length / 2.0
	if p.x > half_w - margin_side:
		return "DRIFTING RIGHT"
	if p.x < -(half_w - margin_side):
		return "DRIFTING LEFT"
	if p.y < -(half_l - margin_back):
		return "DRIFTING BACK"
	if p.y > half_l - margin_front:
		return "TOO CLOSE TO THE FRONT"
	return ""


## Records your step length at the current cadence and calibration speed.
## Returns a message for the player.
func calibrate() -> String:
	if not detector.is_stable():
		return "Walk steadily for a few seconds, then calibrate"
	var step := calibration.add_point(detector.cadence_spm, calib_speed_mph * MPS_PER_MPH)
	save_settings()
	return "Calibrated: %d steps/min at %.1f mph = %.2f m steps" \
			% [roundi(detector.cadence_spm), calib_speed_mph, step]


func clear_calibration() -> void:
	calibration.clear()
	save_settings()


func set_footprint(f: TreadmillFootprint) -> void:
	footprint = f
	save_settings()


func speed_mph() -> float:
	return speed_mps / MPS_PER_MPH


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("calibration", "speed_mph", calib_speed_mph)
	cfg.set_value("calibration", "points", calibration.points)
	cfg.set_value("safety", "margin_side", margin_side)
	cfg.set_value("safety", "margin_back", margin_back)
	cfg.set_value("safety", "margin_front", margin_front)
	cfg.set_value("safety", "bubble_height", bubble_height)
	cfg.set_value("display", "show_step_graph", show_step_graph)
	cfg.set_value("display", "show_reticle", show_reticle)
	cfg.set_value("display", "footstep_sounds", footstep_sounds)
	cfg.set_value("display", "refresh_rate", refresh_rate)
	cfg.set_value("progress", "lifetime_distance", lifetime_distance)
	cfg.set_value("treadmill", "footprint", footprint.to_dict())
	cfg.save(SAVE_PATH)
	_unsaved_distance = 0.0
	settings_changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		# Bring over calibration saved by the earlier test version.
		if cfg.load(OLD_CALIBRATION_PATH) == OK:
			calibration.points.assign(cfg.get_value("stride", "points", []))
		return
	calib_speed_mph = cfg.get_value("calibration", "speed_mph", calib_speed_mph)
	calibration.points.assign(cfg.get_value("calibration", "points", []))
	margin_side = cfg.get_value("safety", "margin_side", margin_side)
	margin_back = cfg.get_value("safety", "margin_back", margin_back)
	margin_front = cfg.get_value("safety", "margin_front", margin_front)
	bubble_height = cfg.get_value("safety", "bubble_height", bubble_height)
	show_step_graph = cfg.get_value("display", "show_step_graph", show_step_graph)
	show_reticle = cfg.get_value("display", "show_reticle", show_reticle)
	footstep_sounds = cfg.get_value("display", "footstep_sounds", footstep_sounds)
	refresh_rate = cfg.get_value("display", "refresh_rate", refresh_rate)
	lifetime_distance = cfg.get_value("progress", "lifetime_distance", lifetime_distance)
	footprint = TreadmillFootprint.from_dict(cfg.get_value("treadmill", "footprint", {}))
