class_name MapDef
extends RefCounted

# The map of a scenario that names none, and of the scripted scenarios and balance tools (D-074).
const DEFAULT_ID: StringName = &"whitechapel_1850s"
const TERRAIN_LABELS: Array[StringName] = [&"riverbank", &"marsh"]
# Chronicler's tags (issue #152): every historic place and liberty of a traced map opens with one of them.
const HISTORY_TAGS: Array[String] = ["[FACT", "[DEBATED]", "[LEGEND]", "[INVENTED]"]
# A map drawn as rows of text (issue #61, D-093): one character per cell, y=0 to the north.
const CELL_TYPES: Dictionary[String, StringName] = {"~": &"river", "D": &"dock", "s": &"stairs", "#": &"street",
	".": &"buildable", "r": &"riverbank"}
# A cell of district_by_cell outside every district; only land that cannot be built may be left so.
const NO_DISTRICT: String = "."
# The water of a district that names no source (D-088): it adds no risk.
const DEFAULT_WATER_SOURCE: StringName = &"neutral"
# The sources a district may drink from (issue #209); each one's risk is a source_risk of the data.
const WATER_SOURCES: Array[StringName] = [&"neutral", &"old_ford", &"lea_bridge"]

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
# Tierra de época (issue #176, D-083). The 1870 houses are free land beside a street where the simulation places plain
# dense housing, never demolished, with the people of period_house_population (issue #180, D-085). A damaged wharf is
# a river cell that can be repaired into a wharf; what that costs is repair.wharf_cost_ratio in data/economy (#177).
# Lot styles are only for drawing (#178): the simulation never reads them.
var period_houses: Array[Vector2i] = []
var period_house_population: Dictionary[Vector2i, int] = {}
var damaged_wharves: Array[Vector2i] = []
var lot_styles: Dictionary[Vector2i, StringName] = {}
# Only on a map drawn as rows of text (issue #61, D-093). The Thames stairs are no land to build on, no street for the
# access and no river. Each district is a parish, read by its id, never by its name (D-089); every buildable cell has
# one. The zones open together while zones.all_unlocked holds (D-091).
var stairs_cells: Array[Vector2i] = []
var district_by_cell: Dictionary[Vector2i, StringName] = {}
var district_names: Dictionary[StringName, String] = {}
var district_water_sources: Dictionary[StringName, StringName] = {}
var zones: Dictionary[StringName, Array] = {}


# A tag and some words after it; "[FACT" also covers a FACT with a margin, like "[FACT ±1]".
static func is_history_note(note: Variant) -> bool:
	if note is not String:
		return false
	for tag: String in HISTORY_TAGS:
		if note.begins_with(tag) and note.length() > tag.length() + 1:
			return true
	return false


# Whether a historic street touches a side of the area from outside it: of any cell on its edge (D-079, D-086).
func beside_road(area: Rect2i) -> bool:
	for cell: Vector2i in EconomyContext.cells_of(area):
		for side: Vector2i in RoadNetwork.SIDES:
			if not area.has_point(cell + side) and cell + side in road_cells:
				return true
	return false
