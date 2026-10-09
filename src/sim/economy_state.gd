class_name EconomyState
extends RefCounted

var stocks: Dictionary[StringName, int] = {}
var money: int = 0
var population: int = 0
var buildings: Array[Dictionary] = []
# Uninitialized market sentinel; zero is a valid saved price.
var wheat_price: int = -1
var tax_rate: float = -1.0
var bread_fraction: float = 0.0
var bread_demand: float = 0.0
var bread_consumed: float = 0.0
var bread_coverage: float = 1.0
var satisfaction: float = 0.0
var satisfaction_target: float = 0.0
var satisfaction_breakdown: Dictionary[String, float] = {}
var housing_capacity: int = 0
var overcrowding: float = 0.0
var employed: int = 0
var unemployed: int = 0
var immigration_fraction: float = 0.0
var emigration_fraction: float = 0.0
var tax_fraction: float = 0.0
var wage_fraction: float = 0.0
var upkeep_fraction: float = 0.0
var bankruptcy: DefeatState = DefeatState.new()
var hunger: DefeatState = DefeatState.new()
var depopulation: DefeatState = DefeatState.new()
var defeat_initialized: bool = false
var defeat_elapsed_seconds: int = 0
var hunger_smoothed_coverage: float = 1.0
var hunger_emigration_active: bool = false
var population_peak: float = 0.0
var depopulation_active: bool = false
var defeat_causes: Array[StringName] = []


func to_dict() -> Dictionary:
	var values: Dictionary = {
		"bankruptcy": bankruptcy.to_dict(), "hunger": hunger.to_dict(),
		"depopulation": depopulation.to_dict(), "defeat_initialized": defeat_initialized,
		"defeat_elapsed_seconds": defeat_elapsed_seconds,
		"hunger_smoothed_coverage": hunger_smoothed_coverage,
		"hunger_emigration_active": hunger_emigration_active,
		"population_peak": population_peak, "depopulation_active": depopulation_active,
		"defeat_causes": defeat_causes.duplicate(),
		"stocks": stocks.duplicate(),
		"money": money,
		"population": population,
		"buildings": buildings.duplicate(true),
		"bread_fraction": bread_fraction, "bread_demand": bread_demand,
		"bread_consumed": bread_consumed, "bread_coverage": bread_coverage,
		"satisfaction": satisfaction, "satisfaction_breakdown": satisfaction_breakdown.duplicate(),
		"satisfaction_target": satisfaction_target,
		"housing_capacity": housing_capacity, "overcrowding": overcrowding,
		"employed": employed, "unemployed": unemployed,
		"immigration_fraction": immigration_fraction, "emigration_fraction": emigration_fraction,
		"tax_fraction": tax_fraction, "wage_fraction": wage_fraction, "upkeep_fraction": upkeep_fraction,
	}
	# Missing price means the market has not been initialized; zero remains explicit.
	if wheat_price >= 0:
		values["wheat_price"] = wheat_price
	if tax_rate >= 0.0:
		values["tax_rate"] = tax_rate
	return values


# Internal conversion: expects the complete value schema produced by to_dict().
static func from_dict(values: Dictionary) -> EconomyState:
	var result: EconomyState = EconomyState.new()
	result.bankruptcy = DefeatState.from_dict(values.get("bankruptcy", {}))
	result.hunger = DefeatState.from_dict(values.get("hunger", {}))
	result.depopulation = DefeatState.from_dict(values.get("depopulation", {}))
	result.defeat_initialized = values.get("defeat_initialized", false)
	result.defeat_elapsed_seconds = values.get("defeat_elapsed_seconds", 0)
	result.hunger_smoothed_coverage = values.get("hunger_smoothed_coverage", 1.0)
	result.hunger_emigration_active = values.get("hunger_emigration_active", false)
	result.population_peak = float(values.get("population_peak", 0.0))
	result.depopulation_active = values.get("depopulation_active", false)
	for cause: Variant in values.get("defeat_causes", []):
		result.defeat_causes.append(StringName(cause))
	result.stocks.assign(values["stocks"])
	result.money = values["money"]
	result.population = values["population"]
	result.wheat_price = values.get("wheat_price", -1)
	result.tax_rate = values.get("tax_rate", -1.0)
	result.bread_fraction = values.get("bread_fraction", 0.0)
	result.bread_demand = values.get("bread_demand", 0.0)
	result.bread_consumed = values.get("bread_consumed", 0.0)
	result.bread_coverage = values.get("bread_coverage", 1.0)
	result.satisfaction = values.get("satisfaction", 0.0)
	result.satisfaction_target = values.get("satisfaction_target", 0.0)
	result.satisfaction_breakdown.assign(values.get("satisfaction_breakdown", {}))
	result.housing_capacity = values.get("housing_capacity", 0)
	result.overcrowding = values.get("overcrowding", 0.0)
	result.employed = values.get("employed", 0)
	result.unemployed = values.get("unemployed", 0)
	result.immigration_fraction = values.get("immigration_fraction", 0.0)
	result.emigration_fraction = values.get("emigration_fraction", 0.0)
	result.tax_fraction = values.get("tax_fraction", 0.0)
	result.wage_fraction = values.get("wage_fraction", 0.0)
	result.upkeep_fraction = values.get("upkeep_fraction", 0.0)
	result.buildings.assign(values["buildings"].duplicate(true))
	return result
