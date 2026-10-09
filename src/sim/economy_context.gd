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
