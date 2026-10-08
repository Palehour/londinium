class_name DataLoadResult
extends RefCounted

var catalog: DataCatalog
var errors: Array[String] = []


func is_ok() -> bool:
	return catalog != null and errors.is_empty()
