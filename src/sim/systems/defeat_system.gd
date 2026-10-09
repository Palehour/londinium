class_name DefeatSystem
extends RefCounted


func initialize(state: EconomyState, params: Params) -> void:
	if state.defeat_initialized:
		return
	state.defeat_initialized = true
	state.hunger_smoothed_coverage = state.bread_coverage
	_update_population_history(state, params)
	# Empty cities expose diagnostics immediately only when grace has already ended.
	if state.population == 0 and (float(params.get_value(&"defeat.grace_seconds")) == 0.0 \
			or state.defeat_elapsed_seconds > float(params.get_value(&"defeat.grace_seconds"))):
		_update(state.depopulation, &"depopulation", true, true, false,
			float(params.get_value(&"defeat.depopulation.duration_seconds")))


func update_hunger_coverage(state: EconomyState, params: Params) -> void:
	initialize(state, params)
	state.hunger_smoothed_coverage += (state.bread_coverage - state.hunger_smoothed_coverage) \
		* float(params.get_value(&"defeat.hunger.smoothing"))


func tick(state: EconomyState, params: Params, update_coverage: bool = true) -> void:
	if not state.defeat_causes.is_empty():
		return
	initialize(state, params)
	state.defeat_elapsed_seconds += 1
	if update_coverage:
		update_hunger_coverage(state, params)
	_update_population_history(state, params)
	_decay_population_peak(state, params)
	var counting: bool = state.defeat_elapsed_seconds > float(params.get_value(&"defeat.grace_seconds"))
	var bankrupt: bool = state.money < int(params.get_value(&"defeat.bankruptcy.threshold"))
	_update(state.bankruptcy, &"bankruptcy", bankrupt, bankrupt, counting,
		float(params.get_value(&"defeat.bankruptcy.duration_seconds")))
	var hungry: bool = state.population > 0 and state.hunger_smoothed_coverage \
		< float(params.get_value(&"defeat.hunger.threshold"))
	_update(state.hunger, &"hunger", hungry, hungry, counting,
		float(params.get_value(&"defeat.hunger.duration_seconds")))
	var below_minimum: bool = state.population < int(params.get_value(&"defeat.depopulation.minimum_population"))
	var empty: bool = state.population == 0
	var warning: bool = empty or (state.depopulation_active and (below_minimum or state.population \
		< state.population_peak * float(params.get_value(&"defeat.depopulation.warning_fraction"))))
	var critical: bool = empty or (state.depopulation_active and (below_minimum or state.population \
		< state.population_peak * float(params.get_value(&"defeat.depopulation.defeat_fraction"))))
	if not counting:
		warning = false
	_update(state.depopulation, &"depopulation", warning, critical, counting,
		float(params.get_value(&"defeat.depopulation.duration_seconds")))
	for condition: DefeatState in [state.bankruptcy, state.hunger, state.depopulation]:
		if condition.status == &"defeat":
			state.defeat_causes.append(condition.cause)


func _update_population_history(state: EconomyState, params: Params) -> void:
	state.population_peak = maxf(state.population_peak, float(state.population))
	if state.population_peak >= int(params.get_value(&"defeat.depopulation.minimum_population")):
		state.depopulation_active = true


func _decay_population_peak(state: EconomyState, params: Params) -> void:
	if state.hunger_smoothed_coverage < float(params.get_value(&"population.growth.hunger_emigration_recovery")):
		return
	var rate: float = float(params.get_value(&"defeat.depopulation.peak_decay_per_minute"))
	# A tick is one game second; compounding preserves the configured reduction over 60 ticks.
	state.population_peak = maxf(float(state.population), state.population_peak * pow(1.0 - rate, 1.0 / 60.0))


func _update(condition: DefeatState, cause: StringName, warning: bool,
		critical: bool, counting: bool, duration: float) -> void:
	condition.elapsed_seconds = condition.elapsed_seconds + 1 if counting and critical else 0
	condition.status = &"warning" if warning else &"ok"
	condition.cause = cause if warning else &""
	if counting and critical and condition.elapsed_seconds >= duration:
		condition.status = &"defeat"
		condition.cause = cause
