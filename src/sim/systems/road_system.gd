class_name RoadSystem
extends RefCounted

# Step 1b of the tick (issue #67, D-034, D-070, D-080): production still goes to the global store, the streets
# decide access. A building with no street of the network beside it does not work ("no_road_access"), nor one
# whose inputs have suppliers but none it can reach ("no_route"). Each input comes from the nearest supplier and
# its leg costs units x steps x k (MoneySystem pays it). A house gets a good only within the service radius of a
# building that hands it out, and people move into the served houses first. Everything here is derived from the
# layout and the people, worked out again each tick and never saved, so a loaded game gets the same coverage as one
# that never stopped.

const NO_ROAD_ACCESS: StringName = &"no_road_access"
const NO_ROUTE: StringName = &"no_route"
const SECONDS_PER_MINUTE: float = 60.0
# Key of a class's connected houses, beside the goods, in EconomyState.service_rooms.
const TOTAL: StringName = &"_all"
# Key of the houses with every good of the class's served categories within reach (issue #180, D-085).
const SERVED: StringName = &"_served"

# What the last evaluation was made of; the same layout gives the same result.
var _layout: Array = []


func tick(state: EconomyState, params: Params, context: EconomyContext) -> void:
	if context == null or not context.map.roads_enabled:
		return
	var layout: Array = [state.buildings.map(func(building: Dictionary) -> Array:
		return [building["definition_id"], building["cell"]]), state.player_roads.map(func(road: Dictionary) -> Array:
		return road["cell"]), state.flour_imports_enabled]
	if layout != _layout:
		_layout = layout
		evaluate(state, params, context)
	update_access(state, params, context)


static func evaluate(state: EconomyState, params: Params, context: EconomyContext) -> void:
	var network: RoadNetwork = RoadNetwork.build(context.map, state.player_roads)
	state.road_blocked.clear()
	state.transport_legs.clear()
	state.house_service.clear()
	state.service_rooms.clear()
	var connected: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		if network.has_access(RoadNetwork.cell_of(building)):
			connected.append(building)
		else:
			state.road_blocked[RoadNetwork.cell_of(building)] = NO_ROAD_ACCESS
	for building: Dictionary in connected:
		_add_legs(state, params, context, network, building, connected)
	for def: ClassDef in context.classes.values():
		_add_service(state, params, context, network, def, connected)


# Transport of this tick: every leg's units taken out of the store times its steps times k, in pence.
static func transport_cost(state: EconomyState, params: Params) -> float:
	var rate: float = float(params.get_value(&"transport.cost_per_unit_per_step"))
	var cost: float = 0.0
	for leg: Dictionary in state.transport_legs:
		var cell: Vector2i = Vector2i(int(leg["cell"][0]), int(leg["cell"][1]))
		cost += float(state.transport_units_tick.get(cell, 0)) * int(leg["steps"]) * rate
	return cost


# What the views read: the player's streets, the buildings that do not work and why, every leg and every house.
static func snapshot(state: EconomyState, context: EconomyContext) -> Dictionary:
	var blocked: Array[Dictionary] = []
	for building: Dictionary in state.buildings:
		var reason: StringName = state.road_reason(building)
		if reason != &"":
			blocked.append({"cell": building["cell"].duplicate(), "definition_id": building["definition_id"],
				"reason": reason})
	return {
		"enabled": context != null and context.map.roads_enabled,
		"player_roads": state.player_roads.map(func(road: Dictionary) -> Array: return road["cell"].duplicate()),
		"blocked": blocked,
		"legs": state.transport_legs.duplicate(true),
		"houses": state.house_service.duplicate(true),
	}


# Whether this building brings the good to the others: its recipe makes it, or it is one the data says it supplies.
# Imported flour reaches the wharf only while flour imports are on (D-026).
static func supplies(state: EconomyState, definition: BuildingDef, good: StringName) -> bool:
	if definition.recipe != null and good in definition.recipe.outputs:
		return true
	if good not in definition.supplies:
		return false
	return good != &"flour" or state.flour_imports_enabled


static func _add_legs(state: EconomyState, params: Params, context: EconomyContext, network: RoadNetwork,
		building: Dictionary, connected: Array[Dictionary]) -> void:
	var definition: BuildingDef = context.buildings[building["definition_id"]]
	if definition.recipe == null:
		return
	var cell: Vector2i = RoadNetwork.cell_of(building)
	var legs: Array[Dictionary] = []
	for good: StringName in definition.recipe.inputs:
		var any_supplier: bool = false
		var nearest: Dictionary = {}
		var nearest_steps: int = RoadNetwork.NO_ROUTE
		for other: Dictionary in state.buildings:
			if other == building or not supplies(state, context.buildings[other["definition_id"]], good):
				continue
			any_supplier = true
			if other not in connected:
				continue
			var steps: int = network.steps(RoadNetwork.cell_of(other), cell)
			if steps != RoadNetwork.NO_ROUTE and (nearest_steps == RoadNetwork.NO_ROUTE or steps < nearest_steps):
				nearest = other
				nearest_steps = steps
		# Without any supplier yet there is nothing to reach: the usual diagnostics explain the missing input.
		if not any_supplier:
			continue
		if nearest.is_empty():
			state.road_blocked[cell] = NO_ROUTE
			return
		legs.append(_leg(params, building, good, nearest, nearest_steps))
	state.transport_legs.append_array(legs)


static func _leg(params: Params, building: Dictionary, good: StringName, supplier: Dictionary,
		steps: int) -> Dictionary:
	var prefix: String = "building.%s.recipe" % building["definition_id"]
	var per_minute: float = float(params.get_value(StringName("%s.inputs.%s" % [prefix, good]))) \
		* SECONDS_PER_MINUTE / float(params.get_value(StringName(prefix + ".seconds")))
	return {"cell": building["cell"].duplicate(), "definition_id": building["definition_id"], "good": good,
		"supplier_cell": supplier["cell"].duplicate(), "supplier_id": supplier["definition_id"], "steps": steps,
		"cost_per_minute": per_minute * steps * float(params.get_value(&"transport.cost_per_unit_per_step")),
		"expensive": steps >= int(params.get_value(&"transport.expensive_steps"))}


# Each house of the class gets each good it needs from the buildings that hand it out within their radius (0 is the
# whole network). Kept per class: the base capacity and the number of its connected houses, in all, for each good
# some building hands out (a good nobody hands out stays global) and served in every served category (D-085).
static func _add_service(state: EconomyState, params: Params, context: EconomyContext, network: RoadNetwork,
		def: ClassDef, connected: Array[Dictionary]) -> void:
	var rooms: Dictionary = {}
	var houses: int = 0
	for building: Dictionary in state.buildings:
		var id: StringName = building["definition_id"]
		var owner: StringName = context.class_of_housing(id)
		if "housing" not in context.buildings[id].tags or not (owner == def.id or (def.base and owner == &"")):
			continue
		houses += 1
		var reachable: bool = building in connected
		var capacity: float = float(maxi(0, int(params.get_value(StringName("building.%s.capacity" % id)))))
		var served: Dictionary = {}
		for need: NeedDef in def.needs:
			served[need.good] = reachable and _is_served(params, context, network, building, need.good, connected)
			if served[need.good] and _hands_out(context, need.good):
				rooms[need.good] = _add_room(rooms.get(need.good, Vector2.ZERO), capacity)
		if reachable:
			rooms[TOTAL] = _add_room(rooms.get(TOTAL, Vector2.ZERO), capacity)
		if reachable and def.needs.all(func(need: NeedDef) -> bool:
				return need.category not in def.served_categories or served[need.good]):
			rooms[SERVED] = _add_room(rooms.get(SERVED, Vector2.ZERO), capacity)
		state.house_service.append({"cell": building["cell"].duplicate(), "definition_id": id, "class_id": def.id,
			"connected": reachable, "served": served})
	if houses == 0:
		return
	for key: StringName in [TOTAL, SERVED]:
		if not rooms.has(key):
			rooms[key] = Vector2.ZERO
	for need: NeedDef in def.needs:
		if _hands_out(context, need.good) and not rooms.has(need.good):
			rooms[need.good] = Vector2.ZERO
	state.service_rooms[def.id] = rooms


# Base capacity in x, houses in y.
static func _add_room(room: Vector2, capacity: float) -> Vector2:
	return room + Vector2(capacity, 1.0)


# People move into the served houses first: a class's access to a good is the room of its served houses (base plus
# the class's housing bonus) over the people who have a house; the ones who do not fit there go without. The city's
# bread access weights the classes by their people.
static func update_access(state: EconomyState, params: Params, context: EconomyContext) -> void:
	state.service_access.clear()
	for def: ClassDef in ClassStates.defs(context):
		if not state.service_rooms.has(def.id):
			continue
		var rooms: Dictionary = state.service_rooms[def.id]
		var bonus: float = float(NeedsSystem.housing_bonus(state, params, def.id))
		var housed: float = minf(float(ClassStates.population_of(state, def)), _room(rooms[TOTAL], bonus))
		var access: Dictionary = {}
		for good: Variant in rooms:
			if good in [TOTAL, SERVED]:
				continue
			var served: float = _room(rooms[good], bonus)
			if housed > 0.0:
				access[good] = minf(1.0, served / housed)
			else:
				access[good] = 1.0 if served > 0.0 else 0.0
		state.service_access[def.id] = access
	state.bread_access = _city_access(state, context, &"bread")


# Room of the class's houses with the goods of its served categories within reach (D-085), housing bonus included.
# Without streets every house counts, so it is `all_room`, the class's whole housing capacity.
static func served_room(state: EconomyState, params: Params, def: ClassDef, all_room: int) -> int:
	if not state.service_rooms.has(def.id):
		return all_room
	var bonus: float = float(NeedsSystem.housing_bonus(state, params, def.id))
	return mini(all_room, floori(_room(state.service_rooms[def.id][SERVED], bonus)))


static func _room(room: Vector2, bonus: float) -> float:
	return room.x + room.y * bonus


static func _is_served(params: Params, context: EconomyContext, network: RoadNetwork, house: Dictionary,
		good: StringName, connected: Array[Dictionary]) -> bool:
	if not _hands_out(context, good):
		return true
	for building: Dictionary in connected:
		if good not in context.buildings[building["definition_id"]].distributes:
			continue
		var radius: int = int(params.get_value(StringName("building.%s.service_radius" % building["definition_id"])))
		if radius == 0:
			return true
		var steps: int = network.steps(RoadNetwork.cell_of(building), RoadNetwork.cell_of(house))
		if steps != RoadNetwork.NO_ROUTE and steps <= radius:
			return true
	return false


static func _hands_out(context: EconomyContext, good: StringName) -> bool:
	for definition: BuildingDef in context.buildings.values():
		if good in definition.distributes:
			return true
	return false


# Access of the whole city to a good: each class that needs it weighted by its people; 1 while nobody needs it.
static func _city_access(state: EconomyState, context: EconomyContext, good: StringName) -> float:
	var people: float = 0.0
	var served: float = 0.0
	for def: ClassDef in ClassStates.defs(context):
		if not def.needs.any(func(need: NeedDef) -> bool: return need.good == good):
			continue
		var residents: float = float(ClassStates.population_of(state, def))
		people += residents
		served += residents * state.access(def.id, good)
	return served / people if people > 0.0 else 1.0
