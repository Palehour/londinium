class_name DefeatCriticalConfig
extends RefCounted

# What the UI says about the critical notices' own settings (issue #350). The simulation resolves them into
# snapshot["defeat_critical_config"] = {bankruptcy, hunger, depopulation, critical_sound, complete, incomplete,
# errors}. A value of null, "" or "sin dato" is a value nobody has chosen yet: it is named, never read as zero.

const CONDITIONS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]
const NO_DATA_WORDS: Array[String] = ["", "sin dato"]


# {incomplete, pending: conditions without a threshold, sound_pending, error_count}. A snapshot without the key
# (older tests, hand-built snapshots) is complete: nothing to say.
static func summary(snapshot: Dictionary) -> Dictionary:
	var config: Variant = snapshot.get("defeat_critical_config", null)
	var result: Dictionary = {"incomplete": false, "pending": [] as Array[StringName], "sound_pending": false, "error_count": 0}
	if config is not Dictionary:
		return result
	var errors: Variant = config.get("errors", [])
	result["error_count"] = (errors as Array).size() if errors is Array else 0
	result["incomplete"] = bool(config.get("incomplete", false)) or result["error_count"] > 0
	if not result["incomplete"]:
		return result
	for condition: StringName in CONDITIONS:
		if _is_missing(config.get(condition, null)):
			result["pending"].append(condition)
	result["sound_pending"] = _is_missing(config.get("critical_sound", null))
	return result


# The compact line for the panel, or "" when the settings are complete.
static func message(snapshot: Dictionary) -> String:
	var summed: Dictionary = summary(snapshot)
	if not summed["incomplete"]:
		return ""
	var names: Array[String] = []
	for condition: StringName in summed["pending"]:
		names.append(Strings.label(Strings.CONDITION_LABELS, condition))
	if summed["sound_pending"]:
		names.append(Strings.text(Strings.CRITICAL_CONFIG_SOUND))
	if names.is_empty():
		return Strings.text(Strings.CRITICAL_CONFIG_INVALID) % summed["error_count"]
	return Strings.text(Strings.CRITICAL_CONFIG_PENDING) % ", ".join(names)


# The simulation's own wording of each problem, for a tooltip.
static func details(snapshot: Dictionary) -> String:
	var config: Variant = snapshot.get("defeat_critical_config", null)
	if config is not Dictionary or config.get("errors", []) is not Array:
		return ""
	var lines: Array[String] = []
	for line: Variant in config["errors"]:
		lines.append(str(line))
	return "\n".join(lines)


static func _is_missing(value: Variant) -> bool:
	if value == null:
		return true
	return (value is String or value is StringName) and NO_DATA_WORDS.has(String(value).strip_edges().to_lower())
