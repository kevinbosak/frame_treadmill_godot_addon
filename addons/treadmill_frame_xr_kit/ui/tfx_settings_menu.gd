class_name TFXSettingsMenu
extends PanelContainer
## Treadmill Frame XR Kit: the settings screen.
##
## Built-in tabs: Treadmill, Stride, Display, Sound and Headset; kit settings are saved
## on the headset at once. Games add their own tabs with add_tab() and fill them
## with add_heading(), add_label(), add_button(), add_toggle() and add_stepper()
## (game settings are the game's to save).

signal close_requested
signal measure_requested

const FONT_SIZE := 26

var treadmill: TFXTreadmill
## Set by the scene in the headset (null in the desktop preview).
var xr: OpenXRInterface
var eye: XRController3D

var _tabs: TabContainer
var _refreshers: Array[Callable] = []
var _footprint_label: Label
var _live_label: Label
var _calib_result: Label
var _points_label: Label
var _headset_label: Label
var _headset_timer := 0.0


func _ready() -> void:
	var theme_ := Theme.new()
	theme_.default_font_size = FONT_SIZE
	theme = theme_
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	bg.set_corner_radius_all(18)
	bg.set_content_margin_all(28)
	add_theme_stylebox_override("panel", bg)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_button("Close", func() -> void: close_requested.emit()))
	col.add_child(title_row)

	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 28)
	# Roomy tabs, so they're easy to hit with the laser.
	for style_name in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tab_style := StyleBoxFlat.new()
		tab_style.set_content_margin_all(14)
		tab_style.content_margin_left = 26
		tab_style.content_margin_right = 26
		tab_style.bg_color = Color(0.2, 0.32, 0.45) if style_name == "tab_selected" \
				else Color(0.12, 0.15, 0.2) if style_name == "tab_unselected" else Color(0.16, 0.22, 0.3)
		tab_style.set_corner_radius_all(8)
		tabs.add_theme_stylebox_override(style_name, tab_style)
	col.add_child(tabs)
	_build_treadmill_tab(_tab(tabs, "Treadmill"))
	_build_stride_tab(_tab(tabs, "Stride"))
	_build_display_tab(_tab(tabs, "Display"))
	_build_sound_tab(_tab(tabs, "Sound"))
	_build_headset_tab(_tab(tabs, "Headset"))

	treadmill.settings_changed.connect(refresh)
	refresh()


func _build_treadmill_tab(tab: VBoxContainer) -> void:
	_heading(tab, "Treadmill size")
	_footprint_label = _label(tab, "")
	tab.add_child(_button("Measure treadmill", func() -> void: measure_requested.emit()))
	_heading(tab, "Edge warnings: how close your head may get to each edge")
	_stepper(tab, "Sides", 0.01, 0.0, 0.25,
			func() -> float: return treadmill.margin_side,
			func(v: float) -> void: treadmill.margin_side = v, _cm)
	_stepper(tab, "Back", 0.05, 0.1, 0.9,
			func() -> float: return treadmill.margin_back,
			func(v: float) -> void: treadmill.margin_back = v, _cm)
	_stepper(tab, "Front", 0.05, 0.0, 0.6,
			func() -> float: return treadmill.margin_front,
			func(v: float) -> void: treadmill.margin_front = v, _cm)
	_heading(tab, "See-through area")
	_stepper(tab, "Height above belt", 0.05, 0.5, 1.5,
			func() -> float: return treadmill.bubble_height,
			func(v: float) -> void: treadmill.bubble_height = v,
			func(v: float) -> String: return "%.2f m" % v)


func _build_stride_tab(tab: VBoxContainer) -> void:
	_heading(tab, "Stride calibration")
	_label(tab, "Set the treadmill's speed here, walk steadily until it says ready, then calibrate. Repeat at a few speeds.")
	_stepper(tab, "Treadmill speed", 0.1, 0.5, 12.0,
			func() -> float: return treadmill.calib_speed_mph,
			func(v: float) -> void: treadmill.calib_speed_mph = v,
			func(v: float) -> String: return "%.1f mph" % v)
	_live_label = _label(tab, "")
	tab.add_child(_button("Calibrate at this speed", func() -> void:
		_calib_result.text = treadmill.calibrate()))
	_calib_result = _label(tab, "")
	_points_label = _label(tab, "")
	tab.add_child(_button("Clear calibration", func() -> void:
		treadmill.clear_calibration()
		_calib_result.text = "Calibration cleared"))


func _build_display_tab(tab: VBoxContainer) -> void:
	_heading(tab, "Display")
	_toggle(tab, "Show step graph", treadmill.show_step_graph,
			func(on: bool) -> void: treadmill.show_step_graph = on)
	_toggle(tab, "Show gaze reticle", treadmill.show_reticle,
			func(on: bool) -> void: treadmill.show_reticle = on)


func _build_sound_tab(tab: VBoxContainer) -> void:
	_heading(tab, "Volume")
	_stepper(tab, "Overall", 0.1, 0.0, 1.0,
			func() -> float: return treadmill.volume_master,
			func(v: float) -> void: treadmill.volume_master = v, _percent)
	_stepper(tab, "Background (wind, distant sounds)", 0.1, 0.0, 1.0,
			func() -> float: return treadmill.volume_ambience,
			func(v: float) -> void: treadmill.volume_ambience = v, _percent)
	_stepper(tab, "World sounds (birds, creatures)", 0.1, 0.0, 1.0,
			func() -> float: return treadmill.volume_world,
			func(v: float) -> void: treadmill.volume_world = v, _percent)
	_stepper(tab, "Effects (footsteps, chimes)", 0.1, 0.0, 1.0,
			func() -> float: return treadmill.volume_effects,
			func(v: float) -> void: treadmill.volume_effects = v, _percent)
	_heading(tab, "Spatial sound")
	_toggle(tab, "Binaural cues (switch off to compare)", treadmill.binaural_audio,
			func(on: bool) -> void: treadmill.binaural_audio = on)
	_toggle(tab, "Footstep sounds", treadmill.footstep_sounds,
			func(on: bool) -> void: treadmill.footstep_sounds = on)


func _build_headset_tab(tab: VBoxContainer) -> void:
	_heading(tab, "Refresh rate")
	_label(tab, "Higher is smoother but gives each frame less time. Watch the fps on the walking panel.")
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Display refresh rate"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var value := Label.new()
	value.custom_minimum_size = Vector2(130, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var minus := _button("  -  ", func() -> void: _step_refresh_rate(-1))
	var plus := _button("  +  ", func() -> void: _step_refresh_rate(1))
	minus.custom_minimum_size.x = 70
	plus.custom_minimum_size.x = 70
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	tab.add_child(row)
	_refreshers.append(func() -> void:
		value.text = "%d Hz" % roundi(xr.get_display_refresh_rate()) if xr else "n/a")
	_heading(tab, "Eye tracking diagnostics")
	_headset_label = _label(tab, "")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var d := treadmill.detector
	if _live_label:
		if d.cadence_spm <= 0.0:
			_live_label.text = "Now: not walking"
		else:
			_live_label.text = "Now: %d steps/min, %s" % [roundi(d.cadence_spm),
					"steady - ready to calibrate" if d.is_stable() else "settling..."]
	_headset_timer -= delta
	if _headset_timer <= 0.0 and _headset_label:
		_headset_timer = 0.5
		_headset_label.text = "\n".join(headset_report(xr, eye))


## Plain-language status of everything eye tracking depends on.
static func headset_report(xr_: OpenXRInterface, eye_: XRController3D) -> PackedStringArray:
	var lines: PackedStringArray = []
	if xr_ == null or not xr_.is_initialized():
		lines.append("Not running in a headset.")
		return lines
	var sys := xr_.get_system_info()
	lines.append("Runtime: %s %s" % [sys.get("XRRuntimeName", "?"), sys.get("XRRuntimeVersion", "")])
	lines.append("1. Runtime offers eye gaze: %s" % ("yes" if xr_.is_eye_gaze_interaction_supported() else "NO"))
	var tracker := XRServer.get_tracker(&"/user/eyes_ext") as XRPositionalTracker
	lines.append("2. Eye tracker registered: %s" % ("yes" if tracker else "NO"))
	var pose: XRPose = tracker.get_pose(&"default") if tracker else null
	var tracking := eye_ != null and eye_.get_has_tracking_data()
	lines.append("3. Eye tracker sending data: %s%s" % ["yes" if tracking else "NO",
			" (confidence %d)" % pose.tracking_confidence if pose else ""])
	if OS.get_name() == "Android":
		var eye_perms: PackedStringArray = []
		for p in OS.get_granted_permissions():
			if "EYE" in p:
				eye_perms.append(p.get_slice(".", p.get_slice_count(".") - 1))
		lines.append("4. Eye permissions granted: %s" % (", ".join(eye_perms) if eye_perms.size() > 0 else "none"))
	var rates := xr_.get_available_display_refresh_rates()
	var rate_names: PackedStringArray = []
	for r in rates:
		rate_names.append(str(roundi(r)))
	lines.append("Refresh rates available: %s Hz" % (", ".join(rate_names) if rate_names.size() > 0 else "not reported"))
	return lines


func _step_refresh_rate(direction: int) -> void:
	if xr == null:
		return
	var rates: Array = Array(xr.get_available_display_refresh_rates())
	if rates.is_empty():
		return
	rates.sort()
	var current := xr.get_display_refresh_rate()
	var index := 0
	for i in rates.size():
		if absf(rates[i] - current) < 1.0:
			index = i
	index = clampi(index + direction, 0, rates.size() - 1)
	xr.set_display_refresh_rate(rates[index])
	treadmill.refresh_rate = rates[index]
	treadmill.save_settings()


func refresh() -> void:
	var f := treadmill.footprint
	_footprint_label.text = "Belt: %.2f m wide x %.2f m long" % [f.width, f.length] \
			if f.is_valid() else "Not measured yet. Needed for the see-through area and edge warnings."
	var pts := treadmill.calibration.points
	if pts.is_empty():
		_points_label.text = "No calibration yet (assuming 0.70 m steps)"
	else:
		var parts: PackedStringArray = []
		for p in pts:
			parts.append("%d spm: %.2f m" % [roundi(p.x), p.y])
		_points_label.text = "Saved: " + ",  ".join(parts)
	for r in _refreshers:
		r.call()


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	tabs.add_child(margin)
	return box


func _heading(parent: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	parent.add_child(l)


func _label(parent: Container, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _toggle(parent: Container, text: String, on: bool, setter: Callable,
		save_kit_settings := true) -> CheckButton:
	var t := CheckButton.new()
	t.text = text
	t.button_pressed = on
	t.custom_minimum_size = Vector2(0, 56)
	t.toggled.connect(func(value: bool) -> void:
		setter.call(value)
		if save_kit_settings:
			treadmill.save_settings())
	parent.add_child(t)
	return t


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.pressed.connect(action)
	return b


## A row like:  Label ........ [ - ]  3.0 mph  [ + ]
func _stepper(parent: Container, text: String, step: float, lo: float, hi: float,
		getter: Callable, setter: Callable, fmt: Callable, save_kit_settings := true) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var value := Label.new()
	value.custom_minimum_size = Vector2(130, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var change := func(amount: float) -> void:
		setter.call(clampf(snappedf(getter.call() + amount, step), lo, hi))
		if save_kit_settings:
			treadmill.save_settings()
		else:
			refresh()
	var minus := _button("  -  ", func() -> void: change.call(-step))
	var plus := _button("  +  ", func() -> void: change.call(step))
	minus.custom_minimum_size.x = 70
	plus.custom_minimum_size.x = 70
	row.add_child(minus)
	row.add_child(value)
	row.add_child(plus)
	parent.add_child(row)
	_refreshers.append(func() -> void: value.text = fmt.call(getter.call()))


# --- For games: your own tabs and controls -----------------------------------

## Adds a tab and returns the box to fill. Controls are stacked top to bottom.
func add_tab(title: String) -> VBoxContainer:
	return _tab(_tabs, title)


func add_heading(parent: Container, text: String) -> void:
	_heading(parent, text)


func add_label(parent: Container, text: String) -> Label:
	return _label(parent, text)


func add_button(parent: Container, text: String, action: Callable) -> Button:
	var b := _button(text, action)
	parent.add_child(b)
	return b


## on_toggled(value: bool) is called on every change.
func add_toggle(parent: Container, text: String, on: bool, on_toggled: Callable) -> CheckButton:
	return _toggle(parent, text, on, on_toggled, false)


## A "label [-] value [+]" row. getter() returns the value, setter(v) stores it,
## fmt(v) turns it into text. The value is clamped to lo..hi in steps of step.
func add_stepper(parent: Container, text: String, step: float, lo: float, hi: float,
		getter: Callable, setter: Callable, fmt: Callable) -> void:
	_stepper(parent, text, step, lo, hi, getter, setter, fmt, false)
	refresh()


static func _percent(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)


static func _cm(v: float) -> String:
	return "%d cm" % roundi(v * 100.0)
