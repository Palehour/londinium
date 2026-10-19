class_name VictorySystem
extends RefCounted

const SECONDS_PER_MINUTE: int = 60

var _stages: Array[Dictionary] = []


func _init(stages: Array[Dictionary] = []) -> void:
	_stages.assign(stages.duplicate(true))


func tick(state: EconomyState, params: Params) -> void:
	if _stages.is_empty() or state.victory.won_tick >= 0 or not state.defeat_causes.is_empty():
		return
	var victory: VictoryState = state.victory
	victory.elapsed_seconds += 1
	var completed: int = 0
	for def: Dictionary in _stages:
		var entry: Dictionary = victory.stages.get_or_add(def["id"], _empty_stage())
		if int(entry["completed_tick"]) < 0:
			if def["mode"] == &"mean":
				_mean_tick(state, params, def, entry)
			else:
				_revenue_tick(state, params, def, entry)
		if int(entry["completed_tick"]) >= 0:
			completed += 1
	if completed == _stages.size():
		victory.won_tick = victory.elapsed_seconds


func _mean_tick(state: EconomyState, params: Params, def: Dictionary, entry: Dictionary) -> void:
	var value: int = state.population
	if def["metric"] == &"class_population":
		var member: ClassState = state.class_states.get(def["class_id"])
		value = member.population if member != null else 0
		if def.get("class_base", false):
			value = state.population - ClassStates.others_total(state)
	var samples: Array[int] = entry["samples"]
	samples.append(value)
	var duration: int = int(params.get_value(StringName(def["prefix"] + ".duration_seconds")))
	if samples.size() > duration:
		samples.pop_front()
	var total: int = 0
	for sample: int in samples:
		total += sample
	entry["mean"] = float(total) / float(samples.size())
	if samples.size() == duration and float(entry["mean"]) >= float(params.get_value(StringName(def["prefix"] + ".threshold"))):
		entry["completed_tick"] = state.victory.elapsed_seconds


func _revenue_tick(state: EconomyState, params: Params, def: Dictionary, entry: Dictionary) -> void:
	entry["minute_revenue"] += state.taxes_tick
	if state.victory.elapsed_seconds % SECONDS_PER_MINUTE != 0:
		return
	var threshold: int = int(params.get_value(StringName(def["prefix"] + ".threshold")))
	var revenue: int = int(entry["minute_revenue"])
	entry["minute_revenue"] = 0
	entry["last_minute_revenue"] = revenue
	if revenue >= threshold:
		entry["streak_minutes"] += 1
	else:
		# Keep the measured shortfall, not a guessed explanation such as hunger or taxes being too low.
		entry["last_break"] = {"minute": int(state.victory.elapsed_seconds / float(SECONDS_PER_MINUTE)),
			"revenue": revenue, "threshold": threshold, "reason": &"revenue_below_threshold"}
		entry["streak_minutes"] = 0
	if int(entry["streak_minutes"]) >= int(params.get_value(StringName(def["prefix"] + ".required_minutes"))):
		entry["completed_tick"] = state.victory.elapsed_seconds


func snapshot(state: EconomyState, params: Params) -> Dictionary:
	var stages: Dictionary = {}
	for def: Dictionary in _stages:
		var entry: Dictionary = state.victory.stages.get(def["id"], _empty_stage())
		var result: Dictionary = {"completed": int(entry["completed_tick"]) >= 0,
			"completed_tick": entry["completed_tick"], "metric": def["metric"], "mode": def["mode"],
			"threshold": params.get_value(StringName(def["prefix"] + ".threshold"))}
		if def["mode"] == &"mean":
			result.merge({"mean": entry["mean"], "window_seconds": entry["samples"].size(),
				"duration_seconds": params.get_value(StringName(def["prefix"] + ".duration_seconds")),
				"class_id": def.get("class_id", &"")})
		else:
			result.merge({"streak_minutes": entry["streak_minutes"],
				"required_minutes": params.get_value(StringName(def["prefix"] + ".required_minutes")),
				"last_minute_revenue": entry["last_minute_revenue"], "last_break": entry["last_break"].duplicate()})
		stages[def["id"]] = result
	return {"enabled": not _stages.is_empty(), "won": state.victory.won_tick >= 0,
		"won_tick": state.victory.won_tick, "stages": stages}


func _empty_stage() -> Dictionary:
	return {"completed_tick": -1, "samples": [] as Array[int], "mean": 0.0, "minute_revenue": 0,
		"streak_minutes": 0, "last_minute_revenue": 0, "last_break": {}}
