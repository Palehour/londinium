class_name ClassState
extends RefCounted

# What the simulation keeps for one class (issue #52): its people, how satisfied they are and whether they
# are coming or leaving. The base class lives in the flat fields of EconomyState, so ClassStates copies
# them in and out of one of these when the systems work on it.

# Residents of the class. For the base class this is derived (the total minus the others) and not stored.
var population: int = 0
var takes_jobs: bool = true
var satisfaction: float = 0.0
var satisfaction_target: float = 0.0
var satisfaction_breakdown: Dictionary[String, float] = {}
var housing_capacity: int = 0
var overcrowding: float = 0.0
var immigration_fraction: float = 0.0
var emigration_fraction: float = 0.0
var hunger_emigration_active: bool = false
# Seconds since someone last left because of low satisfaction; -1 means nobody ever has.
var satisfaction_departure_age_seconds: int = -1


func to_dict() -> Dictionary:
	return {
		"population": population, "takes_jobs": takes_jobs,
		"satisfaction": satisfaction, "satisfaction_target": satisfaction_target,
		"satisfaction_breakdown": satisfaction_breakdown.duplicate(),
		"housing_capacity": housing_capacity, "overcrowding": overcrowding,
		"immigration_fraction": immigration_fraction, "emigration_fraction": emigration_fraction,
		"hunger_emigration_active": hunger_emigration_active,
		"satisfaction_departure_age_seconds": satisfaction_departure_age_seconds,
	}


static func from_dict(values: Dictionary) -> ClassState:
	var result: ClassState = ClassState.new()
	result.population = int(values.get("population", 0))
	result.takes_jobs = bool(values.get("takes_jobs", true))
	result.satisfaction = float(values.get("satisfaction", 0.0))
	result.satisfaction_target = float(values.get("satisfaction_target", 0.0))
	result.satisfaction_breakdown.assign(values.get("satisfaction_breakdown", {}))
	result.housing_capacity = int(values.get("housing_capacity", 0))
	result.overcrowding = float(values.get("overcrowding", 0.0))
	result.immigration_fraction = float(values.get("immigration_fraction", 0.0))
	result.emigration_fraction = float(values.get("emigration_fraction", 0.0))
	result.hunger_emigration_active = bool(values.get("hunger_emigration_active", false))
	result.satisfaction_departure_age_seconds = int(values.get("satisfaction_departure_age_seconds", -1))
	return result
