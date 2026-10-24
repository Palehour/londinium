class_name CholeraScenario
extends RefCounted

# Shared by the short and the long check of issue #202 (D-090): the scenario runs with the historic events on, and
# the recovery is the population ten minutes after the mission's close over the population just before its deaths.

const MISSION: String = "oldford"
const RECOVERY_WINDOW_MIN: int = 10


static func runner() -> ScenarioRunner:
	var runner: ScenarioRunner = ScenarioRunner.create()
	if runner != null:
		var events_on: Array[Modifier] = [Modifier.new(&"events.enabled", &"set", 1.0)]
		runner.use_modifiers(events_on)
	return runner


static func close_minute(runner: ScenarioRunner) -> int:
	return int(float(runner.param(&"events.cholera.trigger_min")))


static func status(result: ScenarioResult) -> StringName:
	return StringName(result.final_economy.get("missions", {}).get(MISSION, {}).get("status", ""))


# The row of the close is taken after the deaths, so the deaths are added back.
static func recovered_share(result: ScenarioResult, close: int) -> float:
	var deaths: int = int(result.final_economy["missions"][MISSION]["deaths"])
	var before: int = int(_row(result, close)["population"]) + deaths
	if before == 0:
		return 0.0
	return float(_row(result, close + RECOVERY_WINDOW_MIN)["population"]) / before


static func _row(result: ScenarioResult, minute: int) -> Dictionary:
	for row: Dictionary in result.rows:
		if int(row["minute"]) == minute:
			return row
	return {"population": 0}
