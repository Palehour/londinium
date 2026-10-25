class_name Simulation
extends RefCounted

# Salt of the barley price generator: derived from the seed, but a stream of its own, so the barley walk
# never moves a draw of the wheat one.
const BARLEY_SEED_SALT: int = 0x6A09E667
# The same for the draws of the small incidents (issue #87, D-119): a game with them on keeps the market's numbers.
const INCIDENT_SEED_SALT: int = 0x3C6EF372
const DENSE_HOUSING: StringName = &"dense_housing"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _barley_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _incident_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _state: EconomyState
var _params: Params
var _seed: int
var _tick_count: int = 0
var _commands: Array[SimulationCommand] = []
var _context: EconomyContext
var _workers: WorkersSystem = WorkersSystem.new()
var _market: MarketSystem = MarketSystem.new()
var _imports: ImportSystem = ImportSystem.new()
var _production: ProductionSystem = ProductionSystem.new()
var _consumption: ConsumptionSystem = ConsumptionSystem.new()
var _satisfaction: SatisfactionSystem = SatisfactionSystem.new()
var _growth: GrowthSystem = GrowthSystem.new()
var _mobility: MobilitySystem = MobilitySystem.new()
var _money: MoneySystem = MoneySystem.new()
var _roads: RoadSystem = RoadSystem.new()
var _defeat: DefeatSystem = DefeatSystem.new()
var _victory: VictorySystem
var _stats: Stats
# Chapter-long statistics (issue #82); null without a context, like the systems that feed it.
var _history: StatsHistory
# Classes this simulation had to add to the state it was given; primed once the needs are evaluated.
var _new_classes: Array[ClassDef] = []


# New-game defaults are explicit so loading a snapshot never grants supplies or resets happiness.
static func create_new(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext, victory_stages: Array[Dictionary] = []) -> Simulation:
	var state: EconomyState = EconomyState.from_dict(initial_state.to_dict())
	state.stocks[&"bread"] = int(params.get_value(&"population.initial_bread"))
	state.bread_fraction = 0.0
	state.bread_consumed = 0.0
	if state.tax_rate < 0.0:
		state.tax_rate = float(params.get_value(&"population.tax.rate"))
	_place_dense_housing(state, params, context)
	state.bread_coverage = ConsumptionSystem.new().coverage(state, params, context)
	state.hunger_smoothed_coverage = state.bread_coverage
	SatisfactionSystem.new().update_target(state, params, context)
	SatisfactionSystem.new().snap_to_target(state, context)
	return Simulation.new(params, state, seed_value, context, [], victory_stages)


# The standing dense housing of the map (issue #154, D-075): the first startup.dense_housing_occupied of its cells.
# No build time and no price paid, so it is an established building that refunds half its cost (D-029).
static func _place_dense_housing(state: EconomyState, params: Params, context: EconomyContext) -> void:
	if context == null:
		return
	var cells: Array[Vector2i] = context.map.dense_housing_cells
	var count: int = mini(cells.size(), int(params.get_value(&"startup.dense_housing_occupied")))
	for cell: Vector2i in cells.slice(0, count):
		state.buildings.append({"definition_id": DENSE_HOUSING, "cell": [cell.x, cell.y]})
	# The 1870 houses (issue #180, D-085) stand the same way, with the people the map gives them (none on the strip),
	# who join the base class like the people of startup.json.
	for cell: Vector2i in context.map.period_houses:
		state.buildings.append({"definition_id": DENSE_HOUSING, "cell": [cell.x, cell.y]})
		state.population += int(context.map.period_house_population.get(cell, 0))
	# The other anchors with a use, like Oliver's Wharf (issue #152), stand established in the same way.
	for cell: Vector2i in context.map.anchors:
		var building: StringName = context.map.anchors[cell]
		if building != &"" and building != DENSE_HOUSING:
			state.buildings.append({"definition_id": building, "cell": [cell.x, cell.y]})


# stats_window is snapshot()["stats"]["window"]; it is copied, so callers may keep mutating theirs.
# stats_history is stats_history_to_dict(); a missing or broken one starts an empty history.
func _init(params: Params, initial_state: EconomyState, seed_value: int,
		context: EconomyContext = null, stats_window: Array = [],
		victory_stages: Array[Dictionary] = [], stats_history: Dictionary = {}) -> void:
	_victory = VictorySystem.new(victory_stages)
	_params = params
	_state = EconomyState.from_dict(initial_state.to_dict())
	_seed = seed_value
	_rng.seed = seed_value
	_barley_rng.seed = seed_value ^ BARLEY_SEED_SALT
	_incident_rng.seed = seed_value ^ INCIDENT_SEED_SALT
	_context = context.copy() if context != null else null
	_stats = Stats.new(int(_params.get_value(&"population.stats_window_seconds")))
	_stats.restore(stats_window)
	if _context != null:
		_new_classes = ClassStates.ensure(_state, _context)
		# Derived from the layout and never saved (D-080): a loaded game works its coverage out again.
		_roads.tick(_state, _params, _context)
		_defeat.initialize(_state, _params)
		_history = StatsHistory.new(SeriesRegistry.build(_params, _context, victory_stages), _params, _context)
		_history.restore(stats_history)
	if _context != null and _state.wheat_price < 0:
		_state.wheat_price = int(_params.get_value(&"market.wheat.base_price"))
	if _context != null and _state.barley_price < 0:
		_state.barley_price = int(_params.get_value(&"market.barley.base_price"))
	if _context != null and _state.unloading_barley_percent < 0:
		_state.unloading_barley_percent = int(_params.get_value(&"policy.unloading.default_barley_percent"))
	if _context != null and _state.wheat_reserve_minutes < 0:
		_state.wheat_accumulate_price = int(_params.get_value(&"policy.wheat.default_accumulate_price"))
		_state.wheat_max_price = int(_params.get_value(&"policy.wheat.default_max_price"))
		_state.wheat_target_stock = int(_params.get_value(&"policy.wheat.default_target_stock"))
		_state.wheat_reserve_minutes = int(_params.get_value(&"policy.wheat.default_reserve_minutes"))
	if _context != null and _state.tax_rate < 0.0:
		_state.tax_rate = float(_params.get_value(&"population.tax.rate"))
		# Construction initializes diagnostics, but smoothing advances only on ticks.
		_satisfaction.update_target(_state, _params, _context)
	if _context != null:
		WorkersSystem.refresh_counts(_state)
		# Derived from the restored state, so a save from before the needs existed still explains itself,
		# even if it is already defeated and never ticks again.
		NeedsSystem.evaluate(_state, _params, _context)
		for def: ClassDef in _new_classes:
			_satisfaction.prime_class(_state, _params, _context, def)


# A saved game (issue #57) resumes where it stopped: same tick and the same point of both generators, so playing on
# gives what the game would have given without the save. `saved` is to_save(); its history may be missing.
static func from_save(params: Params, context: EconomyContext, victory_stages: Array[Dictionary],
		saved: Dictionary) -> Simulation:
	var window: Array = saved.get("stats_window", [])
	var history: Dictionary = saved.get("stats_history", {})
	var sim: Simulation = Simulation.new(params, EconomyState.from_dict(saved["economy"]), int(saved["seed"]),
		context, window, victory_stages, history)
	sim._tick_count = int(saved["tick_count"])
	sim._rng.state = int(saved["rng_state"])
	sim._barley_rng.state = int(saved["barley_rng_state"])
	# Saved only by a game with the incidents on (D-122); any other starts them from the seed.
	if saved.has("incident_rng_state"):
		sim._incident_rng.state = int(saved["incident_rng_state"])
	return sim


# The state at the end of the last tick. Commands still queued are not part of it: a save is taken between ticks.
func to_save() -> Dictionary:
	var saved: Dictionary = {
		"economy": _state.to_dict(),
		"stats_window": _stats.snapshot()["window"],
		"stats_history": stats_history_to_dict(),
		"tick_count": _tick_count,
		"seed": _seed,
		"rng_state": get_rng_state(),
		"barley_rng_state": get_barley_rng_state(),
	}
	if _state.incidents_enabled:
		saved["incident_rng_state"] = _incident_rng.state
	return saved


func has_queued_commands() -> bool:
	return not _commands.is_empty()


func get_building_unavailable_reason(id: StringName) -> StringName:
	if _context == null:
		return &"unknown_building"
	if _context.buildings.has(id):
		var events_reason: StringName = WaterSystem.unavailable_reason(_params, _state, _context,
			_context.buildings[id])
		if events_reason != &"":
			return events_reason
	return _context.building_unavailable_reason(id)


func apply_command(command: SimulationCommand) -> void:
	if not _state.defeat_causes.is_empty():
		_reject_after_defeat(command)
		return
	_commands.append(command)


func tick() -> void:
	if not _state.defeat_causes.is_empty():
		return
	# Detach the batch so commands queued during execution wait until the next tick.
	var pending: Array[SimulationCommand] = _commands
	_commands = []
	_state.reset_flows()
	for command: SimulationCommand in pending:
		command.use_context(_context)
		command.execute(_state, _params, _rng)
		command.release_context()
		if _history != null:
			_history.note_command(command)
	_tick_count += 1
	if _context != null:
		CrisisSystem.tick(_state)
		_roads.tick(_state, _params, _context)
		ServiceSystem.tick(_state, _params, _context)
		IncidentSystem.tick(_state, _params, _context, _incident_rng)
		_workers.tick(_state, _params)
		_market.tick(_state, _params, _rng, _tick_count, _barley_rng)
		_imports.tick(_state, _params, _context)
		_production.tick(_state, _params, _context)
		_consumption.tick(_state, _params, _context)
		_defeat.update_hunger_coverage(_state, _params)
		_satisfaction.tick(_state, _params, _context)
		_growth.tick(_state, _params, _context)
		_mobility.tick(_state, _params, _context)
		_money.tick(_state, _params, _context)
		MissionSystem.tick(_state, _params, _context, _tick_count)
		_defeat.tick(_state, _params, false, MissionSystem.defeat_paused(_state, _params, _context))
		if not _state.defeat_causes.is_empty():
			for command: SimulationCommand in _commands:
				_reject_after_defeat(command)
			_commands.clear()
		_victory.tick(_state, _params)
		_stats.record(_state)
		_history.record(_state)


# The hooks of D-109 for the houses in a crisis (issue #222): any cell of the house's footprint. The outbreaks of #87
# (IncidentSystem) make houses sick on their own; the tests call these. False when there is no house there to change.
func mark_house_sick(cell: Vector2i) -> bool:
	var house: Dictionary = _building_at(cell)
	return not house.is_empty() and CrisisSystem.mark_sick(_state, _params, _context, house)


func cure_house(cell: Vector2i) -> bool:
	var house: Dictionary = _building_at(cell)
	return not house.is_empty() and CrisisSystem.cure(_state, house)


# The consume(service, amount) of D-118 (#87), for any cell of the service's footprint: the incidents spend it through
# IncidentSystem, the tests through this. False when no service stands there or the amount is below 0.
func consume_service(cell: Vector2i, amount: float) -> bool:
	var service: Dictionary = _building_at(cell)
	return not service.is_empty() and ServiceSystem.consume(_params, _context, service, amount)


func _building_at(cell: Vector2i) -> Dictionary:
	if _context == null:
		return {}
	for building: Dictionary in _state.buildings:
		if _context.area_of(building).has_point(cell):
			return building
	return {}


# The treasury, without building a snapshot.
func treasury() -> int:
	return _state.money


# What the last tick moved, for balance probes that need every tick (the snapshot is too coarse for them):
# the head tax each class paid, the barley bought, the beer drunk, and the buildings with their workers and
# what they cost to build (it grows with each copy, issue #118).
func tick_flows() -> Dictionary:
	var buildings: Dictionary = {}
	for building: Dictionary in _state.buildings:
		var entry: Dictionary = buildings.get(building["definition_id"], {"count": 0, "workers": 0, "paid": 0})
		entry["count"] += 1
		entry["workers"] += int(building.get("workers", 0))
		entry["paid"] += int(building.get("paid", _params.get_value(StringName("building.%s.cost" % building["definition_id"]))))
		buildings[building["definition_id"]] = entry
	return {"class_tax": _state.class_tax_tick.duplicate(), "barley_spent": _state.barley_spent_tick,
		"beer_consumed": _state.beer_consumed, "buildings": buildings}


# Read-only access to the chapter statistics (issue #82), for the views (#83) and the save (#57). Without a context
# there is no history: no series, no events and an empty dictionary.
func stats_series_defs() -> Array[Dictionary]:
	return _history.defs() if _history != null else [] as Array[Dictionary]


# tier is StatsHistory.TIER_FINE, TIER_MEDIUM or TIER_CHAPTER.
func stats_series(id: StringName, tier: StringName) -> Dictionary:
	return _history.series(id, tier) if _history != null else {}


func stats_events(from_second: int = 0) -> Array[Dictionary]:
	return _history.events(from_second) if _history != null else [] as Array[Dictionary]


func stats_history_to_dict() -> Dictionary:
	return _history.to_dict() if _history != null else {}


func _reject_after_defeat(command: SimulationCommand) -> void:
	command.accepted = false
	command.reason = &"simulation_defeated"


func get_rng_state() -> int:
	# Expose a value, not the mutable generator that commands use.
	return _rng.state


# The barley price walk has a generator of its own (see BARLEY_SEED_SALT); same rule as get_rng_state().
func get_barley_rng_state() -> int:
	return _barley_rng.state


func snapshot() -> Dictionary:
	return {
		"economy": _state.to_dict(),
		"stats": _stats.snapshot(),
		"diagnostics": BreadDiagnostics.build(_state, _params, _context),
		"needs": NeedsDiagnostics.build(_state, _params, _context),
		"production": {"input_starved": _state.input_starved_tick.duplicate()},
		"market": {"wheat": MarketSystem.wheat_snapshot(_state, _params),
			"barley": MarketSystem.barley_snapshot(_state, _params),
			"malt": MarketSystem.storage_snapshot(_state, _params, &"malt"),
			"beer": MarketSystem.storage_snapshot(_state, _params, &"beer")},
		"imports": ImportSystem.snapshot(_state, _params, _context),
		"distance": RoadSystem.snapshot(_state, _context),
		"repair": RepairWharfCommand.snapshot(_state, _params, _context),
		"crisis": CrisisSystem.snapshot(_state, _params, _context),
		"services": ServiceSystem.snapshot(_state, _params, _context),
		"incidents": IncidentSystem.snapshot(_state, _params, _context),
		"defeat": _defeat_snapshot(),
		"victory": _victory.snapshot(_state, _params),
		"tick_count": _tick_count,
		"seed": _seed,
		"rng_state": get_rng_state(),
		"barley_rng_state": get_barley_rng_state(),
	}


func _defeat_snapshot() -> Dictionary:
	var grace: int = int(_params.get_value(&"defeat.grace_seconds"))
	return {
		"grace_active": _state.defeat_elapsed_seconds <= grace,
		"grace_remaining_seconds": maxi(0, grace - _state.defeat_elapsed_seconds),
		"causes": _state.defeat_causes.duplicate(),
		"bankruptcy": _condition_snapshot(_state.bankruptcy, &"bankruptcy",
			{"money": _state.money, "threshold": int(_params.get_value(&"defeat.bankruptcy.threshold"))}),
		"hunger": _condition_snapshot(_state.hunger, &"hunger",
			{"coverage": _state.hunger_coverage(), "threshold": float(_params.get_value(&"defeat.hunger.threshold"))}),
		"depopulation": _condition_snapshot(_state.depopulation, &"depopulation",
			{"population": _state.population, "peak": _state.population_peak, "active": _state.depopulation_active}),
	}


func _condition_snapshot(condition: DefeatState, key: StringName, metrics: Dictionary) -> Dictionary:
	var duration: int = int(_params.get_value(StringName("defeat.%s.duration_seconds" % key)))
	var result: Dictionary = metrics.duplicate(true)
	result["status"] = condition.status
	result["cause"] = condition.cause
	# The timer runs while the critical condition holds, which can differ from the warning.
	result["timer_running"] = condition.elapsed_seconds > 0
	result["elapsed_seconds"] = condition.elapsed_seconds
	result["remaining_seconds"] = maxi(0, duration - condition.elapsed_seconds)
	result["duration_seconds"] = duration
	return result
