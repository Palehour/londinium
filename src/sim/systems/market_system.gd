class_name MarketSystem
extends RefCounted


func tick(state: EconomyState, params: Params, rng: RandomNumberGenerator, tick_count: int) -> void:
	var interval: int = int(params.get_value(&"market.wheat.price_update_seconds"))
	# Nonpositive modifier results disable repricing, not purchases at the saved price.
	if interval > 0 and tick_count % interval == 0:
		var minimum: int = int(params.get_value(&"market.wheat.min_price"))
		var maximum: int = int(params.get_value(&"market.wheat.max_price"))
		# Keep the scheduled draw even if modifiers temporarily fix the price.
		if minimum == maximum:
			rng.randi()
		state.wheat_price = rng.randi_range(minimum, maximum)
	if not state.wheat_purchases_enabled:
		return
	for building: Dictionary in state.buildings:
		if building["definition_id"] != &"wharf":
			continue
		var capacity: float = float(building.get("output_fraction", 0.0)) \
			+ ProductionSystem.staffed_rate(params, building, "outputs.wheat")
		var units: int = ProductionSystem.whole_units(capacity)
		building["output_fraction"] = maxf(0.0, capacity - units)
		if state.wheat_price > 0:
			@warning_ignore("integer_division")
			var affordable: int = maxi(0, state.money) / state.wheat_price
			units = mini(units, affordable)
		state.money -= units * state.wheat_price
		state.wheat_spent_tick += units * state.wheat_price
		state.stocks[&"wheat"] = state.stocks.get(&"wheat", 0) + units
