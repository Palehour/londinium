class_name WorkersSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	var available: int = maxi(0, state.population)
	for building: Dictionary in state.buildings:
		building["workers"] = 0
	for id: StringName in [&"bakery", &"mill", &"wharf"]:
		var jobs: int = job_capacity(params, id)
		for building: Dictionary in state.buildings:
			if building["definition_id"] != id:
				continue
			var assigned: int = mini(available, jobs)
			building["workers"] = assigned
			available -= assigned


static func job_capacity(params: Params, definition_id: StringName) -> int:
	# A fractional modifier cannot create a partial worker slot.
	return maxi(0, int(params.get_value(StringName("building.%s.jobs" % definition_id))))
