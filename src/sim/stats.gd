class_name Stats
extends RefCounted

const KEYS: Array[StringName] = [&"bread_produced", &"bread_consumed", &"bread_demand",
	&"taxes", &"wages", &"upkeep", &"wheat", &"construction"]

var _window_size: int
var _samples: Array[Dictionary] = []


func _init(window_size: int) -> void:
	_window_size = maxi(1, window_size)


# Loading resumes the per-minute rates where the snapshot left them. Only the newest samples
# that fit the current window are kept; a malformed window is dropped rather than half-used.
func restore(window: Array) -> void:
	_samples.clear()
	for entry: Variant in window.slice(maxi(0, window.size() - _window_size)):
		if entry is not Dictionary or not KEYS.all(func(key: StringName) -> bool:
				return entry.has(key) and typeof(entry[key]) in [TYPE_INT, TYPE_FLOAT]):
			push_error("Stats: malformed window sample; starting an empty window")
			_samples.clear()
			return
		var sample: Dictionary = {}
		for key: StringName in KEYS:
			sample[key] = float(entry[key])
		_samples.append(sample)


# Records real per-tick flows; rates never infer production from stock differences.
func record(state: EconomyState) -> void:
	_samples.append({
		&"bread_produced": float(state.bread_produced_tick),
		&"bread_consumed": state.bread_consumed_tick,
		&"bread_demand": state.bread_demand_tick,
		&"taxes": float(state.taxes_tick),
		&"wages": float(state.wages_tick),
		&"upkeep": float(state.upkeep_tick),
		&"wheat": float(state.wheat_spent_tick),
		&"construction": float(state.construction_spent_tick),
	})
	if _samples.size() > _window_size:
		_samples.pop_front()


func snapshot() -> Dictionary:
	# Summing on demand avoids float drift from a running total over long games.
	var sums: Dictionary[StringName, float] = {}
	for key: StringName in KEYS:
		sums[key] = 0.0
	for sample: Dictionary in _samples:
		for key: StringName in KEYS:
			sums[key] += float(sample[key])
	# A tick is one game second; a partial window is scaled by the seconds it covers.
	var per_minute: float = 60.0 / float(maxi(_samples.size(), 1))
	return {
		"window_size": _window_size,
		"window_seconds": _samples.size(),
		"complete": _samples.size() >= _window_size,
		# Per-tick samples, oldest first; a deep copy so readers cannot alter the window.
		"window": _samples.duplicate(true),
		"bread_produced_per_minute": sums[&"bread_produced"] * per_minute,
		"bread_consumed_per_minute": sums[&"bread_consumed"] * per_minute,
		"bread_demand_per_minute": sums[&"bread_demand"] * per_minute,
		"taxes_per_minute": sums[&"taxes"] * per_minute,
		"wages_per_minute": sums[&"wages"] * per_minute,
		"upkeep_per_minute": sums[&"upkeep"] * per_minute,
		"wheat_spent_per_minute": sums[&"wheat"] * per_minute,
		"operating_balance_per_minute": (sums[&"taxes"] - sums[&"wages"] - sums[&"upkeep"] - sums[&"wheat"]) * per_minute,
		"construction_spent_per_minute": sums[&"construction"] * per_minute,
	}
