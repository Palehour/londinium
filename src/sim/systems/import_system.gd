class_name ImportSystem
extends RefCounted

# Imports bought at the wharf at a fixed price (D-025 tea, D-026 flour). They need a staffed wharf but
# take none of its wheat capacity, and each one is a switch the player turns on: they start off.

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


# Flour per second the staffed mills can still make: none once they have no wheat to grind.
static func mill_flour_rate(state: EconomyState, params: Params) -> float:
	var rate: float = 0.0
	var has_wheat: bool = int(state.stocks.get(&"wheat", 0)) > 0
	for building: Dictionary in state.buildings:
		if building["definition_id"] != &"mill":
			continue
		if has_wheat or float(building.get("reserved_input", 0.0)) > 0.0:
			rate += ProductionSystem.staffed_rate(params, building, "outputs.flour")
	return rate


# What the bakeries want beyond what the mills can supply; imports only cover this, so a working mill
# is never undercut and a missing one is replaced (D-026).
static func flour_deficit(state: EconomyState, params: Params) -> float:
	return maxf(0.0, bakery_flour_rate(state, params) - mill_flour_rate(state, params))


static func tea_demand_per_second(state: EconomyState, params: Params) -> float:
	return float(state.population) * float(params.get_value(&"population.tea.per_person_per_minute")) \
		/ SECONDS_PER_MINUTE


# Money pays whole units at an integer price; a free price buys everything wanted.
static func affordable(state: EconomyState, wanted: int, price: int) -> int:
	if price <= 0:
		return wanted
	@warning_ignore("integer_division")
	return mini(wanted, maxi(0, state.money) / price)


# One lot whenever the warehouse has run out of flour and the bakeries would still be left short.
func _import_flour(state: EconomyState, params: Params) -> void:
	if flour_deficit(state, params) <= DEFICIT_EPSILON or int(state.stocks.get(&"flour", 0)) > 0:
		return
	var price: int = int(params.get_value(&"market.imported_flour.price_per_lot"))
	if affordable(state, 1, price) <= 0:
		return
	state.money -= price
	state.imports_spent_tick += price
	state.stocks[&"flour"] = int(state.stocks.get(&"flour", 0)) \
		+ int(params.get_value(&"market.imported_flour.lot_size"))


# Keeps a small buffer of tea in store, so one empty tick does not drop the coverage.
func _import_tea(state: EconomyState, params: Params) -> void:
	var buffer: float = tea_demand_per_second(state, params) \
		* float(params.get_value(&"market.tea.buffer_seconds"))
	var target: int = ceili(buffer - ProductionSystem.ROUNDING_EPSILON)
	var stock: int = int(state.stocks.get(&"tea", 0))
	var price: int = int(params.get_value(&"market.tea.price"))
	var units: int = affordable(state, maxi(0, target - stock), price)
	if units <= 0:
		return
	state.money -= units * price
	state.imports_spent_tick += units * price
	state.stocks[&"tea"] = stock + units


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
			"reason": flour_reason(state, params),
		},
	}
