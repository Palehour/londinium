class_name ScenarioRunner
extends RefCounted

# Runs scripted games on the pure simulation: no nodes, no clock, no UI. Same seed and same
# command list always give the same ScenarioResult (docs/ARCHITECTURE.md, principle 2).
# It lives in src/ because both tests/ and tools/balance_report.gd use it; it reads the scenario
# files only through load_file()/scenario_paths(), never from game code.

const SCENARIO_DIR: String = "res://tests/scenarios"
const TICKS_PER_MINUTE: int = 60
const COMMAND_NAMES: Array[String] = ["build", "demolish", "set_tax", "set_wheat_purchases"]
# What a rule may look at (EconomyState.to_dict() keys) and what it may do. Only commands that set
# a switch or a rate: a rule that built or demolished would repeat itself on every edge.
const RULE_PATHS: Array[String] = ["wheat_price", "money", "population", "stocks.wheat", "stocks.flour",
	"stocks.bread"]
const RULE_OPERATORS: Array[String] = ["==", "!=", "<", "<=", ">", ">="]
const RULE_ACTIONS: Array[String] = ["set_wheat_purchases", "set_tax"]
const RULE_MAX_DEPTH: int = 3
const CONDITIONS: Array[StringName] = [&"bankruptcy", &"hunger", &"depopulation"]

var _catalog: DataCatalog
var _params: Params
var _context: EconomyContext
var _map_id: StringName = &"whitechapel_1850s"


# Returns null (and logs the errors) when data/ does not load.
static func create() -> ScenarioRunner:
	var loaded: DataLoadResult = DataLoader.new().load_all()
	if not loaded.is_ok():
		push_error("ScenarioRunner: data did not load: %s" % str(loaded.errors))
		return null
	var runner: ScenarioRunner = ScenarioRunner.new()
	runner._catalog = loaded.catalog
	runner._params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
	runner._context = EconomyContext.new(loaded.catalog, loaded.catalog.maps[runner._map_id])
	return runner


# Read-only view of a parameter, so tests derive timings from data/ instead of copying them.
func param(key: StringName) -> Variant:
	return _params.get_value(key)


# Balance probes only: every draw of the wheat price becomes `price`. It changes this runner's
# copy of the values, never the files in data/.
func pin_wheat_price(price: int) -> void:
	for key: StringName in [&"market.wheat.base_price", &"market.wheat.min_price", &"market.wheat.max_price"]:
		_catalog.base_values[key] = price
	_params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])


static func scenario_paths() -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(SCENARIO_DIR)
	if dir == null:
		return found
	for entry: String in dir.get_files():
		if entry.ends_with(".json"):
			found.append(SCENARIO_DIR.path_join(entry))
	found.sort()
	return found


# An empty dictionary means the file is missing or is not a JSON object.
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func validate(scenario: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if scenario.get("id", "") is not String or String(scenario.get("id", "")) == "":
		errors.append("id must be a non-empty string")
	if not _is_whole(scenario.get("seed")):
		errors.append("seed must be an integer")
	var duration: int = int(scenario.get("duration_ticks", 0)) if _is_whole(scenario.get("duration_ticks")) else 0
	if duration <= 0:
		errors.append("duration_ticks must be a positive integer")
	if scenario.get("commands") is not Array:
		errors.append("commands must be a list")
		return errors
	if scenario.has("tax_override") and scenario["tax_override"] is not bool:
		errors.append("tax_override must be true or false")
	if scenario.has("rules"):
		errors.append_array(_validate_rules(scenario["rules"]))
	var previous_tick: int = 0
	var command_before_tick: int = -1
	var index: int = 0
	for entry: Variant in scenario["commands"]:
		errors.append_array(_validate_command(entry, index, duration, previous_tick, command_before_tick))
		var declared: bool = entry is Dictionary and _is_whole(entry.get("tick"))
		command_before_tick = int(entry["tick"]) if declared else -1
		if declared:
			previous_tick = maxi(previous_tick, int(entry["tick"]))
		index += 1
	return errors


func run(scenario: Dictionary) -> ScenarioResult:
	var errors: Array[String] = validate(scenario)
	assert(errors.is_empty(), "Invalid scenario: %s" % str(errors))
	var result: ScenarioResult = ScenarioResult.new()
	result.id = String(scenario["id"])
	for condition: StringName in CONDITIONS:
		result.max_timer[condition] = 0
	var sim: Simulation = Simulation.create_new(_params, _initial_state(), int(scenario["seed"]), _context)
	var script: Array = scenario["commands"]
	var issued: Array[Dictionary] = []
	var next_command: int = 0
	var rules: Array = scenario.get("rules", [])
	var rule_holds: Array[bool] = []
	rule_holds.resize(rules.size())
	rule_holds.fill(false)
	var snapshot: Dictionary = sim.snapshot()
	result.rows.append(_row(result.id, 0, 0, snapshot))
	for tick_index: int in range(int(scenario["duration_ticks"])):
		var ran_this_tick: bool = false
		while next_command < script.size() and _is_due(script[next_command], tick_index, sim, ran_this_tick):
			var entry: Dictionary = script[next_command]
			var command: SimulationCommand = _make_command(entry)
			sim.apply_command(command)
			issued.append({"entry": entry, "command": command, "tick": tick_index})
			ran_this_tick = true
			next_command += 1
		# Rules look at the state the previous tick left, so what they order runs in this tick.
		for rule_index: int in range(rules.size()):
			var rule: Dictionary = rules[rule_index]
			var holds: bool = _condition_holds(rule["when"], snapshot["economy"])
			if holds == rule_holds[rule_index]:
				continue
			rule_holds[rule_index] = holds
			var action: Variant = rule["then"] if holds else rule.get("otherwise")
			if action == null:
				continue
			var ordered: Dictionary = action.duplicate()
			ordered["tick"] = tick_index
			ordered["rule"] = String(rule["id"])
			var rule_command: SimulationCommand = _make_command(ordered)
			sim.apply_command(rule_command)
			issued.append({"entry": ordered, "command": rule_command, "tick": tick_index})
		sim.tick()
		# After a defeat the state is frozen, so the last snapshot stays valid.
		if result.defeat_tick < 0:
			snapshot = sim.snapshot()
			_observe(result, snapshot, tick_index + 1)
		if (tick_index + 1) % TICKS_PER_MINUTE == 0:
			result.rows.append(_row(result.id, (tick_index + 1) / TICKS_PER_MINUTE, tick_index + 1, snapshot))
	# A game that does not end on a whole minute gets a last, partial-minute row, so final_row()
	# is the state final_economy describes and not one up to 59 ticks older.
	var duration_ticks: int = int(scenario["duration_ticks"])
	if duration_ticks % TICKS_PER_MINUTE != 0:
		@warning_ignore("integer_division")
		var last_minute: int = duration_ticks / TICKS_PER_MINUTE + 1
		result.rows.append(_row(result.id, last_minute, duration_ticks, snapshot))
	result.final_economy = snapshot["economy"]
	for item: Dictionary in issued:
		var done: SimulationCommand = item["command"]
		var source: Dictionary = item["entry"]
		result.commands.append({"tick": int(source["tick"]), "executed_tick": int(item["tick"]),
			"cmd": String(source["cmd"]), "building": String(source.get("building", "")),
			"rule": String(source.get("rule", "")), "accepted": done.accepted, "reason": done.reason,
			"expect_reject": StringName(source.get("expect_reject", ""))})
	# A command still waiting for its money when the game ends never ran; that counts as a refusal.
	for pending: int in range(next_command, script.size()):
		result.commands.append({"tick": int(script[pending]["tick"]), "executed_tick": -1,
			"cmd": String(script[pending]["cmd"]), "building": String(script[pending].get("building", "")),
			"rule": "", "accepted": false, "reason": &"never_ran",
			"expect_reject": StringName(script[pending].get("expect_reject", ""))})
	return result


# Same predicate the simulation uses for "nobody is leaving", evaluated on the final state.
func is_stable(result: ScenarioResult) -> bool:
	return DefeatSystem.new().is_city_stable(EconomyState.from_dict(result.final_economy), _params)


# Copy of `scenario` with every set_tax rate replaced, for probes: the commands and the actions of
# the rules (otherwise a rule that fires would put its own rate back). A scenario with
# "tax_override": false is left alone: its tax rate is part of what it demonstrates (the defeat_*
# ones lose partly because of it), so overriding it would change the scenario itself.
static func with_tax(scenario: Dictionary, rate: float) -> Dictionary:
	var copy: Dictionary = scenario.duplicate(true)
	if copy.get("tax_override", true) == false:
		return copy
	var actions: Array = []
	actions.append_array(copy["commands"])
	for rule: Dictionary in copy.get("rules", []):
		actions.append(rule["then"])
		if rule.has("otherwise"):
			actions.append(rule["otherwise"])
	for action: Dictionary in actions:
		if action["cmd"] == "set_tax":
			action["rate"] = rate
	return copy


# Commands run in order. `tick` is the earliest tick; `wait_for_money` holds the command back
# until the treasury reaches that amount, and `with_previous` runs it in the same tick as the
# command before it, so a purchase made of several buildings is priced once.
func _is_due(entry: Dictionary, tick_index: int, sim: Simulation, ran_this_tick: bool) -> bool:
	if entry.get("with_previous", false):
		return ran_this_tick
	if tick_index < int(entry["tick"]):
		return false
	if entry.has("wait_for_money"):
		return int(sim.snapshot()["economy"]["money"]) >= int(entry["wait_for_money"])
	return true


func _initial_state() -> EconomyState:
	# Same startup as GameSession; the scenario only overrides the seed.
	var state: EconomyState = EconomyState.new()
	state.money = int(_params.get_value(&"startup.money"))
	state.population = int(_params.get_value(&"startup.population"))
	state.wheat_purchases_enabled = _params.get_value(&"startup.wheat_purchases_enabled")
	return state


func _make_command(entry: Dictionary) -> SimulationCommand:
	match String(entry["cmd"]):
		"build":
			var cell: Array = entry["cell"]
			return BuildCommand.new(_context, StringName(entry["building"]), Vector2i(int(cell[0]), int(cell[1])))
		"demolish":
			var target: Array = entry["cell"]
			return DemolishCommand.new(Vector2i(int(target[0]), int(target[1])))
		"set_tax":
			return SetTaxCommand.new(float(entry["rate"]))
		_:
			return SetWheatPurchasesCommand.new(bool(entry["enabled"]))


func _observe(result: ScenarioResult, snapshot: Dictionary, tick_count: int) -> void:
	var defeat: Dictionary = snapshot["defeat"]
	for condition: StringName in CONDITIONS:
		var status: Dictionary = defeat[condition]
		result.max_timer[condition] = maxi(result.max_timer[condition], int(status["elapsed_seconds"]))
		if status["status"] != &"ok" and not result.first_warning_tick.has(condition):
			result.first_warning_tick[condition] = tick_count
	for cause: Dictionary in snapshot["diagnostics"]["bread_causes"]:
		result.bread_cause_pairs["%s:%s" % [cause["definition_id"], cause["reason"]]] = true
	if not defeat["causes"].is_empty():
		result.defeat_tick = tick_count
		result.defeat_causes.assign(defeat["causes"])


func _row(scenario_id: String, minute: int, tick_count: int, snapshot: Dictionary) -> Dictionary:
	var economy: Dictionary = snapshot["economy"]
	var stats: Dictionary = snapshot["stats"]
	var defeat: Dictionary = snapshot["defeat"]
	var counts: Dictionary[StringName, int] = {&"wharf": 0, &"mill": 0, &"bakery": 0, &"housing": 0}
	for building: Dictionary in economy["buildings"]:
		var id: StringName = StringName(building["definition_id"])
		if counts.has(id):
			counts[id] += 1
	var causes: PackedStringArray = PackedStringArray()
	for cause: StringName in defeat["causes"]:
		causes.append(String(cause))
	return {
		"scenario": scenario_id, "minute": minute, "tick": tick_count,
		"population": economy["population"], "money": economy["money"],
		# The smoothed value is what hunger emigration and the riot use; the raw one is a sawtooth.
		"bread_coverage": economy["hunger_smoothed_coverage"], "satisfaction": economy["satisfaction"],
		"bread_coverage_instant": economy["bread_coverage"],
		"satisfaction_target": economy["satisfaction_target"], "tax_rate": economy["tax_rate"],
		"bread_stock": economy["stocks"].get(&"bread", 0),
		"bread_produced_pm": stats["bread_produced_per_minute"],
		"bread_consumed_pm": stats["bread_consumed_per_minute"],
		"bread_demand_pm": stats["bread_demand_per_minute"], "taxes_pm": stats["taxes_per_minute"],
		"wages_pm": stats["wages_per_minute"], "upkeep_pm": stats["upkeep_per_minute"],
		"wheat_spent_pm": stats["wheat_spent_per_minute"],
		"operating_balance_pm": stats["operating_balance_per_minute"],
		"construction_pm": stats["construction_spent_per_minute"],
		"wheat_price": economy["wheat_price"], "employed": economy["employed"],
		"unemployed": economy["unemployed"], "housing_capacity": economy["housing_capacity"],
		"n_wharf": counts[&"wharf"], "n_mill": counts[&"mill"], "n_bakery": counts[&"bakery"],
		"n_housing": counts[&"housing"],
		"bankruptcy": defeat[&"bankruptcy"]["status"], "hunger": defeat[&"hunger"]["status"],
		"depopulation": defeat[&"depopulation"]["status"], "defeat_causes": "|".join(causes),
	}


func _validate_command(entry: Variant, index: int, duration: int, previous_tick: int,
		command_before_tick: int) -> Array[String]:
	var errors: Array[String] = []
	var where: String = "commands[%d]" % index
	if entry is not Dictionary:
		errors.append("%s must be an object" % where)
		return errors
	if not _is_whole(entry.get("tick")) or int(entry["tick"]) < 0 or int(entry["tick"]) >= duration:
		errors.append("%s: tick must be an integer in [0, duration_ticks)" % where)
	elif int(entry["tick"]) < previous_tick:
		errors.append("%s: ticks must not go backwards" % where)
	if entry.has("wait_for_money") and (not _is_whole(entry["wait_for_money"]) or int(entry["wait_for_money"]) < 0):
		errors.append("%s: wait_for_money must be a whole amount of pence >= 0" % where)
	errors.append_array(_validate_grouping(entry, where, index, command_before_tick))
	var name: String = String(entry.get("cmd", ""))
	if name not in COMMAND_NAMES:
		errors.append("%s: unknown cmd '%s'" % [where, name])
		return errors
	match name:
		"build":
			if not _catalog.buildings.has(StringName(entry.get("building", ""))):
				errors.append("%s: unknown building" % where)
			errors.append_array(_validate_cell(entry.get("cell"), where))
		"demolish":
			errors.append_array(_validate_cell(entry.get("cell"), where))
		"set_tax":
			if typeof(entry.get("rate")) not in [TYPE_INT, TYPE_FLOAT]:
				errors.append("%s: rate must be a number" % where)
		_:
			if entry.get("enabled") is not bool:
				errors.append("%s: enabled must be true or false" % where)
	return errors


# with_previous runs a command in the same tick as the one before it, so it needs a predecessor,
# the same declared tick, and cannot wait for money on its own.
func _validate_grouping(entry: Dictionary, where: String, index: int,
		command_before_tick: int) -> Array[String]:
	var errors: Array[String] = []
	if not entry.has("with_previous"):
		return errors
	if entry["with_previous"] is not bool or index == 0:
		errors.append("%s: with_previous must be true or false and cannot be on the first command" % where)
		return errors
	if not entry["with_previous"]:
		return errors
	var declared_tick: Variant = entry.get("tick")
	if command_before_tick >= 0 and _is_whole(declared_tick) and int(declared_tick) != command_before_tick:
		errors.append("%s: with_previous must declare the same tick as the command before it (%d)"
			% [where, command_before_tick])
	if entry.has("wait_for_money"):
		errors.append("%s: with_previous follows the command before it and cannot wait for money" % where)
	return errors


# Rules are conditional commands: {"id", "when", "then", "otherwise"?}. They are checked every tick
# against the state left by the previous tick and act on the edge: "then" runs when "when" turns
# true, "otherwise" when it turns false again. Nothing runs while the condition keeps its value, and
# nothing runs at the start for a condition that begins false.
func _validate_rules(rules: Variant) -> Array[String]:
	var errors: Array[String] = []
	if rules is not Array:
		errors.append("rules must be a list")
		return errors
	var seen: Dictionary[String, bool] = {}
	var index: int = 0
	for rule: Variant in rules:
		var where: String = "rules[%d]" % index
		index += 1
		if rule is not Dictionary:
			errors.append("%s must be an object" % where)
			continue
		for key: Variant in rule:
			if String(key) not in ["id", "when", "then", "otherwise"]:
				errors.append("%s: unknown field '%s'" % [where, key])
		var id: String = String(rule.get("id", "")) if rule.get("id") is String else ""
		if id == "":
			errors.append("%s: id must be a non-empty string" % where)
		elif seen.has(id):
			errors.append("%s: id '%s' is used twice" % [where, id])
		seen[id] = true
		errors.append_array(_validate_condition(rule.get("when"), "%s.when" % where, 1))
		errors.append_array(_validate_action(rule.get("then"), "%s.then" % where))
		if rule.has("otherwise"):
			errors.append_array(_validate_action(rule["otherwise"], "%s.otherwise" % where))
	return errors


func _validate_condition(condition: Variant, where: String, depth: int) -> Array[String]:
	var errors: Array[String] = []
	if condition is not Dictionary:
		errors.append("%s must be an object" % where)
		return errors
	if condition.has("all") or condition.has("any"):
		var combinator: String = "all" if condition.has("all") else "any"
		if condition.size() != 1:
			errors.append("%s: %s cannot be mixed with other fields" % [where, combinator])
		elif depth >= RULE_MAX_DEPTH:
			errors.append("%s: conditions nest at most %d levels" % [where, RULE_MAX_DEPTH])
		elif condition[combinator] is not Array or condition[combinator].is_empty():
			errors.append("%s.%s must be a non-empty list" % [where, combinator])
		else:
			var part: int = 0
			for child: Variant in condition[combinator]:
				errors.append_array(_validate_condition(child, "%s.%s[%d]" % [where, combinator, part], depth + 1))
				part += 1
		return errors
	for key: Variant in condition:
		if String(key) not in ["path", "op", "value"]:
			errors.append("%s: unknown field '%s'" % [where, key])
	if String(condition.get("path", "")) not in RULE_PATHS:
		errors.append("%s: path must be one of %s" % [where, str(RULE_PATHS)])
	if String(condition.get("op", "")) not in RULE_OPERATORS:
		errors.append("%s: op must be one of %s" % [where, str(RULE_OPERATORS)])
	if typeof(condition.get("value")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: value must be a number" % where)
	return errors


func _validate_action(action: Variant, where: String) -> Array[String]:
	var errors: Array[String] = []
	if action is not Dictionary:
		errors.append("%s must be an object" % where)
		return errors
	var name: String = String(action.get("cmd", ""))
	if name not in RULE_ACTIONS:
		errors.append("%s: cmd must be one of %s" % [where, str(RULE_ACTIONS)])
		return errors
	var allowed: Array[String] = ["cmd", "enabled"]
	if name == "set_tax":
		allowed = ["cmd", "rate"]
	for key: Variant in action:
		if String(key) not in allowed:
			errors.append("%s: unknown field '%s'" % [where, key])
	if name == "set_tax" and typeof(action.get("rate")) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("%s: rate must be a number" % where)
	if name == "set_wheat_purchases" and action.get("enabled") is not bool:
		errors.append("%s: enabled must be true or false" % where)
	return errors


func _condition_holds(condition: Dictionary, economy: Dictionary) -> bool:
	if condition.has("all"):
		for part: Dictionary in condition["all"]:
			if not _condition_holds(part, economy):
				return false
		return true
	if condition.has("any"):
		for part: Dictionary in condition["any"]:
			if _condition_holds(part, economy):
				return true
		return false
	var actual: float = _economy_value(economy, String(condition["path"]))
	var wanted: float = float(condition["value"])
	match String(condition["op"]):
		"==":
			return is_equal_approx(actual, wanted)
		"!=":
			return not is_equal_approx(actual, wanted)
		"<":
			return actual < wanted
		"<=":
			return actual <= wanted
		">":
			return actual > wanted
		_:
			return actual >= wanted


func _economy_value(economy: Dictionary, path: String) -> float:
	if path.begins_with("stocks."):
		return float(economy["stocks"].get(StringName(path.trim_prefix("stocks.")), 0))
	return float(economy.get(path, -1))


func _validate_cell(cell: Variant, where: String) -> Array[String]:
	var map: MapDef = _catalog.maps[_map_id]
	if cell is not Array or cell.size() != 2 or not _is_whole(cell[0]) or not _is_whole(cell[1]) \
			or int(cell[0]) < 0 or int(cell[1]) < 0 or int(cell[0]) >= map.width or int(cell[1]) >= map.height:
		return ["%s: cell must be [x, y] inside the %dx%d map" % [where, map.width, map.height]]
	return []


# JSON has one number type; a whole value is an integer for our purposes.
static func _is_whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(value), roundf(float(value)))
