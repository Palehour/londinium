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
# Layers from the historical map import (issue #60). Dock basins are water; terrain labels carry no rule yet (#88);
# standing buildings block building (D-075). The streets are the historic network of the
# distance model (#67).
var dock_cells: Array[Vector2i] = []
var road_cells: Array[Vector2i] = []
var existing_cells: Array[Vector2i] = []
# Only cells that are not firm ground: riverbank or marsh.
var terrain: Dictionary[Vector2i, StringName] = {}
# Whether this map plays the distance model (D-080): true on the strip, false on the 8x8 of the harness (D-070).
var roads_enabled: bool = false
# Diagonal edges between historic street cells, as (x1, y1, x2, y2) (D-058); only these connect corner to corner.
var road_diagonals: Array[Vector4i] = []
# Standing buildings where dense housing stands at the start, in order; startup.dense_housing_occupied says how many
# of them (issue #154, D-075, D-079).
var dense_housing_cells: Array[Vector2i] = []
# Historic anchors of the traced map (issue #152): cell to the building that stands there from the start, &"" for one
# with no use. None is ever demolished. Named sites are only a name on a cell and block nothing.
var anchors: Dictionary[Vector2i, StringName] = {}
var named_sites: Dictionary[Vector2i, String] = {}


func beside_road(cell: Vector2i) -> bool:
	for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if cell + side in road_cells:
			return true
	return false
