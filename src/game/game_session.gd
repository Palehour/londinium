class_name GameSession
extends RefCounted

signal snapshot_changed(snapshot: Dictionary)
signal command_resolved(accepted: bool, reason: StringName)

# The player's street on the build menu (issue #168, D-080). Not a building: it can be placed on any map with streets.
const ROAD: StringName = &"road"

var simulation: Simulation
var context: EconomyContext
# The preset this game runs on (D-065), kept for saving (#57).
var difficulty: StringName = DataLayers.NORMAL
# Active mods in load order and their conflicts (D-065), for the mods menu and saving (#57).
var mods: Array[StringName] = []
var mod_conflicts: Array[Dictionary] = []
# {name, version, hash} of each active mod, for saving (issue #136).
var mod_fingerprints: Array[Dictionary] = []
# On while this game runs on the mods of the save it loaded instead of the player's (issue #136, D-117).
var mods_from_save: bool = false
var _params: Params
var _initial_state: EconomyState
var _victory_stages: Array[Dictionary] = []
var _seed: int
var _pending: Array[SimulationCommand] = []
var _scenario_id: StringName


func _init(catalog: DataCatalog, params: Params, scenario_id: StringName = &"victorian_demo",
		preset_id: StringName = DataLayers.NORMAL) -> void:
	_scenario_id = scenario_id
	_use_catalog(catalog)
	_start(params, preset_id)


# A new game on data loaded again (another mod order): same scenario and difficulty, new definitions.
func restart_with_catalog(catalog: DataCatalog, params: Params) -> void:
	_pending.clear()
	_use_catalog(catalog)
	_start(params, difficulty)


# A new game on another difficulty: the startup values come from the new parameters, and from `catalog` when the
# data loaded again (back to the player's mods after a save's, issue #136).
func restart_with(params: Params, preset_id: StringName, catalog: DataCatalog = null) -> void:
	_pending.clear()
	if catalog != null:
		_use_catalog(catalog)
	_start(params, preset_id)


func _use_catalog(catalog: DataCatalog) -> void:
	var scenario: Dictionary = catalog.scenarios.get(_scenario_id, {})
	_victory_stages.assign(scenario.get("stages", []))
	context = EconomyContext.new(catalog, catalog.maps[scenario.get("map", MapDef.DEFAULT_ID)])


func _start(params: Params, preset_id: StringName) -> void:
	_params = params
	difficulty = preset_id
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"startup.money"))
	state.population = int(params.get_value(&"startup.population"))
	state.wheat_purchases_enabled = params.get_value(&"startup.wheat_purchases_enabled")
	state.tea_imports_enabled = params.get_value(&"startup.tea_imports_enabled")
	state.flour_imports_enabled = params.get_value(&"startup.flour_imports_enabled")
	# create_new copies the state, so this template stays pristine for restarts.
	_initial_state = state
	_seed = int(params.get_value(&"startup.seed"))
	simulation = Simulation.create_new(params, _initial_state, _seed, context, _victory_stages)


# A saved game (issue #57) on the parameters of its difficulty: a later restart starts a new game on them. One saved on
# cells of 50 m is converted first (D-087). `catalog` is the data loaded with the save's own mods (issue #136).
func load_save(saved: Dictionary, params: Params, catalog: DataCatalog = null) -> void:
	_pending.clear()
	if catalog != null:
		_use_catalog(catalog)
	_start(params, StringName(saved["difficulty"]))
	var upgraded: Dictionary = SaveFile.upgraded(saved, int(params.get_value(&"map.cell_size_m")))
	simulation = Simulation.from_save(params, context, _victory_stages, upgraded["simulation"])


func scenario_id() -> StringName:
	return _scenario_id


# The side of a map cell in metres (D-086, D-093), so the 3D city draws the map at its real size (issue #65).
func cell_size_m() -> int:
	return int(_params.get_value(&"map.cell_size_m"))


func get_snapshot() -> Dictionary:
	return simulation.snapshot()


func get_building_unavailable_reason(id: StringName) -> StringName:
	if id == ROAD:
		return &"" if context.map.roads_enabled else &"roads_disabled"
	return simulation.get_building_unavailable_reason(id)


func submit_command(command: SimulationCommand) -> void:
	simulation.apply_command(command)
	_pending.append(command)
	_resolve_commands()


# A restart is a brand-new game from the same startup data and seed.
func restart() -> void:
	_pending.clear()
	simulation = Simulation.create_new(_params, _initial_state, _seed, context, _victory_stages)


func publish_tick() -> void:
	snapshot_changed.emit(get_snapshot())
	_resolve_commands()


func _resolve_commands() -> void:
	var waiting: Array[SimulationCommand] = []
	for command: SimulationCommand in _pending:
		if command.reason == &"pending":
			waiting.append(command)
		else:
			command_resolved.emit(command.accepted, command.reason)
	_pending = waiting
