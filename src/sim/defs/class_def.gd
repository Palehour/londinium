class_name ClassDef
extends RefCounted

# Basis of a class's head tax: the jobs its members hold, or all of its residents.
const TAX_EMPLOYED: StringName = &"employed"
const TAX_RESIDENTS: StringName = &"residents"

var id: StringName
# The class whose state lives in the flat fields of EconomyState (issue #52); exactly one per era.
var base: bool = false
# Whether its members fill the jobs of the buildings (D-021). A class that does not never counts as unemployed.
var takes_jobs: bool = true
# The housing building this class lives in; its capacity is the base the category bonus grows from.
var housing_building: StringName
# Declaration order matters: satisfaction terms are summed in this order.
var needs: Array[NeedDef] = []
# Params keys, resolved by the loader: a class either points at an existing key or owns a new one.
var tax_weight_key: StringName
var overcrowding_weight_key: StringName
var smoothing_key: StringName
var snap_epsilon_key: StringName
var immigration_threshold_key: StringName
var emigration_threshold_key: StringName
var immigration_per_minute_key: StringName
var emigration_per_minute_key: StringName
var hunger_threshold_key: StringName
var hunger_recovery_key: StringName
var hunger_multiplier_key: StringName
# Need categories whose goods a house must have within reach for immigrants to count its room (issue #180, D-085).
# Empty: every house counts, as before the rule.
var served_categories: Array[StringName] = []
var tax_basis: StringName = TAX_EMPLOYED
var tax_base_key: StringName
# Mobility (issue #53): the class people of mobility_from rise into, and fall back from. Empty when the class
# has none. Every key is a Params key, like the blocks above.
var mobility_from: StringName
# Category -> key of the lowest score of this class's category that lets people rise into it.
var promotion_min_score_keys: Dictionary[StringName, StringName] = {}
var promotion_source_satisfaction_key: StringName
var promotion_per_minute_key: StringName
# People fall back when this category stays under the key's score for the key's seconds.
var demotion_category: StringName
var demotion_below_key: StringName
var demotion_seconds_key: StringName
var demotion_per_minute_key: StringName


# The only class of a context that has none (tests that build a bare context): the legacy population keys.
static func legacy() -> ClassDef:
	var result: ClassDef = ClassDef.new()
	result.id = &""
	result.base = true
	result.tax_weight_key = &"population.satisfaction.tax_weight"
	result.overcrowding_weight_key = &"population.satisfaction.overcrowding_weight"
	result.smoothing_key = &"population.satisfaction.smoothing_per_second"
	result.snap_epsilon_key = &"population.satisfaction.snap_epsilon"
	result.immigration_threshold_key = &"population.growth.immigration_threshold"
	result.emigration_threshold_key = &"population.growth.emigration_threshold"
	result.immigration_per_minute_key = &"population.growth.immigration_per_minute"
	result.emigration_per_minute_key = &"population.growth.emigration_per_minute"
	result.hunger_threshold_key = &"population.growth.hunger_emigration_threshold"
	result.hunger_recovery_key = &"population.growth.hunger_emigration_recovery"
	result.hunger_multiplier_key = &"population.growth.hunger_emigration_multiplier"
	result.tax_base_key = &"population.tax.base_per_employed_worker_per_minute"
	return result


func has_mobility() -> bool:
	return mobility_from != &""


func copy() -> ClassDef:
	var result: ClassDef = ClassDef.new()
	result.id = id
	result.base = base
	result.takes_jobs = takes_jobs
	result.housing_building = housing_building
	for need: NeedDef in needs:
		var need_copy: NeedDef = NeedDef.new()
		need_copy.good = need.good
		need_copy.category = need.category
		need_copy.satisfaction_key = need.satisfaction_key
		need_copy.consumption_key = need.consumption_key
		result.needs.append(need_copy)
	result.tax_weight_key = tax_weight_key
	result.overcrowding_weight_key = overcrowding_weight_key
	result.smoothing_key = smoothing_key
	result.snap_epsilon_key = snap_epsilon_key
	result.immigration_threshold_key = immigration_threshold_key
	result.emigration_threshold_key = emigration_threshold_key
	result.immigration_per_minute_key = immigration_per_minute_key
	result.emigration_per_minute_key = emigration_per_minute_key
	result.hunger_threshold_key = hunger_threshold_key
	result.hunger_recovery_key = hunger_recovery_key
	result.hunger_multiplier_key = hunger_multiplier_key
	result.served_categories = served_categories.duplicate()
	result.tax_basis = tax_basis
	result.tax_base_key = tax_base_key
	result.mobility_from = mobility_from
	result.promotion_min_score_keys = promotion_min_score_keys.duplicate()
	result.promotion_source_satisfaction_key = promotion_source_satisfaction_key
	result.promotion_per_minute_key = promotion_per_minute_key
	result.demotion_category = demotion_category
	result.demotion_below_key = demotion_below_key
	result.demotion_seconds_key = demotion_seconds_key
	result.demotion_per_minute_key = demotion_per_minute_key
	return result
