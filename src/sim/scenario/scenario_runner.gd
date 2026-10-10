class_name ScenarioRunner
extends RefCounted

# Runs scripted games on the pure simulation: no nodes, no clock, no UI. Same seed and same
# command list always give the same ScenarioResult (docs/ARCHITECTURE.md, principle 2).
# It lives in src/ because both tests/ and tools/balance_report.gd use it; it reads the scenario
# files only through load_file()/scenario_paths(), never from game code.

const SCENARIO_DIR: String = "res://tests/scenarios"
const TICKS_PER_MINUTE: int = 60
const COMMAND_NAMES: Array[String] = ["build", "demolish", "set_tax", "set_wheat_purchases"]
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
	var previous_tick: int = 0
	var index: int = 0
	for entry: Variant in scenario["commands"]:
		errors.append_array(_validate_command(entry, index, duration, previous_tick))
		if entry is Dictionary and _is_whole(entry.get("tick")):
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
	var snapshot: Dictionary = sim.snapshot()
	result.rows.append(_row(result.id, 0, 0, snapshot))
	for tick_index: int in range(int(scenario["duration_ticks"])):
		while next_command < script.size() and int(script[next_command]["tick"]) == tick_index:
			var entry: Dictionary = script[next_command]
			var command: SimulationCommand = _make_command(entry)
			sim.apply_command(command)
			issued.append({"entry": entry, "command": command})
			next_command += 1
		sim.tick()
		# After a defeat the state is frozen, so the last snapshot stays valid.
		if result.defeat_tick < 0:
			snapshot = sim.snapshot()
			_observe(result, snapshot, tick_index + 1)
		if (tick_index + 1) % TICKS_PER_MINUTE == 0:
			result.rows.append(_row(result.id, (tick_index + 1) / TICKS_PER_MINUTE, tick_index + 1, snapshot))
	for item: Dictionary in issued:
		var done: SimulationCommand = item["command"]
		var source: Dictionary = item["entry"]
		result.commands.append({"tick": int(source["tick"]), "cmd": String(source["cmd"]),
			"accepted": done.accepted, "reason": done.reason,
			"expect_reject": StringName(source.get("expect_reject", ""))})
	return result


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


func _validate_command(entry: Variant, index: int, duration: int, previous_tick: int) -> Array[String]:
	var errors: Array[String] = []
	var where: String = "commands[%d]" % index
	if entry is not Dictionary:
		errors.append("%s must be an object" % where)
		return errors
	if not _is_whole(entry.get("tick")) or int(entry["tick"]) < 0 or int(entry["tick"]) >= duration:
		errors.append("%s: tick must be an integer in [0, duration_ticks)" % where)
	elif int(entry["tick"]) < previous_tick:
		errors.append("%s: ticks must not go backwards" % where)
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


func _validate_cell(cell: Variant, where: String) -> Array[String]:
	var map: MapDef = _catalog.maps[_map_id]
	if cell is not Array or cell.size() != 2 or not _is_whole(cell[0]) or not _is_whole(cell[1]) \
			or int(cell[0]) < 0 or int(cell[1]) < 0 or int(cell[0]) >= map.width or int(cell[1]) >= map.height:
		return ["%s: cell must be [x, y] inside the %dx%d map" % [where, map.width, map.height]]
	return []


# JSON has one number type; a whole value is an integer for our purposes.
static func _is_whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(value), roundf(float(value)))
