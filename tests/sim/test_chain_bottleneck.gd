extends GutTest


func _inputs() -> Dictionary:
	return {"bread_demand": 120.0, "margin": 0.05, "tie_break": &"upstream",
		"stock_start:bread": 0.0, "stock_start:flour": 0.0, "stock_start:wheat": 0.0,
		"pot:bakery": 120.0, "pot:mill": 30.0, "pot:wharf": 120.0,
		"count:bakery": 1, "count:mill": 1, "count:wharf": 1,
		"recipe:bakery:inputs:flour": 10.0, "recipe:bakery:outputs:bread": 20.0,
		"recipe:mill:inputs:wheat": 10.0, "recipe:mill:outputs:flour": 10.0,
		"imported_flour": 0.0, "no_money_for_imports": false,
		"barley_percent": 0.0, "imported_flour_uses_capacity": false}


func _compute(inputs: Dictionary) -> Dictionary:
	return ChainBottleneck.compute_bottleneck(inputs, ChainBottleneck.BREAD_CHAIN, &"fixture")


func test_mill_at_half_required_output_limits_bread() -> void:
	var result: Dictionary = _compute(_inputs())
	assert_eq(result["status"], &"bottleneck")
	assert_eq(result["limiting_link"], &"mill")
	assert_eq(result["links"][&"mill"], &"bottleneck")


func test_all_links_above_threshold_have_no_bottleneck() -> void:
	var inputs: Dictionary = _inputs()
	inputs["pot:mill"] = 60.0
	assert_eq(_compute(inputs)["status"], &"no_bottleneck")


func test_margin_changes_result_and_equal_threshold_is_not_a_bottleneck() -> void:
	var inputs: Dictionary = _inputs()
	inputs["pot:mill"] = 51.0 # 85% of required flour.
	assert_eq(_compute(inputs)["limiting_link"], &"mill")
	inputs["margin"] = 0.2
	assert_eq(_compute(inputs)["status"], &"no_bottleneck")
	inputs["margin"] = 0.5
	inputs["pot:mill"] = 30.0
	assert_eq(_compute(inputs)["status"], &"no_bottleneck")


func test_exact_tie_prefers_upstream() -> void:
	var inputs: Dictionary = _inputs()
	inputs["pot:wharf"] = 30.0
	assert_eq(_compute(inputs)["limiting_link"], &"wharf")


func test_missing_capacity_is_not_zero_or_a_candidate() -> void:
	var inputs: Dictionary = _inputs()
	inputs.erase("pot:mill")
	assert_eq(_compute(inputs)["status"], &"no_data")
	inputs["pot:bakery"] = 50.0
	var result: Dictionary = _compute(inputs)
	assert_eq(result["limiting_link"], &"bakery")
	assert_eq(result["links"][&"mill"], &"no_data")


func test_nan_stock_is_unknown_not_zero() -> void:
	var inputs: Dictionary = _inputs()
	inputs["stock_start:bread"] = NAN
	assert_eq(_compute(inputs)["status"], &"no_data")


func test_opening_bread_stock_covers_and_excludes_all_links() -> void:
	var inputs: Dictionary = _inputs()
	inputs["stock_start:bread"] = 120.0
	var result: Dictionary = _compute(inputs)
	assert_eq(result["status"], &"no_bottleneck")
	for link: StringName in ChainBottleneck.BREAD_CHAIN:
		assert_eq(result["links"][link], &"excluded")


func test_flour_imports_cover_mill_and_wharf_but_not_bakery() -> void:
	var inputs: Dictionary = _inputs()
	inputs["imported_flour"] = 60.0
	var result: Dictionary = _compute(inputs)
	assert_eq(result["status"], &"no_bottleneck")
	assert_eq(result["links"][&"mill"], &"excluded")
	assert_eq(result["links"][&"wharf"], &"excluded")
	inputs["pot:bakery"] = 10.0
	assert_eq(_compute(inputs)["limiting_link"], &"bakery")


func test_no_money_does_not_count_imported_flour() -> void:
	var inputs: Dictionary = _inputs()
	inputs["imported_flour"] = 60.0
	inputs["no_money_for_imports"] = true
	assert_eq(_compute(inputs)["limiting_link"], &"mill")


func test_absent_building_is_not_a_candidate_but_zero_workers_are() -> void:
	var inputs: Dictionary = _inputs()
	inputs["count:mill"] = 0
	assert_eq(_compute(inputs)["status"], &"no_data")
	inputs["count:mill"] = 1
	inputs["pot:mill"] = 0.0
	assert_eq(_compute(inputs)["limiting_link"], &"mill")


func test_recipe_amounts_change_required_flour() -> void:
	var inputs: Dictionary = _inputs()
	assert_eq(_compute(inputs)["limiting_link"], &"mill")
	inputs["recipe:bakery:inputs:flour"] = 5.0
	assert_eq(_compute(inputs)["status"], &"no_bottleneck")


func test_zero_demand_needs_no_stocks_but_still_requires_configuration() -> void:
	var inputs: Dictionary = {"bread_demand": 0.0, "margin": 0.0, "tie_break": &"upstream"}
	assert_eq(_compute(inputs)["status"], &"no_bottleneck")
	inputs.erase("margin")
	assert_eq(_compute(inputs)["status"], &"no_data")
