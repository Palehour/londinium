class_name ParameterRanges
extends RefCounted

const INT64_UPPER_BOUND: float = 9223372036854775808.0

const BY_KEY: Dictionary[StringName, Dictionary] = {
	&"startup.seed": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"startup.money": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"startup.population": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"population.hunger_coverage_snap_epsilon": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": false},
	&"population.satisfaction.snap_epsilon": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": false},
	&"population.initial_bread": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"population.growth.hunger_emigration_threshold": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"population.growth.hunger_emigration_recovery": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"defeat.bankruptcy.threshold": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"defeat.hunger.threshold": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.warning_fraction": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.defeat_fraction": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.peak_decay_per_minute": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.minimum_population": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"defeat.hunger.smoothing": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
	&"demolish.refund_ratio": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"demolish.no_jobs_refund_ratio": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	# Above 0, or a repair would be free, and at most 1, or a new wharf would be cheaper (issue #177, D-083).
	&"repair.wharf_cost_ratio": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
	&"demolish.refund_grace_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"defeat.grace_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.duration_seconds": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": false, "max_inclusive": false},
	&"defeat.depopulation.stability_window_seconds": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": false, "max_inclusive": false},
	&"defeat.bankruptcy.duration_seconds": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": false, "max_inclusive": false},
	&"defeat.hunger.duration_seconds": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": false, "max_inclusive": false},
	&"population.growth.hunger_emigration_multiplier": {
		"min": 1.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"population.empty_city_bread_lookahead_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"population.stats_window_seconds": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"stats.fine.span_seconds": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"stats.medium.bucket_seconds": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"stats.medium.span_seconds": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"stats.chapter.bucket_seconds": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	# Cristian on 2026-10-15 (Mason's proposal, D-066): a cap of 1000 to 100000 events, and a cause must last 0 to
	# 30 s to be logged.
	&"stats.causes.max_events": {
		"min": 1000.0, "max": 100000.0, "min_inclusive": true, "max_inclusive": true},
	&"stats.causes.min_duration_seconds": {
		"min": 0.0, "max": 30.0, "min_inclusive": true, "max_inclusive": true},
	# The policy uses -1 for "off" / "no limit" (WheatPolicy), so a price bound must not be negative.
	&"market.wheat.min_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.wheat.max_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	# -1 is the "uninitialised" sentinel of EconomyState.wheat_price, so the base price must not be negative.
	&"market.wheat.base_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.wheat.max_step": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.wheat.reversion": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"market.wheat.storage_capacity": {
		"min": 0.0, "max": 10000.0, "min_inclusive": true, "max_inclusive": true},
	&"market.wheat.decay_fraction_per_minute": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": false},
	&"market.wheat.accumulate_factor": {
		"min": 1.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"policy.wheat.default_accumulate_price": {
		"min": -1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"policy.wheat.default_max_price": {
		"min": -1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"policy.wheat.default_reserve_minutes": {
		"min": 0.0, "max": float(WheatPolicy.MAX_RESERVE_MINUTES), "min_inclusive": true, "max_inclusive": true},
	&"policy.wheat.default_target_stock": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	# Barley (issue #50) walks like wheat, with its own parameters; same bounds as the wheat ones.
	&"market.barley.min_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.barley.max_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.barley.base_price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.barley.max_step": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.barley.reversion": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": true},
	&"market.barley.storage_capacity": {
		"min": 0.0, "max": 10000.0, "min_inclusive": true, "max_inclusive": true},
	&"market.barley.decay_fraction_per_minute": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": false},
	# Malt and beer (issue #51): not traded, so only a warehouse cap and a spoilage rate.
	&"market.malt.storage_capacity": {
		"min": 0.0, "max": 10000.0, "min_inclusive": true, "max_inclusive": true},
	&"market.malt.decay_fraction_per_minute": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": false},
	&"market.beer.storage_capacity": {
		"min": 0.0, "max": 10000.0, "min_inclusive": true, "max_inclusive": true},
	&"market.beer.decay_fraction_per_minute": {
		"min": 0.0, "max": 1.0, "min_inclusive": true, "max_inclusive": false},
	# Share of the wharf's unloading capacity that goes to barley, in whole percent (0 = all wheat).
	&"policy.unloading.default_barley_percent": {
		"min": 0.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
	# How far one notch of the on-screen split moves it, in whole percent (issue #54); 0 would never move.
	&"policy.unloading.step_percent": {
		"min": 1.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
	# Imports (D-025, D-026). A lot is a whole number of units; the tea buffer may be 0 (buy on demand).
	&"market.imported_flour.price_per_lot": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.imported_flour.lot_size": {
		"min": 1.0, "max": 10000.0, "min_inclusive": true, "max_inclusive": true},
	# How many lots of unloading the wharf may owe at once (issue #50); at least one, or no lot could ever be bought.
	&"market.imported_flour.max_debt_lots": {
		"min": 1.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
	&"market.tea.price": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"market.tea.buffer_seconds": {
		"min": 0.0, "max": 3600.0, "min_inclusive": true, "max_inclusive": true},
	&"population.tea.per_person_per_minute": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": false},
	&"population.tea.satisfaction_bonus": {
		"min": 0.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
	&"population.satisfaction.smoothing_per_second": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
	# Money sinks (issue #118). A multiplier below 1 would turn a sink into a discount.
	&"economy.administration.per_building": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": false},
	&"economy.administration.free_buildings": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"economy.administration.max_multiplier": {
		"min": 1.0, "max": INF, "min_inclusive": true, "max_inclusive": false},
	&"economy.construction_escalation.free_copies": {
		"min": 0.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"economy.construction_escalation.per_building": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": false},
	&"economy.construction_escalation.max_multiplier": {
		"min": 1.0, "max": INF, "min_inclusive": true, "max_inclusive": false},
	# Distance model (issue #67, D-070): street cost and upkeep, and the transport rate per unit and metre (issue #186,
	# D-086: the old top of 1 a step of 50 m).
	&"roads.cost": {
		"min": 0.0, "max": 1000.0, "min_inclusive": true, "max_inclusive": true},
	&"roads.upkeep_per_minute": {
		"min": 0.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
	&"transport.cost_per_unit_per_m": {
		"min": 0.0, "max": 0.02, "min_inclusive": true, "max_inclusive": true},
	&"transport.expensive_m": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	&"map.cell_size_m": {
		"min": 1.0, "max": INT64_UPPER_BOUND, "min_inclusive": true, "max_inclusive": false},
	# Bonus of housing capacity for each need category a class meets (issue #86).
	&"needs.housing_bonus_per_category": {
		"min": 0.0, "max": 100.0, "min_inclusive": true, "max_inclusive": true},
}

# Keys with ids in the middle (a category, a class, a good) come from the era's data, so they are matched
# by shape instead of listed: a new era needs no edit here. Bounds are inclusive unless marked exclusive.
const PATTERNS: Array[Dictionary] = [
	{"prefix": "victory.", "suffix": ".threshold", "min": 0.0, "max": INT64_UPPER_BOUND, "integer": true, "max_exclusive": true},
	{"prefix": "victory.", "suffix": ".duration_seconds", "min": 1.0, "max": INT64_UPPER_BOUND, "integer": true, "max_exclusive": true},
	{"prefix": "victory.", "suffix": ".required_minutes", "min": 1.0, "max": INT64_UPPER_BOUND, "integer": true, "max_exclusive": true},
	{"prefix": "needs.", "suffix": ".threshold", "min": 0.0, "max": 100.0, "integer": false},
	# Metres along the streets a building serves the houses around it (issue #67, #186); 0 is the whole map. The top is
	# the old 30 steps of 50 m.
	{"prefix": "building.", "suffix": ".service_radius_m", "min": 0.0, "max": 1500.0, "integer": true},
	# 20 is the base capacity of today's housing: a class that more than doubles its house is not a bonus.
	{"prefix": "class.", "suffix": ".housing_max_bonus", "min": 0.0, "max": 20.0, "integer": true},
	{"prefix": "class.", "suffix": ".value", "min": 0.0, "max": 100.0, "integer": false},
	# Satisfaction of a class (issue #52): weights of what it adds or takes away, and how fast it follows its target.
	{"prefix": "class.", "suffix": ".satisfaction_weight", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".satisfaction.tax_weight", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".satisfaction.overcrowding_weight", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".satisfaction.smoothing_per_second", "min": 0.0, "max": 1.0, "integer": false,
		"min_exclusive": true},
	{"prefix": "class.", "suffix": ".satisfaction.snap_epsilon", "min": 0.0, "max": INF, "integer": false,
		"min_exclusive": true},
	# Growth of a class: thresholds in satisfaction points, hunger ones in coverage (0 to 1), rates per minute.
	{"prefix": "class.", "suffix": ".growth.immigration_threshold", "min": 0.0, "max": 100.0, "integer": false},
	{"prefix": "class.", "suffix": ".growth.emigration_threshold", "min": 0.0, "max": 100.0, "integer": false},
	{"prefix": "class.", "suffix": ".growth.immigration_per_minute", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".growth.emigration_per_minute", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".growth.hunger_emigration_threshold", "min": 0.0, "max": 1.0, "integer": false},
	{"prefix": "class.", "suffix": ".growth.hunger_emigration_recovery", "min": 0.0, "max": 1.0, "integer": false},
	{"prefix": "class.", "suffix": ".growth.hunger_emigration_multiplier", "min": 1.0, "max": INF, "integer": false},
	# Consumption and head tax of a class.
	{"prefix": "class.", "suffix": ".per_person_per_minute", "min": 0.0, "max": INF, "integer": false,
		"min_exclusive": true},
	{"prefix": "class.", "suffix": ".tax.base", "min": 0.0, "max": INT64_UPPER_BOUND, "integer": false},
	# Mobility between classes (issue #53): scores and satisfaction in points, rates per minute, whole seconds.
	{"prefix": "class.", "suffix": ".min_score", "min": 0.0, "max": 100.0, "integer": false},
	{"prefix": "class.", "suffix": ".mobility.promotion.source_satisfaction", "min": 0.0, "max": 100.0, "integer": false},
	{"prefix": "class.", "suffix": ".mobility.promotion.per_minute", "min": 0.0, "max": INF, "integer": false},
	{"prefix": "class.", "suffix": ".mobility.demotion.below", "min": 0.0, "max": 100.0, "integer": false},
	{"prefix": "class.", "suffix": ".mobility.demotion.seconds", "min": 1.0, "max": INT64_UPPER_BOUND, "integer": true},
	{"prefix": "class.", "suffix": ".mobility.demotion.per_minute", "min": 0.0, "max": INF, "integer": false},
]


static func is_valid(key: StringName, value: float) -> bool:
	if key in [&"startup.seed", &"startup.population", &"population.initial_bread", &"defeat.depopulation.duration_seconds", &"defeat.bankruptcy.duration_seconds",
			&"defeat.hunger.duration_seconds", &"defeat.depopulation.minimum_population",
			&"defeat.depopulation.stability_window_seconds", &"population.stats_window_seconds", &"market.wheat.max_step", &"market.wheat.storage_capacity",
			&"policy.wheat.default_target_stock", &"policy.wheat.default_reserve_minutes",
				&"market.imported_flour.lot_size", &"market.imported_flour.max_debt_lots", &"market.tea.buffer_seconds",
				&"market.barley.max_step", &"market.barley.storage_capacity",
				&"market.malt.storage_capacity", &"market.beer.storage_capacity",
				&"policy.unloading.default_barley_percent", &"policy.unloading.step_percent",
				&"needs.housing_bonus_per_category", &"economy.administration.free_buildings",
				&"economy.construction_escalation.free_copies", &"stats.fine.span_seconds",
				&"stats.medium.bucket_seconds", &"stats.medium.span_seconds", &"stats.chapter.bucket_seconds",
				&"stats.causes.max_events", &"stats.causes.min_duration_seconds", &"transport.expensive_m", &"map.cell_size_m"] \
			and value != floor(value):
		return false
	if not BY_KEY.has(key):
		return _pattern_allows(key, value)
	var bounds: Dictionary = BY_KEY[key]
	var minimum: float = bounds["min"]
	var maximum: float = bounds["max"]
	var above_minimum: bool = value >= minimum if bounds["min_inclusive"] else value > minimum
	var below_maximum: bool = value <= maximum if bounds["max_inclusive"] else value < maximum
	return above_minimum and below_maximum


static func _pattern_allows(key: StringName, value: float) -> bool:
	for pattern: Dictionary in PATTERNS:
		if String(key).begins_with(pattern["prefix"]) and String(key).ends_with(pattern["suffix"]):
			if pattern["integer"] and value != floor(value):
				return false
			var above: bool = value > pattern["min"] if pattern.get("min_exclusive", false) else value >= pattern["min"]
			var below: bool = value < pattern["max"] if pattern.get("max_exclusive", false) else value <= pattern["max"]
			return above and below
	return true
