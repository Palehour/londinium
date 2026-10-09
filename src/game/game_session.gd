class_name GameSession
extends RefCounted

signal snapshot_changed(snapshot: Dictionary)
signal command_resolved(accepted: bool, reason: StringName)

var simulation: Simulation
var context: EconomyContext
var _params: Params
var _initial_state: EconomyState
var _seed: int
var _pending: Array[SimulationCommand] = []


func _init(catalog: DataCatalog, params: Params) -> void:
	_params = params
	context = EconomyContext.new(catalog, catalog.maps[&"whitechapel_1850s"])
	var state: EconomyState = EconomyState.new()
	state.money = int(params.get_value(&"startup.money"))
	state.population = int(params.get_value(&"startup.population"))
	state.wheat_purchases_enabled = params.get_value(&"startup.wheat_purchases_enabled")
	# create_new copies the state, so this template stays pristine for restarts.
	_initial_state = state
	_seed = int(params.get_value(&"startup.seed"))
	simulation = Simulation.create_new(params, _initial_state, _seed, context)


func get_snapshot() -> Dictionary:
	return simulation.snapshot()


func get_building_unavailable_reason(id: StringName) -> StringName:
	return simulation.get_building_unavailable_reason(id)


func submit_command(command: SimulationCommand) -> void:
	simulation.apply_command(command)
	_pending.append(command)
	_resolve_commands()


# A restart is a brand-new game from the same startup data and seed.
func restart() -> void:
	_pending.clear()
	simulation = Simulation.create_new(_params, _initial_state, _seed, context)


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
