class_name MarketSystem
extends RefCounted

const SECONDS_PER_MINUTE: float = 60.0
const FULL_RATE: float = 1.0
const PERCENT: float = 100.0
const WHOLE_PERCENT: int = 100
# Debt below this is floating point noise from summing capacity, not a unit still to unload.
const DEBT_EPSILON: float = 1e-9


# Barley has its own generator so its price walk never shifts the wheat series.
func tick(state: EconomyState, params: Params, rng: RandomNumberGenerator, tick_count: int,
		barley_rng: RandomNumberGenerator = null) -> void:
	var interval: int = int(params.get_value(&"market.wheat.price_update_seconds"))
	# Nonpositive modifier results disable repricing, not purchases at the saved price.
	if interval > 0 and tick_count % interval == 0:
		state.wheat_previous_price = state.wheat_price
		state.wheat_price = next_price(state.wheat_price, params, rng)
	if barley_rng != null:
		_reprice_barley(state, params, barley_rng, tick_count)
	# Before buying and before the mill runs, so it never touches wheat bought this tick.
	_decay(state, params)
	_decay_barley(state, params)
	var wharves: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"wharf":
			wharves.append(building)
	# The wharf unloads the imported flour first (issue #50); what it leaves is shared by wheat and barley.
	var grain_fraction: float = _pay_flour_unloading(state, wharves, params)
	if state.wheat_purchases_enabled:
		_buy_wheat(state, params, wharves, grain_fraction * wheat_share(state))
	_buy_barley(state, params, wharves, grain_fraction)


# Capacity of the wharves goes to the lots of flour already bought before it goes to any grain. Returns
# the fraction of this tick's capacity that is left for wheat and barley.
func _pay_flour_unloading(state: EconomyState, wharves: Array[Dictionary], params: Params) -> float:
	if state.flour_unloading_debt <= 0.0:
		return FULL_RATE
	var capacity: float = unloading_capacity(params, wharves)
	if capacity <= 0.0:
		return FULL_RATE
	var paid: float = minf(state.flour_unloading_debt, capacity)
	state.flour_unloading_debt -= paid
	if state.flour_unloading_debt < DEBT_EPSILON:
		state.flour_unloading_debt = 0.0
	return (capacity - paid) / capacity


# Units per second the staffed wharves can unload, whatever the good (a wharf's wheat output is its capacity).
static func unloading_capacity(params: Params, wharves: Array[Dictionary]) -> float:
	var capacity: float = 0.0
	for building: Dictionary in wharves:
		capacity += ProductionSystem.staffed_rate(params, building, "outputs.wheat")
	return capacity


# Share of the capacity left for grain that goes to wheat; 1.0 until the player gives some to barley.
static func wheat_share(state: EconomyState) -> float:
	return float(WHOLE_PERCENT - barley_percent(state)) / PERCENT


static func barley_percent(state: EconomyState) -> int:
	return clampi(state.unloading_barley_percent, 0, WHOLE_PERCENT)


func _buy_wheat(state: EconomyState, params: Params, wharves: Array[Dictionary], share: float) -> void:
	# A price above the player's maximum stops the wharf (it does not bank capacity), unless the stock
	# is under the safety reserve: then it buys at any price, but only what the mills consume. The
	# limit is shared by all the wharves in proportion to what each one can buy.
	var rate_scale: float = FULL_RATE
	if is_blocked_by_price(state):
		if reserve_covered(state, params):
			return
		rate_scale = _emergency_scale(state, params, wharves, share)
	for building: Dictionary in wharves:
		_buy(state, params, building, rate_scale, share)


# Fraction of every wharf's staffed capacity that keeps the total at what the mills consume. share is the
# part of the capacity wheat has this tick (barley and the flour take the rest).
func _emergency_scale(state: EconomyState, params: Params, wharves: Array[Dictionary], share: float) -> float:
	var capacity: float = unloading_capacity(params, wharves) * share
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
		"min_price": mini(int(params.get_value(&"market.wheat.min_price")), int(params.get_value(&"market.wheat.max_price"))),
		"top_price": maxi(int(params.get_value(&"market.wheat.min_price")), int(params.get_value(&"market.wheat.max_price"))),
		"accumulate_price": state.wheat_accumulate_price, "max_price": state.wheat_max_price,
		"target_stock": state.wheat_target_stock, "reserve_minutes": state.wheat_reserve_minutes,
		"max_reserve_minutes": WheatPolicy.MAX_RESERVE_MINUTES,
		"consumption_per_minute": consumption,
		"minutes_covered": float(stock) / consumption if consumption > 0.0 else -1.0,
		"blocked_by_price": is_halted_by_price(state, params),
	}


static func is_blocked_by_price(state: EconomyState) -> bool:
	return state.wheat_max_price != WheatPolicy.NO_LIMIT and state.wheat_price > state.wheat_max_price


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
	var reserve: float = (float(state.wheat_reserve_minutes) * mill_consumption_per_second(state, params)
		* SECONDS_PER_MINUTE)
	return float(state.stocks.get(&"wheat", 0)) >= reserve


# The maximum price really stops the wharf: purchases are on, the price is above it, the reserve is
# covered, and without the limit a wharf would buy. With the toggle off, a full warehouse, no workers or
# no money the cause is that, not the price.
static func is_halted_by_price(state: EconomyState, params: Params) -> bool:
	return state.wheat_purchases_enabled and is_blocked_by_price(state) and reserve_covered(state, params) \
		and could_buy(state, params)


# Some wharf has hands, there is room in the warehouse and the treasury pays for a unit.
static func could_buy(state: EconomyState, params: Params) -> bool:
	if int(state.stocks.get(&"wheat", 0)) >= int(params.get_value(&"market.wheat.storage_capacity")):
		return false
	if affordable_wheat(state, 1) <= 0:
		return false
	for building: Dictionary in state.buildings:
		if building["definition_id"] == &"wharf" and ProductionSystem.staffed_rate(params, building, "outputs.wheat") > 0.0:
			return true
	return false


static func is_accumulating(state: EconomyState) -> bool:
	return state.wheat_accumulate_price != WheatPolicy.OFF and state.wheat_price <= state.wheat_accumulate_price \
		and int(state.stocks.get(&"wheat", 0)) < state.wheat_target_stock


func _buy(state: EconomyState, params: Params, building: Dictionary, rate_scale: float, share: float) -> void:
	var stock: int = int(state.stocks.get(&"wheat", 0))
	var rate: float = ProductionSystem.staffed_rate(params, building, "outputs.wheat")
	var accumulating: bool = is_accumulating(state)
	if accumulating:
		rate *= float(params.get_value(&"market.wheat.accumulate_factor"))
	rate *= rate_scale
	rate *= share
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
	state.wheat_decay_fraction = _decayed(state, params, &"wheat", state.wheat_decay_fraction)


func _decay_barley(state: EconomyState, params: Params) -> void:
	state.barley_decay_fraction = _decayed(state, params, &"barley", state.barley_decay_fraction)


# Spoils a stock in whole units; returns the fraction of a unit lost but not yet counted.
func _decayed(state: EconomyState, params: Params, good: StringName, carried: float) -> float:
	var stock: int = int(state.stocks.get(good, 0))
	var rate: float = float(params.get_value(StringName("market.%s.decay_fraction_per_minute" % good)))
	# Loss accrued against stock that is gone does not carry over to the next delivery.
	if stock <= 0:
		return 0.0
	if rate <= 0.0:
		return carried
	# The configured fraction is what is lost in a minute, so each tick keeps (1 - rate)^(1/60), as the bread does.
	carried += float(stock) * (1.0 - pow(1.0 - rate, 1.0 / SECONDS_PER_MINUTE))
	var lost: int = mini(stock, ProductionSystem.whole_units(carried))
	carried -= float(lost)
	state.stocks[good] = stock - lost
	# Decay that empties the warehouse leaves nothing owed to the delivery that may refill it this tick.
	if stock - lost <= 0:
		return 0.0
	return carried


# Mean-reverting walk: one update moves the price by at most market.wheat.max_step and never leaves
# [min_price, max_price]. Away from base_price the price is pulled toward it (without overshooting)
# with probability market.wheat.reversion; otherwise it goes up, down or stays. Both draws are always
# taken, in this order, so a series depends only on the seed (a modifier that fixes the price
# still consumes its scheduled draws).
static func next_price(price: int, params: Params, rng: RandomNumberGenerator) -> int:
	return _walk_price(&"wheat", price, params, rng)


static func next_barley_price(price: int, params: Params, rng: RandomNumberGenerator) -> int:
	return _walk_price(&"barley", price, params, rng)


static func _walk_price(good: StringName, price: int, params: Params, rng: RandomNumberGenerator) -> int:
	var minimum: int = int(params.get_value(StringName("market.%s.min_price" % good)))
	var maximum: int = int(params.get_value(StringName("market.%s.max_price" % good)))
	var base: int = int(params.get_value(StringName("market.%s.base_price" % good)))
	var max_step: int = int(params.get_value(StringName("market.%s.max_step" % good)))
	var reverts: bool = rng.randf() < float(params.get_value(StringName("market.%s.reversion" % good)))
	var step: int = rng.randi_range(-max_step, max_step)
	if reverts and price != base:
		step = clampi(base - price, -max_step, max_step)
	return clampi(price + step, mini(minimum, maximum), maxi(minimum, maximum))


func _reprice_barley(state: EconomyState, params: Params, rng: RandomNumberGenerator, tick_count: int) -> void:
	var interval: int = int(params.get_value(&"market.barley.price_update_seconds"))
	if state.barley_price < 0:
		state.barley_price = int(params.get_value(&"market.barley.base_price"))
	if interval > 0 and tick_count % interval == 0:
		state.barley_previous_price = state.barley_price
		state.barley_price = next_barley_price(state.barley_price, params, rng)


# Barley takes its share of what the flour leaves. It has no purchase policy yet (nothing consumes it), so
# it only stops at a full warehouse or an empty treasury; units that do not fit are lost like the wheat ones.
func _buy_barley(state: EconomyState, params: Params, wharves: Array[Dictionary], grain_fraction: float) -> void:
	var share: float = float(barley_percent(state)) / PERCENT
	if share <= 0.0:
		return
	var price: int = _barley_price(state, params)
	var room: int = int(params.get_value(&"market.barley.storage_capacity"))
	for building: Dictionary in wharves:
		var rate: float = ProductionSystem.staffed_rate(params, building, "outputs.wheat") * grain_fraction * share
		var capacity: float = float(building.get("barley_fraction", 0.0)) + rate
		var units: int = ProductionSystem.whole_units(capacity)
		building["barley_fraction"] = maxf(0.0, capacity - units)
		var stock: int = int(state.stocks.get(&"barley", 0))
		units = ImportSystem.affordable(state, mini(units, maxi(0, room - stock)), price)
		state.money -= units * price
		state.barley_spent_tick += units * price
		state.stocks[&"barley"] = stock + units


# Before the simulation loads the price (systems driven by hand in tests) barley sells at its base price.
static func _barley_price(state: EconomyState, params: Params) -> int:
	return state.barley_price if state.barley_price >= 0 else int(params.get_value(&"market.barley.base_price"))


# Everything the panel shows about barley and the split of the wharf's capacity, so the UI holds no rules.
static func barley_snapshot(state: EconomyState, params: Params) -> Dictionary:
	var price: int = _barley_price(state, params)
	return {
		"stock": int(state.stocks.get(&"barley", 0)),
		"capacity": int(params.get_value(&"market.barley.storage_capacity")),
		"price": price,
		"previous_price": state.barley_previous_price if state.barley_previous_price >= 0 else price,
		"barley_percent": barley_percent(state), "wheat_percent": WHOLE_PERCENT - barley_percent(state),
		"flour_unloading_debt": state.flour_unloading_debt,
	}


# Shared with BreadDiagnostics so the panel's "no money" reason matches what the wharf buys.
static func affordable_wheat(state: EconomyState, wanted: int) -> int:
	if state.wheat_price <= 0:
		return wanted
	@warning_ignore("integer_division")
	return mini(wanted, maxi(0, state.money) / state.wheat_price)
