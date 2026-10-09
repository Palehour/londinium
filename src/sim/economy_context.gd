class_name EconomyContext
extends RefCounted

var buildings: Dictionary[StringName, BuildingDef] = {}
var map: MapDef


func _init(catalog: DataCatalog, selected_map: MapDef) -> void:
	# Only structural definitions are exposed here; numbers still go through Params.
	for definition: BuildingDef in catalog.buildings.values():
		var copy: BuildingDef = BuildingDef.new()
		copy.id = definition.id
		copy.tags.assign(definition.tags)
		if definition.recipe != null:
			copy.recipe = RecipeDef.new()
			copy.recipe.inputs.assign(definition.recipe.inputs)
			copy.recipe.outputs.assign(definition.recipe.outputs)
		buildings[copy.id] = copy
	map = MapDef.new()
	map.id = selected_map.id
	map.width = selected_map.width
	map.height = selected_map.height
	map.river_cells.assign(selected_map.river_cells)
	map.cultivable_cells.assign(selected_map.cultivable_cells)


func copy() -> EconomyContext:
	var catalog: DataCatalog = DataCatalog.new()
	catalog.buildings.assign(buildings)
	return EconomyContext.new(catalog, map)


func building_unavailable_reason(id: StringName) -> StringName:
	if not buildings.has(id):
		return &"unknown_building"
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
	if "river" not in tags and cell in map.river_cells:
		return &"requires_land"
	return &""
