class_name Autosave
extends RefCounted

# Autosaves (issue #57, numbers approved on 2026-10-13): every `autosave_interval_seconds` of game time into
# `autosave_slots` rotating slots, and one file of its own for each chapter stage the moment it is met (#56). It
# listens to every published tick, so it always saves between ticks.

signal saved(path: String)

var _session: GameSession
var _settings: SaveSettings
var _root: String
var _next_slot: int = 1
var _completed: Array[StringName] = []


func _init(session: GameSession, settings: SaveSettings, root: String) -> void:
	_session = session
	_settings = settings
	_root = root
	_next_slot = _slot_after_newest()
	reset()


# A new or loaded game: the stages it already met do not save again.
func reset() -> void:
	_completed = _completed_stages(_session.get_snapshot())


func observe(snapshot: Dictionary) -> void:
	var tick: int = int(snapshot["tick_count"])
	if tick > 0 and tick % _settings.autosave_interval_seconds == 0:
		_write(SaveFile.autosave_path(_root, _next_slot))
		_next_slot = _next_slot % _settings.autosave_slots + 1
	for stage_id: StringName in _completed_stages(snapshot):
		if not _completed.has(stage_id):
			_completed.append(stage_id)
			_write(SaveFile.stage_path(_root, stage_id))


func _write(path: String) -> void:
	var error: Error = SaveFile.write(path, SaveFile.build(_session))
	if error != OK:
		push_warning("Autosave: could not write %s (%s)" % [path, error_string(error)])
		return
	saved.emit(path)


func _completed_stages(snapshot: Dictionary) -> Array[StringName]:
	var completed: Array[StringName] = []
	var stages: Dictionary = snapshot["victory"]["stages"]
	for stage_id: Variant in stages:
		if stages[stage_id]["completed"]:
			completed.append(StringName(stage_id))
	return completed


# Rotation goes on across sessions: the slot after the newest autosave already on disk.
func _slot_after_newest() -> int:
	for entry: Dictionary in SaveFile.list(_root):
		var slot: int = int(entry["slot"])
		if entry["kind"] == SaveFile.KIND_AUTOSAVE and slot >= 1 and slot <= _settings.autosave_slots:
			return slot % _settings.autosave_slots + 1
	return 1
