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
