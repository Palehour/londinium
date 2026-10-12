class_name Splash
extends Control

signal finished

const VIDEO_PATH: String = "res://assets/branding/palehour-intro/palehour-intro.ogv"
const FALLBACK_IMAGE_PATH: String = "res://assets/branding/palehour-intro/palehour-intro-final.png"
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const VIDEO_ASPECT: float = 16.0 / 9.0
const FADE_SECONDS: float = 0.4
const FALLBACK_SECONDS: float = 3.0
# The intro lasts 10 s; this only guards against a stream that loads but never ends.
const WATCHDOG_SECONDS: float = 15.0
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
	_flow = SplashFlow.new(enabled and SplashSettings.is_enabled())
	_flow.phase_changed.connect(_on_phase_changed)
	_flow.completed.connect(_on_completed)
	if _flow.is_done():
		_on_completed()
		return
	_start_video()


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
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_flow.video_finished)


func _on_phase_changed(phase: SplashFlow.Phase) -> void:
	match phase:
		SplashFlow.Phase.FALLBACK:
			_show_fallback()
		SplashFlow.Phase.FADING:
			_start_fade()


func _show_fallback() -> void:
	_player.stop()
	_player.visible = false
	if ResourceLoader.exists(FALLBACK_IMAGE_PATH):
		_image.texture = load(FALLBACK_IMAGE_PATH) as Texture2D
	_image.visible = _image.texture != null
	get_tree().create_timer(FALLBACK_SECONDS).timeout.connect(_flow.fallback_elapsed)


func _start_fade() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(_fade, "color:a", 1.0, FADE_SECONDS)
	tween.tween_property(_player, "volume_db", SILENT_DB, FADE_SECONDS)
	tween.finished.connect(_flow.fade_finished)


func _on_completed() -> void:
	_player.stop()
	finished.emit()
	if auto_change_scene:
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
