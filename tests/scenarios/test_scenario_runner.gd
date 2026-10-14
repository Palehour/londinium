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


func test_pinned_wheat_price_holds_for_every_draw_and_changes_only_that_runner() -> void:
	_runner.pin_wheat_price(2)
	var result: ScenarioResult = _runner.run(_scenario(_chain()))
	for minute: int in range(MINUTES + 1):
		assert_eq(result.row(minute)["wheat_price"], 2, "minute %d" % minute)
	var untouched: ScenarioRunner = ScenarioRunner.create()
	assert_eq(untouched.param(&"market.wheat.min_price"), 1)
	assert_eq(untouched.param(&"market.wheat.max_price"), 3)


func _extra_chain(first_extra: Dictionary) -> Array:
	var wharf: Dictionary = {"tick": 60, "cmd": "build", "building": "wharf", "cell": [4, 7]}
	wharf.merge(first_extra)
	# A high tax so the first chain's profit can pay for the second one.
	return [{"tick": 0, "cmd": "set_tax", "rate": 0.7}] + _chain() + [wharf,
		{"tick": 60, "cmd": "build", "building": "mill", "cell": [4, 5], "with_previous": true},
		{"tick": 60, "cmd": "build", "building": "bakery", "cell": [5, 5], "with_previous": true}]


func test_wait_for_money_buys_the_group_in_one_tick_once_the_treasury_reaches_it() -> void:
	var price: int = 540
	var result: ScenarioResult = _runner.run(_scenario(_extra_chain({"wait_for_money": price})))
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary])
	var executed: Array[int] = []
	for entry: Dictionary in result.commands:
		if entry["tick"] == 60:
			executed.append(entry["executed_tick"])
	assert_eq(executed.size(), 3)
	assert_eq(executed[0], executed[1], "with_previous runs in the same tick")
	assert_eq(executed[1], executed[2])
	assert_gt(executed[0], 60, "it waited: the treasury is below 540 after the first chain")
	assert_lt(int(result.row(executed[0] / 60)["money"]), price, "at the start of that minute it did not have the money yet")
	assert_eq(result.final_row()["n_wharf"], 2)
	assert_eq(result.final_row()["n_bakery"], 2)


func test_command_that_never_gets_its_money_is_reported_as_never_run() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_extra_chain({"wait_for_money": 1000000})))
	var never: Array[Dictionary] = result.unexpected_rejections()
	assert_eq(never.size(), 3)
	for entry: Dictionary in never:
		assert_eq(entry["reason"], &"never_ran")
		assert_eq(entry["executed_tick"], -1)
	assert_eq(result.final_row()["n_wharf"], 1)


func test_validation_of_wait_for_money_and_with_previous() -> void:
	var cases: Dictionary[String, Array] = {
		"negative wait": [{"tick": 0, "cmd": "set_tax", "rate": 0.5, "wait_for_money": -1}],
		"fractional wait": [{"tick": 0, "cmd": "set_tax", "rate": 0.5, "wait_for_money": 10.5}],
		"with_previous first": [{"tick": 0, "cmd": "set_tax", "rate": 0.5, "with_previous": true}],
		"with_previous not a boolean": [{"tick": 0, "cmd": "set_tax", "rate": 0.5},
			{"tick": 0, "cmd": "set_tax", "rate": 0.4, "with_previous": 1}],
		"with_previous at a different tick": [{"tick": 0, "cmd": "set_tax", "rate": 0.5},
			{"tick": 60, "cmd": "set_tax", "rate": 0.4, "with_previous": true}],
		"with_previous and wait": [{"tick": 0, "cmd": "set_tax", "rate": 0.5},
			{"tick": 0, "cmd": "set_tax", "rate": 0.4, "with_previous": true, "wait_for_money": 5}],
	}
	for label: String in cases:
		assert_gt(_runner.validate(_scenario(cases[label])).size(), 0, label)
	assert_eq(_runner.validate(_scenario(_extra_chain({"wait_for_money": 540}))).size(), 0)


func _city_with_mill_crisis(demolish_tick: int, rebuild_tick: int) -> Array:
	var commands: Array = [{"tick": 0, "cmd": "set_tax", "rate": 0.5}] + _chain() + [
		{"tick": 0, "cmd": "build", "building": "housing", "cell": [5, 3]},
		{"tick": 0, "cmd": "build", "building": "housing", "cell": [6, 3]},
		{"tick": demolish_tick, "cmd": "demolish", "cell": [2, 5]}]
	if rebuild_tick > 0:
		commands.append({"tick": rebuild_tick, "cmd": "build", "building": "mill", "cell": [2, 5]})
	return commands


func test_a_city_recovering_in_minutes_13_to_15_counts_as_stable() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_city_with_mill_crisis(660, 780)))
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary])
	assert_lt(int(result.final_row()["population"]), int(result.row(12)["population"]),
		"smaller than at minute 12, which a population-delta proxy would call unstable")
	assert_gte(float(result.final_row()["bread_coverage"]), 0.95)
	assert_true(_runner.is_stable(result), "the simulation's own rule: nobody is leaving")


func test_a_city_still_starving_at_the_end_is_not_stable() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_city_with_mill_crisis(780, 0)))
	assert_lt(float(result.final_row()["bread_coverage"]), 0.6)
	assert_false(_runner.is_stable(result))


func test_second_chain_purchase_tick_is_the_real_tick_not_a_minute_row() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_extra_chain({"wait_for_money": 540})))
	var tick: int = result.second_chain_purchase_tick()
	var executed: int = -1
	for entry: Dictionary in result.commands:
		if entry["tick"] == 60 and entry["building"] == "wharf":
			executed = entry["executed_tick"]
	assert_gt(tick, 60)
	assert_eq(tick, executed)
	# The purchase falls between two per-minute rows: one chain before, two right after.
	assert_eq(result.row(tick / 60)["n_wharf"], 1)
	assert_eq(result.row(tick / 60 + 1)["n_wharf"], 2)
	assert_eq(_runner.run(_scenario(_chain())).second_chain_purchase_tick(), -1, "one chain only")


func test_with_tax_skips_exactly_the_scenarios_that_say_tax_override_false() -> void:
	var commands: Array = [{"tick": 0, "cmd": "set_tax", "rate": 0.0}]
	var plain: Dictionary = {"id": "small_rich", "seed": 1, "duration_ticks": 10, "commands": commands}
	var opted_out: Dictionary = {"id": "anything", "tax_override": false, "seed": 1, "duration_ticks": 10,
		"commands": commands}
	var opted_in: Dictionary = {"id": "defeat_by_name_only", "tax_override": true, "seed": 1,
		"duration_ticks": 10, "commands": commands}
	assert_eq(ScenarioRunner.with_tax(plain, 0.6)["commands"][0]["rate"], 0.6)
	assert_eq(ScenarioRunner.with_tax(opted_in, 0.6)["commands"][0]["rate"], 0.6, "the id prefix decides nothing")
	assert_eq(ScenarioRunner.with_tax(opted_out, 0.6)["commands"][0]["rate"], 0.0)
	assert_eq(plain["commands"][0]["rate"], 0.0, "the original is not modified")
	opted_out["tax_override"] = "no"
	assert_gt(_runner.validate(opted_out).size(), 0, "tax_override must be a boolean")


func test_every_defeat_scenario_opts_out_of_the_tax_override() -> void:
	for path: String in ScenarioRunner.scenario_paths():
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		if String(scenario["id"]).begins_with("defeat_"):
			assert_eq(scenario.get("tax_override"), false, scenario["id"])


func test_a_game_that_ends_mid_minute_gets_a_last_row_with_the_terminal_state() -> void:
	var result: ScenarioResult = _runner.run(_scenario(_chain(), 42, 90))
	assert_eq(result.rows.size(), 3, "minute 0, minute 1 and the partial row")
	assert_eq(result.final_row()["tick"], 90)
	assert_eq(result.final_row()["minute"], 2)
	assert_eq(result.final_row()["money"], result.final_economy["money"], "final_row is the terminal state")
	assert_eq(result.final_row()["population"], result.final_economy["population"])
	assert_ne(result.row(1)["tick"], result.final_row()["tick"])
	var whole: ScenarioResult = _runner.run(_scenario(_chain(), 42, 120))
	assert_eq(whole.rows.size(), 3, "no extra row when the game ends on a whole minute")
	assert_eq(whole.final_row()["tick"], 120)


func test_a_wait_after_commands_of_the_same_tick_sees_what_they_spent() -> void:
	# The first chain is queued at tick 0 and has not touched the treasury yet. A wait for 540 behind
	# it must not be released by the 1050 of the starting treasury: after the chain only 510 is left.
	var commands: Array = [{"tick": 0, "cmd": "set_tax", "rate": 0.7}] + _chain() + [
		{"tick": 0, "cmd": "build", "building": "wharf", "cell": [4, 7], "wait_for_money": 540},
		{"tick": 0, "cmd": "build", "building": "mill", "cell": [4, 5], "with_previous": true},
		{"tick": 0, "cmd": "build", "building": "bakery", "cell": [5, 5], "with_previous": true}]
	var result: ScenarioResult = _runner.run(_scenario(commands))
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary], "the group was not released on stale funds")
	var tick: int = result.second_chain_purchase_tick()
	# Released on stale funds it would have run at tick 0 and the bakery would have been refused.
	assert_gt(tick, 0, "it waited for the first chain's profit")
	assert_eq(result.final_row()["n_wharf"], 2)


# A wait that is already satisfied must not lose a tick to commands that cannot change the treasury.
func _wait_executed_tick(first: Dictionary, tick: int, duration: int) -> int:
	var waiting: Dictionary = {"tick": tick, "cmd": "set_tax", "rate": 0.4, "wait_for_money": 100}
	var result: ScenarioResult = _runner.run(_scenario([first, waiting], 42, duration))
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary])
	assert_eq(result.commands.size(), 2)
	return int(result.commands[1]["executed_tick"])


func test_a_wait_is_not_postponed_by_a_set_tax_in_the_same_tick() -> void:
	assert_eq(_wait_executed_tick({"tick": 0, "cmd": "set_tax", "rate": 0.5}, 0, 60), 0)


func test_a_wait_is_not_postponed_by_a_set_wheat_purchases_in_the_same_tick() -> void:
	assert_eq(_wait_executed_tick({"tick": 0, "cmd": "set_wheat_purchases", "enabled": false}, 0, 60), 0)


func test_a_wait_is_not_postponed_by_a_refused_command_in_the_same_tick() -> void:
	# A wharf on a land cell is refused (requires_river), so it spends nothing.
	var refused: Dictionary = {"tick": 0, "cmd": "build", "building": "wharf", "cell": [2, 5],
		"expect_reject": "requires_river"}
	assert_eq(_wait_executed_tick(refused, 0, 60), 0)


func test_a_wait_on_the_last_tick_still_runs_after_a_non_spending_command() -> void:
	var result: ScenarioResult = _runner.run(_scenario([{"tick": 9, "cmd": "set_tax", "rate": 0.5},
		{"tick": 9, "cmd": "set_tax", "rate": 0.4, "wait_for_money": 100}], 42, 10))
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary], "not reported as never_ran")
	assert_eq(int(result.commands[1]["executed_tick"]), 9)


func test_a_wait_is_postponed_only_when_an_accepted_build_takes_it_below_the_amount() -> void:
	# Housing costs 60 and leaves 990, still above 100: nothing to wait for.
	var cheap: Dictionary = {"tick": 0, "cmd": "build", "building": "housing", "cell": [5, 3]}
	assert_eq(_wait_executed_tick(cheap, 0, 60), 0)
	# The same housing against a wait for 1050 (the whole starting treasury) does have to wait.
	var result: ScenarioResult = _runner.run(_scenario([cheap,
		{"tick": 0, "cmd": "set_tax", "rate": 0.7, "wait_for_money": 1050}], 42, 600))
	# With no income the treasury never gets back to 1050, so it may not run at all; what matters is
	# that it did not run in tick 0 against the 1050 the treasury had before the housing was paid.
	assert_ne(int(result.commands[1]["executed_tick"]), 0, "60 pence were spent, so 1050 is out of reach at tick 0")


func test_a_wait_after_a_build_in_a_lost_game_ends_as_simulation_defeated_not_never_ran() -> void:
	# Nobody lives here, so the city is lost at about tick 480 with the whole 1050 still in the
	# treasury. On the last tick the build is refused by the defeat; if the preview counted it as
	# spending 60, the wait for 1050 would be postponed past the end and show up as never_ran.
	var commands: Array = [
		{"tick": 599, "cmd": "build", "building": "housing", "cell": [5, 3], "expect_reject": "simulation_defeated"},
		{"tick": 599, "cmd": "set_tax", "rate": 0.4, "wait_for_money": 1050, "expect_reject": "simulation_defeated"}]
	var result: ScenarioResult = _runner.run(_scenario(commands, 42, 600))
	assert_gt(result.defeat_tick, 0, "the game was lost before the last tick")
	assert_lt(result.defeat_tick, 599)
	assert_eq(result.final_economy["money"], 1050, "the treasury did not move")
	assert_eq(result.commands.size(), 2)
	assert_eq(result.commands[1]["reason"], &"simulation_defeated")
	assert_eq(int(result.commands[1]["executed_tick"]), 599, "it ran on its tick instead of being left waiting")
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary])


# --- Issue #55: stock schedule, measure, in_all and the grain sweep ---

func test_long_scenario_files_are_valid_and_named_after_their_ids() -> void:
	var paths: Array[String] = ScenarioRunner.long_scenario_paths()
	assert_gt(paths.size(), 0)
	var left_out: Array[String] = []
	for path: String in paths:
		var scenario: Dictionary = ScenarioRunner.load_file(path)
		assert_false(scenario.is_empty(), "%s is not a JSON object" % path)
		assert_eq(_runner.validate(scenario), [] as Array[String], path)
		assert_eq(String(scenario.get("id", "")), path.get_file().get_basename(), path)
		if scenario.get("in_all", true) == false:
			left_out.append(String(scenario["id"]))
	# Only the hours-long drift games are too slow for balance_report --scenario all.
	assert_eq(left_out, ["drift_4h", "drift_8h"] as Array[String])


func test_validation_rejects_bad_stock_schedules_measures_and_in_all() -> void:
	var cases: Dictionary[String, Dictionary] = {
		"in_all not a bool": {"in_all": "no"},
		"stock schedule not a list": {"stock_schedule": {}},
		"unknown good": {"stock_schedule": [{"tick": 0, "good": "gin", "amount": 0}]},
		"negative amount": {"stock_schedule": [{"tick": 0, "good": "beer", "amount": -1}]},
		"stock tick past the end": {"stock_schedule": [{"tick": 900, "good": "beer", "amount": 0}]},
		"stock ticks going backwards": {"stock_schedule": [{"tick": 10, "good": "beer", "amount": 0},
			{"tick": 5, "good": "beer", "amount": 0}]},
		"measure not an object": {"measure": []},
		"unknown measure": {"measure": {"wealth": true}},
		"tax window past the end": {"measure": {"tax_window": [10, 16]}},
		"tax window backwards": {"measure": {"tax_window": [10, 5]}},
		"beer back before the cut": {"measure": {"beer_cut": {"from_minute": 5, "back_minute": 5,
			"recovery_minutes": 2, "recovered_share": 0.8}}},
		"recovery past the end": {"measure": {"beer_cut": {"from_minute": 5, "back_minute": 10,
			"recovery_minutes": 6, "recovered_share": 0.8}}},
		"share above one": {"measure": {"beer_cut": {"from_minute": 5, "back_minute": 10,
			"recovery_minutes": 5, "recovered_share": 1.5}}},
		"hourly in a short game": {"measure": {"hourly": true}},
	}
	for label: String in cases:
		var scenario: Dictionary = _scenario(_chain())
		scenario.merge(cases[label], true)
		assert_gt(_runner.validate(scenario).size(), 0, label)
	var good: Dictionary = _scenario(_chain())
	good.merge({"in_all": false, "stock_schedule": [{"tick": 0, "good": "beer", "amount": 0}],
		"measure": {"tax_window": [10, 15], "beer_cut": {"from_minute": 5, "back_minute": 10,
			"recovery_minutes": 5, "recovered_share": 0.8}}}, true)
	assert_eq(_runner.validate(good), [] as Array[String])


func test_stock_schedule_sets_the_store_before_the_tick_it_is_scheduled_on() -> void:
	# Malt with no brewery and no spoilage stays where the schedule puts it, so the rows show it exactly.
	var scenario: Dictionary = _scenario(_chain())
	scenario["stock_schedule"] = [{"tick": 0, "good": "malt", "amount": 25},
		{"tick": 300, "good": "malt", "amount": 0}]
	var result: ScenarioResult = _runner.run(scenario)
	assert_eq(result.unexpected_rejections(), [] as Array[Dictionary])
	assert_eq(int(result.row(0)["malt_stock"]), 0, "minute 0 is before the first tick")
	assert_eq(int(result.row(1)["malt_stock"]), 25)
	assert_eq(int(result.row(5)["malt_stock"]), 25, "row 5 is written after tick 299")
	assert_eq(int(result.row(6)["malt_stock"]), 0, "tick 300 is the first tick of minute 6")
	assert_eq(int(result.row(MINUTES)["malt_stock"]), 0)


func test_with_barley_percent_replaces_only_the_unloading_split() -> void:
	var scenario: Dictionary = _scenario([{"tick": 0, "cmd": "set_unloading_split", "barley_percent": 15},
		{"tick": 0, "cmd": "set_tax", "rate": 0.4}])
	var swept: Dictionary = ScenarioRunner.with_barley_percent(scenario, 30)
	assert_eq(swept["commands"][0]["barley_percent"], 30)
	assert_eq(swept["commands"][1], {"tick": 0, "cmd": "set_tax", "rate": 0.4})
	assert_eq(scenario["commands"][0]["barley_percent"], 15, "the original is not modified")


func _measured_result(columns: Dictionary[String, Array]) -> ScenarioResult:
	var result: ScenarioResult = ScenarioResult.new()
	var count: int = columns.values()[0].size()
	for minute: int in range(count):
		var values: Dictionary = {}
		for column: String in columns:
			values[column] = columns[column][minute]
		result.rows.append(values)
	return result


func test_tax_window_is_the_mean_of_taxes_per_minute_over_both_ends() -> void:
	var result: ScenarioResult = _measured_result({"taxes_pm": [0.0, 10.0, 20.0, 30.0, 99.0]})
	assert_eq(result.measured({"tax_window": [1, 3]}), {"taxes_pm_window": 20.0})
	assert_eq(result.measured({}), {}, "no measure, no extra metrics")


func test_beer_cut_counts_the_artisans_lost_and_the_minutes_to_recover() -> void:
	# Cut at minute 1 with 10 artisans, beer back at minute 3: 80 % (8) is reached at minute 5, two minutes later.
	var result: ScenarioResult = _measured_result({"artisan_population": [10, 10, 6, 5, 7, 8, 9]})
	var cut: Dictionary = {"from_minute": 1, "back_minute": 3, "recovery_minutes": 3, "recovered_share": 0.8}
	var found: Dictionary = result.measured({"beer_cut": cut})
	assert_eq(found["artisans_before_cut"], 10.0)
	assert_eq(found["artisans_lowest_after_cut"], 5.0)
	assert_eq(found["artisans_lost_in_cut"], 5.0)
	assert_eq(found["artisans_recovery_minutes"], 2)
	assert_eq(found["artisans_recovered"], 1)
	cut["recovery_minutes"] = 1
	assert_eq(result.measured({"beer_cut": cut})["artisans_recovered"], 0, "minute 5 is outside the window")
	assert_eq(result.measured({"beer_cut": cut})["artisans_recovery_minutes"], -1)


func test_beer_cut_with_no_artisans_before_it_is_not_a_recovery() -> void:
	var result: ScenarioResult = _measured_result({"artisan_population": [0, 0, 0, 0, 0]})
	var cut: Dictionary = {"from_minute": 1, "back_minute": 2, "recovery_minutes": 2, "recovered_share": 0.8}
	var found: Dictionary = result.measured({"beer_cut": cut})
	assert_eq(found["artisans_recovered"], 0)
	assert_eq(found["artisans_recovery_minutes"], -1)


func test_hourly_drift_starts_after_the_first_hour() -> void:
	# Three hours: money climbs 100 per minute after minute 60 and dips under zero twice in the first hour.
	var money: Array = []
	var bread: Array = []
	var beer: Array = []
	for minute: int in range(181):
		money.append(-5 if minute in [10, 11] else maxi(0, minute - 60) * 100)
		bread.append(0.5 if minute == 30 else (0.9 if minute == 150 else 1.0))
		beer.append(0.0 if minute < 60 else 0.7)
	var result: ScenarioResult = _measured_result({"money": money, "bread_coverage": bread, "beer_coverage": beer})
	var found: Dictionary = result.measured({"hourly": true})
	assert_eq(found["money_drift_per_hour"], 6000.0)
	assert_eq(found["bread_coverage_lowest_after_hour1"], 0.9, "minute 30 is still the build-up")
	assert_eq(found["beer_coverage_lowest_after_hour1"], 0.7)
	assert_eq(found["minutes_in_debt"], 2)
	assert_eq(result.lowest_per_hour("bread_coverage"), [1.0, 0.9] as Array[float])
