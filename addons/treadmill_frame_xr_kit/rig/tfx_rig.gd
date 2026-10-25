class_name TFXRig
extends Node3D
## Treadmill Frame XR Kit: everything a treadmill game needs around the player.
##
## Instance tfx_rig.tscn in your main scene. It brings the headset and controllers,
## passthrough, step counting and speed (TFXTreadmill), treadmill measuring, the
## see-through safety bubble, edge warnings, the walking panel (HUD), settings
## screen, laser pointers, gaze tracking with a reticle, sound (audio buses,
## volumes, binaural positional audio, footsteps) and a graphics test bench
## (TFXGraphics: live settings plus a GPU/CPU readout).
##
## Warm-up: things that first appear mid-walk (a creature, an effect) can cause a
## one-time stall while the GPU driver prepares their materials. Register them
## with add_warm_up(); the first time World view turns on, the rig draws them
## once (shrunk to invisible) and plays the sounds once (near silent).
##
## Your game provides the world: set `world_root` to the node to show in World
## view (a TFXPathWorld is lined up with the treadmill and fed the walking speed
## automatically). React to `view_changed`, `treadmill.step_taken`,
## `treadmill.edge_warning_changed`, `gaze.target_noticed`...
##
## Two views (view button switches): Passthrough (the real room) and World
## (your world, with the treadmill area left see-through). World view needs the
## treadmill to be measured first.
##
## Desktop preview keys (no headset): Tab settings, T switch view, F pretend
## treadmill under you, W simulate walking, [ / ] simulated cadence, Up / Down
## look up or down, C quick calibrate. The mouse is the gaze and clicks settings.

signal view_changed(world_view: bool)
signal treadmill_measured(footprint: TFXFootprint)

## Refresh rate to ask for at startup (Hz), unless the player picked one in
## Settings. Only used if the headset offers it to the app; otherwise the app
## follows the headset's own setting (SteamOS VR settings).
@export var preferred_refresh_rate := 90.0
## Shown while World view is prepared for the first time.
@export var preparing_text := "Preparing the world..."

## Controller buttons (OpenXR action names from the default action map).
@export var settings_button := "by_button"
@export var view_button := "trigger_click"
@export var calibrate_button := "ax_button"

## Shown in World view. Set it from your game.
var world_root: Node3D:
	set = set_world_root
## Extra lines for the walking panel, e.g. score or clues found.
var hud_extra_lines: PackedStringArray = []

const HUD_DISTANCE := 1.6   # metres in front of you
const HUD_DROP := 0.35      # panel centre this far below eye level, under the view of the road
const MENU_DISTANCE := 0.8
const TIP_OFFSET := 0.03    # measuring point, ahead of the controller's aim point
const VR_BACKGROUND := Color(0.05, 0.07, 0.12)
const METRES_PER_MILE := 1609.34
const GAZE_DEPTH_LAYER := 1 << 3   # lets the reticle sit at the panel's depth

const MEASURE_STEPS := [
	"Step 1 of 3: touch the FRONT-LEFT corner of the belt\nwith a controller tip, then pull its trigger",
	"Step 2 of 3: touch the FRONT-RIGHT corner of the belt",
	"Step 3 of 3: touch the BACK end of the belt (anywhere along it)",
]

@onready var treadmill: TFXTreadmill = $Treadmill
@onready var gaze: TFXGazeTracker = $Gaze
@onready var reticle: TFXGazeReticle = $Reticle
@onready var bubble: TFXPassthroughBubble = $Bubble
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var default_light: DirectionalLight3D = $DefaultLight
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var eye_gaze: XRController3D = $XROrigin3D/EyeGaze
@onready var prompt: Label3D = $XROrigin3D/XRCamera3D/Prompt
@onready var controllers: Array[XRController3D] = [$XROrigin3D/LeftHand, $XROrigin3D/RightHand]
@onready var hud: Node3D = $Hud
@onready var readout: Label3D = $Hud/Readout
@onready var info: Label3D = $Hud/Info
@onready var warning: Label3D = $Hud/Warning
@onready var waveform: TFXBobWaveform = $Hud/Waveform
@onready var hud_panel: MeshInstance3D = $Hud/Panel
@onready var step_player: AudioStreamPlayer = $StepSound
@onready var audio: TFXAudio = $Audio
@onready var graphics: TFXGraphics = $Graphics

var xr_interface: OpenXRInterface
var xr_active := false
var world_view := false
var menu_open := false
var measuring := false

var settings_panel := TFXUiPanel3D.new()
var settings_menu := TFXSettingsMenu.new()

var _measure_points: Array[Vector3] = []
var _measure_markers: Array[MeshInstance3D] = []
var _toast_timer := 0.0
var _hud_placed := false
var _time := 0.0
var _haptic_timer := 0.0
var _hud_wait := 0.0
var _fade := MeshInstance3D.new()
var _fade_material := StandardMaterial3D.new()
var _world_prepared := false
var _preparing := false
var _warm_visuals: Array[Node3D] = []
var _warm_sounds: Array[AudioStream] = []
var _warmed := false

## How many frames the warm-up objects are drawn for.
const WARM_UP_FRAMES := 12
var _default_env: Environment

## Walking panel text updates per second. Changing 3D text is costly, and a few
## updates a second reads just as well.
const HUD_RATE := 5.0


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface and xr_interface.is_initialized():
		xr_active = true
		get_viewport().use_xr = true
		# The headset paces frames; desktop vsync would only slow things down.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr_interface.session_begun.connect(_on_session_begun)
	else:
		xr_camera.position = Vector3(0.0, 1.6, 0.0)
		_place_hud()
	_apply_background()

	treadmill.camera = xr_camera
	treadmill.settings_changed.connect(_on_settings_changed)

	graphics.xr = xr_interface if xr_active else null
	graphics.world_env = world_env
	graphics.apply()
	settings_menu.treadmill = treadmill
	settings_menu.graphics = graphics
	settings_menu.xr = xr_interface if xr_active else null
	settings_menu.eye = eye_gaze
	settings_menu.close_requested.connect(close_settings)
	settings_menu.measure_requested.connect(start_measuring)
	settings_panel.setup(settings_menu, Vector2i(1000, 1060))
	settings_panel.visible = false
	add_child(settings_panel)

	for c in controllers:
		c.button_pressed.connect(_on_button_pressed.bind(c))
		c.button_released.connect(_on_button_released.bind(c))

	gaze.camera = xr_camera
	gaze.eye = eye_gaze
	gaze.xr_active = xr_active
	reticle.tracker = gaze
	_add_gaze_depth_surface()
	step_player.stream = TFXSounds.footstep()
	step_player.bus = TFXAudio.EFFECTS
	_apply_sound_settings()

	_default_env = world_env.environment.duplicate()
	_build_fade()
	set_world_view(false)


func _process(delta: float) -> void:
	_time += delta
	waveform.add_sample(treadmill.detector.signal_value, treadmill.detector.threshold,
			delta, treadmill.stepped_this_frame)
	# Place the panel once tracking has settled, in front of wherever you face.
	if xr_active and not _hud_placed and _time > 1.0:
		_place_hud()
	_update_warning(delta)
	if world_root is TFXPathWorld:
		(world_root as TFXPathWorld).speed = treadmill.speed_mps
	reticle.visible = treadmill.show_reticle
	if world_view and treadmill.footstep_sounds and treadmill.stepped_this_frame:
		step_player.pitch_scale = randf_range(0.85, 1.15)
		step_player.play()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and not measuring:
			prompt.visible = false
	_hud_wait -= delta
	if _hud_wait <= 0.0 and hud.visible:
		_hud_wait = 1.0 / HUD_RATE
		_refresh_hud()


# --- Views -----------------------------------------------------------------------

func _on_session_begun() -> void:
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr_interface.get_supported_environment_blend_modes():
		xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	else:
		toast("Passthrough isn't available")
	_request_refresh_rate()
	if OS.get_name() == "Android":
		# Asks for the eye-tracking permissions listed in the export preset.
		get_tree().on_request_permissions_result.connect(_on_permission_result)
		OS.request_permissions()
	# Shows up in `adb logcat -s godot` for troubleshooting.
	for line in TFXSettingsMenu.headset_report(xr_interface, eye_gaze):
		print("[headset] ", line)


## Asks for the player's chosen refresh rate, or preferred_refresh_rate, if the
## headset offers it to the app. Otherwise keeps the headset's own setting.
func _request_refresh_rate() -> void:
	var wanted := treadmill.refresh_rate if treadmill.refresh_rate > 0.0 else preferred_refresh_rate
	var offered := xr_interface.get_available_display_refresh_rates()
	for rate in offered:
		if absf(rate - wanted) < 1.0:
			xr_interface.set_display_refresh_rate(rate)
			print("[headset] refresh rate set to %d Hz" % roundi(rate))
			return
	var names: PackedStringArray = []
	for rate in offered:
		names.append(str(roundi(rate)))
	print("[headset] %d Hz isn't offered to the app (offered: %s); running at the headset's setting, %d Hz. Change it in SteamOS VR settings." % [
			roundi(wanted), ", ".join(names) if names.size() > 0 else "none", roundi(xr_interface.get_display_refresh_rate())])


func _on_permission_result(permission: String, granted: bool) -> void:
	print("[headset] permission %s: %s" % [permission, "granted" if granted else "denied"])
	if granted and "EYE" in permission:
		toast("Eye tracking permission granted.\nRestart the app if gaze still says head direction.")


## In the headset the background is always see-through; World view covers it
## with the world's sky, except inside the bubble.
func _apply_background() -> void:
	get_viewport().transparent_bg = xr_active
	var env := world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if xr_active else VR_BACKGROUND


func set_world_root(node: Node3D) -> void:
	world_root = node
	if is_node_ready():
		var path := node as TFXPathWorld
		graphics.path_world = path
		settings_menu.set_theme_options(path.theme if path else null)
		graphics.log_settings_snapshot("startup")
		set_world_view(world_view)


## Switches between Passthrough (false) and World (true) view.
## World view needs a measured treadmill, so the safety bubble can be placed.
## The first time, it fades to dark while the world is drawn for the first time
## (a one-off cost that can freeze the picture for up to a second).
func set_world_view(on: bool) -> void:
	if _preparing:
		return
	if on and not world_view and not _world_prepared and treadmill.footprint.is_valid() and world_root:
		_prepare_world()
		return
	_apply_world_view(on)


func _apply_world_view(on: bool) -> void:
	if on and not treadmill.footprint.is_valid():
		toast("Measure your treadmill first:\nopen settings > Measure treadmill")
		on = false
	if on and world_root == null:
		on = false
	var changed := on != world_view
	world_view = on
	if world_root:
		world_root.visible = on
	bubble.visible = on
	default_light.visible = not on
	var env := world_env.environment
	if on:
		bubble.fit(treadmill.footprint, treadmill.bubble_height)
		var path := world_root as TFXPathWorld
		if path and path.theme:
			path.align(treadmill.footprint)
			path.theme.apply_environment(env)
	else:
		env.fog_enabled = false
		env.ambient_light_source = _default_env.ambient_light_source
		env.ambient_light_color = _default_env.ambient_light_color
		env.ambient_light_energy = _default_env.ambient_light_energy
	audio.set_world_audible(on)
	if changed:
		TFXGraphics.log_event("world view on" if on else "world view off")
		if on:
			graphics.log_settings_snapshot("world view on")
		view_changed.emit(on)


## First switch into World view: fade to dark, turn the world on (and warm up)
## behind the dark screen, wait until frames run smoothly, then fade in.
func _prepare_world() -> void:
	_preparing = true
	TFXGraphics.log_event("preparing world")
	await _fade_to(1.0, 0.25)
	_show_prompt(preparing_text)
	_apply_world_view(true)
	_world_prepared = true
	if not _warmed:
		_run_warm_up()
	var waited := 0.0
	var smooth := 0
	while waited < 4.0 and (waited < 0.4 or smooth < 15):
		await get_tree().process_frame
		waited += get_process_delta_time()
		var ok := graphics.last_frame_interval_ms() < graphics.budget_ms * 1.5
		smooth = smooth + 1 if ok else 0
	prompt.visible = false
	await _fade_to(0.0, 0.4)
	_preparing = false


## A dark screen fixed to your view, for fades. It draws over everything except
## the prompt text.
func _build_fade() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(3.0, 3.0)
	_fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_material.no_depth_test = true
	_fade_material.disable_fog = true
	_fade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_material.albedo_color = Color(0.02, 0.025, 0.04, 0.0)
	_fade_material.render_priority = 125   # over the HUD (116) and reticle (120), under the prompt (127)
	quad.material = _fade_material
	_fade.mesh = quad
	_fade.position = Vector3(0, 0, -0.25)
	_fade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade.visible = false
	xr_camera.add_child(_fade)


func _fade_to(alpha: float, seconds: float) -> void:
	_fade.visible = true
	var tween := create_tween()
	tween.tween_method(func(a: float) -> void: _fade_material.albedo_color.a = a,
			_fade_material.albedo_color.a, alpha, seconds)
	await tween.finished
	_fade.visible = alpha > 0.0


## Registers things to draw and play once, the first time World view turns on,
## so their one-time setup happens then rather than mid-walk. The rig takes
## ownership of the visuals (they're freed afterwards); they don't process.
func add_warm_up(visuals: Array, sounds: Array = []) -> void:
	for v in visuals:
		_warm_visuals.append(v)
	for s in sounds:
		_warm_sounds.append(s)
	if world_view and _warmed:
		_warmed = false
		_run_warm_up()


func _run_warm_up() -> void:
	_warmed = true
	TFXGraphics.note("warm-up")
	var holder := Node3D.new()
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	holder.position = Vector3(0, 0, -0.6)
	holder.scale = Vector3.ONE * 0.002   # in view, so it's drawn, but far too small to see
	xr_camera.add_child(holder)
	# The kit's own late-appearing pieces: the settings panel and the laser.
	var kit_meshes: Array[Mesh] = []
	var panel_quad := QuadMesh.new()
	panel_quad.material = settings_panel.panel_material()
	kit_meshes.append(panel_quad)
	kit_meshes.append_array((controllers[0].get_node("Pointer") as TFXPointer).meshes())
	for m in kit_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		holder.add_child(mi)
	for v in _warm_visuals:
		holder.add_child(v)
	_warm_visuals.clear()
	var players: Array[AudioStreamPlayer] = []
	for s in _warm_sounds:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = TFXAudio.WARMUP
		p.volume_db = -80.0
		add_child(p)
		p.play()
		players.append(p)
	_warm_sounds.clear()
	for i in WARM_UP_FRAMES:
		await get_tree().process_frame
	holder.queue_free()
	for p in players:
		p.queue_free()


func _on_settings_changed() -> void:
	if bubble.visible:
		bubble.fit(treadmill.footprint, treadmill.bubble_height)
	_apply_sound_settings()


func _apply_sound_settings() -> void:
	audio.set_volumes(treadmill.volume_master, treadmill.volume_ambience,
			treadmill.volume_world, treadmill.volume_effects)
	audio.binaural_enabled = treadmill.binaural_audio


# --- Settings ----------------------------------------------------------------------

func open_settings() -> void:
	# The panel draws on top of the see-through bubble, so World view can stay
	# on (handy for judging graphics settings).
	var head := xr_camera.global_position
	var fwd := _flat_forward()
	var pos := head + Vector3(fwd.x, 0.0, fwd.y) * MENU_DISTANCE
	pos.y = head.y - 0.1
	settings_panel.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.y)), pos)
	settings_menu.refresh()
	settings_panel.visible = true
	TFXGraphics.log_event("settings opened")
	hud.visible = false  # the menu shows live cadence itself
	menu_open = true


func close_settings() -> void:
	if menu_open:
		TFXGraphics.log_event("settings closed")
	settings_panel.visible = false
	hud.visible = true
	menu_open = false


# --- Measuring the treadmill ------------------------------------------------------

func start_measuring() -> void:
	close_settings()
	set_world_view(false)
	measuring = true
	_measure_points.clear()
	_clear_markers()
	_show_prompt(MEASURE_STEPS[0] + "\n(%s to cancel)" % _button_label(settings_button))


func _record_measure_point(c: XRController3D) -> void:
	var p := c.global_transform * Vector3(0, 0, -TIP_OFFSET)
	_measure_points.append(p)
	_add_marker(p)
	var cancel := "\n(%s to cancel)" % _button_label(settings_button)
	if _measure_points.size() < 3:
		_show_prompt(MEASURE_STEPS[_measure_points.size()] + cancel)
		return
	var f := TFXFootprint.from_points(_measure_points[0], _measure_points[1], _measure_points[2])
	var problem := f.problem()
	_measure_points.clear()
	if problem != "":
		_clear_markers()
		_show_prompt(problem + ". Let's try again.\n" + MEASURE_STEPS[0] + cancel)
		return
	_finish_measuring(f)
	toast("Treadmill measured: %.2f m x %.2f m\nSwitch view to try the World view" % [f.width, f.length])


func _finish_measuring(f: TFXFootprint) -> void:
	measuring = false
	treadmill.set_footprint(f)
	_clear_markers()
	_place_hud()
	TFXGraphics.log_event("treadmill measured %.2f x %.2f m" % [f.width, f.length])
	treadmill_measured.emit(f)


func _cancel_measuring() -> void:
	measuring = false
	_clear_markers()
	toast("Measuring cancelled")


func _add_marker(p: Vector3) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.015
	s.height = 0.03
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.8, 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = TFXPassthroughBubble.RENDER_PRIORITY + 10   # over the bubble
	s.material = mat
	m.mesh = s
	add_child(m)
	m.global_position = p
	_measure_markers.append(m)


func _clear_markers() -> void:
	for m in _measure_markers:
		m.queue_free()
	_measure_markers.clear()


## Desktop preview: a 0.5 m x 1.4 m belt under the camera.
func pretend_treadmill() -> void:
	var c := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
	var f := TFXFootprint.from_points(Vector3(c.x - 0.25, 0.2, c.y - 0.5),
			Vector3(c.x + 0.25, 0.2, c.y - 0.5), Vector3(c.x, 0.2, c.y + 0.9))
	_finish_measuring(f)
	toast("Pretend treadmill placed under you")


# --- Walking panel, prompts and warnings -----------------------------------------

func _place_hud() -> void:
	var head := xr_camera.global_position
	var f := treadmill.footprint
	var fwd := f.forward if f.is_valid() else _flat_forward()
	var pos := head + Vector3(fwd.x, 0.0, fwd.y) * HUD_DISTANCE
	pos.y = head.y - HUD_DROP
	hud.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.y)), pos)
	_hud_placed = true


func _flat_forward() -> Vector2:
	var f := -xr_camera.global_transform.basis.z
	var flat := Vector2(f.x, f.z)
	return flat.normalized() if flat.length() > 0.01 else Vector2(0, -1)


func _refresh_hud() -> void:
	var d := treadmill.detector
	if d.cadence_spm > 0.0:
		var mph := treadmill.speed_mph()
		_set_text(readout, "%d spm\n%.1f mph   %s /mi" % [roundi(d.cadence_spm), mph, _format_pace(mph)])
	else:
		_set_text(readout, "-- spm\nstart walking")

	var stride := "default stride" if treadmill.calibration.points.is_empty() \
			else "%d calibration point(s)" % treadmill.calibration.points.size()
	var lines: PackedStringArray = [
		"Steps %d    Bob %.1f cm    %s" % [d.step_count, d.amplitude * 100.0, stride],
		"Today %.2f mi    All time %.1f mi    %d fps" % [treadmill.session_distance / METRES_PER_MILE,
				treadmill.lifetime_distance / METRES_PER_MILE, roundi(Engine.get_frames_per_second())],
		"Gaze: %s" % gaze.source,
	]
	if graphics.show_performance:
		lines.append(graphics.summary())
		var hitch := graphics.hitch_summary()
		if hitch != "":
			lines.append(hitch)
	lines.append_array(hud_extra_lines)
	lines.append("%s settings    %s: %s view    %s quick calibrate" % [
			_button_label(settings_button), _button_label(view_button),
			"passthrough" if world_view else "world", _button_label(calibrate_button)])
	if not treadmill.footprint.is_valid():
		lines.append("Treadmill not measured yet: open settings")
	if treadmill.sim_walking:
		lines.append("SIMULATED WALKING  %d spm" % roundi(treadmill.sim_cadence))
	_set_text(info, "\n".join(lines))
	waveform.visible = treadmill.show_step_graph
	hud_panel.scale.y = 1.0 if treadmill.show_step_graph else 0.75
	hud_panel.position.y = 0.0 if treadmill.show_step_graph else 0.1


func _update_warning(delta: float) -> void:
	var msg := treadmill.edge_warning
	if warning.text != msg:
		warning.text = msg
		warning.visible = msg != ""
		readout.modulate = Color(1, 0.4, 0.35) if warning.visible else Color.WHITE
	if msg != "" and xr_active:
		_haptic_timer -= delta
		if _haptic_timer <= 0.0:
			_haptic_timer = 0.5
			for c in controllers:
				c.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)
	else:
		_haptic_timer = 0.0


## Shows a message under your view for a few seconds.
func toast(text: String) -> void:
	_show_prompt(text)
	_toast_timer = 4.0
	print("[tfx] ", text.replace("\n", " "))


func _show_prompt(text: String) -> void:
	prompt.text = text
	prompt.visible = true
	_toast_timer = 0.0


## An invisible surface on the panel so the reticle sits at the panel's depth
## when you read it, instead of floating behind it.
func _add_gaze_depth_surface() -> void:
	var area := Area3D.new()
	area.collision_layer = GAZE_DEPTH_LAYER
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.85, 0.02)
	shape.shape = box
	area.add_child(shape)
	hud_panel.add_child(area)


## Only touches the label when the text really changed (rebuilding 3D text costs).
static func _set_text(label: Label3D, text: String) -> void:
	if label.text != text:
		label.text = text


static func _format_pace(mph: float) -> String:
	if mph < 0.5:
		return "--:--"
	var total_seconds := roundi(3600.0 / mph)
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


static func _button_label(action: String) -> String:
	match action:
		"by_button":
			return "B/Y"
		"ax_button":
			return "A/X"
		"trigger_click":
			return "Trigger"
		"grip_click":
			return "Grip"
		"menu_button":
			return "Menu"
	return action


# --- Input -----------------------------------------------------------------------

func _on_button_pressed(button_name: String, c: XRController3D) -> void:
	if button_name == "trigger_click" and (c.get_node("Pointer") as TFXPointer).press(true):
		return   # the laser was on a panel and clicked it
	if measuring:
		if button_name == "trigger_click":
			_record_measure_point(c)
		elif button_name == settings_button:
			_cancel_measuring()
		return
	if button_name == settings_button:
		if menu_open:
			close_settings()
		else:
			open_settings()
	elif button_name == view_button and not menu_open:
		set_world_view(not world_view)
	elif button_name == calibrate_button and not menu_open:
		toast(treadmill.calibrate())


func _on_button_released(button_name: String, c: XRController3D) -> void:
	if button_name == "trigger_click":
		(c.get_node("Pointer") as TFXPointer).press(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_desktop_pointer(event)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_TAB:
			if menu_open:
				close_settings()
			else:
				open_settings()
		KEY_T, KEY_SPACE:
			set_world_view(not world_view)
		KEY_F:
			pretend_treadmill()
		KEY_W:
			treadmill.sim_walking = not treadmill.sim_walking
		KEY_BRACKETLEFT:
			treadmill.sim_cadence = maxf(treadmill.sim_cadence - 10.0, 40.0)
		KEY_BRACKETRIGHT:
			treadmill.sim_cadence = minf(treadmill.sim_cadence + 10.0, 200.0)
		KEY_UP:
			xr_camera.rotation_degrees.x = minf(xr_camera.rotation_degrees.x + 10.0, 60.0)
		KEY_DOWN:
			xr_camera.rotation_degrees.x = maxf(xr_camera.rotation_degrees.x - 10.0, -80.0)
		KEY_C:
			toast(treadmill.calibrate())


## Lets the mouse use the settings panel in the desktop preview.
func _desktop_pointer(event: InputEventMouse) -> void:
	if xr_active or not menu_open:
		return
	var from := xr_camera.project_ray_origin(event.position)
	var query := PhysicsRayQueryParameters3D.create(from,
			from + xr_camera.project_ray_normal(event.position) * 5.0, TFXUiPanel3D.UI_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider.has_meta("ui_panel"):
		settings_panel.pointer_exit()
		return
	settings_panel.pointer_move(hit.position)
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		settings_panel.pointer_button(button.pressed)
