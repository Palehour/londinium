class_name WorkersSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	var available: int = maxi(0, state.population)
	for building: Dictionary in state.buildings:
		building["workers"] = 0
	for id: StringName in [&"bakery", &"mill", &"wharf"]:
		var jobs: int = int(params.get_value(StringName("building.%s.jobs" % id)))
		for building: Dictionary in state.buildings:
			if building["definition_id"] != id:
				continue
			var assigned: int = mini(available, maxi(0, jobs))
			building["workers"] = assigned
			available -= assigned
