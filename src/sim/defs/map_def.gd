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
# Layers from the historical map import (issue #60). Dock basins are water; streets, standing buildings and terrain
# labels carry no rule yet (#67, #154, #88).
var dock_cells: Array[Vector2i] = []
var road_cells: Array[Vector2i] = []
var existing_cells: Array[Vector2i] = []
# Only cells that are not firm ground: riverbank or marsh.
var terrain: Dictionary[Vector2i, StringName] = {}
