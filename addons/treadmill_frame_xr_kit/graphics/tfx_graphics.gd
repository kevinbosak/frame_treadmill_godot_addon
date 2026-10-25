class_name TFXGraphics
extends Node
## Treadmill Frame XR Kit: graphics settings and the performance readout.
##
## A test bench for finding what the headset can afford: every setting applies
## live, and the readout shows what it costs. Settings are saved on the headset.
##
## Performance: GPU time per frame, the time spent in game code (every _process
## call, timed between markers that run first and last in each frame), and the
## real interval between frames. Each must fit the frame budget (1000 ms /
## refresh rate). In the headset the interval sits at the budget; anything much
## longer means frames were missed. (Godot's TIME_PROCESS monitor isn't used: it
## reports the worst frame of the last second, refreshed once a second.)
##
## Log: every LOG_INTERVAL seconds a "[tfx perf]" line goes to the log with the
## averages and the worst single frames since the previous line. On the headset:
##   adb logcat -s godot > perf_log.txt
##
## Hitches: a frame that takes far longer than the budget is logged with the
## events noted just before it (TFXGraphics.note("bird fly-by") from anywhere),
## shown on the walking panel and printed to the log ("[tfx hitch]").

## The active instance, so any script can call TFXGraphics.note().
static var instance: TFXGraphics

signal changed

const SAVE_PATH := "user://treadmill_frame_xr_kit_graphics.cfg"
const TONEMAP_NAMES := ["Linear", "Reinhard", "Filmic", "ACES", "AgX"]
## Seconds between "[tfx perf]" log lines.
const LOG_INTERVAL := 5.0
const FOVEATION_NAMES := ["Off", "Low", "Medium", "High"]

# --- Settings (saved) ----------------------------------------------------------
## Defaults, chosen from Steam Frame measurements (GPU about half the 72 Hz
## budget with everything on). reset_to_defaults() restores them.
const DEFAULTS := {
	"msaa": 4, "foveation": 2, "render_scale": 1.0, "tonemap": Environment.TONE_MAPPER_FILMIC,
	"shadows": true, "shadow_distance": 25.0, "density": 2.0, "show_performance": true,
}

## Edge smoothing: 0 (off), 2 or 4 samples. Nearly free on mobile GPUs.
var msaa := 4
## Lower detail towards the edges of your view: 0 off .. 3 high.
var foveation := 2
## 3D render resolution, 1.0 = native.
var render_scale := 1.0
var tonemap := Environment.TONE_MAPPER_FILMIC
var shadows := true
## How far from you shadows are drawn (m). Shorter is cheaper and sharper.
var shadow_distance := 25.0
## Scenery amount for TFXPathWorld themes (1.0 = normal).
var density := 2.0
var show_performance := true
## Theme option values by key, so they survive restarts.
var theme_options := {}

# --- Live readings (smoothed) --------------------------------------------------
var gpu_ms := 0.0
## Real time between frames (ms).
var frame_ms := 0.0
## Game code: all _process callbacks this frame.
var game_ms := 0.0
## Worst single frames over the last couple of seconds (spikes).
var frame_peak_ms := 0.0
var game_peak_ms := 0.0
## The most recent hitch: {"ms", "at_msec", "events"}; empty if none yet.
var last_hitch := {}
## Kept for compatibility: same as game_ms.
var cpu_ms := 0.0
var budget_ms := 13.9
var draw_calls := 0
var primitives := 0
var objects := 0

## Set by the rig.
var xr: OpenXRInterface
var world_env: WorldEnvironment
var path_world: TFXPathWorld:
	set = set_path_world

var _peak_window := 0.0
var _frame_peak_running := 0.0
var _game_peak_running := 0.0
var _frame_start_usec := 0
var _interval_ms := 0.0
var _game_last_ms := 0.0
var _age := 0.0
var _events: Array = []   # [msec, text], newest last
var _log_wait := LOG_INTERVAL
var _log_gpu_max := 0.0
var _log_frame_max := 0.0
var _log_game_max := 0.0
var _log_hitches := 0


## Runs first and last in every frame, to time the game code in between.
class FrameMarker:
	extends Node
	var on_process: Callable

	func _process(_delta: float) -> void:
		on_process.call()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	var first := FrameMarker.new()
	first.process_priority = -1000000
	first.on_process = func() -> void:
		var now := Time.get_ticks_usec()
		if _frame_start_usec > 0:
			_interval_ms = (now - _frame_start_usec) / 1000.0
		_frame_start_usec = now
	add_child(first)
	var last := FrameMarker.new()
	last.process_priority = 1000000
	last.on_process = func() -> void:
		_game_last_ms = (Time.get_ticks_usec() - _frame_start_usec) / 1000.0
	add_child(last)
	load_settings()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	apply()


func _process(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	var k := 1.0 - exp(-delta / 0.5)
	gpu_ms = lerpf(gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(rid), k)
	var frame := _interval_ms
	frame_ms = lerpf(frame_ms, frame, k)
	game_ms = lerpf(game_ms, _game_last_ms, k)
	cpu_ms = game_ms
	_age += delta
	_frame_peak_running = maxf(_frame_peak_running, frame)
	_game_peak_running = maxf(_game_peak_running, _game_last_ms)
	_peak_window += delta
	if _peak_window >= 2.0:
		frame_peak_ms = _frame_peak_running
		game_peak_ms = _game_peak_running
		_frame_peak_running = 0.0
		_game_peak_running = 0.0
		_peak_window = 0.0
	# A hitch: the gap since the last frame means at least two frames were missed.
	# (The first seconds, while everything loads, don't count.)
	if _age > 3.0 and frame > maxf(budget_ms * 2.5, 30.0):
		_record_hitch(frame)
		_log_hitches += 1
	_log_gpu_max = maxf(_log_gpu_max, RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_log_frame_max = maxf(_log_frame_max, frame)
	_log_game_max = maxf(_log_game_max, _game_last_ms)
	_log_wait -= delta
	if _log_wait <= 0.0:
		_log_wait = LOG_INTERVAL
		_write_log_line()
	draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	objects = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var rate := xr.get_display_refresh_rate() if xr else 0.0
	budget_ms = 1000.0 / rate if rate > 1.0 else 1000.0 / 60.0


## The real time the last frame took (ms), unsmoothed.
func last_frame_interval_ms() -> float:
	return _interval_ms


## One line for the walking panel.
func summary() -> String:
	var gpu := "GPU %.1f" % gpu_ms if gpu_ms > 0.0 else "GPU n/a"
	return "%s / %.1f ms (%d%%)   game code %.1f (peak %.1f)   frame interval %.1f (peak %.1f)   %d draws  %dk tris" % [
			gpu, budget_ms, roundi(gpu_ms / budget_ms * 100.0), game_ms, game_peak_ms,
			frame_ms, frame_peak_ms, draw_calls, roundi(primitives / 1000.0)]


## One "[tfx perf]" line: averages, then the worst single frame since the last line.
func _write_log_line() -> void:
	var world := "world" if path_world and path_world.is_visible_in_tree() else "passthrough"
	print("[tfx perf] %s view, %d fps of %d Hz | GPU avg %.1f max %.1f ms (budget %.1f) | game code avg %.1f max %.1f | frame interval avg %.1f max %.1f | %d draws, %dk tris | hitches %d" % [
			world, roundi(Engine.get_frames_per_second()), roundi(1000.0 / budget_ms),
			gpu_ms, _log_gpu_max, budget_ms, game_ms, _log_game_max, frame_ms, _log_frame_max,
			draw_calls, roundi(primitives / 1000.0), _log_hitches])
	_log_gpu_max = 0.0
	_log_frame_max = 0.0
	_log_game_max = 0.0
	_log_hitches = 0


## The last hitch in words, or "" if there hasn't been one.
func hitch_summary() -> String:
	if last_hitch.is_empty():
		return ""
	var ago: float = (Time.get_ticks_msec() - int(last_hitch.at_msec)) / 1000.0
	var events: PackedStringArray = last_hitch.events
	return "Last hitch %d ms, %ds ago, after: %s" % [roundi(last_hitch.ms), roundi(ago),
			", ".join(events) if events.size() > 0 else "nothing noted"]


## Records something that happened, so hitches can be traced back to it.
static func note(text: String) -> void:
	if instance:
		instance._events.append([Time.get_ticks_msec(), text])
		if instance._events.size() > 30:
			instance._events.pop_front()


func _record_hitch(ms: float) -> void:
	var now := Time.get_ticks_msec()
	var counts := {}   # event -> times, in first-seen order
	for e in _events:
		if now - e[0] <= 700:
			counts[e[1]] = counts.get(e[1], 0) + 1
	var recent: PackedStringArray = []
	for text in counts:
		recent.append(text if counts[text] == 1 else "%s x%d" % [text, counts[text]])
	last_hitch = {"ms": ms, "at_msec": now, "events": recent}
	print("[tfx hitch] %d ms (budget %.1f); just before: %s" % [roundi(ms), budget_ms,
			", ".join(recent) if recent.size() > 0 else "nothing noted"])


func is_foveation_supported() -> bool:
	return xr != null and xr.is_foveation_supported()


func set_path_world(world: TFXPathWorld) -> void:
	path_world = world
	if world and world.theme:
		for key in theme_options:
			world.theme.set_option(key, theme_options[key])
	apply()


## Applies everything. Cheap settings apply at once; density rebuilds the path.
func apply() -> void:
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(msaa / 2, 0, 2)]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	if is_foveation_supported():
		xr.foveation_level = foveation
		xr.foveation_dynamic = false
	if world_env:
		world_env.environment.tonemap_mode = tonemap
	if path_world and path_world.theme:
		var theme := path_world.theme
		if theme.sun:
			theme.sun.shadow_enabled = shadows
			theme.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			theme.sun.directional_shadow_max_distance = shadow_distance
		path_world.set_shadows(shadows)
		if not is_equal_approx(theme.density, density):
			theme.density = density
			path_world.rebuild()
	note("graphics settings applied")
	changed.emit()


func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set(key, DEFAULTS[key])
	apply()
	save_settings()


func set_theme_option(key: String, value: bool) -> void:
	theme_options[key] = value
	if path_world and path_world.theme:
		path_world.theme.set_option(key, value)
		for o in path_world.theme.get_options():
			if o.key == key and o.get("rebuild", false):
				path_world.rebuild()
	save_settings()
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in ["msaa", "foveation", "render_scale", "tonemap", "shadows",
			"shadow_distance", "density", "show_performance", "theme_options"]:
		cfg.set_value("graphics", key, get(key))
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in cfg.get_section_keys("graphics"):
		if key in self:
			set(key, cfg.get_value("graphics", key))
