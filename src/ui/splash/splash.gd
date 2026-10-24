class_name Splash
extends Control

signal finished

const VIDEO_PATH: String = "res://assets/branding/palehour-intro/palehour-intro.ogv"
const FALLBACK_IMAGE_PATH: String = "res://assets/branding/palehour-intro/palehour-intro-final.png"
# The game opens on the 3D city of the full map (issue #65); scenes/main.tscn keeps the 2D map the tests drive.
const MAIN_SCENE_PATH: String = "res://scenes/city.tscn"
const VIDEO_ASPECT: float = 16.0 / 9.0
const FULL_DB: float = 0.0
const SILENT_DB: float = -60.0

@export var auto_change_scene: bool = true
@export var enabled: bool = true

var _flow: SplashFlow
var _player: VideoStreamPlayer
var _image: TextureRect
var _fade: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	var timings: SplashTimings = SplashTimings.new()
	timings.load_data()
	var has_timings: bool = timings.errors.is_empty()
	if not has_timings:
		# A broken data file must never trap the player on the splash: skip it and go to the game.
		push_error("Splash: %s. Skipping the intro." % "; ".join(timings.errors))
	_flow = SplashFlow.new(enabled and has_timings and SplashSettings.is_enabled(), timings)
	_flow.phase_changed.connect(_on_phase_changed)
	_flow.completed.connect(_on_completed)
	if _flow.is_done():
		_on_completed()
		return
	_start_video()


func _process(delta: float) -> void:
	_flow.advance(delta)
	if _flow.phase == SplashFlow.Phase.FADING:
		_apply_fade(_flow.fade_progress())


func _input(event: InputEvent) -> void:
	if SplashFlow.is_skip_event(event):
		get_viewport().set_input_as_handled()
		_flow.skip_requested()


func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_image = TextureRect.new()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.visible = false
	add_child(_image)
	var frame: AspectRatioContainer = AspectRatioContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.ratio = VIDEO_ASPECT
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	add_child(frame)
	_player = VideoStreamPlayer.new()
	_player.expand = true
	_player.finished.connect(func() -> void: _flow.video_finished())
	frame.add_child(_player)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _start_video() -> void:
	var stream: VideoStream = null
	if ResourceLoader.exists(VIDEO_PATH):
		stream = load(VIDEO_PATH) as VideoStream
	if stream == null:
		push_warning("Splash: could not load %s, showing the fallback image." % VIDEO_PATH)
		_flow.video_failed()
		return
	_player.stream = stream
	_player.play()


func _on_phase_changed(phase: SplashFlow.Phase) -> void:
	match phase:
		SplashFlow.Phase.FALLBACK:
			_show_fallback()


func _show_fallback() -> void:
	_player.stop()
	_player.visible = false
	if ResourceLoader.exists(FALLBACK_IMAGE_PATH):
		_image.texture = load(FALLBACK_IMAGE_PATH) as Texture2D
	_image.visible = _image.texture != null


func _apply_fade(progress: float) -> void:
	_fade.color = Color(0.0, 0.0, 0.0, progress)
	_player.volume_db = lerpf(FULL_DB, SILENT_DB, progress)


func _on_completed() -> void:
	_player.stop()
	finished.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
