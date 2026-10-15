class_name VictoryState
extends RefCounted

var elapsed_seconds: int = 0
var won_tick: int = -1
var stages: Dictionary[StringName, Dictionary] = {}


func to_dict() -> Dictionary:
	return {"elapsed_seconds": elapsed_seconds, "won_tick": won_tick, "stages": stages.duplicate(true)}


static func from_dict(values: Dictionary) -> VictoryState:
	var result: VictoryState = VictoryState.new()
	result.elapsed_seconds = int(values.get("elapsed_seconds", 0))
	result.won_tick = int(values.get("won_tick", -1))
	for id: Variant in values.get("stages", {}):
		var entry: Dictionary = values["stages"][id].duplicate(true)
		for field: String in ["completed_tick", "minute_revenue", "streak_minutes", "last_minute_revenue"]:
			entry[field] = int(entry[field])
		for field: String in ["minute", "revenue", "threshold"]:
			if entry["last_break"].has(field):
				entry["last_break"][field] = int(entry["last_break"][field])
		var samples: Array[int] = []
		for sample: Variant in entry["samples"]:
			samples.append(int(sample))
		entry["samples"] = samples
		result.stages[StringName(id)] = entry
	return result
