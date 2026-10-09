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
	assert_eq(params.get_value(&"population.growth.hunger_emigration_multiplier"), 2.0)
