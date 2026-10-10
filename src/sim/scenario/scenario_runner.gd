class_name ScenarioRunner
extends RefCounted

# Runs scripted games on the pure simulation: no nodes, no clock, no UI. Same seed and same
# command list always give the same ScenarioResult (docs/ARCHITECTURE.md, principle 2).
# It lives in src/ because both tests/ and tools/balance_report.gd use it; it reads the scenario
# files only through load_file()/scenario_paths(), never from game code.

const SCENARIO_DIR: String = "res://tests/scenarios"
const TICKS_PER_MINUTE: int = 60
const COMMAND_NAMES: Array[String] = ["build", "demolish", "set_tax", "set_wheat_purchases", "set_wheat_policy"]
const POLICY_FIELDS: Array[String] = ["accumulate_price", "max_price", "target_stock", "reserve_minutes"]
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
	errors.append_array(_validate_price_schedule(scenario.get("price_schedule", []), duration))
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
	var normal_params: Params = _params
	var schedule: Array = scenario.get("price_schedule", [])
	if not schedule.is_empty():
		_params = _params_without_repricing(int(scenario["duration_ticks"]))
	var sim: Simulation = Simulation.create_new(_params, _initial_state(), int(scenario["seed"]), _context)
	var next_price: int = 0
	var script: Array = scenario["commands"]
	var issued: Array[Dictionary] = []
	var next_command: int = 0
	var snapshot: Dictionary = sim.snapshot()
	result.rows.append(_row(result.id, 0, 0, snapshot))
	for tick_index: int in range(int(scenario["duration_ticks"])):
		while next_price < schedule.size() and int(schedule[next_price]["tick"]) <= tick_index:
			sim.apply_command(ForceWheatPriceCommand.new(int(schedule[next_price]["price"])))
			next_price += 1
		var queued: Array[Dictionary] = []
		while next_command < script.size() and _is_due(script[next_command], tick_index, sim, queued):
			var entry: Dictionary = script[next_command]
			var command: SimulationCommand = _make_command(entry)
			sim.apply_command(command)
			issued.append({"entry": entry, "command": command, "tick": tick_index})
			queued.append(entry)
			next_command += 1
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
			"accepted": done.accepted, "reason": done.reason,
			"expect_reject": StringName(source.get("expect_reject", ""))})
	# A command still waiting for its money when the game ends never ran; that counts as a refusal.
	for pending: int in range(next_command, script.size()):
		result.commands.append({"tick": int(script[pending]["tick"]), "executed_tick": -1,
			"cmd": String(script[pending]["cmd"]), "building": String(script[pending].get("building", "")),
			"accepted": false, "reason": &"never_ran",
			"expect_reject": StringName(script[pending].get("expect_reject", ""))})
	_params = normal_params
	return result


# A scheduled price must stay where the script put it, so the random walk gets an interval that
# never comes up during the game. Works on a copy of the values: data/ and later runs are untouched.
func _params_without_repricing(duration_ticks: int) -> Params:
	var key: StringName = &"market.wheat.price_update_seconds"
	var saved: Variant = _catalog.base_values[key]
	_catalog.base_values[key] = duration_ticks + 1
	var params: Params = Params.new(_catalog, _catalog.roles[&"neutral_administrator"])
	_catalog.base_values[key] = saved
	return params


func _validate_price_schedule(schedule: Variant, duration: int) -> Array[String]:
	var errors: Array[String] = []
	if schedule is not Array:
		return ["price_schedule must be a list"]
	var previous: int = 0
	for entry: Variant in schedule:
		if entry is not Dictionary or not _is_whole(entry.get("tick")) or not _is_whole(entry.get("price")) \
				or int(entry["tick"]) < previous or int(entry["tick"]) >= duration or int(entry["price"]) < 0:
			errors.append("price_schedule entries need whole tick (in order, inside the game) and price >= 0")
			break
		previous = int(entry["tick"])
	return errors



# Same predicate the simulation uses for "nobody is leaving", evaluated on the final state.
func is_stable(result: ScenarioResult) -> bool:
	return DefeatSystem.new().is_city_stable(EconomyState.from_dict(result.final_economy), _params)


# Copy of `scenario` with every set_tax rate replaced, for probes. A scenario with
# "tax_override": false is left alone: its tax rate is part of what it demonstrates (the defeat_*
# ones lose partly because of it), so overriding it would change the scenario itself.
static func with_tax(scenario: Dictionary, rate: float) -> Dictionary:
	var copy: Dictionary = scenario.duplicate(true)
	if copy.get("tax_override", true) == false:
		return copy
	for command: Dictionary in copy["commands"]:
		if command["cmd"] == "set_tax":
			command["rate"] = rate
	return copy


# Commands run in order. `tick` is the earliest tick; `wait_for_money` holds the command back
# until the treasury reaches that amount, and `with_previous` runs it in the same tick as the
# command before it, so a purchase made of several buildings is priced once. `queued` are the
# commands already sent in this tick: they have not run yet, so a wait is checked against the
# treasury they would leave (see _money_after).
func _is_due(entry: Dictionary, tick_index: int, sim: Simulation, queued: Array[Dictionary]) -> bool:
	if entry.get("with_previous", false):
		return not queued.is_empty()
	if tick_index < int(entry["tick"]):
		return false
	if entry.has("wait_for_money"):
		return _money_after(sim, queued) >= int(entry["wait_for_money"])
	return true


# The treasury once the commands queued in this tick have run. Only an accepted build spends:
# set_tax, set_wheat_purchases and a refused build leave the money as it is. They are tried on a
# copy of the state with fresh command objects, in the order the simulation will run them. Once the
# game is lost Simulation.apply_command() refuses every command (simulation_defeated) before the
# command itself runs, so nothing queued spends and the copy is left as it is.
func _money_after(sim: Simulation, queued: Array[Dictionary]) -> int:
	var snapshot: Dictionary = sim.snapshot()
	var state: EconomyState = EconomyState.from_dict(snapshot["economy"])
	if not snapshot["defeat"]["causes"].is_empty():
		return state.money
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for entry: Dictionary in queued:
		_make_command(entry).execute(state, _params, rng)
	return state.money


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
		"set_wheat_policy":
			return SetWheatPolicyCommand.new(int(entry["accumulate_price"]), int(entry["max_price"]),
				int(entry["target_stock"]), int(entry["reserve_minutes"]))
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
		"wheat_stock": economy["stocks"].get(&"wheat", 0),
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
		"set_wheat_policy":
			for field: String in POLICY_FIELDS:
				# accumulate_price and max_price take -1 for "off" and "no limit".
				var lowest: int = -1 if field in ["accumulate_price", "max_price"] else 0
				if not _is_whole(entry.get(field)) or int(entry[field]) < lowest:
					errors.append("%s: %s must be a whole number >= %d" % [where, field, lowest])
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


func _validate_cell(cell: Variant, where: String) -> Array[String]:
	var map: MapDef = _catalog.maps[_map_id]
	if cell is not Array or cell.size() != 2 or not _is_whole(cell[0]) or not _is_whole(cell[1]) \
			or int(cell[0]) < 0 or int(cell[1]) < 0 or int(cell[0]) >= map.width or int(cell[1]) >= map.height:
		return ["%s: cell must be [x, y] inside the %dx%d map" % [where, map.width, map.height]]
	return []


# JSON has one number type; a whole value is an integer for our purposes.
static func _is_whole(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(value), roundf(float(value)))
