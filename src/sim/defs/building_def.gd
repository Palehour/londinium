class_name BuildingDef
extends RefCounted

var id: StringName
var tags: Array[String] = []
var recipe: RecipeDef
# False for buildings only the map puts down, like the standing dense housing (issue #154, D-075).
var buildable: bool = true
