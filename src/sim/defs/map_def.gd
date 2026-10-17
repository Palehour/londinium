class_name MapDef
extends RefCounted

# The map of a scenario that names none, and of the scripted scenarios and balance tools (D-074).
const DEFAULT_ID: StringName = &"whitechapel_1850s"
const TERRAIN_LABELS: Array[StringName] = [&"riverbank", &"marsh"]

var id: StringName
var width: int
var height: int
var river_cells: Array[Vector2i] = []
var cultivable_cells: Array[Vector2i] = []
# Layers from the historical map import (issue #60). Dock basins are water; streets and terrain labels carry no rule
# yet (#67, #88); standing buildings block building until the tracing of #152 (D-075).
var dock_cells: Array[Vector2i] = []
var road_cells: Array[Vector2i] = []
var existing_cells: Array[Vector2i] = []
# Only cells that are not firm ground: riverbank or marsh.
var terrain: Dictionary[Vector2i, StringName] = {}
# Standing buildings where dense housing stands at the start, in order; startup.dense_housing_occupied says how many
# of them (issue #154, D-075, D-079).
var dense_housing_cells: Array[Vector2i] = []


func beside_road(cell: Vector2i) -> bool:
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if cell + side in road_cells:
			return true
	return false
