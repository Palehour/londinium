class_name ProductionSystem
extends RefCounted

# Absolute arithmetic tolerance, not an economic threshold.
const ROUNDING_EPSILON: float = 1e-12
# Converters in chain order, so a stage never uses what the stage before it makes in the same tick.
const CONVERTERS: Array[StringName] = [&"mill", &"bakery", &"malthouse", &"brewery"]
# Pending output passed to _convert for a good without a warehouse cap.
const NOT_CAPPED: float = -1.0


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	var capped: Array[StringName] = capped_outputs(params, context)
	for id: StringName in CONVERTERS:
		var recipe: RecipeDef = context.buildings[id].recipe
		for building: Dictionary in state.buildings:
			if building["definition_id"] == id:
				var output: StringName = recipe.outputs[0]
				_convert(state, params, building, recipe,
					_pending_output(state, context, output) if output in capped else NOT_CAPPED)
		if recipe.outputs[0] in capped:
			_settle_shared_output(state, context, recipe.outputs[0])


# Outputs of the converters whose good has a warehouse cap (market.<good>.storage_capacity in the data):
# their producer stops when it is full instead of throwing the output away, because they are consumed only
# when someone lives who needs them (issue #51, #52). Derived from the data, so a good gets a cap by defining one.
static func capped_outputs(params: Params, context: EconomyContext) -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in CONVERTERS:
		for good: StringName in context.buildings[id].recipe.outputs:
			if has_storage_cap(params, good) and good not in found:
				found.append(good)
	return found


# Every building whose recipe makes the good.
static func _producers(state: EconomyState, context: EconomyContext, good: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		var definition: BuildingDef = context.buildings.get(building["definition_id"])
		if definition != null and definition.recipe != null and definition.recipe.outputs[0] == good:
			found.append(building)
	return found


# Output every producer of the good holds as a fraction of a unit that is not in the warehouse yet. A cap
# has to leave room for all of it, or two producers would each use the same free space.
static func _pending_output(state: EconomyState, context: EconomyContext, good: StringName) -> float:
	var pending: float = 0.0
	for building: Dictionary in _producers(state, context, good):
		pending += float(building.get("output_fraction", 0.0))
	return pending


# The room of a capped good is shared, so its fractions are one pool: two producers holding half a unit
# each have made a whole one, and without this neither could ever deliver it.
static func _settle_shared_output(state: EconomyState, context: EconomyContext, good: StringName) -> void:
	var producers: Array[Dictionary] = _producers(state, context, good)
	var units: int = whole_units(_pending_output(state, context, good))
	if units <= 0:
		return
	state.stocks[good] = int(state.stocks.get(good, 0)) + units
	var owed: float = float(units)
	for building: Dictionary in producers:
		var taken: float = minf(owed, float(building.get("output_fraction", 0.0)))
		building["output_fraction"] = maxf(0.0, float(building.get("output_fraction", 0.0)) - taken)
		owed -= taken


static func has_storage_cap(params: Params, good: StringName) -> bool:
	return params.has_value(_capacity_key(good))


static func _capacity_key(good: StringName) -> StringName:
	return StringName("market.%s.storage_capacity" % good)


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
	if not has_storage_cap(params, good):
		return false
	return int(state.stocks.get(good, 0)) >= int(params.get_value(_capacity_key(good)))


static func whole_units(value: float) -> int:
	# Repeated sixths must not delay an exact unit because of floating point noise.
	var nearest: int = roundi(value)
	return nearest if absf(value - float(nearest)) <= ROUNDING_EPSILON else floori(value)


func _convert(state: EconomyState, params: Params, building: Dictionary, recipe: RecipeDef, pending: float) -> void:
	var input: StringName = recipe.inputs[0]
	var output: StringName = recipe.outputs[0]
	var prefix: String = "building.%s.recipe" % building["definition_id"]
	var input_amount: float = float(params.get_value(StringName("%s.inputs.%s" % [prefix, input])))
	var output_amount: float = float(params.get_value(StringName("%s.outputs.%s" % [prefix, output])))
	var budget: float = staffed_rate(params, building, "inputs.%s" % input)
	var fraction: float = float(building.get("output_fraction", 0.0))
	if pending != NOT_CAPPED:
		# Output already owed by every producer of this good counts against the room, so a full warehouse never
		# overshoots; so does the part of a unit people left after drinking from it.
		var capacity: int = int(params.get_value(_capacity_key(output)))
		var room: float = float(capacity - int(state.stocks.get(output, 0))) - pending 			- ConsumptionSystem.stored_fraction(state, output)
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
	if budget > ROUNDING_EPSILON:
		var id: StringName = building["definition_id"]
		state.input_starved_tick[id] = int(state.input_starved_tick.get(id, 0)) + 1
	var produced: int = whole_units(fraction)
	state.stocks[output] = state.stocks.get(output, 0) + produced
	if output == &"bread":
		state.bread_produced_tick += produced
	building["reserved_input"] = reserved
	building["output_fraction"] = maxf(0.0, fraction - produced)
