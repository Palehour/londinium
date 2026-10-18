class_name EconomyContext
extends RefCounted

var buildings: Dictionary[StringName, BuildingDef] = {}
var map: MapDef
var classes: Dictionary[StringName, ClassDef] = {}


func _init(catalog: DataCatalog, selected_map: MapDef) -> void:
	# Only structural definitions are exposed here; numbers still go through Params.
	for definition: BuildingDef in catalog.buildings.values():
		var copy: BuildingDef = BuildingDef.new()
		copy.id = definition.id
		copy.tags.assign(definition.tags)
		copy.buildable = definition.buildable
		copy.distributes.assign(definition.distributes)
		copy.supplies.assign(definition.supplies)
		if definition.recipe != null:
			copy.recipe = RecipeDef.new()
			copy.recipe.inputs.assign(definition.recipe.inputs)
			copy.recipe.outputs.assign(definition.recipe.outputs)
		buildings[copy.id] = copy
	for definition: ClassDef in catalog.classes.values():
		classes[definition.id] = definition.copy()
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
	map.roads_enabled = selected_map.roads_enabled
	map.road_diagonals.assign(selected_map.road_diagonals)


func copy() -> EconomyContext:
	var catalog: DataCatalog = DataCatalog.new()
	catalog.buildings.assign(buildings)
	catalog.classes.assign(classes)
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
			if terrain_placement_reason(id, Vector2i(x, y)) == &"":
				return &""
	return &"requires_river" if "river" in buildings[id].tags else &"requires_land"


func terrain_placement_reason(id: StringName, cell: Vector2i) -> StringName:
	var tags: Array[String] = buildings[id].tags
	if "cultivable" in tags and cell not in map.cultivable_cells:
		return &"not_cultivable"
	if "river" in tags and cell not in map.river_cells:
		return &"requires_river"
	# A dock basin is water but not a grain source (D-020): nothing is built on it.
	if "river" not in tags and (cell in map.river_cells or cell in map.dock_cells):
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
