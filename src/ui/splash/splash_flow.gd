class_name SplashFlow
extends RefCounted

signal phase_changed(phase: Phase)
signal completed

enum Phase { PLAYING, FALLBACK, FADING, DONE }

var phase: Phase = Phase.PLAYING


func _init(enabled: bool = true) -> void:
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
	phase_changed.emit(next)


func _finish() -> void:
	_set_phase(Phase.DONE)
	completed.emit()
