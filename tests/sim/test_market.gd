extends GutTest

# The wheat price is a mean-reverting walk (MarketSystem.next_price): at most max_step per update,
# never outside [min_price, max_price], pulled toward base_price with probability `reversion`.

const UPDATES: int = 50000

var _catalog: DataCatalog


func before_each() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	assert_true(loaded.is_ok(), str(loaded.errors))
	_catalog = loaded.catalog


func _params(overrides: Dictionary[StringName, float] = {}) -> Params:
	var role: RoleDef = RoleDef.new()
	for key: StringName in overrides:
		role.modifiers.append(Modifier.new(key, &"set", overrides[key]))
	return Params.new(_catalog, role)


func _series(params: Params, seed_value: int, count: int) -> Array[int]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var price: int = int(params.get_value(&"market.wheat.base_price"))
	var prices: Array[int] = []
	for index: int in range(count):
		price = MarketSystem.next_price(price, params, rng)
		prices.append(price)
	return prices


func _mean(values: Array[int]) -> float:
	var total: float = 0.0
	for value: int in values:
		total += float(value)
	return total / float(values.size())


func _widest_step(start: int, prices: Array[int]) -> int:
	var widest: int = 0
	var previous: int = start
	for price: int in prices:
		widest = maxi(widest, absi(price - previous))
		previous = price
	return widest


func test_a_step_never_exceeds_max_step_and_the_price_never_leaves_the_range() -> void:
	for max_step: int in [1, 2, 3]:
		var params: Params = _params({&"market.wheat.min_price": 1.0, &"market.wheat.max_price": 9.0,
			&"market.wheat.base_price": 5.0, &"market.wheat.max_step": float(max_step)})
		var prices: Array[int] = _series(params, 7, 5000)
		assert_lte(_widest_step(5, prices), max_step, "max_step %d" % max_step)
		assert_gte(prices.min(), 1)
		assert_lte(prices.max(), 9)
		assert_eq(_widest_step(5, prices), max_step, "the walk does use the whole step")


func test_shipped_data_moves_one_pound_at_most_inside_one_to_three() -> void:
	var params: Params = _params()
	var prices: Array[int] = _series(params, 42, 5000)
	assert_lte(_widest_step(int(params.get_value(&"market.wheat.base_price")), prices), 1)
	assert_gte(prices.min(), int(params.get_value(&"market.wheat.min_price")))
	assert_lte(prices.max(), int(params.get_value(&"market.wheat.max_price")))
	assert_eq(prices.min(), 1, "it reaches the bottom of the range")
	assert_eq(prices.max(), 3, "and the top")


func test_the_price_reverts_to_the_mean() -> void:
	var params: Params = _params()
	assert_almost_eq(_mean(_series(params, 11, UPDATES)), float(params.get_value(&"market.wheat.base_price")), 0.05)
	# In a wide range the pull is what keeps the average near base_price.
	var wide: Dictionary[StringName, float] = {&"market.wheat.min_price": 1.0, &"market.wheat.max_price": 9.0,
		&"market.wheat.base_price": 3.0}
	var pulled: float = _mean(_series(_params(wide), 11, UPDATES))
	wide[&"market.wheat.reversion"] = 0.0
	var free: float = _mean(_series(_params(wide), 11, UPDATES))
	assert_lt(absf(pulled - 3.0), 0.5, "pulled toward base_price")
	assert_lt(absf(pulled - 3.0), absf(free - 3.0), "closer to base_price than a walk without reversion")


func test_full_reversion_always_steps_toward_base_price() -> void:
	var params: Params = _params({&"market.wheat.min_price": 1.0, &"market.wheat.max_price": 9.0,
		&"market.wheat.base_price": 5.0, &"market.wheat.max_step": 2.0, &"market.wheat.reversion": 1.0})
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for _index: int in range(200):
		assert_eq(MarketSystem.next_price(9, params, rng), 7, "two steps down")
		assert_eq(MarketSystem.next_price(1, params, rng), 3, "two steps up")
		assert_eq(MarketSystem.next_price(6, params, rng), 5, "does not overshoot")
		assert_eq(MarketSystem.next_price(4, params, rng), 5)


func test_no_reversion_is_a_plain_bounded_walk() -> void:
	var params: Params = _params({&"market.wheat.min_price": 1.0, &"market.wheat.max_price": 9.0,
		&"market.wheat.base_price": 5.0, &"market.wheat.reversion": 0.0})
	var prices: Array[int] = _series(params, 5, 3000)
	assert_lte(_widest_step(5, prices), 1)
	assert_gt(prices.max() - prices.min(), 3, "free to wander away from base_price")


func test_same_seed_gives_the_same_series_and_another_seed_a_different_one() -> void:
	var params: Params = _params()
	assert_eq(_series(params, 99, 500), _series(params, 99, 500))
	assert_ne(_series(params, 99, 500), _series(params, 100, 500))


func test_a_fixed_price_still_consumes_its_scheduled_draws() -> void:
	var params: Params = _params({&"market.wheat.min_price": 5.0, &"market.wheat.max_price": 5.0})
	var used: RandomNumberGenerator = RandomNumberGenerator.new()
	var reference: RandomNumberGenerator = RandomNumberGenerator.new()
	used.seed = 8
	reference.seed = 8
	assert_eq(MarketSystem.next_price(5, params, used), 5)
	reference.randf()
	reference.randi_range(-1, 1)
	assert_eq(used.state, reference.state, "two draws per update whatever the modifiers say")


func test_simulation_prices_follow_the_walk_every_update_interval() -> void:
	var params: Params = _params()
	var sim: Simulation = Simulation.create_new(params, EconomyState.new(), 42,
		EconomyContext.new(_catalog, _catalog.maps[&"whitechapel_1850s"]))
	var interval: int = int(params.get_value(&"market.wheat.price_update_seconds"))
	var previous: int = sim.snapshot()["economy"]["wheat_price"]
	assert_eq(previous, int(params.get_value(&"market.wheat.base_price")))
	for update: int in range(40):
		for tick_index: int in range(interval):
			sim.tick()
		var price: int = sim.snapshot()["economy"]["wheat_price"]
		assert_lte(absi(price - previous), 1, "update %d" % update)
		assert_between(price, 1, 3)
		previous = price


func test_modifiers_can_widen_the_step_and_invalid_values_are_rejected() -> void:
	var wide: Params = _params({&"market.wheat.max_step": 2.0, &"market.wheat.min_price": 1.0,
		&"market.wheat.max_price": 9.0, &"market.wheat.base_price": 5.0})
	assert_eq(_widest_step(5, _series(wide, 1, 3000)), 2)
	var invalid: Dictionary[StringName, Array] = {
		&"market.wheat.max_step": [0.0, -1.0, 1.5],
		&"market.wheat.reversion": [-0.01, 1.01],
	}
	for key: StringName in invalid:
		assert_true(ParameterRanges.BY_KEY.has(key))
		for value: float in invalid[key]:
			var role: RoleDef = RoleDef.new()
			role.modifiers.append(Modifier.new(key, &"set", value))
			assert_null(Params.new(_catalog, role).get_value(key))
			assert_push_error("Params: invalid range for '%s'" % key)
	for boundary: float in [0.0, 1.0]:
		assert_eq(_params({&"market.wheat.reversion": boundary}).get_value(&"market.wheat.reversion"), boundary)
