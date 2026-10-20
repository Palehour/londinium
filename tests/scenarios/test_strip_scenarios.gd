extends GutTest

# Issue #67, scenarios (a), (b) and (c) on the 32x24 strip with streets (D-070, D-074, D-080). They live in
# tests/scenarios/strip/, apart from the 8x8 scripts, so the parity of the existing scenarios stays byte for byte;
# balance_report plays them with --strip. Since issue #152 they stand on the traced streets of Wapping: only their
# cells moved, what each one measures did not. Since issue #186 (D-086) every cell (x, y) of them is (2x, 2y), the
# corner of its 2x2 block, and they measure the same.

var _runner: ScenarioRunner
var _results: Dictionary[String, ScenarioResult] = {}


func before_all() -> void:
	_runner = ScenarioRunner.create()
	assert_not_null(_runner, "data/ must load")
	if _runner == null:
		return
	for path: String in ScenarioRunner.strip_scenario_paths():
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		assert_eq(_runner.validate(scenario), [] as Array[String], path)
		assert_eq(path.get_file().get_basename(), String(scenario["id"]))
		_results[String(scenario["id"])] = _runner.run(scenario)


func _result(id: String) -> ScenarioResult:
	assert_true(_results.has(id), "scenario %s is missing" % id)
	return _results.get(id)


func _entry(entries: Array, cell: Array) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["cell"] == cell:
			return entry
	return {}


func test_strip_scenarios_play_every_command() -> void:
	assert_eq(_results.size(), 4)
	for id: String in _results:
		assert_eq(_results[id].unexpected_rejections(), [] as Array[Dictionary], id)


# A house out of reach is extra room nobody uses: the city with it lives like the one without it.
func test_the_chains_and_the_city_with_an_unserved_house_survive() -> void:
	for id: String in ["strip_chain_near", "strip_chain_far", "strip_out_of_radius"]:
		assert_true(_result(id).survived(), id)


# (a) The same chain near the river and far from it: the far one pays the long legs and ends with less money.
func test_the_same_chain_far_from_the_river_has_a_smaller_surplus() -> void:
	var near: ScenarioResult = _result("strip_chain_near")
	var far: ScenarioResult = _result("strip_chain_far")
	var near_legs: int = 0
	var far_legs: int = 0
	for leg: Dictionary in near.final_distance["legs"]:
		near_legs += int(leg["steps"])
	for leg: Dictionary in far.final_distance["legs"]:
		far_legs += int(leg["steps"])
	assert_gt(far_legs, near_legs)
	assert_gt(int(near.final_economy["money"]), int(far.final_economy["money"]),
		"near %d, far %d" % [near.final_economy["money"], far.final_economy["money"]])


# (b) A house beyond the bakery's radius gets no bread, and the overlay's data says so.
func test_a_house_beyond_the_radius_is_reported_unserved() -> void:
	var houses: Array = _result("strip_out_of_radius").final_distance["houses"]
	assert_false(_entry(houses, [30, 2])["served"][&"bread"])
	assert_true(_entry(houses, [26, 12])["served"][&"bread"])


# (c) Cutting the player's street breaks the chain, and the diagnostics name why.
func test_cutting_a_street_breaks_the_chain_and_the_panel_says_why() -> void:
	var diagnostics: Dictionary = _result("strip_cut_street").final_diagnostics
	assert_eq(_entry(diagnostics["buildings"], [16, 6])["reason"], &"no_road_access")
	assert_eq(_entry(diagnostics["buildings"], [18, 12])["reason"], &"no_route")
	assert_true(diagnostics["bread_causes"].has({"definition_id": &"mill", "reason": &"no_road_access"}),
		str(diagnostics["bread_causes"]))
