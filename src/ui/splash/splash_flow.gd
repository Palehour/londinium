class_name SplashFlow
extends RefCounted

signal phase_changed(phase: Phase)
signal completed

enum Phase { PLAYING, FALLBACK, FADING, DONE }

var phase: Phase = Phase.PLAYING
var _timings: SplashTimings
var _elapsed: float = 0.0


# Without timings the flow only reacts to events; with them, advance() drives the watchdog,
# the fallback image and the fade from a clock the caller owns (a node's delta, or a test's).
func _init(enabled: bool = true, timings: SplashTimings = null) -> void:
	_timings = timings
	if not enabled:
		phase = Phase.DONE


static func is_skip_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		return event.is_pressed()
	return false


func is_done() -> bool:
	return phase == Phase.DONE


# The clock restarts on every phase change, so a stalled video, the fallback image and the fade each get their own budget.
func advance(delta: float) -> void:
	if _timings == null or phase == Phase.DONE:
		return
	_elapsed += delta
	match phase:
		Phase.PLAYING:
			if _elapsed >= _timings.watchdog_seconds:
				video_failed()
		Phase.FALLBACK:
			if _elapsed >= _timings.fallback_seconds:
				fallback_elapsed()
		Phase.FADING:
			if _elapsed >= _timings.fade_seconds:
				fade_finished()


func fade_progress() -> float:
	if _timings == null or phase != Phase.FADING:
		return 0.0
	return clampf(_elapsed / _timings.fade_seconds, 0.0, 1.0)


func video_finished() -> void:
	if phase == Phase.PLAYING:
		_finish()


func video_failed() -> void:
	if phase == Phase.PLAYING:
		_set_phase(Phase.FALLBACK)


func fallback_elapsed() -> void:
	if phase == Phase.FALLBACK:
		_finish()


func skip_requested() -> void:
	if phase == Phase.PLAYING or phase == Phase.FALLBACK:
		_set_phase(Phase.FADING)


func fade_finished() -> void:
	if phase == Phase.FADING:
		_finish()


func _set_phase(next: Phase) -> void:
	phase = next
	_elapsed = 0.0
	phase_changed.emit(next)


func _finish() -> void:
	_set_phase(Phase.DONE)
	completed.emit()
