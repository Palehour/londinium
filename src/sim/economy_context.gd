class_name EconomyContext
extends RefCounted

var buildings: Dictionary[StringName, BuildingDef] = {}
# Cells of one street piece (issue #186, D-086).
var road_footprint: Vector2i = Vector2i.ONE
var map: MapDef
var classes: Dictionary[StringName, ClassDef] = {}
# Never changed after loading, so they are shared, not copied (issue #63).
var missions: Dictionary[StringName, MissionDef] = {}


func _init(catalog: DataCatalog, selected_map: MapDef) -> void:
	# Only structural definitions are exposed here; numbers still go through Params.
	for definition: BuildingDef in catalog.buildings.values():
		var copy: BuildingDef = BuildingDef.new()
		copy.id = definition.id
		copy.tags.assign(definition.tags)
		copy.buildable = definition.buildable
		copy.footprint = definition.footprint
		copy.distributes.assign(definition.distributes)
		copy.supplies.assign(definition.supplies)
		copy.coverage = definition.coverage
		copy.water_source = definition.water_source
		copy.priced_as = definition.priced_as
		if definition.recipe != null:
			copy.recipe = RecipeDef.new()
			copy.recipe.inputs.assign(definition.recipe.inputs)
			copy.recipe.outputs.assign(definition.recipe.outputs)
		buildings[copy.id] = copy
	road_footprint = catalog.road_footprint
	for definition: ClassDef in catalog.classes.values():
		classes[definition.id] = definition.copy()
	missions.assign(catalog.missions)
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
	return EconomyContext.new(catalog, map)


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


# Whether the map lets the whole footprint stand from this cell (issue #184, D-086): inside the map and every cell it
# covers fit for the building. Taken cells and streets are the state's, so BuildCommand checks them.
func placement_reason(id: StringName, origin: Vector2i) -> StringName:
	var area: Rect2i = Rect2i(origin, buildings[id].footprint)
	if not Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).encloses(area):
		return &"outside_map"
	for cell: Vector2i in cells_of(area):
		var reason: StringName = terrain_placement_reason(id, cell)
		if reason != &"":
			return reason
	return &""


# The cells a building of the state covers: its cell is the north-west corner of its footprint (D-086). A saved building
# whose type the data no longer has keeps the one cell it always had.
func area_of(building: Dictionary) -> Rect2i:
	var definition: BuildingDef = buildings.get(StringName(building["definition_id"]))
	return Rect2i(RoadNetwork.cell_of(building), definition.footprint if definition != null else Vector2i.ONE)


# The cells a street of the player covers: a whole piece from its cell, the north-west corner (issue #186, D-086).
func road_area(road: Dictionary) -> Rect2i:
	return Rect2i(RoadNetwork.cell_of(road), road_footprint)


# The building of the state that covers the cell, or {} when none does.
func building_at(state: EconomyState, cell: Vector2i) -> Dictionary:
	for building: Dictionary in state.buildings:
		if area_of(building).has_point(cell):
			return building
	return {}


# Row by row from the north-west corner, so every walk over an area goes in the same order.
static func cells_of(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			cells.append(Vector2i(x, y))
	return cells


func terrain_placement_reason(id: StringName, cell: Vector2i) -> StringName:
	var tags: Array[String] = buildings[id].tags
	if "cultivable" in tags and cell not in map.cultivable_cells:
		return &"not_cultivable"
	if "river" in tags and cell not in map.river_cells:
		return &"requires_river"
	# A dock basin is water but not a grain source (D-020): nothing is built on it, nor on the Thames stairs (#61).
	if "river" not in tags and (cell in map.river_cells or cell in map.dock_cells or cell in map.stairs_cells):
		return &"requires_land"
	# Standing buildings, the anchors of the traced map (#152), stay a block (D-075). Only new building is stopped: a
	# saved building on one of these cells stays and works (D-076).
	if cell in map.existing_cells:
		return &"existing_building"
	return &""


# The class whose housing building this is, or &"" when no class claims it.
func class_of_housing(building_id: StringName) -> StringName:
	for definition: ClassDef in classes.values():
		if definition.housing_building == building_id:
			return definition.id
	return &""
