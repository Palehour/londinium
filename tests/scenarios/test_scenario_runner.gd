extends GutTest

const MINUTES: int = 15

var _runner: ScenarioRunner


func before_each() -> void:
	_runner = ScenarioRunner.create()
	assert_not_null(_runner, "data/ must load")


func _scenario(commands: Array, seed_value: int = 42, duration: int = 900) -> Dictionary:
	return {"id": "unit", "seed": seed_value, "duration_ticks": duration, "commands": commands}


func _chain() -> Array:
	return [
		{"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 7]},
		{"tick": 0, "cmd": "build", "building": "mill", "cell": [2, 5]},
		{"tick": 0, "cmd": "build", "building": "bakery", "cell": [3, 5]},
	]


func test_valid_scenario_has_no_errors() -> void:
	assert_eq(_runner.validate(_scenario(_chain())).size(), 0)


func test_validation_rejects_bad_scripts() -> void:
	var cases: Dictionary[String, Array] = {
		"unknown cmd": [{"tick": 0, "cmd": "teleport"}],
		"unknown building": [{"tick": 0, "cmd": "build", "building": "castle", "cell": [1, 1]}],
		"cell outside the map": [{"tick": 0, "cmd": "demolish", "cell": [8, 0]}],
		"cell not a pair": [{"tick": 0, "cmd": "demolish", "cell": [1]}],
		"tick past the end": [{"tick": 900, "cmd": "set_tax", "rate": 0.5}],
		"negative tick": [{"tick": -1, "cmd": "set_tax", "rate": 0.5}],
		"ticks going backwards": [{"tick": 10, "cmd": "set_tax", "rate": 0.5}, {"tick": 5, "cmd": "set_tax", "rate": 0.4}],
		"tax is not a number": [{"tick": 0, "cmd": "set_tax", "rate": "high"}],
		"purchases flag missing": [{"tick": 0, "cmd": "set_wheat_purchases"}],
	}
	for label: String in cases:
		assert_gt(_runner.validate(_scenario(cases[label])).size(), 0, label)


func test_validation_rejects_missing_header_fields() -> void:
	assert_gt(_runner.validate({"commands": []}).size(), 0)
	assert_gt(_runner.validate({"id": "x", "seed": 1, "duration_ticks": 0, "commands": []}).size(), 0)
	assert_gt(_runner.validate({"id": "x", "seed": 1, "duration_ticks": 10}).size(), 0)


func test_rejected_command_is_reported_unless_expected() -> void:
	# The wharf only goes on river cells (y = 7), so this build is refused.
	var script: Array = [{"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 5]}]
	var result: ScenarioResult = _runner.run(_scenario(script, 42, 60))
	assert_eq(result.unexpected_rejections().size(), 1)
	assert_eq(result.unexpected_rejections()[0]["reason"], &"requires_river")
	script[0]["expect_reject"] = "requires_river"
	assert_eq(_runner.run(_scenario(script, 42, 60)).unexpected_rejections().size(), 0)


func test_expected_rejection_that_succeeds_is_reported() -> void:
	# Housing on a land cell is accepted; the script claims it should be refused.
	var script: Array = [{"tick": 0, "cmd": "build", "building": "housing", "cell": [5, 3], "expect_reject": "insufficient_money"}]
	var result: ScenarioResult = _runner.run(_scenario(script, 42, 60))
	assert_eq(result.unexpected_rejections().size(), 1)
	assert_true(result.unexpected_rejections()[0]["accepted"])


func test_expected_rejection_with_a_different_reason_is_reported() -> void:
	var script: Array = [{"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 5], "expect_reject": "insufficient_money"}]
	assert_eq(_runner.run(_scenario(script, 42, 60)).unexpected_rejections().size(), 1)


func test_accepted_commands_are_logged() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_chain(), 42, 60))
	assert_eq(result.commands.size(), 3)
	assert_eq(result.unexpected_rejections().size(), 0)


func test_command_runs_before_the_tick_it_is_scheduled_on() -> void:
	var script: Array = [{"tick": 70, "cmd": "build", "building": "housing", "cell": [5, 3]}]
	var result: ScenarioResult = _runner.run(_scenario(script, 42, 180))
	assert_eq(result.row(1)["n_housing"], 0, "tick 70 is after minute 1")
	assert_eq(result.row(2)["n_housing"], 1)


func test_same_seed_gives_the_same_series() -> void:
	var first: ScenarioResult = _runner.run(_scenario(_chain(), 7))
	var second: ScenarioResult = _runner.run(_scenario(_chain(), 7))
	assert_eq(first.csv_lines(), second.csv_lines())
	assert_eq(first.defeat_tick, second.defeat_tick)


func test_other_seed_changes_the_wheat_market() -> void:
	var first: ScenarioResult = _runner.run(_scenario(_chain(), 1))
	var second: ScenarioResult = _runner.run(_scenario(_chain(), 2))
	assert_ne(first.csv_lines(), second.csv_lines())


func test_csv_has_one_row_per_minute_with_every_column() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_chain()))
	var lines: Array[String] = result.csv_lines()
	assert_eq(lines.size(), MINUTES + 1, "minutes 0 to 15")
	var width: int = ScenarioResult.CSV_COLUMNS.size()
	assert_eq(ScenarioResult.csv_header().split(",").size(), width)
	for line: String in lines:
		assert_eq(line.split(",").size(), width, line)
	for required: String in ["population", "money", "bread_coverage", "satisfaction"]:
		assert_true(required in ScenarioResult.CSV_COLUMNS, required)
	assert_eq(result.row(MINUTES)["tick"], 900)


func test_defeat_freezes_the_series_and_records_the_tick() -> void:
	# An empty city loses by depopulation at tick 480 with the current data.
	var result: ScenarioResult = _runner.run(_scenario([]))
	assert_false(result.survived())
	assert_gt(result.defeat_tick, 0)
	assert_eq(result.rows.size(), MINUTES + 1, "the run keeps going to the full duration")
	assert_eq(result.final_row()["defeat_causes"], "depopulation")


func test_scenario_files_are_valid_and_named_after_their_ids() -> void:
	var paths: Array[String] = ScenarioRunner.scenario_paths()
	assert_gt(paths.size(), 0)
	var seen: Dictionary[String, bool] = {}
	for path: String in paths:
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		assert_false(scenario.is_empty(), "%s is not a JSON object" % path)
		assert_eq(_runner.validate(scenario), [] as Array[String], path)
		assert_eq(String(scenario.get("id", "")), path.get_file().get_basename(), path)
		assert_false(seen.has(scenario["id"]), "duplicate id %s" % scenario["id"])
		seen[scenario["id"]] = true
		assert_eq(int(scenario["duration_ticks"]), 900, "15 minutes: %s" % path)


func test_missing_file_loads_as_empty() -> void:
	assert_true(ScenarioRunner.load_file("res://tests/scenarios/nope.json").is_empty())
