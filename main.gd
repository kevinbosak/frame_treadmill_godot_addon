extends Node3D
## Treadmill game, part 4: the walking world and the eye-tracking test.
##
## Two views (Trigger switches between them):
##   Passthrough  the real room with the panel floating in it
##   World        the endless dusk forest road, moving at your walking speed,
##                with the treadmill area left see-through. Rune-marked waystones
##                along the way test eye tracking: look at one for half a second
##                to notice it.
##
## Controls (either controller):
##   B / Y        open / close settings (cancels measuring)
##   Trigger      click in settings, record a point while measuring,
##                otherwise switch view
##   A / X        quick calibrate at the speed set in settings
## Desktop preview keys:
##   Tab settings   T switch view   F pretend treadmill under you
##   W simulate walking   [ / ] simulated cadence   Up / Down look up or down
##   C quick calibrate    the mouse acts as your gaze, and clicks the settings panel

const HUD_DISTANCE := 1.6   # metres in front of you
const HUD_DROP := 0.35      # panel centre sits this far below eye level, under the view of the road
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

@onready var treadmill: Treadmill = $Treadmill
@onready var world: PathWorld = $PathWorld
@onready var sun: DirectionalLight3D = $Sun
@onready var gaze: GazeTracker = $Gaze
@onready var reticle: GazeReticle = $Reticle
@onready var eye_gaze: XRController3D = $XROrigin3D/EyeGaze
@onready var step_player: AudioStreamPlayer = $StepSound
@onready var notice_player: AudioStreamPlayer = $NoticeSound
@onready var bubble: PassthroughBubble = $Bubble
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var prompt: Label3D = $XROrigin3D/XRCamera3D/Prompt
@onready var controllers: Array[XRController3D] = [$XROrigin3D/LeftHand, $XROrigin3D/RightHand]
@onready var hud: Node3D = $Hud
@onready var readout: Label3D = $Hud/Readout
@onready var info: Label3D = $Hud/Info
@onready var warning: Label3D = $Hud/Warning
@onready var waveform: BobWaveform = $Hud/Waveform
@onready var hud_panel: MeshInstance3D = $Hud/Panel

var xr_interface: OpenXRInterface
var xr_active := false
var world_view := false
var menu_open := false
var measuring := false

var settings_panel := UiPanel3D.new()
var settings_menu := SettingsMenu.new()

var _measure_points: Array[Vector3] = []
var _measure_markers: Array[MeshInstance3D] = []
var _toast_timer := 0.0
var _hud_placed := false
var _time := 0.0
var _haptic_timer := 0.0
var _noticed_count := 0
var _passed_count := 0
var _default_env: Environment


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

	settings_menu.treadmill = treadmill
	settings_menu.xr = xr_interface if xr_active else null
	settings_menu.eye = eye_gaze
	settings_menu.close_requested.connect(_close_menu)
	settings_menu.measure_requested.connect(_start_measuring)
	settings_panel.setup(settings_menu, Vector2i(900, 1000))
	settings_panel.visible = false
	add_child(settings_panel)

	for c in controllers:
		c.button_pressed.connect(_on_button_pressed.bind(c))
		c.button_released.connect(_on_button_released.bind(c))

	gaze.camera = xr_camera
	gaze.eye = eye_gaze
	gaze.xr_active = xr_active
	gaze.target_noticed.connect(_on_target_noticed)
	reticle.tracker = gaze
	world.target_passed.connect(func(_t: GazeTarget) -> void: _passed_count += 1)
	_add_gaze_depth_surface()
	step_player.stream = Sounds.footstep()
	notice_player.stream = Sounds.chime()

	_default_env = world_env.environment.duplicate()
	_set_world_view(false)


func _process(delta: float) -> void:
	_time += delta
	waveform.add_sample(treadmill.detector.signal_value, treadmill.detector.threshold,
			delta, treadmill.stepped_this_frame)
	# Place the panel once tracking has settled, in front of wherever you face.
	if xr_active and not _hud_placed and _time > 1.0:
		_place_hud()
	_update_warning(delta)
	world.speed = treadmill.speed_mps
	reticle.visible = treadmill.show_reticle
	if world_view and treadmill.footstep_sounds and treadmill.stepped_this_frame:
		step_player.pitch_scale = randf_range(0.85, 1.15)
		step_player.play()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and not measuring:
			prompt.visible = false
	_refresh_hud()


# --- Views ---------------------------------------------------------------------

func _on_session_begun() -> void:
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr_interface.get_supported_environment_blend_modes():
		xr_interface.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)
	else:
		_toast("Passthrough isn't available")
	if treadmill.refresh_rate > 0.0:
		xr_interface.set_display_refresh_rate(treadmill.refresh_rate)
	if OS.get_name() == "Android":
		# Asks for the eye-tracking permissions listed in the export preset.
		get_tree().on_request_permissions_result.connect(_on_permission_result)
		OS.request_permissions()
	# Shows up in `adb logcat -s godot` for troubleshooting.
	for line in SettingsMenu.headset_report(xr_interface, eye_gaze):
		print("[headset] ", line)


func _on_permission_result(permission: String, granted: bool) -> void:
	print("[headset] permission %s: %s" % [permission, "granted" if granted else "denied"])
	if granted and "EYE" in permission:
		_toast("Eye tracking permission granted.\nRestart the app if gaze still says head direction.")


## In the headset the background is always see-through; the World view covers
## it with a sky dome and ground, except inside the bubble.
func _apply_background() -> void:
	get_viewport().transparent_bg = xr_active
	var env := world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if xr_active else VR_BACKGROUND


func _set_world_view(on: bool) -> void:
	if on and not treadmill.footprint.is_valid():
		_toast("Measure your treadmill first:\nB/Y opens settings > Measure treadmill")
		on = false
	world_view = on
	world.visible = on
	bubble.visible = on
	sun.visible = not on
	var env := world_env.environment
	if on:
		bubble.fit(treadmill.footprint, treadmill.bubble_height)
		world.align(treadmill.footprint)
		world.theme.apply_environment(env)
	else:
		env.fog_enabled = false
		env.ambient_light_source = _default_env.ambient_light_source
		env.ambient_light_color = _default_env.ambient_light_color
		env.ambient_light_energy = _default_env.ambient_light_energy


func _on_settings_changed() -> void:
	if bubble.visible:
		bubble.fit(treadmill.footprint, treadmill.bubble_height)


# --- Settings menu -------------------------------------------------------------

func _open_menu() -> void:
	# Settings are used in the real room, so the menu never hides in the bubble.
	_set_world_view(false)
	var head := xr_camera.global_position
	var fwd := _flat_forward()
	var pos := head + Vector3(fwd.x, 0.0, fwd.y) * MENU_DISTANCE
	pos.y = head.y - 0.1
	settings_panel.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.y)), pos)
	settings_menu.refresh()
	settings_panel.visible = true
	hud.visible = false  # the menu shows live cadence itself
	menu_open = true


func _close_menu() -> void:
	settings_panel.visible = false
	hud.visible = true
	menu_open = false


# --- Measuring the treadmill ---------------------------------------------------

func _start_measuring() -> void:
	_close_menu()
	_set_world_view(false)
	measuring = true
	_measure_points.clear()
	_clear_markers()
	_show_prompt(MEASURE_STEPS[0] + "\n(B/Y to cancel)")


func _record_measure_point(c: XRController3D) -> void:
	var p := c.global_transform * Vector3(0, 0, -TIP_OFFSET)
	_measure_points.append(p)
	_add_marker(p)
	if _measure_points.size() < 3:
		_show_prompt(MEASURE_STEPS[_measure_points.size()] + "\n(B/Y to cancel)")
		return
	var f := TreadmillFootprint.from_points(_measure_points[0], _measure_points[1], _measure_points[2])
	var problem := f.problem()
	_measure_points.clear()
	if problem != "":
		_clear_markers()
		_show_prompt(problem + ". Let's try again.\n" + MEASURE_STEPS[0] + "\n(B/Y to cancel)")
		return
	measuring = false
	treadmill.set_footprint(f)
	_clear_markers()
	_place_hud()
	_toast("Treadmill measured: %.2f m x %.2f m\nPull the trigger to try the World view" % [f.width, f.length])


func _cancel_measuring() -> void:
	measuring = false
	_clear_markers()
	_toast("Measuring cancelled")


func _add_marker(p: Vector3) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.015
	s.height = 0.03
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.8, 0.1)
	s.material = mat
	m.mesh = s
	add_child(m)
	m.global_position = p
	_measure_markers.append(m)


func _clear_markers() -> void:
	for m in _measure_markers:
		m.queue_free()
	_measure_markers.clear()


## For trying things on the Mac: a 0.5 m x 1.4 m belt under the camera.
func _pretend_treadmill() -> void:
	var c := Vector2(xr_camera.global_position.x, xr_camera.global_position.z)
	var f := TreadmillFootprint.from_points(Vector3(c.x - 0.25, 0.2, c.y - 0.5),
			Vector3(c.x + 0.25, 0.2, c.y - 0.5), Vector3(c.x, 0.2, c.y + 0.9))
	treadmill.set_footprint(f)
	_place_hud()
	_toast("Pretend treadmill placed under you")


# --- HUD, prompts and warnings -------------------------------------------------

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
		readout.text = "%d spm\n%.1f mph   %s /mi" % [roundi(d.cadence_spm), mph, _format_pace(mph)]
	else:
		readout.text = "-- spm\nstart walking"
	readout.modulate = Color(1, 0.4, 0.35) if warning.visible else Color.WHITE

	var stride := "default stride" if treadmill.calibration.points.is_empty() \
			else "%d calibration point(s)" % treadmill.calibration.points.size()
	var lines: PackedStringArray = [
		"Steps %d    Bob %.1f cm    %s" % [d.step_count, d.amplitude * 100.0, stride],
		"Today %.2f mi    All time %.1f mi    %d fps" % [treadmill.session_distance / METRES_PER_MILE,
				treadmill.lifetime_distance / METRES_PER_MILE, Engine.get_frames_per_second()],
		"Gaze: %s    Waystones noticed %d of %d passed" % [gaze.source, _noticed_count, _passed_count],
		"B/Y settings    Trigger: %s view    A/X quick calibrate"
				% ("passthrough" if world_view else "world"),
	]
	if not treadmill.footprint.is_valid():
		lines.append("Treadmill not measured yet: open settings")
	if treadmill.sim_walking:
		lines.append("SIMULATED WALKING  %d spm" % roundi(treadmill.sim_cadence))
	info.text = "\n".join(lines)
	waveform.visible = treadmill.show_step_graph
	hud_panel.scale.y = 1.0 if treadmill.show_step_graph else 0.75
	hud_panel.position.y = 0.0 if treadmill.show_step_graph else 0.1


func _update_warning(delta: float) -> void:
	var msg := treadmill.edge_warning
	warning.text = msg
	warning.visible = msg != ""
	if msg != "" and xr_active:
		_haptic_timer -= delta
		if _haptic_timer <= 0.0:
			_haptic_timer = 0.5
			for c in controllers:
				c.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.15, 0.0)
	else:
		_haptic_timer = 0.0


func _on_target_noticed(_t: GazeTarget) -> void:
	_noticed_count += 1
	notice_player.play()


## An invisible surface on the HUD so the reticle sits at the panel's depth
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


func _show_prompt(text: String) -> void:
	prompt.text = text
	prompt.visible = true
	_toast_timer = 0.0


func _toast(text: String) -> void:
	_show_prompt(text)
	_toast_timer = 4.0
	print("[treadmill] ", text.replace("\n", " "))


func _format_pace(mph: float) -> String:
	if mph < 0.5:
		return "--:--"
	var total_seconds := roundi(3600.0 / mph)
	return "%d:%02d" % [total_seconds / 60, total_seconds % 60]


# --- Input ---------------------------------------------------------------------

func _on_button_pressed(button_name: String, c: XRController3D) -> void:
	match button_name:
		"trigger_click":
			if (c.get_node("Pointer") as XRPointer).press(true):
				return
			if measuring:
				_record_measure_point(c)
			elif not menu_open:
				_set_world_view(not world_view)
		"by_button":
			if measuring:
				_cancel_measuring()
			elif menu_open:
				_close_menu()
			else:
				_open_menu()
		"ax_button":
			if not menu_open and not measuring:
				_toast(treadmill.calibrate())


func _on_button_released(button_name: String, c: XRController3D) -> void:
	if button_name == "trigger_click":
		(c.get_node("Pointer") as XRPointer).press(false)


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
				_close_menu()
			else:
				_open_menu()
		KEY_T, KEY_SPACE:
			_set_world_view(not world_view)
		KEY_F:
			_pretend_treadmill()
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
			_toast(treadmill.calibrate())


## Lets the mouse use the settings panel in the desktop preview.
func _desktop_pointer(event: InputEventMouse) -> void:
	if xr_active or not menu_open:
		return
	var from := xr_camera.project_ray_origin(event.position)
	var query := PhysicsRayQueryParameters3D.create(from,
			from + xr_camera.project_ray_normal(event.position) * 5.0, UiPanel3D.UI_LAYER)
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
