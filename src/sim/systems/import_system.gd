class_name ImportSystem
extends RefCounted

# Imports bought at the wharf at a fixed price (D-025 tea, D-026 flour). They need a staffed wharf and
# each one is a switch the player turns on: they start off. The tea is a small volume and is exempt from
# the wharf's unloading capacity; the flour shares it with wheat and barley (issue #50): a lot is paid for
# at once and leaves a debt of units that the capacity of the next ticks unloads (MarketSystem), so a new
# lot waits while the debt is a lot or more.

const SECONDS_PER_MINUTE: float = 60.0
# A flour deficit below this is rounding noise, not a reason to buy a lot.
const DEFICIT_EPSILON: float = 1e-9


func tick(state: EconomyState, params: Params) -> void:
	if not has_staffed_wharf(state):
		return
	if state.flour_imports_enabled:
		_import_flour(state, params)
	if state.tea_imports_enabled:
		_import_tea(state, params)


static func has_staffed_wharf(state: EconomyState) -> bool:
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"wharf" and int(building.get("workers", 0)) > 0:
			return true
	return false


# Flour per second the staffed bakeries want to take in.
static func bakery_flour_rate(state: EconomyState, params: Params) -> float:
	var rate: float = 0.0
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"bakery":
			rate += ProductionSystem.staffed_rate(params, building, "inputs.flour")
	return rate


# Whole units of flour the bakeries will take from the store this tick: each reserves one at a time
# until its modified rate for the tick is covered, counting what it already holds.
static func bakery_units_needed(state: EconomyState, params: Params) -> int:
	var units: int = 0
	for building: Dictionary in state.buildings:
		if building["definition_id"] != &"bakery":
			continue
		var budget: float = ProductionSystem.staffed_rate(params, building, "inputs.flour")
		var missing: float = budget - float(building.get("reserved_input", 0.0))
		units += ceili(maxf(0.0, missing) - ProductionSystem.ROUNDING_EPSILON)
	return units


# What the staffed mills can still make this tick: flour per second, and the whole units that will land
# in the store before the bakeries run (the mills convert first). A mill works through the wheat it
# already holds plus whole units of the stock, up to what its modified rate takes in a tick; each unit
# goes to one mill (as in ProductionSystem), so scarce wheat limits the flour credited.
static func mill_flour_credit(state: EconomyState, params: Params) -> Dictionary:
	var rate: float = 0.0
	var units: int = 0
	var spare_wheat: int = int(state.stocks.get(&"wheat", 0))
	for building: Dictionary in state.buildings:
		if building["definition_id"] != &"mill":
			continue
		var input_budget: float = ProductionSystem.staffed_rate(params, building, "inputs.wheat")
		if input_budget <= 0.0:
			continue
		var held: float = maxf(0.0, float(building.get("reserved_input", 0.0)))
		var taken: int = mini(spare_wheat, ceili(maxf(0.0, input_budget - held) - ProductionSystem.ROUNDING_EPSILON))
		spare_wheat -= taken
		var processed: float = minf(input_budget, held + float(taken))
		var flour: float = processed * ProductionSystem.staffed_rate(params, building, "outputs.flour") / input_budget
		rate += flour
		units += ProductionSystem.whole_units(float(building.get("output_fraction", 0.0)) + flour)
	return {"rate": rate, "units": units}


static func mill_flour_rate(state: EconomyState, params: Params) -> float:
	return float(mill_flour_credit(state, params)["rate"])


# What the bakeries want beyond what the mills can supply; imports only cover this, so a working mill
# is never undercut and a missing one is replaced (D-026).
static func flour_deficit(state: EconomyState, params: Params) -> float:
	return maxf(0.0, bakery_flour_rate(state, params) - mill_flour_rate(state, params))


# The flour comes through the wharf: the stages before the bakery are bypassed (D-026).
static func flour_import_active(state: EconomyState) -> bool:
	return state.flour_imports_enabled and has_staffed_wharf(state)


static func tea_demand_per_second(state: EconomyState, params: Params) -> float:
	return float(state.population) * float(params.get_value(&"population.tea.per_person_per_minute")) \
		/ SECONDS_PER_MINUTE


# Money pays whole units at an integer price; a free price buys everything wanted.
static func affordable(state: EconomyState, wanted: int, price: int) -> int:
	if price <= 0:
		return wanted
	@warning_ignore("integer_division")
	return mini(wanted, maxi(0, state.money) / price)


# Whole lots until the flour in store covers the units the bakeries will reserve this tick, when the
# mills would still leave the bakeries short.
func _import_flour(state: EconomyState, params: Params) -> void:
	var stock: int = int(state.stocks.get(&"flour", 0))
	# What the mills hand over this tick comes off the bakeries' request.
	var needed: int = bakery_units_needed(state, params) - int(mill_flour_credit(state, params)["units"])
	if flour_deficit(state, params) <= DEFICIT_EPSILON or stock >= needed:
		return
	var lot: int = int(params.get_value(&"market.imported_flour.lot_size"))
	if unloading_is_busy(state, lot):
		return
	var price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	@warning_ignore("integer_division")
	var wanted: int = (needed - stock + lot - 1) / lot
	# Only as many lots as keep the debt inside its bound, so the flour cannot skip the wharf's limit.
	var max_debt: float = float(int(params.get_value(&"market.imported_flour.max_debt_lots")) * lot)
	var allowed: int = floori((max_debt - state.flour_unloading_debt) / float(lot))
	var lots: int = affordable(state, mini(wanted, allowed), price)
	if lots <= 0:
		return
	state.money -= lots * price
	state.imports_spent_tick += lots * price
	state.stocks[&"flour"] = stock + lots * lot
	state.flour_unloading_debt += float(lots * lot)


# Keeps a small buffer of tea in store, so one empty tick does not drop the coverage. With no buffer it
# still buys the tea this tick will eat. The part of a unit already in tea_fraction counts as stock.
func _import_tea(state: EconomyState, params: Params) -> void:
	var demand: float = tea_demand_per_second(state, params)
	var buffer: float = demand * float(params.get_value(&"market.tea.buffer_seconds"))
	var stock: int = int(state.stocks.get(&"tea", 0))
	var shortage: float = maxf(buffer, demand) - (float(stock) + state.tea_fraction)
	var price: int = int(params.get_value(&"market.tea.price"))
	var units: int = affordable(state, ceili(maxf(0.0, shortage) - ProductionSystem.ROUNDING_EPSILON), price)
	if units <= 0:
		return
	state.money -= units * price
	state.imports_spent_tick += units * price
	state.tea_spent_tick += units * price
	state.stocks[&"tea"] = stock + units


# The wharf still has a lot or more to unload, so it takes no new flour until the capacity catches up.
static func unloading_is_busy(state: EconomyState, lot: int) -> bool:
	return state.flour_unloading_debt >= float(lot)


# Why the tea import is not (fully) working, as a panel reason; &"ok" when it is.
static func tea_reason(state: EconomyState, params: Params) -> StringName:
	if not state.tea_imports_enabled:
		return &"tea_imports_disabled"
	if not has_staffed_wharf(state):
		return &"no_wharf_for_imports"
	if state.tea_coverage < 1.0 and affordable(state, 1, int(params.get_value(&"market.tea.price"))) <= 0:
		return &"no_money_for_imports"
	return &"ok"


static func flour_reason(state: EconomyState, params: Params) -> StringName:
	if not state.flour_imports_enabled:
		return &"flour_imports_disabled"
	if not has_staffed_wharf(state):
		return &"no_wharf_for_imports"
	if flour_deficit(state, params) <= DEFICIT_EPSILON:
		return &"mill_covers_flour"
	if int(state.stocks.get(&"flour", 0)) <= 0 \
			and unloading_is_busy(state, int(params.get_value(&"market.imported_flour.lot_size"))):
		return &"wharf_unloading_busy"
	if int(state.stocks.get(&"flour", 0)) <= 0 \
			and affordable(state, 1, int(params.get_value(&"market.imported_flour.price_per_lot"))) <= 0:
		return &"no_money_for_imports"
	return &"ok"


# Everything the panel shows about imports, so the UI holds no rules.
static func snapshot(state: EconomyState, params: Params) -> Dictionary:
	var demand: float = tea_demand_per_second(state, params) * SECONDS_PER_MINUTE
	var stock: int = int(state.stocks.get(&"tea", 0))
	var lot: int = int(params.get_value(&"market.imported_flour.lot_size"))
	var lot_price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	return {
		"tea": {
			"enabled": state.tea_imports_enabled, "stock": stock,
			"price": int(params.get_value(&"market.tea.price")), "coverage": state.tea_coverage,
			"consumption_per_minute": demand,
			"minutes_covered": float(stock) / demand if demand > 0.0 else -1.0,
			"satisfaction_bonus": state.tea_coverage * float(params.get_value(&"population.tea.satisfaction_bonus")),
			"reason": tea_reason(state, params),
		},
		"flour": {
			"enabled": state.flour_imports_enabled, "stock": int(state.stocks.get(&"flour", 0)),
			"lot_size": lot, "lot_price": lot_price,
			"unit_price": float(lot_price) / float(lot),
			"unloading_debt": state.flour_unloading_debt,
			"reason": flour_reason(state, params),
		},
	}
