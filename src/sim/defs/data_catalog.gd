class_name DataCatalog
extends RefCounted

var goods: Dictionary[StringName, GoodDef] = {}
var buildings: Dictionary[StringName, BuildingDef] = {}
# Cells of one street piece, economy/roads.json (issue #186, D-086): the historic streets are made of these and the
# player places one at a time.
var road_footprint: Vector2i = Vector2i.ONE
var roles: Dictionary[StringName, RoleDef] = {}
var maps: Dictionary[StringName, MapDef] = {}
var classes: Dictionary[StringName, ClassDef] = {}
var scenarios: Dictionary[StringName, Dictionary] = {}
var difficulties: Dictionary[StringName, DifficultyDef] = {}
var knobs: Dictionary[StringName, KnobDef] = {}
var categories: Array[StringName] = []
var base_values: Dictionary[StringName, Variant] = {}
var money_keys: Array[StringName] = []
var integer_keys: Array[StringName] = []
var boolean_keys: Array[StringName] = []
