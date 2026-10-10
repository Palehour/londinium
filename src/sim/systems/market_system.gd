class_name MarketSystem
extends RefCounted


func tick(state: EconomyState, params: Params, rng: RandomNumberGenerator, tick_count: int) -> void:
	var interval: int = int(params.get_value(&"market.wheat.price_update_seconds"))
	# Nonpositive modifier results disable repricing, not purchases at the saved price.
	if interval > 0 and tick_count % interval == 0:
		state.wheat_price = next_price(state.wheat_price, params, rng)
	if not state.wheat_purchases_enabled:
		return
	for building: Dictionary in state.buildings:
		if building["definition_id"] != &"wharf":
			continue
		var capacity: float = float(building.get("output_fraction", 0.0)) \
			+ ProductionSystem.staffed_rate(params, building, "outputs.wheat")
		var units: int = ProductionSystem.whole_units(capacity)
		building["output_fraction"] = maxf(0.0, capacity - units)
		units = affordable_wheat(state, units)
		state.money -= units * state.wheat_price
		state.wheat_spent_tick += units * state.wheat_price
		state.stocks[&"wheat"] = state.stocks.get(&"wheat", 0) + units


# Mean-reverting walk: one update moves the price by at most market.wheat.max_step and never leaves
# [min_price, max_price]. Away from base_price the price is pulled toward it (without overshooting)
# with probability market.wheat.reversion; otherwise it goes up, down or stays. Both draws are always
# taken, in this order, so a series depends only on the seed (a modifier that fixes the price
# still consumes its scheduled draws).
static func next_price(price: int, params: Params, rng: RandomNumberGenerator) -> int:
	var minimum: int = int(params.get_value(&"market.wheat.min_price"))
	var maximum: int = int(params.get_value(&"market.wheat.max_price"))
	var base: int = int(params.get_value(&"market.wheat.base_price"))
	var max_step: int = int(params.get_value(&"market.wheat.max_step"))
	var reverts: bool = rng.randf() < float(params.get_value(&"market.wheat.reversion"))
	var step: int = rng.randi_range(-max_step, max_step)
	if reverts and price != base:
		step = clampi(base - price, -max_step, max_step)
	return clampi(price + step, mini(minimum, maximum), maxi(minimum, maximum))


# Shared with BreadDiagnostics so the panel's "no money" reason matches what the wharf buys.
static func affordable_wheat(state: EconomyState, wanted: int) -> int:
	if state.wheat_price <= 0:
		return wanted
	@warning_ignore("integer_division")
	return mini(wanted, maxi(0, state.money) / state.wheat_price)
