class_name ClassDef
extends RefCounted

var id: StringName
# The housing building this class lives in; its capacity is the base the category bonus grows from.
var housing_building: StringName
# Declaration order matters: satisfaction terms are summed in this order.
var needs: Array[NeedDef] = []
