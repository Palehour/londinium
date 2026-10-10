class_name MarketSystem
extends RefCounted

const SECONDS_PER_MINUTE: float = 60.0
const FULL_RATE: float = 1.0


func tick(state: EconomyState, params: Params, rng: RandomNumberGenerator, tick_count: int) -> void:
	var interval: int = int(params.get_value(&"market.wheat.price_update_seconds"))
	# Nonpositive modifier results disable repricing, not purchases at the saved price.
	if interval > 0 and tick_count % interval == 0:
		state.wheat_previous_price = state.wheat_price
		state.wheat_price = next_price(state.wheat_price, params, rng)
	# Before buying and before the mill runs, so it never touches wheat bought this tick.
	_decay(state, params)
	if not state.wheat_purchases_enabled:
		return
	var wharves: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"wharf":
			wharves.append(building)
	# A price above the player's maximum stops the wharf (it does not bank capacity), unless the stock
	# is under the safety reserve: then it buys at any price, but only what the mills consume. The
	# limit is shared by all the wharves in proportion to what each one can buy.
	var rate_scale: float = FULL_RATE
	if is_blocked_by_price(state):
		if reserve_covered(state, params):
			return
		rate_scale = _emergency_scale(state, params, wharves)
	for building: Dictionary in wharves:
		_buy(state, params, building, rate_scale)


# Fraction of every wharf's staffed capacity that keeps the total at what the mills consume.
func _emergency_scale(state: EconomyState, params: Params, wharves: Array[Dictionary]) -> float:
	var capacity: float = 0.0
	for building: Dictionary in wharves:
		capacity += ProductionSystem.staffed_rate(params, building, "outputs.wheat")
	if capacity <= 0.0:
		return FULL_RATE
	return minf(FULL_RATE, mill_consumption_per_second(state, params) / capacity)


# Everything the panel shows about wheat, so the UI holds no rules. minutes_covered is -1 when no mill
# is working (there is no consumption to divide by).
static func wheat_snapshot(state: EconomyState, params: Params) -> Dictionary:
	var stock: int = int(state.stocks.get(&"wheat", 0))
	var consumption: float = mill_consumption_per_second(state, params) * SECONDS_PER_MINUTE
	return {
		"stock": stock, "capacity": int(params.get_value(&"market.wheat.storage_capacity")),
		"price": state.wheat_price,
		"previous_price": state.wheat_previous_price if state.wheat_previous_price >= 0 else state.wheat_price,
		"min_price": int(params.get_value(&"market.wheat.min_price")),
		"top_price": int(params.get_value(&"market.wheat.max_price")),
		"accumulate_price": state.wheat_accumulate_price, "max_price": state.wheat_max_price,
		"target_stock": state.wheat_target_stock, "reserve_minutes": state.wheat_reserve_minutes,
		"max_reserve_minutes": WheatPolicy.MAX_RESERVE_MINUTES,
		"consumption_per_minute": consumption,
		"minutes_covered": float(stock) / consumption if consumption > 0.0 else -1.0,
		"blocked_by_price": is_halted_by_price(state, params),
	}


static func is_blocked_by_price(state: EconomyState) -> bool:
	return state.wheat_max_price > WheatPolicy.NO_LIMIT and state.wheat_price > state.wheat_max_price


# Wheat the staffed mills grind per second; the reserve and the buying cap are measured against it.
static func mill_consumption_per_second(state: EconomyState, params: Params) -> float:
	var consumption: float = 0.0
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"mill":
			consumption += ProductionSystem.staffed_rate(params, building, "inputs.wheat")
	return consumption


# Stock for at least reserve_minutes of mill. With 0 minutes it always is, so the maximum price
# applies in full (the behaviour before the reserve existed).
static func reserve_covered(state: EconomyState, params: Params) -> bool:
	var reserve: float = float(state.wheat_reserve_minutes) * mill_consumption_per_second(state, params) 		* SECONDS_PER_MINUTE
	return float(state.stocks.get(&"wheat", 0)) >= reserve


# The maximum price really stops the wharf: purchases are on, the price is above it and the reserve is
# covered. With the toggle off the cause is the toggle, not the price.
static func is_halted_by_price(state: EconomyState, params: Params) -> bool:
	return state.wheat_purchases_enabled and is_blocked_by_price(state) and reserve_covered(state, params)


static func is_accumulating(state: EconomyState) -> bool:
	return state.wheat_accumulate_price > WheatPolicy.OFF and state.wheat_price <= state.wheat_accumulate_price \
		and int(state.stocks.get(&"wheat", 0)) < state.wheat_target_stock


func _buy(state: EconomyState, params: Params, building: Dictionary, rate_scale: float) -> void:
	var stock: int = int(state.stocks.get(&"wheat", 0))
	var rate: float = ProductionSystem.staffed_rate(params, building, "outputs.wheat")
	var accumulating: bool = is_accumulating(state)
	if accumulating:
		rate *= float(params.get_value(&"market.wheat.accumulate_factor"))
	rate *= rate_scale
	var capacity: float = float(building.get("output_fraction", 0.0)) + rate
	var units: int = ProductionSystem.whole_units(capacity)
	building["output_fraction"] = maxf(0.0, capacity - units)
	# Units that do not fit, or that the target no longer needs, are lost like unaffordable ones.
	units = mini(units, maxi(0, int(params.get_value(&"market.wheat.storage_capacity")) - stock))
	if accumulating:
		units = mini(units, state.wheat_target_stock - stock)
	units = affordable_wheat(state, units)
	state.money -= units * state.wheat_price
	state.wheat_spent_tick += units * state.wheat_price
	state.stocks[&"wheat"] = stock + units


func _decay(state: EconomyState, params: Params) -> void:
	var stock: int = int(state.stocks.get(&"wheat", 0))
	var rate: float = float(params.get_value(&"market.wheat.decay_fraction_per_minute"))
	if stock <= 0 or rate <= 0.0:
		return
	state.wheat_decay_fraction += float(stock) * rate / 60.0
	var lost: int = mini(stock, ProductionSystem.whole_units(state.wheat_decay_fraction))
	state.wheat_decay_fraction -= float(lost)
	state.stocks[&"wheat"] = stock - lost


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
