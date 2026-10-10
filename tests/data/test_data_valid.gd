extends GutTest


func test_every_json_loads_into_typed_definitions() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	var catalog: DataCatalog = result.catalog
	assert_eq(catalog.goods.size(), 3)
	assert_eq(catalog.buildings.size(), 5)
	assert_eq(catalog.roles.size(), 1)
	assert_eq(catalog.maps.size(), 1)
	for good: GoodDef in catalog.goods.values():
		assert_false(good.unit.is_empty())
	var mill: RecipeDef = catalog.buildings[&"mill"].recipe
	assert_eq(mill.inputs, [&"wheat"])
	assert_eq(mill.outputs, [&"flour"])
	var bakery: RecipeDef = catalog.buildings[&"bakery"].recipe
	assert_eq(bakery.inputs, [&"flour"])
	assert_eq(bakery.outputs, [&"bread"])
	assert_null(catalog.buildings[&"housing"].recipe)
	for role: RoleDef in catalog.roles.values():
		for modifier: Modifier in role.modifiers:
			assert_true(catalog.base_values.has(modifier.key), str(modifier.key))
	assert_true(catalog.roles[&"neutral_administrator"].modifiers.is_empty())
	for key: StringName in catalog.money_keys:
		assert_typeof(catalog.base_values[key], TYPE_INT, str(key))


func test_whitechapel_has_no_cultivation_or_pending_content() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	var catalog: DataCatalog = result.catalog
	var map: MapDef = catalog.maps[&"whitechapel_1850s"]
	assert_true(map.cultivable_cells.is_empty())
	assert_false(map.river_cells.is_empty())
	assert_true(catalog.buildings.has(&"wheat_field"))
	assert_false(catalog.goods.has(&"tea"))
	assert_true(catalog.buildings[&"wharf"].recipe.inputs.is_empty())
	assert_eq(catalog.buildings[&"wharf"].recipe.outputs, [&"wheat"])
	assert_false(catalog.base_values.has(&"market.imported_flour.price"))


func test_wheat_field_loads_with_recipe_tags_and_parameters() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	assert_true(result.catalog.buildings.has(&"wheat_field"))
	if not result.catalog.buildings.has(&"wheat_field"):
		return
	var field: BuildingDef = result.catalog.buildings[&"wheat_field"]
	assert_true("cultivable" in field.tags)
	assert_true("source" in field.tags)
	assert_not_null(field.recipe)
	if field.recipe == null:
		return
	assert_true(field.recipe.inputs.is_empty())
	assert_eq(field.recipe.outputs, [&"wheat"])
	var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
	for suffix: String in ["cost", "upkeep_per_minute", "wage_per_worker_per_minute", "jobs",
			"recipe.seconds", "recipe.outputs.wheat"]:
		var key: StringName = StringName("building.wheat_field." + suffix)
		assert_true(result.catalog.base_values.has(key), str(key))
		assert_true(float(params.get_value(key)) > 0.0, str(key))


func test_gdd_parameter_categories_and_defeat_placeholders_exist() -> void:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	if not result.is_ok():
		return
	var params: Params = Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])
	for key: StringName in [&"building.bakery.cost", &"building.bakery.upkeep_per_minute",
			&"building.bakery.wage_per_worker_per_minute", &"building.bakery.jobs",
			&"building.bakery.recipe.seconds", &"building.bakery.recipe.outputs.bread",
			&"population.satisfaction.bread_weight", &"population.satisfaction.tax_weight",
			&"population.satisfaction.overcrowding_weight", &"population.growth.immigration_threshold",
			&"population.growth.emigration_threshold", &"market.wheat.base_price"]:
		assert_true(result.catalog.base_values.has(key), str(key))
	assert_eq(params.get_value(&"defeat.bankruptcy.threshold"), 0)
	assert_eq(params.get_value(&"defeat.bankruptcy.duration_seconds"), 180)
	assert_eq(params.get_value(&"defeat.hunger.threshold"), 0.5)
	assert_eq(params.get_value(&"defeat.hunger.duration_seconds"), 180)
	assert_eq(params.get_value(&"defeat.depopulation.warning_fraction"), 0.5)
	assert_eq(params.get_value(&"defeat.depopulation.defeat_fraction"), 0.25)
	assert_eq(params.get_value(&"defeat.depopulation.minimum_population"), 10)
	assert_eq(params.get_value(&"defeat.depopulation.duration_seconds"), 180)
	assert_eq(params.get_value(&"defeat.hunger.smoothing"), 0.1)
	assert_eq(params.get_value(&"defeat.grace_seconds"), 300.0)
	assert_eq(params.get_value(&"population.growth.hunger_emigration_multiplier"), 2.0)


# #39 (F1/F2/F7): building costs, starting money and taxes must live on the same scale as the
# money flows, otherwise a second chain is out of reach. These are relations, not exact values, so
# retuning in data/ does not trip them unless the scale itself breaks.
func _economy_params() -> Params:
	var result: DataLoadResult = DataLoader.new().load_all()
	assert_true(result.is_ok(), str(result.errors))
	return Params.new(result.catalog, result.catalog.roles[&"neutral_administrator"])


func _chain_cost(params: Params) -> int:
	var total: int = 0
	for building: String in ["wharf", "mill", "bakery"]:
		total += int(params.get_value(StringName("building.%s.cost" % building)))
	return total


func test_starting_money_builds_one_chain_but_not_two() -> void:
	var params: Params = _economy_params()
	var money: int = int(params.get_value(&"startup.money"))
	var chain: int = _chain_cost(params)
	assert_gte(money, chain, "the first chain is affordable from the start")
	assert_lt(money, 2 * chain, "the second chain has to be financed")


func test_a_staffed_chain_pays_for_the_next_one_within_the_game() -> void:
	var params: Params = _economy_params()
	var jobs: int = 0
	var upkeep: int = 0
	var wages: int = 0
	for building: String in ["wharf", "mill", "bakery"]:
		jobs += int(params.get_value(StringName("building.%s.jobs" % building)))
		upkeep += int(params.get_value(StringName("building.%s.upkeep_per_minute" % building)))
		wages += int(params.get_value(StringName("building.%s.jobs" % building))) 			* int(params.get_value(StringName("building.%s.wage_per_worker_per_minute" % building)))
	# At the highest tax the chain's own taxes cover its wages and upkeep with room to save.
	var taxes: float = float(jobs) * float(params.get_value(&"population.tax.base_per_employed_worker_per_minute"))
	assert_gt(taxes, float(wages + upkeep), "a staffed chain at 100% tax is profitable")
	var money: int = int(params.get_value(&"startup.money"))
	var surplus: float = taxes - float(wages + upkeep)
	var gap: float = float(2 * _chain_cost(params) - money)
	assert_lt(gap / surplus, 15.0, "even at the top tax rate the gap closes inside a 15 minute game")
