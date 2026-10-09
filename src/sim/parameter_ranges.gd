class_name ParameterRanges
extends RefCounted

const BY_KEY: Dictionary[StringName, Dictionary] = {
	&"defeat.hunger.smoothing": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
	&"defeat.grace_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"defeat.depopulation.duration_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": true},
	&"defeat.bankruptcy.duration_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": true},
	&"defeat.hunger.duration_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": false, "max_inclusive": true},
	&"population.growth.hunger_emigration_multiplier": {
		"min": 1.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"population.empty_city_bread_lookahead_seconds": {
		"min": 0.0, "max": INF, "min_inclusive": true, "max_inclusive": true},
	&"population.satisfaction.smoothing_per_second": {
		"min": 0.0, "max": 1.0, "min_inclusive": false, "max_inclusive": true},
}


static func is_valid(key: StringName, value: float) -> bool:
	if key in [&"defeat.depopulation.duration_seconds", &"defeat.bankruptcy.duration_seconds",
			&"defeat.hunger.duration_seconds"] and value != floor(value):
		return false
	if not BY_KEY.has(key):
		return true
	var bounds: Dictionary = BY_KEY[key]
	var minimum: float = bounds["min"]
	var maximum: float = bounds["max"]
	var above_minimum: bool = value >= minimum if bounds["min_inclusive"] else value > minimum
	var below_maximum: bool = value <= maximum if bounds["max_inclusive"] else value < maximum
	return above_minimum and below_maximum
