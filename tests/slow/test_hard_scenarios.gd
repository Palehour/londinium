extends GutTest

# Issue #128: the scripts of tests/scenarios/hard/ are the Normal ones rewritten for the 800 d of Hard. Playing
# them (75 and 150 min) does not fit in the CI time limit, so their 20 seeds are only in long/long_test_hard.gd
# (tools/run_long_tests); test_scenario_runner.gd checks the files. This one keeps the short finding of #128.

const PRESET: StringName = &"hard"
# The finding behind the 0.6 of crisis_recovery_hard (Cristian's decision in #128): at 0.4 the one-chain city
# runs out of money on Hard and empties. Seed 5 is the one that loses soonest (tick 1077), so the game is cut there.
const LOW_TAX: float = 0.4
const LOW_TAX_SEED: int = 5
const LOW_TAX_TICKS: int = 1200


# The "why?" of #73 will read the cause log (D-066): before the city empties it must name the lack of money (the
# wharf cannot pay for wheat) and the tax in force, and the money must run out before people leave out of hunger.
func test_crisis_recovery_at_low_tax_depopulates_and_the_causes_name_money_and_tax() -> void:
	var runner: ScenarioRunner = ScenarioRunner.create()
	assert_not_null(runner, "data/ must load")
	if runner == null:
		return
	assert_eq(runner.use_difficulty(PRESET), [] as Array[String])
	runner.keep_cause_events = true
	var scenario: Dictionary = ScenarioRunner.load_file("res://tests/scenarios/hard/crisis_recovery_hard.json")
	scenario["seed"] = LOW_TAX_SEED
	scenario["duration_ticks"] = LOW_TAX_TICKS
	for entry: Dictionary in scenario["commands"]:
		if entry["cmd"] == "set_tax":
			entry["rate"] = LOW_TAX
	var result: ScenarioResult = runner.run(scenario)
	assert_false(result.survived())
	assert_eq(result.final_row()["defeat_causes"], "depopulation")
	var no_money: int = _first_cause(result, &"building", "wharf", &"no_money_for_wheat")
	var tax: int = _first_cause(result, &"policy", "tax_rate", StringName(str(LOW_TAX)))
	var hunger: int = _first_cause(result, &"emigration", "worker", GrowthSystem.REASON_HUNGRY)
	assert_between(no_money, 0, result.defeat_tick, "the wharf runs out of money for wheat before the defeat")
	assert_between(tax, 0, result.defeat_tick, "the tax in force is in the log")
	assert_between(hunger, no_money, result.defeat_tick, "people leave out of hunger after the money runs out")


# First second the log gives `subject` (a building is "<id>@x,y", so only its prefix is compared) that cause; -1 if never.
func _first_cause(result: ScenarioResult, kind: StringName, subject: String, cause: StringName) -> int:
	for event: Dictionary in result.cause_events:
		if event["kind"] == kind and String(event["subject"]).get_slice("@", 0) == subject and event["cause"] == cause:
			return int(event["second"])
	return -1
