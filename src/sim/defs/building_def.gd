class_name BuildingDef
extends RefCounted

var id: StringName
var tags: Array[String] = []
var recipe: RecipeDef
# False for buildings only the map puts down, like the standing dense housing (issue #154, D-075).
var buildable: bool = true
# Distance model (issue #67): goods it hands out to the houses within its service radius, and goods it supplies
# to other buildings besides its recipe's output (the wharf's barley and imported flour).
var distributes: Array[StringName] = []
var supplies: Array[StringName] = []
# Cells it covers from its cell, the north-west corner, w x h (issue #184, D-086). 1x1 unless the data says otherwise.
var footprint: Vector2i = Vector2i.ONE
# Water buildings (issue #202, D-090): the Params section of its radius (`<coverage>.radius_m`) and of its own source
# (`<water_source>.source_risk`); without a source it drinks from the district's.
var coverage: StringName = &""
var water_source: StringName = &""
# Service buildings (issue #87, D-118): the district attribute it covers (ServiceSystem.ATTRIBUTES), from
# services/<id>.json; empty for any other building.
var service_attribute: StringName = &""
# Another building whose cost, upkeep, wage and jobs it reads (Params aliases its keys); empty: its own.
var priced_as: StringName = &""
