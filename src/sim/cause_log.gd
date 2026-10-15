class_name CauseLog
extends RefCounted

# Why things happened, as events (issue #82, D-066): one entry each time the cause of a subject changes (a building
# stops for lack of input, a class starts leaving out of hunger, a policy moves). It is the base of the backward
# "why?" (#73). A change is logged only once it lasts min_duration seconds; a subject that flips faster gets one
# "intermittent" event whose count grows until a cause holds. The oldest events are dropped past the cap, so a
# long game cannot grow a save forever.

const SEPARATOR: String = "|"
const INTERMITTENT: StringName = &"intermittent"

var _max_events: int
var _min_duration: int
# Ring of events, the oldest at _head once full: {"second", "kind", "subject", "cause"}, plus "count" (changes
# that did not last) on an intermittent event.
var _events: Array[Dictionary] = []
var _head: int = 0
# Events ever logged: an intermittent event is found by this serial while the ring still holds it.
var _logged: int = 0
# "kind|subject" -> its logged cause, so a repeated cause is not logged again.
var _current: Dictionary[String, StringName] = {}
# "kind|subject" -> [cause, first second] of a change that has not lasted min_duration yet.
var _pending: Dictionary[String, Array] = {}
# "kind|subject" -> serial of its intermittent event, while the subject keeps flipping.
var _flicker: Dictionary[String, int] = {}


func _init(max_events: int, min_duration: int = 0) -> void:
	_max_events = maxi(1, max_events)
	_min_duration = maxi(0, min_duration)


# Returns whether the log changed (a new event, or one more flip on an intermittent one). An immediate note skips
# the duration filter: milestones that may end the game (a defeat) or that are not states (a command).
func note(second: int, kind: StringName, subject: StringName, cause: StringName, immediate: bool = false) -> bool:
	var key: String = String(kind) + SEPARATOR + String(subject)
	# The first cause of a subject is its starting state: nothing to flip against.
	if immediate or _min_duration == 0 or not _current.has(key):
		_pending.erase(key)
		_flicker.erase(key)
		return _log(key, second, kind, subject, cause)
	if not _pending.has(key):
		if _current[key] == cause:
			return false
		_pending[key] = [cause, second]
		return false
	var candidate: Array = _pending[key]
	if cause == candidate[0]:
		if second - int(candidate[1]) < _min_duration:
			return false
		_pending.erase(key)
		_flicker.erase(key)
		return _log(key, int(candidate[1]), kind, subject, cause)
	# The change did not last: the subject is flipping.
	_pending.erase(key)
	_flipped(key, int(candidate[1]), kind, subject)
	if cause != _current[key]:
		_pending[key] = [cause, second]
	return true


# Subjects of a kind that no longer exist (a demolished building) are logged as gone once, without waiting.
func forget_missing(second: int, kind: StringName, present: Array[StringName], gone: StringName) -> void:
	var prefix: String = String(kind) + SEPARATOR
	for key: String in _current.keys():
		if not key.begins_with(prefix) or _current[key] == gone:
			continue
		var subject: StringName = StringName(key.substr(prefix.length()))
		if subject not in present:
			note(second, kind, subject, gone, true)


func events(from_second: int = 0) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for index: int in _events.size():
		var event: Dictionary = _at(index)
		if int(event["second"]) >= from_second:
			found.append(event.duplicate())
	return found


func _log(key: String, second: int, kind: StringName, subject: StringName, cause: StringName) -> bool:
	if _current.get(key) == cause:
		return false
	_current[key] = cause
	_append({"second": second, "kind": kind, "subject": subject, "cause": cause})
	return true


func _flipped(key: String, second: int, kind: StringName, subject: StringName) -> void:
	var index: int = _flicker.get(key, -1) - (_logged - _events.size())
	if _flicker.has(key) and index >= 0:
		_at(index)["count"] += 1
		return
	_current[key] = INTERMITTENT
	_append({"second": second, "kind": kind, "subject": subject, "cause": INTERMITTENT, "count": 1})
	_flicker[key] = _logged - 1


func _append(event: Dictionary) -> void:
	_logged += 1
	if _events.size() < _max_events:
		_events.append(event)
		return
	_events[_head] = event
	_head = (_head + 1) % _max_events


# The index-th oldest event held.
func _at(index: int) -> Dictionary:
	return _events[(_head + index) % _events.size()]


# Parallel packed arrays: much smaller in a save than one dictionary per event.
func to_dict() -> Dictionary:
	var seconds: PackedInt32Array = []
	var kinds: PackedStringArray = []
	var subjects: PackedStringArray = []
	var causes: PackedStringArray = []
	var counts: PackedInt32Array = []
	for event: Dictionary in events():
		seconds.append(int(event["second"]))
		kinds.append(String(event["kind"]))
		subjects.append(String(event["subject"]))
		causes.append(String(event["cause"]))
		counts.append(int(event.get("count", 0)))
	var current_keys: PackedStringArray = []
	var current_causes: PackedStringArray = []
	for key: String in _current:
		current_keys.append(key)
		current_causes.append(String(_current[key]))
	var pending_keys: PackedStringArray = []
	var pending_causes: PackedStringArray = []
	var pending_seconds: PackedInt32Array = []
	for key: String in _pending:
		pending_keys.append(key)
		pending_causes.append(String(_pending[key][0]))
		pending_seconds.append(int(_pending[key][1]))
	var flicker_keys: PackedStringArray = []
	var flicker_serials: PackedInt32Array = []
	for key: String in _flicker:
		flicker_keys.append(key)
		flicker_serials.append(_flicker[key])
	return {"seconds": seconds, "kinds": kinds, "subjects": subjects, "causes": causes, "counts": counts,
		"logged": _logged, "current_keys": current_keys, "current_causes": current_causes,
		"pending_keys": pending_keys, "pending_causes": pending_causes, "pending_seconds": pending_seconds,
		"flicker_keys": flicker_keys, "flicker_serials": flicker_serials}


# Returns false (and keeps the log empty) when the saved log is malformed.
func restore(saved: Dictionary) -> bool:
	_clear()
	var types: Dictionary[String, int] = {"seconds": TYPE_PACKED_INT32_ARRAY, "kinds": TYPE_PACKED_STRING_ARRAY,
		"subjects": TYPE_PACKED_STRING_ARRAY, "causes": TYPE_PACKED_STRING_ARRAY, "counts": TYPE_PACKED_INT32_ARRAY,
		"logged": TYPE_INT, "current_keys": TYPE_PACKED_STRING_ARRAY, "current_causes": TYPE_PACKED_STRING_ARRAY,
		"pending_keys": TYPE_PACKED_STRING_ARRAY, "pending_causes": TYPE_PACKED_STRING_ARRAY,
		"pending_seconds": TYPE_PACKED_INT32_ARRAY, "flicker_keys": TYPE_PACKED_STRING_ARRAY,
		"flicker_serials": TYPE_PACKED_INT32_ARRAY}
	for field: String in types:
		if typeof(saved.get(field)) != types[field]:
			return false
	var count: int = saved["seconds"].size()
	if saved["kinds"].size() != count or saved["subjects"].size() != count or saved["causes"].size() != count \
			or saved["counts"].size() != count or int(saved["logged"]) < count \
			or saved["current_keys"].size() != saved["current_causes"].size() \
			or saved["pending_keys"].size() != saved["pending_causes"].size() \
			or saved["pending_keys"].size() != saved["pending_seconds"].size() \
			or saved["flicker_keys"].size() != saved["flicker_serials"].size():
		return false
	for index: int in range(maxi(0, count - _max_events), count):
		var event: Dictionary = {"second": saved["seconds"][index], "kind": StringName(saved["kinds"][index]),
			"subject": StringName(saved["subjects"][index]), "cause": StringName(saved["causes"][index])}
		if saved["counts"][index] > 0:
			event["count"] = saved["counts"][index]
		_events.append(event)
	_logged = int(saved["logged"])
	for index: int in saved["current_keys"].size():
		_current[saved["current_keys"][index]] = StringName(saved["current_causes"][index])
	for index: int in saved["pending_keys"].size():
		_pending[saved["pending_keys"][index]] = [StringName(saved["pending_causes"][index]),
			saved["pending_seconds"][index]]
	for index: int in saved["flicker_keys"].size():
		_flicker[saved["flicker_keys"][index]] = saved["flicker_serials"][index]
	return true


func _clear() -> void:
	_events.clear()
	_head = 0
	_logged = 0
	_current.clear()
	_pending.clear()
	_flicker.clear()
