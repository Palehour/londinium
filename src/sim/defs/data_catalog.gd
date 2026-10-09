class_name DataCatalog
extends RefCounted

var goods: Dictionary[StringName, GoodDef] = {}
var buildings: Dictionary[StringName, BuildingDef] = {}
var roles: Dictionary[StringName, RoleDef] = {}
var maps: Dictionary[StringName, MapDef] = {}
var base_values: Dictionary[StringName, Variant] = {}
var money_keys: Array[StringName] = []
var boolean_keys: Array[StringName] = []
