class_name ChainBottleneck
extends RefCounted

# Read-only diagnostic for #353. Pure inputs contain the summed bread demand, opening stocks,
# staffed capacities for the closed window, recipe amounts, building counts and configured knobs.
# Missing numeric inputs remain NaN. Stocks reduce requirements once, never capacity as well.
const BREAD_CHAIN: Array[StringName] = [&"wharf", &"mill", &"bakery"]
const GOODS: Dictionary[StringName, StringName] = {&"wharf": &"wheat", &"mill": &"flour", &"bakery": &"bread"}
const UPSTREAM: Dictionary[StringName, StringName] = {&"bakery": &"flour", &"mill": &"wheat"}


static func compute_bottleneck(inputs: Dictionary, chain: Array[StringName], _window: StringName) -> Dictionary:
	var result: Dictionary = _result(&"no_data", inputs)
	var margin: float = _number(inputs.get("margin"))
	if chain != BREAD_CHAIN or is_nan(margin) or margin < 0.0 or margin > 1.0 \
			or inputs.get("tie_break") != &"upstream":
		return result
	var required: float = _number(inputs.get("bread_demand"))
	if is_nan(required) or required < 0.0:
		return result
	if required == 0.0:
		result["status"] = &"no_bottleneck"
		return result
	var ratios: Dictionary[StringName, float] = {}
	var missing: bool = false
	var statuses: Dictionary[StringName, StringName] = {}
	for building: StringName in [&"bakery", &"mill", &"wharf"]:
		if required == 0.0:
			statuses[building] = &"excluded"
			continue
		var stock: float = _number(inputs.get("stock_start:%s" % GOODS[building]))
		if building == &"mill":
			var imported: float = 0.0 if inputs.get("no_money_for_imports", false) \
				else _number(inputs.get("imported_flour"))
			stock = stock + imported
		if is_nan(stock) or stock < 0.0:
			missing = true
			statuses[building] = &"no_data"
			break # Unknown remaining requirement also makes all upstream links unknown.
		required = maxf(0.0, required - stock)
		if required == 0.0:
			statuses[building] = &"excluded"
			continue
		var capacity: float = _number(inputs.get("pot:%s" % building))
		var count: float = _number(inputs.get("count:%s" % building))
		if is_nan(capacity) or capacity < 0.0 or is_nan(count) or count <= 0.0:
			missing = true
			statuses[building] = &"no_data"
		else:
			ratios[building] = capacity / required
			statuses[building] = &"available"
		if UPSTREAM.has(building):
			var input: float = _number(inputs.get("recipe:%s:inputs:%s" % [building, UPSTREAM[building]]))
			var output: float = _number(inputs.get("recipe:%s:outputs:%s" % [building, GOODS[building]]))
			if is_nan(input) or input <= 0.0 or is_nan(output) or output <= 0.0:
				missing = true
				break
			required *= input / output
	# Strict comparison preserves the threshold and makes exact ties prefer the upstream link.
	var lowest: float = 1.0 - margin
	for building: StringName in chain:
		if ratios.has(building) and ratios[building] < lowest:
			lowest = ratios[building]
			result["limiting_link"] = building
	if result["limiting_link"] != &"":
		result["status"] = &"bottleneck"
		result["reason"] = &"insufficient_capacity"
		statuses[result["limiting_link"]] = &"bottleneck"
	elif not missing:
		result["status"] = &"no_bottleneck"
	result["links"] = statuses
	return result


static func snapshot(history: StatsHistory, params: Params, context: EconomyContext,
		state: EconomyState, ranges: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for entry: Dictionary in ranges:
		var id: StringName = StringName(entry.get("id", &""))
		result[id] = _result(&"no_data", {})
		if history == null or params == null or context == null or state == null or not _configured(params):
			continue
		var tier: StringName = StringName(entry.get("tier", &""))
		var span: float = _number(entry.get("span_seconds"))
		if tier not in [StatsHistory.TIER_MEDIUM, StatsHistory.TIER_CHAPTER] \
				or is_nan(span) or span < 0.0 or span != floor(span):
			continue
		var demand: Dictionary = history.series(&"bread_demand", tier)
		var start: int = _start(demand, int(span))
		if start < 0:
			continue
		var samples: int = demand["total"].size() - start
		if samples < int(params.get_value(&"ui.chains.min_samples")):
			continue
		var seconds: float = samples * float(demand["bucket_seconds"])
		var inputs: Dictionary = {
			"bread_demand": _sum(demand, start),
			"margin": params.get_value(&"ui.chains.bottleneck_margin"),
			"tie_break": params.get_value(&"ui.chains.tie_break"),
			"barley_percent": MarketSystem.barley_percent(state),
		}
		for building: StringName in BREAD_CHAIN:
			var good: StringName = GOODS[building]
			var column: Dictionary = history.series(StringName("stock:%s" % good), tier)
			inputs["stock_start:%s" % good] = _opening_stock(history, column, good, demand, start)
			var count: int = 0
			var capacity: float = 0.0
			for placed: Dictionary in state.buildings:
				if placed["definition_id"] == building:
					count += 1
					capacity += ProductionSystem.staffed_rate(params, placed, "outputs.%s" % good) * seconds
			inputs["count:%s" % building] = count
			inputs["pot:%s" % building] = capacity
			if UPSTREAM.has(building):
				inputs["recipe:%s:inputs:%s" % [building, UPSTREAM[building]]] = params.get_value(
					StringName("building.%s.recipe.inputs.%s" % [building, UPSTREAM[building]]))
				inputs["recipe:%s:outputs:%s" % [building, good]] = params.get_value(
					StringName("building.%s.recipe.outputs.%s" % [building, good]))
		var imports: Dictionary = history.series(&"bought:flour", tier)
		var imported: float = _sum(imports, start) if _aligned(imports, demand) else NAN
		var no_money: bool = ImportSystem.flour_reason(state, params, context) == &"no_money_for_imports"
		if no_money:
			imported = 0.0
		var border: bool = context.border_supplies(&"flour") and not ImportSystem.has_staffed_wharf(state)
		var uses_capacity: bool = not border and not is_nan(imported) and imported > 0.0
		var wheat_capacity: float = MarketSystem.wheat_unloading_per_minute(state, params) \
			* seconds / MarketSystem.SECONDS_PER_MINUTE
		# Barley is reserved first; imported flour uses the remainder before wheat, once (D-031).
		if not border:
			wheat_capacity = NAN if is_nan(imported) else maxf(0.0, wheat_capacity - imported)
		inputs["pot:wharf"] = wheat_capacity
		inputs["imported_flour"] = imported
		inputs["no_money_for_imports"] = no_money
		inputs["imported_flour_uses_capacity"] = uses_capacity
		result[id] = compute_bottleneck(inputs, BREAD_CHAIN, id)
	return result


static func _configured(params: Params) -> bool:
	for key: StringName in [&"ui.chains.bottleneck_margin", &"ui.chains.min_samples", &"ui.chains.tie_break"]:
		if not params.has_value(key):
			return false
	var margin: float = _number(params.get_value(&"ui.chains.bottleneck_margin"))
	var minimum: float = _number(params.get_value(&"ui.chains.min_samples"))
	return not is_nan(margin) and margin >= 0.0 and margin <= 1.0 and not is_nan(minimum) \
		and minimum >= 1.0 and minimum == floor(minimum) and params.get_value(&"ui.chains.tie_break") == "upstream"


static func _start(column: Dictionary, span: int) -> int:
	if not column.has("total") or not column.has("bucket_seconds") or column["total"].is_empty():
		return -1
	var bucket: int = int(column["bucket_seconds"])
	if bucket <= 0:
		return -1
	var count: int = column["total"].size()
	if span <= 0:
		return 0
	@warning_ignore("integer_division")
	var take: int = maxi(1, span / bucket)
	return maxi(0, count - take)


static func _aligned(column: Dictionary, reference: Dictionary) -> bool:
	return column.has("total") and column.get("bucket_seconds") == reference.get("bucket_seconds") \
		and column.get("first_bucket") == reference.get("first_bucket") \
		and column["total"].size() == reference["total"].size()


static func _sum(column: Dictionary, start: int) -> float:
	if not column.has("total") or start < 0 or start >= column["total"].size():
		return NAN
	var total: float = 0.0
	for index: int in range(start, column["total"].size()):
		var value: float = column["total"][index]
		if is_nan(value):
			return NAN
		total += value
	return total


static func _opening_stock(history: StatsHistory, column: Dictionary, good: StringName,
		reference: Dictionary, start: int) -> float:
	if not _aligned(column, reference):
		return NAN
	if start > 0:
		return column["total"][start - 1]
	return history.opening(good) if column["first_bucket"] == 0 else NAN


static func _number(value: Variant) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) else NAN


static func _result(status: StringName, inputs: Dictionary) -> Dictionary:
	return {"status": status, "limiting_link": &"", "reason": &"", "links": {},
		"barley_percent": inputs.get("barley_percent", 0.0),
		"imported_flour_uses_capacity": inputs.get("imported_flour_uses_capacity", false)}
