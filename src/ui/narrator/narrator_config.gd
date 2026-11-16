class_name NarratorConfig
extends RefCounted

# The knobs and rules of the narrator (issue #73), from data/ui/narrator.json: the pause on what is critical (D-145),
# the anti-saturation (D-146) and which events of the cause log become notices. A rule matches a kind and, if it
# names one, a cause; the first rule that matches decides, and a silent one says nothing. Only the kinds the cause
# log keeps are accepted (D-147).

const PATH: String = "res://data/ui/narrator.json"
# Most urgent first: a lower index wins a slot.
const PRIORITIES: Array[StringName] = [&"critical", &"high", &"normal", &"low"]
const CRITICAL: StringName = &"critical"
const COUNT_KNOBS: Array[String] = ["group_window_s", "max_visible", "attention_budget_per_min", "digest_interval_s",
	"threshold_hysteresis", "min_button_px"]
# Rules that name no target go nowhere on the map; a building's subject carries its cell. Districts fall back to none
# until the log keeps one as a subject (#82 note).
# The points a threshold is read in (0 to 100, spec §10).
const MAX_POINTS: int = 100
const TARGET_NONE: StringName = &"none"
const TARGET_SUBJECT_CELL: StringName = &"subject_cell"
const TARGETS: Array[StringName] = [TARGET_NONE, TARGET_SUBJECT_CELL]

var pause_on_critical: bool = false
var cooldown_s: Dictionary[StringName, int] = {}
var group_window_s: int = 0
var max_visible: int = 0
var attention_budget_per_min: int = 0
# What a notice of each priority spends of the budget; what is critical spends nothing.
var attention_cost: Dictionary[StringName, int] = {}
var digest_interval_s: int = 0
# Seconds a notice stays up by priority; a critical one stays until it is closed.
var toast_lifetime_s: Dictionary[StringName, int] = {}
# Reserved for the thresholds of the kinds the log does not keep yet (legitimacy, factions): read and checked, not used.
var threshold_hysteresis: int = 0
var legitimacy_thresholds: Array[int] = []
# The smallest side of a button of the notices, for the gamepad and the Steam Deck.
var min_button_px: int = 0
# Each {kind, cause (&"" for any), silent, priority, key, pause, crisis, series, overlay, target_from}; `series` and
# `overlay` may hold {subject} (the event's subject) and {building} (its building id).
var rules: Array[Dictionary] = []
var errors: Array[String] = []


func load_data() -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
		errors.append("data/ui/narrator.json: invalid JSON")
		return
	validate(json.data)


# `kinds`: the kinds a rule may name, the cause log's unless a test adds one that is not logged yet.
func validate(raw: Variant, kinds: Array[StringName] = StatsHistory.CAUSE_KINDS) -> void:
	if raw is not Dictionary:
		errors.append("data/ui/narrator.json: expected an object")
		return
	if typeof(raw.get("pause_on_critical")) != TYPE_BOOL:
		errors.append("data/ui/narrator.json.pause_on_critical: expected true or false")
	else:
		pause_on_critical = raw["pause_on_critical"]
	for knob: String in COUNT_KNOBS:
		var value: int = _count(raw.get(knob), "data/ui/narrator.json.%s" % knob)
		set(knob, value)
	if raw.get("max_visible") is float and max_visible < 1:
		errors.append("data/ui/narrator.json.max_visible: expected at least 1")
	cooldown_s = _by_priority(raw.get("cooldown_s"), "cooldown_s", PRIORITIES)
	var costed: Array[StringName] = PRIORITIES.duplicate()
	costed.erase(CRITICAL)
	attention_cost = _by_priority(raw.get("attention_cost"), "attention_cost", costed)
	attention_cost[CRITICAL] = 0
	var lived: Array[StringName] = costed.duplicate()
	toast_lifetime_s = _by_priority(raw.get("toast_lifetime_s"), "toast_lifetime_s", lived)
	_read_thresholds(raw.get("legitimacy_thresholds"))
	_read_rules(raw.get("rules"), kinds)


func rule_for(kind: StringName, cause: StringName) -> Dictionary:
	for rule: Dictionary in rules:
		if rule["kind"] == kind and (rule["cause"] == &"" or rule["cause"] == cause):
			return rule
	return {}


# The translation key of every rule that speaks.
func keys() -> Array[StringName]:
	var found: Array[StringName] = []
	for rule: Dictionary in rules:
		if not rule["silent"] and rule["key"] not in found:
			found.append(rule["key"])
	return found


func _count(value: Variant, path: String) -> int:
	if value is not float or value < 0 or value != floorf(value):
		errors.append("%s: expected a whole number, 0 or more" % path)
		return 0
	return int(value)


func _by_priority(raw: Variant, field: String, priorities: Array[StringName]) -> Dictionary[StringName, int]:
	var found: Dictionary[StringName, int] = {}
	if raw is not Dictionary:
		errors.append("data/ui/narrator.json.%s: expected an object by priority" % field)
		return found
	for priority: StringName in priorities:
		found[priority] = _count(raw.get(String(priority)), "data/ui/narrator.json.%s.%s" % [field, priority])
	return found


func _read_thresholds(raw: Variant) -> void:
	legitimacy_thresholds.clear()
	if raw is not Array or raw.is_empty():
		errors.append("data/ui/narrator.json.legitimacy_thresholds: expected a list of numbers from 0 to 100")
		return
	for value: Variant in raw:
		if value is not float or value < 0 or value > MAX_POINTS or value != floorf(value):
			errors.append("data/ui/narrator.json.legitimacy_thresholds: expected a list of numbers from 0 to 100")
			legitimacy_thresholds.clear()
			return
		legitimacy_thresholds.append(int(value))


func _read_rules(raw: Variant, kinds: Array[StringName]) -> void:
	if raw is not Array:
		errors.append("data/ui/narrator.json.rules: expected a list")
		return
	for index: int in raw.size():
		var path: String = "data/ui/narrator.json.rules[%d]" % index
		var entry: Variant = raw[index]
		if entry is not Dictionary or entry.get("kind") is not String:
			errors.append("%s: expected an object with a kind" % path)
			continue
		var rule: Dictionary = {"kind": StringName(entry["kind"]), "cause": StringName(str(entry.get("cause", ""))),
			"silent": entry.get("silent", false) == true, "priority": &"", "key": &"",
			"pause": entry.get("pause", false) == true, "crisis": entry.get("crisis", false) == true,
			"series": String(entry.get("series", "")), "overlay": String(entry.get("overlay", "")),
			"target_from": StringName(str(entry.get("target_from", TARGET_NONE)))}
		if rule["target_from"] not in TARGETS:
			errors.append("%s.target_from: expected one of %s" % [path, TARGETS])
			continue
		if rule["kind"] not in kinds:
			errors.append("%s.kind: '%s' is not a kind the cause log keeps" % [path, rule["kind"]])
			continue
		if not rule["silent"]:
			rule["priority"] = StringName(str(entry.get("priority", "")))
			if rule["priority"] not in PRIORITIES:
				errors.append("%s.priority: expected one of %s" % [path, PRIORITIES])
				continue
			if entry.get("key") is not String or String(entry["key"]).is_empty():
				errors.append("%s.key: expected a translation key" % path)
				continue
			rule["key"] = StringName(entry["key"])
		rules.append(rule)
