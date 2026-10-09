class_name GrowthSystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	var free_housing: int = maxi(0, state.housing_capacity - state.population)
	var hungry: bool = state.hunger_smoothed_coverage \
		< float(params.get_value(&"population.growth.hunger_emigration_threshold"))
	if not hungry and state.satisfaction >= float(params.get_value(&"population.growth.immigration_threshold")) \
			and free_housing > 0 and (state.population > 0 or state.bread_coverage > 0.0):
		state.emigration_fraction = 0.0
		state.immigration_fraction += float(params.get_value(&"population.growth.immigration_per_minute")) / 60.0
		var arrivals: int = mini(free_housing, ProductionSystem.whole_units(state.immigration_fraction))
		state.population += arrivals
		state.immigration_fraction = maxf(0.0, state.immigration_fraction - arrivals) \
			if arrivals < free_housing else 0.0
	elif (hungry or state.satisfaction < float(params.get_value(&"population.growth.emigration_threshold"))) \
			and state.population > 0:
		state.immigration_fraction = 0.0
		var multiplier: float = float(params.get_value(&"population.growth.hunger_emigration_multiplier"))
		var rate: float = float(params.get_value(&"population.growth.emigration_per_minute")) \
			* (1.0 + (multiplier - 1.0) * (1.0 - state.bread_coverage))
		state.emigration_fraction += rate / 60.0
		var departures: int = mini(state.population, ProductionSystem.whole_units(state.emigration_fraction))
		state.population -= departures
		state.emigration_fraction = maxf(0.0, state.emigration_fraction - departures) \
			if state.population > 0 else 0.0
	else:
		# Blocked growth never becomes a backlog when housing or happiness recovers.
		state.immigration_fraction = 0.0
		state.emigration_fraction = 0.0
	# Keep existing jobs; arrivals wait for step 2 of the following tick.
	WorkersSystem.trim_to_population(state)
