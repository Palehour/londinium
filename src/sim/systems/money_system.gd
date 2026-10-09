class_name MoneySystem
extends RefCounted


func tick(state: EconomyState, params: Params) -> void:
	var employed: int = 0
	var wages: float = 0.0
	var upkeep: float = 0.0
	for building: Dictionary in state.buildings:
		var workers: int = int(building.get("workers", 0))
		var prefix: String = "building.%s" % building["definition_id"]
		employed += workers
		wages += workers * float(params.get_value(StringName(prefix + ".wage_per_worker_per_minute")))
		upkeep += float(params.get_value(StringName(prefix + ".upkeep_per_minute")))
	state.tax_fraction += employed * state.tax_rate \
		* float(params.get_value(&"population.tax.base_per_employed_worker_per_minute")) / 60.0
	state.wage_fraction += wages / 60.0
	state.upkeep_fraction += upkeep / 60.0
	var taxes_paid: int = ProductionSystem.whole_units(state.tax_fraction)
	var wages_paid: int = ProductionSystem.whole_units(state.wage_fraction)
	var upkeep_paid: int = ProductionSystem.whole_units(state.upkeep_fraction)
	state.money += taxes_paid - wages_paid - upkeep_paid
	state.tax_fraction = maxf(0.0, state.tax_fraction - taxes_paid)
	state.wage_fraction = maxf(0.0, state.wage_fraction - wages_paid)
	state.upkeep_fraction = maxf(0.0, state.upkeep_fraction - upkeep_paid)
