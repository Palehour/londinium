class_name ProductionSystem
extends RefCounted

# Absolute arithmetic tolerance, not an economic threshold.
const ROUNDING_EPSILON: float = 1e-12


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	for id: StringName in [&"mill", &"bakery"]:
		var recipe: RecipeDef = context.buildings[id].recipe
		for building: Dictionary in state.buildings:
			if building["definition_id"] == id:
				_convert(state, params, building, recipe)


static func staffed_rate(params: Params, building: Dictionary, quantity_key: String) -> float:
	var prefix: String = "building.%s" % building["definition_id"]
	var jobs: int = WorkersSystem.job_capacity(params, building["definition_id"])
	var seconds: float = float(params.get_value(StringName(prefix + ".recipe.seconds")))
	if jobs <= 0 or seconds <= 0.0:
		return 0.0
	return float(params.get_value(StringName(prefix + ".recipe." + quantity_key))) \
		/ seconds * float(building.get("workers", 0)) / jobs


static func whole_units(value: float) -> int:
	# Repeated sixths must not delay an exact unit because of floating point noise.
	var nearest: int = roundi(value)
	return nearest if absf(value - float(nearest)) <= ROUNDING_EPSILON else floori(value)


func _convert(state: EconomyState, params: Params, building: Dictionary, recipe: RecipeDef) -> void:
	var input: StringName = recipe.inputs[0]
	var output: StringName = recipe.outputs[0]
	var prefix: String = "building.%s.recipe" % building["definition_id"]
	var input_amount: float = float(params.get_value(StringName("%s.inputs.%s" % [prefix, input])))
	var output_amount: float = float(params.get_value(StringName("%s.outputs.%s" % [prefix, output])))
	var budget: float = staffed_rate(params, building, "inputs.%s" % input)
	var reserved: float = float(building.get("reserved_input", 0.0))
	var fraction: float = float(building.get("output_fraction", 0.0))
	while budget > 0.0:
		if reserved <= 0.0:
			if state.stocks.get(input, 0) <= 0:
				break
			state.stocks[input] -= 1
			reserved = 1.0
		var processed: float = minf(budget, reserved)
		reserved -= processed
		budget -= processed
		fraction += processed * output_amount / input_amount
		if absf(reserved) <= ROUNDING_EPSILON:
			reserved = 0.0
		if absf(budget) <= ROUNDING_EPSILON:
			budget = 0.0
	var produced: int = whole_units(fraction)
	state.stocks[output] = state.stocks.get(output, 0) + produced
	if output == &"bread":
		state.bread_produced_tick += produced
	building["reserved_input"] = reserved
	building["output_fraction"] = maxf(0.0, fraction - produced)
