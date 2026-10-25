extends Node3D
## Demo game for Treadmill Frame XR Kit: walk an endless dusk forest road and
## notice the rune-marked waystones along it (a gaze test), surrounded by
## positional forest sound: a bee around your head, songbirds, crickets, birds
## flying over, a distant owl and woodpecker, and wind in the trees.
##
## Shows the usual pattern for a kit game: instance TFXRig, give it a world,
## listen to its signals, add lines to the walking panel and a settings tab.

@onready var rig: TFXRig = $Rig
@onready var world: TFXPathWorld = $PathWorld
@onready var chime: AudioStreamPlayer = $Chime
@onready var ambience: AudioStreamPlayer = $Ambience

var noticed := 0
var passed := 0


func _ready() -> void:
	world.setup(DemoForestTheme.new())
	rig.world_root = world
	rig.gaze.target_noticed.connect(_on_target_noticed)
	world.target_passed.connect(func(_t: TFXGazeTarget) -> void: passed += 1)
	chime.stream = TFXSounds.chime()
	chime.bus = TFXAudio.EFFECTS
	ambience.stream = DemoSounds.AMBIENCE
	ambience.bus = TFXAudio.AMBIENCE   # muted by the rig outside World view
	ambience.play()
	var wildlife := DemoWildlife.new()
	wildlife.rig = rig
	world.add_child(wildlife)

	var menu := rig.settings_menu
	var tab := menu.add_tab("Demo")
	menu.add_heading(tab, "Waystone gaze test")
	menu.add_label(tab, "Each 30 m of road has one rune-marked waystone. Look at one for half a second and it turns gold. The bee counts too, if you can find it by its buzz.")
	menu.add_button(tab, "Reset waystone count", _reset_count)


func _process(_delta: float) -> void:
	rig.hud_extra_lines = ["Waystones noticed %d of %d passed" % [noticed, passed]]


func _on_target_noticed(target: TFXGazeTarget) -> void:
	chime.play()
	if target.label == "bee":
		rig.toast("You found the bee!")
		return
	noticed += 1


func _reset_count() -> void:
	noticed = 0
	passed = 0
