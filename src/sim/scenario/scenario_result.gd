class_name ScenarioResult
extends RefCounted

# One CSV row per game minute (0 = before the first tick), plus a last row at the final tick when
# the game does not end on a whole minute. Order here is the CSV order.
const CSV_COLUMNS: Array[String] = [
	"scenario", "minute", "tick", "population", "money", "bread_coverage", "satisfaction",
	"bread_coverage_instant", "satisfaction_target", "tax_rate", "bread_stock",
	"bread_produced_pm", "bread_consumed_pm", "bread_demand_pm", "taxes_pm", "wages_pm",
	"upkeep_pm", "wheat_spent_pm", "operating_balance_pm", "construction_pm", "wheat_price",
	"employed", "unemployed", "housing_capacity", "n_wharf", "n_mill", "n_bakery", "n_housing",
	"bankruptcy", "hunger", "depopulation", "defeat_causes",
]
# Float columns are printed with two decimals; everything else is printed as it is.
const FLOAT_COLUMNS: Array[String] = [
	"bread_coverage", "satisfaction", "bread_coverage_instant", "satisfaction_target", "tax_rate",
	"bread_produced_pm", "bread_consumed_pm", "bread_demand_pm", "taxes_pm", "wages_pm",
	"upkeep_pm", "wheat_spent_pm", "operating_balance_pm", "construction_pm",
]

var id: String = ""
var rows: Array[Dictionary] = []
# The economy dictionary of the last snapshot (EconomyState.to_dict()), for questions about the
# final state that the per-minute rows do not answer, such as DefeatSystem.is_city_stable().
var final_economy: Dictionary = {}
# First tick (1-based count of ticks run) with a defeat cause, or -1 if the city survived.
var defeat_tick: int = -1
var defeat_causes: Array[StringName] = []
# One entry per scripted command: {tick, cmd, accepted, reason, expect_reject}.
var commands: Array[Dictionary] = []
# Highest timer ever reached by each defeat condition, in seconds.
var max_timer: Dictionary[StringName, int] = {}
# Tick count at which each condition first showed a warning (or defeat); absent if never.
var first_warning_tick: Dictionary[StringName, int] = {}
# "building:reason" pairs the panel's bread diagnostics showed at any tick, e.g. "mill:missing_building".
var bread_cause_pairs: Dictionary[String, bool] = {}


func row(minute: int) -> Dictionary:
	return rows[minute]


func final_row() -> Dictionary:
	return rows[rows.size() - 1]


# Average of one column over minutes [from_minute, to_minute], both included.
func mean(column: String, from_minute: int, to_minute: int) -> float:
	var total: float = 0.0
	var count: int = 0
	for minute: int in range(from_minute, mini(to_minute, rows.size() - 1) + 1):
		total += float(rows[minute][column])
		count += 1
	return total / float(count) if count > 0 else 0.0


# Tick (0-based, as in `executed_tick`) at which the second wharf was actually bought, or -1. The
# purchase is the financing event: with wait_for_money it happens between two per-minute rows.
func second_chain_purchase_tick() -> int:
	var wharves: int = 0
	for entry: Dictionary in commands:
		if entry["cmd"] == "build" and entry["building"] == "wharf" and entry["accepted"]:
			wharves += 1
			if wharves == 2:
				return int(entry["executed_tick"])
	return -1


# Ticks at which the rule `rule_id` issued a command, in order.
func rule_firing_ticks(rule_id: String) -> Array[int]:
	var ticks: Array[int] = []
	for entry: Dictionary in commands:
		if entry["rule"] == rule_id:
			ticks.append(int(entry["executed_tick"]))
	return ticks


# Commands issued by any rule of the scenario.
func rule_command_count() -> int:
	var total: int = 0
	for entry: Dictionary in commands:
		if entry["rule"] != "":
			total += 1
	return total


func survived() -> bool:
	return defeat_tick < 0


func unexpected_rejections() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry: Dictionary in commands:
		# An accepted command only counts as expected when the script did not expect a refusal.
		var expected: StringName = entry["expect_reject"]
		var matches: bool = entry["reason"] == expected if not entry["accepted"] else expected == &""
		if not matches:
			found.append(entry)
	return found


static func csv_header() -> String:
	return ",".join(CSV_COLUMNS)


func csv_lines() -> Array[String]:
	var lines: Array[String] = []
	for values: Dictionary in rows:
		var cells: PackedStringArray = PackedStringArray()
		for column: String in CSV_COLUMNS:
			var value: Variant = values[column]
			cells.append("%.2f" % float(value) if column in FLOAT_COLUMNS else str(value))
		lines.append(",".join(cells))
	return lines
