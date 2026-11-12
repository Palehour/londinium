class_name EconomyContext
extends RefCounted

# Terrain of a dry cell (issue #88): the map leaves firm ground unlabelled (MapDef.TERRAIN_LABELS).
const FIRM: StringName = &"firm"
const RIVERBANK: StringName = &"riverbank"
const MARSH: StringName = &"marsh"

var buildings: Dictionary[StringName, BuildingDef] = {}
# Cells of one street piece (issue #186, D-086).
var road_footprint: Vector2i = Vector2i.ONE
var map: MapDef
var classes: Dictionary[StringName, ClassDef] = {}
# Never changed after loading, so they are shared, not copied (issue #63).
var missions: Dictionary[StringName, MissionDef] = {}
# The era's factions (issue #84); shared like the missions.
var factions: Dictionary[StringName, FactionDef] = {}
# The era's decrees (issue #71); shared like the factions. Competencies come from the scenario, not the era.
var decrees: Dictionary[StringName, DecreeDef] = {}
var decree_competencies: Array[StringName] = []
# Issue #306 (D-164). Filled from the scenario, not from the map: two scenarios can share a map.
# A map with a river ignores them. Not saved; the scenario id loads them again.
const BORDER_SUPPLIER: StringName = &"border"
var import_entries: Array[Vector2i] = []
var import_goods: Array[StringName] = []


func _init(catalog: DataCatalog, selected_map: MapDef) -> void:
	# Only structural definitions are exposed here; numbers still go through Params.
	for definition: BuildingDef in catalog.buildings.values():
		var copy: BuildingDef = BuildingDef.new()
		copy.id = definition.id
		copy.tags.assign(definition.tags)
		copy.buildable = definition.buildable
		copy.footprint = definition.footprint
		copy.rotates = definition.rotates
		copy.allowed_terrain.assign(definition.allowed_terrain)
		copy.terrain_mask.assign(definition.terrain_mask)
		copy.distributes.assign(definition.distributes)
		copy.supplies.assign(definition.supplies)
		copy.coverage = definition.coverage
		copy.water_source = definition.water_source
		copy.priced_as = definition.priced_as
		copy.service_attribute = definition.service_attribute
		if definition.recipe != null:
			copy.recipe = RecipeDef.new()
			copy.recipe.inputs.assign(definition.recipe.inputs)
			copy.recipe.outputs.assign(definition.recipe.outputs)
		buildings[copy.id] = copy
	road_footprint = catalog.road_footprint
	for definition: ClassDef in catalog.classes.values():
		classes[definition.id] = definition.copy()
	missions.assign(catalog.missions)
	factions.assign(catalog.factions)
	decrees.assign(catalog.decrees)
	map = MapDef.new()
	map.id = selected_map.id
	map.width = selected_map.width
	map.height = selected_map.height
	map.river_cells.assign(selected_map.river_cells)
	map.cultivable_cells.assign(selected_map.cultivable_cells)
	map.dock_cells.assign(selected_map.dock_cells)
	map.road_cells.assign(selected_map.road_cells)
	map.existing_cells.assign(selected_map.existing_cells)
	map.terrain.assign(selected_map.terrain)
	map.dense_housing_cells.assign(selected_map.dense_housing_cells)
	map.anchors.assign(selected_map.anchors)
	map.anchor_historical_refs.assign(selected_map.anchor_historical_refs)
	map.named_sites.assign(selected_map.named_sites)
	map.period_houses.assign(selected_map.period_houses)
	map.period_house_population.assign(selected_map.period_house_population)
	map.damaged_wharves.assign(selected_map.damaged_wharves)
	map.lot_styles.assign(selected_map.lot_styles)
	map.roads_enabled = selected_map.roads_enabled
	map.road_diagonals.assign(selected_map.road_diagonals)
	map.stairs_cells.assign(selected_map.stairs_cells)
	map.district_by_cell.assign(selected_map.district_by_cell)
	map.district_names.assign(selected_map.district_names)
	map.district_water_sources.assign(selected_map.district_water_sources)
	map.zones.assign(selected_map.zones)


func copy() -> EconomyContext:
	var catalog: DataCatalog = DataCatalog.new()
	catalog.buildings.assign(buildings)
	catalog.road_footprint = road_footprint
	catalog.classes.assign(classes)
	catalog.missions.assign(missions)
	catalog.factions.assign(factions)
	catalog.decrees.assign(decrees)
	var copied: EconomyContext = EconomyContext.new(catalog, map)
	copied.import_entries.assign(import_entries)
	copied.import_goods.assign(import_goods)
	copied.decree_competencies.assign(decree_competencies)
	return copied


# The edge supplies imports only on a map with no river, and only the goods the scenario lists (D-164).
func border_import_active() -> bool:
	return map.river_cells.is_empty() and not import_entries.is_empty()


func border_supplies(good: StringName) -> bool:
	return border_import_active() and good in import_goods


# Cells and goods from a data/scenarios entry. Missing keys clear the previous scenario.
func apply_border(scenario: Dictionary) -> void:
	import_entries.clear()
	import_goods.clear()
	var cells: Variant = scenario.get("import_entries", [])
	if cells is Array:
		for cell: Variant in cells:
			if cell is Vector2i:
				import_entries.append(cell)
			elif cell is Array and cell.size() >= 2:
				import_entries.append(Vector2i(int(cell[0]), int(cell[1])))
	var goods: Variant = scenario.get("import_goods", [])
	if goods is Array:
		for good: Variant in goods:
			import_goods.append(StringName(str(good)))


func building_unavailable_reason(id: StringName) -> StringName:
	if not buildings.has(id):
		return &"unknown_building"
	if not buildings[id].buildable:
		return &"not_buildable"
	if "cultivable" in buildings[id].tags and map.cultivable_cells.is_empty():
		return &"no_cultivable_cells"
	for x: int in range(map.width):
		for y: int in range(map.height):
			if placement_reason(id, Vector2i(x, y)) == &"":
				return &""
	return &"requires_river" if "river" in buildings[id].tags else &"requires_land"


# Quarter turns, clockwise (issue #296, D-157). 1 turns a 2x1 into a 1x2; the north-west corner stays the origin.
const QUARTER_TURNS: int = 4


static func rotation_of(building: Dictionary) -> int:
	var raw: Variant = building.get("rotation", 0)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return 0
	var rotation: int = int(raw)
	if rotation < 0 or rotation >= QUARTER_TURNS:
		return 0
	return rotation


static func rotated_size(footprint: Vector2i, rotation: int) -> Vector2i:
	if posmod(rotation, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


# Where a cell of the rotated footprint sits in the unrotated mask. Rotation 1 is 90° clockwise.
static func unrotated_offset(footprint: Vector2i, rotation: int, rotated: Vector2i) -> Vector2i:
	match posmod(rotation, QUARTER_TURNS):
		1:
			return Vector2i(rotated.y, footprint.y - 1 - rotated.x)
		2:
			return Vector2i(footprint.x - 1 - rotated.x, footprint.y - 1 - rotated.y)
		3:
			return Vector2i(footprint.x - 1 - rotated.y, rotated.x)
		_:
			return rotated


# Whether the map lets the whole footprint stand from this cell (issue #184, D-086): inside the map and every cell it
# covers fit for the building. Taken cells and streets are the state's, so BuildCommand checks them. `rotation` is a
# quarter turn clockwise (issue #296, D-157); the wharf refuses any turn.
func placement_reason(id: StringName, origin: Vector2i, rotation: int = 0) -> StringName:
	var definition: BuildingDef = buildings[id]
	if rotation < 0 or rotation >= QUARTER_TURNS or (not definition.rotates and rotation != 0):
		return &"cannot_rotate"
	var area: Rect2i = Rect2i(origin, rotated_size(definition.footprint, rotation))
	if not Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).encloses(area):
		return &"outside_map"
	for cell: Vector2i in cells_of(area):
		var reason: StringName = terrain_placement_reason(id, cell,
			unrotated_offset(definition.footprint, rotation, cell - origin))
		if reason != &"":
			return reason
	return &""


# The cells a building of the state covers: its cell is the north-west corner of its footprint (D-086), turned by the
# rotation it was built with (D-157). A saved building whose type the data no longer has keeps the one cell it always had.
func area_of(building: Dictionary) -> Rect2i:
	var definition: BuildingDef = buildings.get(StringName(building["definition_id"]))
	if definition == null:
		return Rect2i(RoadNetwork.cell_of(building), Vector2i.ONE)
	var rotation: int = 0 if not definition.rotates else rotation_of(building)
	return Rect2i(RoadNetwork.cell_of(building), rotated_size(definition.footprint, rotation))


# The cells a street of the player covers: a whole piece from its cell, the north-west corner (issue #186, D-086).
func road_area(road: Dictionary) -> Rect2i:
	return Rect2i(RoadNetwork.cell_of(road), road_footprint)


# The building of the state that covers the cell, or {} when none does.
func building_at(state: EconomyState, cell: Vector2i) -> Dictionary:
	for building: Dictionary in state.buildings:
		if area_of(building).has_point(cell):
			return building
	return {}


# The terrain of a dry cell now: what the player transformed it into (issue #88, D-148), else the map's label, else
# firm ground.
func terrain_at(state: EconomyState, cell: Vector2i) -> StringName:
	if state.terrain_changes.has(cell):
		return state.terrain_changes[cell]
	return map.terrain.get(cell, FIRM)


# The river and the dock basins (D-020) are water.
func is_water(cell: Vector2i) -> bool:
	return cell in map.river_cells or cell in map.dock_cells


# Row by row from the north-west corner, so every walk over an area goes in the same order.
static func cells_of(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			cells.append(Vector2i(x, y))
	return cells


# Whether the cell suits the cell of the footprint at offset from its north-west corner (issue #88, D-152): the river
# where the terrain mask says so, otherwise land of a terrain the building allows (D-149, D-151).
func terrain_placement_reason(id: StringName, cell: Vector2i, offset: Vector2i = Vector2i.ZERO) -> StringName:
	var definition: BuildingDef = buildings[id]
	if "cultivable" in definition.tags and cell not in map.cultivable_cells:
		return &"not_cultivable"
	var wanted: Array[StringName] = _terrains_at(definition, offset)
	if wanted == [DataLoader.MASK_RIVER]:
		return &"" if cell in map.river_cells else &"requires_river"
	# A dock basin is water but not a grain source (D-020): nothing is built on it, nor on the Thames stairs (#61).
	if cell in map.river_cells or cell in map.dock_cells or cell in map.stairs_cells:
		return &"requires_land"
	# Standing buildings, the anchors of the traced map (#152), stay a block (D-075). Only new building is stopped: a
	# saved building on one of these cells stays and works (D-076).
	if cell in map.existing_cells:
		return &"existing_building"
	var terrain: StringName = map.terrain.get(cell, FIRM)
	if terrain in wanted:
		return &""
	# Nothing is built on a marsh until it is drained (D-136).
	if terrain == MARSH:
		return &"marsh"
	return StringName("requires_%s" % wanted[0])


# The terrains one cell of the footprint may stand on: its label in the mask, or any the building allows.
static func _terrains_at(definition: BuildingDef, offset: Vector2i) -> Array[StringName]:
	var terrains: Array[StringName] = []
	if not definition.terrain_mask.is_empty():
		terrains.append(definition.terrain_mask[offset.y * definition.footprint.x + offset.x])
	elif definition.allowed_terrain.is_empty():
		terrains.append(FIRM)
	else:
		terrains.assign(definition.allowed_terrain)
	return terrains


# The class whose housing building this is, or &"" when no class claims it.
func class_of_housing(building_id: StringName) -> StringName:
	for definition: ClassDef in classes.values():
		if definition.housing_building == building_id:
			return definition.id
	return &""
