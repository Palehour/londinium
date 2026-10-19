class_name DifficultyDef
extends RefCounted

# A difficulty preset (D-044, D-065): modifiers relative to the values below it (mul or add only, never set).
var id: StringName
var modifiers: Array[Modifier] = []
# Reserved in the format until the events of issue #63; it has no effect yet and must stay empty.
var events: Array = []
