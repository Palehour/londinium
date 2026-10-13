class_name WorkersSystem
extends RefCounted

# D-021. The first round gives one worker per building in chain order; the second fills the rest, bakery
# first, and the beer chain (issue #51) comes last, so it is the first to stop when hands run short.
# Emigration frees the same slots in the opposite order.
const FIRST_ROUND: Array[StringName] = [&"wharf", &"mill", &"bakery", &"malthouse", &"brewery"]
const EXTRA_ROUND: Array[StringName] = [&"bakery", &"mill", &"wharf", &"malthouse", &"brewery"]


func tick(state: EconomyState, params: Params) -> void:
	# Only the classes that take jobs look for one (D-021): artisans never fill a post.
	var available: int = maxi(0, ClassStates.job_seekers(state))
	for building: Dictionary in state.buildings:
		building["workers"] = 0
	# Staff the complete chain before expanding any one stage.
	for id: StringName in FIRST_ROUND:
		if job_capacity(params, id) <= 0:
			continue
		for building: Dictionary in state.buildings:
			if building["definition_id"] == id and available > 0:
				building["workers"] = 1
				available -= 1
	for id: StringName in EXTRA_ROUND:
		var jobs: int = job_capacity(params, id)
		for building: Dictionary in state.buildings:
			if building["definition_id"] != id:
				continue
			var assigned: int = mini(available, jobs - int(building["workers"]))
			building["workers"] += assigned
			available -= assigned
	refresh_counts(state)


static func refresh_counts(state: EconomyState) -> void:
	state.employed = 0
	for building: Dictionary in state.buildings:
		state.employed += int(building.get("workers", 0))
	state.unemployed = maxi(0, ClassStates.job_seekers(state) - state.employed)


static func trim_to_population(state: EconomyState) -> void:
	refresh_counts(state)
	var excess: int = maxi(0, state.employed - ClassStates.job_seekers(state))
	# Reverse extras first, then the first-worker pass; no assignment log is needed.
	excess = _release_workers(state, excess, _reversed(EXTRA_ROUND), 1)
	_release_workers(state, excess, _reversed(FIRST_ROUND), 0)
	refresh_counts(state)


static func _reversed(order: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = order.duplicate()
	result.reverse()
	return result


static func _release_workers(state: EconomyState, excess: int,
		order: Array[StringName], retained: int) -> int:
	for id: StringName in order:
		for index: int in range(state.buildings.size() - 1, -1, -1):
			var building: Dictionary = state.buildings[index]
			if building["definition_id"] != id:
				continue
			var workers: int = int(building.get("workers", 0))
			var released: int = mini(excess, maxi(0, workers - retained))
			building["workers"] = workers - released
			excess -= released
	return excess


static func job_capacity(params: Params, definition_id: StringName) -> int:
	# A fractional modifier cannot create a partial worker slot.
	return maxi(0, int(params.get_value(StringName("building.%s.jobs" % definition_id))))
