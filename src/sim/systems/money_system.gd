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
		var heads: int = employed if def.tax_basis == ClassDef.TAX_EMPLOYED else ClassStates.population_of(state, def)
		var collected: float = heads * state.tax_rate * float(params.get_value(def.tax_base_key)) / 60.0
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
