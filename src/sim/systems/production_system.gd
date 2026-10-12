class_name ProductionSystem
extends RefCounted

# Absolute arithmetic tolerance, not an economic threshold.
const ROUNDING_EPSILON: float = 1e-12
# Converters in chain order, so a stage never uses what the stage before it makes in the same tick.
const CONVERTERS: Array[StringName] = [&"mill", &"bakery", &"malthouse", &"brewery"]
# Goods with a warehouse cap (market.<good>.storage_capacity): their producer stops when it is full instead
# of throwing the output away, because nothing consumes them yet (issue #51).
const CAPPED_OUTPUTS: Array[StringName] = [&"malt", &"beer"]


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	for id: StringName in CONVERTERS:
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


# True when the warehouse of a capped good has no room left; false for goods without a cap.
static func storage_full(state: EconomyState, params: Params, good: StringName) -> bool:
	if good not in CAPPED_OUTPUTS:
		return false
	return int(state.stocks.get(good, 0)) >= int(params.get_value(StringName("market.%s.storage_capacity" % good)))


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
	var fraction: float = float(building.get("output_fraction", 0.0))
	if output in CAPPED_OUTPUTS:
		# Output already owed (the fraction) counts against the room, so a full warehouse never overshoots.
		var capacity: int = int(params.get_value(StringName("market.%s.storage_capacity" % output)))
		var room: float = float(capacity - int(state.stocks.get(output, 0))) - fraction
		budget = minf(budget, maxf(0.0, room) * input_amount / output_amount)
		if budget <= ROUNDING_EPSILON:
			budget = 0.0
	var reserved: float = float(building.get("reserved_input", 0.0))
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
