class_name CauseLog
extends RefCounted

# Why things happened, as events (issue #82, D-066): one entry each time the cause of a subject changes (a building
# stops for lack of input, a class starts leaving out of hunger, a policy moves). It is the base of the backward
# "why?" (#73). The oldest events are dropped past the cap, so a cause that flickers cannot grow a save forever.

const SEPARATOR: String = "|"

var _max_events: int
# Oldest first: {"second", "kind", "subject", "cause"}.
var _events: Array[Dictionary] = []
# "kind|subject" -> its current cause, so a repeated cause is not logged again.
var _current: Dictionary[String, StringName] = {}


func _init(max_events: int) -> void:
	_max_events = maxi(1, max_events)


# Returns whether the cause changed (and so was logged).
func note(second: int, kind: StringName, subject: StringName, cause: StringName) -> bool:
	var key: String = String(kind) + SEPARATOR + String(subject)
	if _current.has(key) and _current[key] == cause:
		return false
	_current[key] = cause
	_events.append({"second": second, "kind": kind, "subject": subject, "cause": cause})
	if _events.size() > _max_events:
		_events.pop_front()
	return true


# Subjects of a kind that no longer exist (a demolished building) are logged as gone once.
func forget_missing(second: int, kind: StringName, present: Array[StringName], gone: StringName) -> void:
	var prefix: String = String(kind) + SEPARATOR
	for key: String in _current.keys():
		if not key.begins_with(prefix) or _current[key] == gone:
			continue
		var subject: StringName = StringName(key.substr(prefix.length()))
		if subject not in present:
			note(second, kind, subject, gone)


func events(from_second: int = 0) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event: Dictionary in _events:
		if int(event["second"]) >= from_second:
			found.append(event.duplicate())
	return found


# Parallel packed arrays: much smaller in a save than one dictionary per event.
func to_dict() -> Dictionary:
	var seconds: PackedInt32Array = []
	var kinds: PackedStringArray = []
	var subjects: PackedStringArray = []
	var causes: PackedStringArray = []
	for event: Dictionary in _events:
		seconds.append(int(event["second"]))
		kinds.append(String(event["kind"]))
		subjects.append(String(event["subject"]))
		causes.append(String(event["cause"]))
	var current_keys: PackedStringArray = []
	var current_causes: PackedStringArray = []
	for key: String in _current:
		current_keys.append(key)
		current_causes.append(String(_current[key]))
	return {"seconds": seconds, "kinds": kinds, "subjects": subjects, "causes": causes,
		"current_keys": current_keys, "current_causes": current_causes}


# Returns false (and keeps the log empty) when the saved log is malformed.
func restore(saved: Dictionary) -> bool:
	_events.clear()
	_current.clear()
	var fields: Array[String] = ["seconds", "kinds", "subjects", "causes", "current_keys", "current_causes"]
	if not fields.all(func(field: String) -> bool: return saved.has(field)):
		return false
	var seconds: Variant = saved["seconds"]
	var kinds: Variant = saved["kinds"]
	var subjects: Variant = saved["subjects"]
	var causes: Variant = saved["causes"]
	var current_keys: Variant = saved["current_keys"]
	var current_causes: Variant = saved["current_causes"]
	if seconds is not PackedInt32Array or kinds is not PackedStringArray or subjects is not PackedStringArray \
			or causes is not PackedStringArray or current_keys is not PackedStringArray \
			or current_causes is not PackedStringArray:
		return false
	var count: int = seconds.size()
	if kinds.size() != count or subjects.size() != count or causes.size() != count \
			or current_keys.size() != current_causes.size():
		return false
	for index: int in range(maxi(0, count - _max_events), count):
		_events.append({"second": seconds[index], "kind": StringName(kinds[index]),
			"subject": StringName(subjects[index]), "cause": StringName(causes[index])})
	for index: int in current_keys.size():
		_current[current_keys[index]] = StringName(current_causes[index])
	return true
