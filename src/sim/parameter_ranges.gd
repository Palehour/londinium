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
	&"defeat.grace_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.duration_seconds": {
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
	&"population.satisfaction.smoothing_per_second": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
}


static func is_valid(key: StringName, value: float) -> bool:
	if key in [&"startup.seed", &"startup.population", &"population.initial_bread", &"defeat.depopulation.duration_seconds", &"defeat.bankruptcy.duration_seconds",
			&"defeat.hunger.duration_seconds", &"defeat.depopulation.minimum_population"] \
			and value != floor(value):
		return false
	if not BY_KEY.has(key):
		return true
	var bounds: Dictionary = BY_KEY[key]
	var minimum: float = bounds["min"]
	var maximum: float = bounds["max"]
	var above_minimum: bool = value >= minimum if bounds["min_inclusive"] else value > minimum
	var below_maximum: bool = value <= maximum if bounds["max_inclusive"] else value < maximum
	return above_minimum and below_maximum
