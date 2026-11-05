class_name MobilityNoticeWindow
extends RefCounted

# Adds up, over a window of simulation seconds, the posts the promoted workers left (issue #352). The panel feeds it
# GameSession.get_mobility_events(); it only counts and orders what the simulation reported, it decides no rule.
# One tick is one simulation second, so the window runs on the tick counter and never on frames or real time.

const KEY_WINDOW: StringName = &"ui.mobility.labor_notice_window_seconds"
const KEY_WARNING: StringName = &"ui.mobility.demotion_warning_seconds"
const KEY_MAX_BUILDINGS: StringName = &"ui.mobility.max_buildings_listed"
# Returned by read_knob() for a knob that is missing or has no data yet: its notice stays off.
const PENDING: int = -1

# Each entry is one tick in which employed people rose: {"tick": int, "employed": int, "buildings": Array}.
var _entries: Array[Dictionary] = []
var _now: int = -1


# A knob counts only as a non-negative number. The "sin dato" literal, a missing key or anything else is PENDING:
# there is no default to fall back on.
static func read_knob(params: Params, key: StringName, minimum: int = 0) -> int:
	if params == null or not params.has_value(key):
		return PENDING
	var value: Variant = params.get_value(key)
	if not (value is int or value is float):
		return PENDING
	if value < minimum:
		return PENDING
	return int(value)


func clear() -> void:
	_entries.clear()
	_now = -1


# `events` is what GameSession.get_mobility_events() returns; `window_seconds` is PENDING while the knob has no data, which empties
# the window. The same tick twice adds nothing; a tick before the last one means another game, so it starts over.
func record(events: Dictionary, window_seconds: int) -> void:
	if window_seconds < 0:
		clear()
		return
	if events.is_empty() or not events.has("tick"):
		return
	var tick: int = int(events["tick"])
	if tick < _now:
		clear()
	if tick > _now:
		_now = tick
		var employed: int = int(events.get("employed_promoted", 0))
		if employed > 0:
			_entries.append({"tick": tick, "employed": employed, "buildings": events.get("buildings", [])})
	_prune(window_seconds)


# Posts lost inside the window, and the buildings that lost them, in the order they were reported. At most `limit`
# are listed; `hidden` counts those left out.
func summary(limit: int) -> Dictionary:
	var total: int = 0
	for entry: Dictionary in _entries:
		total += int(entry["employed"])
	var by_building: Dictionary[String, Dictionary] = {}
	for entry: Dictionary in _entries:
		for building: Dictionary in entry["buildings"]:
			var lost: int = int(building.get("workers_lost", 0))
			if lost <= 0:
				continue
			var id: String = str(building.get("id", building.get("definition_id", "")))
			if not by_building.has(id):
				by_building[id] = {"definition_id": building.get("definition_id", &""), "workers_lost": 0}
			by_building[id]["workers_lost"] += lost
	# No ranking rule: the buildings keep the order the simulation reported them in, so the cut is predictable.
	var rows: Array[Dictionary] = []
	rows.assign(by_building.values())
	var shown: Array[Dictionary] = rows.slice(0, maxi(0, limit))
	return {"total": total, "buildings": shown, "hidden": rows.size() - shown.size()}


func _prune(window_seconds: int) -> void:
	while not _entries.is_empty() and _now - int(_entries[0]["tick"]) >= window_seconds:
		_entries.pop_front()
