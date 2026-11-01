class_name MoneySystem
extends RefCounted


func tick(state: EconomyState, params: Params, context: EconomyContext = null) -> void:
	var employed: int = 0
	var wages: float = 0.0
	var upkeep: float = 0.0
	for building: Dictionary in state.buildings:
		var workers: int = int(building.get("workers", 0))
		var prefix: String = "building.%s" % building["definition_id"]
		employed += workers
		wages += workers * float(params.get_value(StringName(prefix + ".wage_per_worker_per_minute")))
		upkeep += float(params.get_value(StringName(prefix + ".upkeep_per_minute")))
	# Head tax per class: on the jobs its members hold or on all of its residents (the data says which).
	for def: ClassDef in ClassStates.defs(context):
		var collected: float = _class_tax_per_minute(state, params, def, employed) / 60.0
		state.tax_fraction += collected
		state.class_tax_tick[def.id] = collected
	state.wage_fraction += wages / 60.0
	# Administration (issue #118): a bigger city pays more upkeep for every building; wages do not grow.
	var multiplier: float = BuildingCosts.administration_multiplier(params, state.buildings.size())
	upkeep *= multiplier
	state.upkeep_fraction += upkeep / 60.0
	var taxes_paid: int = ProductionSystem.whole_units(state.tax_fraction)
	var wages_paid: int = ProductionSystem.whole_units(state.wage_fraction)
	var upkeep_paid: int = ProductionSystem.whole_units(state.upkeep_fraction)
	state.money += taxes_paid - wages_paid - upkeep_paid
	state.taxes_tick = taxes_paid
	state.wages_tick = wages_paid
	state.upkeep_tick = upkeep_paid
	# The statistics split what was paid, so base upkeep and administration always add up to it.
	state.administration_tick = upkeep_paid * maxf(0.0, 1.0 - 1.0 / multiplier) if multiplier > 0.0 else 0.0
	state.tax_fraction = maxf(0.0, state.tax_fraction - taxes_paid)
	state.wage_fraction = maxf(0.0, state.wage_fraction - wages_paid)
	state.upkeep_fraction = maxf(0.0, state.upkeep_fraction - upkeep_paid)
	_pay_streets(state, params, context)


# The R of the loans (issue #72, D-127): the head tax the city pays per minute at its current rate.
static func tax_per_minute(state: EconomyState, params: Params, context: EconomyContext) -> float:
	return _tax_with_employed(state, params, context, _employed(state))


static func _employed(state: EconomyState) -> int:
	var employed: int = 0
	for building: Dictionary in state.buildings:
		employed += int(building.get("workers", 0))
	return employed


static func _tax_with_employed(state: EconomyState, params: Params, context: EconomyContext, employed: int) -> float:
	var total: float = 0.0
	for def: ClassDef in ClassStates.defs(context):
		total += _class_tax_per_minute(state, params, def, employed)
	return total


# The delta per minute (D-134) if this building were built now: the head tax, including that of the jobs it would
# open, less the upkeep of every building (the new one included) times the administration of one more building.
# The new jobs are taken by people who look for work and have none (as WorkersSystem assigns them), so they never
# exceed the unemployed; classes taxed on residents gain nothing from them. Wages, streets and transport are left out.
static func projected_delta_per_minute(state: EconomyState, params: Params, context: EconomyContext,
		definition_id: StringName) -> float:
	var upkeep: float = float(params.get_value(StringName("building.%s.upkeep_per_minute" % definition_id)))
	for building: Dictionary in state.buildings:
		upkeep += float(params.get_value(StringName("building.%s.upkeep_per_minute" % building["definition_id"])))
	var employed: int = _employed(state)
	var unemployed: int = maxi(0, ClassStates.job_seekers(state) - employed)
	var added_jobs: int = mini(WorkersSystem.job_capacity(params, definition_id), unemployed)
	return _tax_with_employed(state, params, context, employed + added_jobs) \
		- upkeep * BuildingCosts.administration_multiplier(params, state.buildings.size() + 1)


# D-134: a building with upkeep is refused when it would leave the delta below 0; one without upkeep never is.
static func blocks_negative_balance(state: EconomyState, params: Params, context: EconomyContext,
		definition_id: StringName) -> bool:
	if float(params.get_value(StringName("building.%s.upkeep_per_minute" % definition_id))) <= 0.0:
		return false
	return projected_delta_per_minute(state, params, context, definition_id) < 0.0


static func _class_tax_per_minute(state: EconomyState, params: Params, def: ClassDef, employed: int) -> float:
	var heads: int = employed if def.tax_basis == ClassDef.TAX_EMPLOYED else ClassStates.population_of(state, def)
	return heads * state.tax_rate * float(params.get_value(def.tax_base_key))


# Streets and transport (issue #67, D-070) are upkeep too, but outside administration (D-063): the player's streets
# pay roads.upkeep_per_minute each and every leg its units x metres x k, in whole pence with the fraction carried.
func _pay_streets(state: EconomyState, params: Params, context: EconomyContext) -> void:
	if state.player_roads.is_empty() and state.transport_legs.is_empty():
		return
	state.transport_fraction += RoadSystem.transport_cost(state, params, context) \
		+ state.player_roads.size() * float(params.get_value(&"roads.upkeep_per_minute")) / 60.0
	var paid: int = ProductionSystem.whole_units(state.transport_fraction)
	state.money -= paid
	state.upkeep_tick += paid
	state.transport_fraction = maxf(0.0, state.transport_fraction - paid)
