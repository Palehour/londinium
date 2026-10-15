class_name DataLoadResult
extends RefCounted

var catalog: DataCatalog
var errors: Array[String] = []
# Active mods in load order and the values more than one of them set ({key, mods, winner}), see ModLayer.
var mods: Array[StringName] = []
var mod_conflicts: Array[Dictionary] = []


func is_ok() -> bool:
	return catalog != null and errors.is_empty()
