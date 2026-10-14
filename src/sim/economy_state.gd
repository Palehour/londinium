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
# Per class and category: {value, threshold, met} (issue #86). Derived by NeedsSystem every tick.
var class_needs: Dictionary[StringName, Dictionary] = {}
var overcrowding: float = 0.0
# Every class but the base one (issue #52). The base class keeps its values in the flat fields of this state
# (satisfaction, overcrowding, growth fractions...); population is the total of every class.
var class_states: Dictionary[StringName, ClassState] = {}
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
# Seconds since someone last left because of low satisfaction; -1 means nobody ever has.
var satisfaction_departure_age_seconds: int = -1
var population_peak: float = 0.0
var depopulation_active: bool = false
var defeat_causes: Array[StringName] = []
var wheat_purchases_enabled: bool = true
# Wharf purchase policy (WheatPolicy). The reserve is -1 until the simulation loads the defaults from
# data; that marks the whole policy as pending (-1 is a real value for the two prices: off / no limit).
var wheat_accumulate_price: int = WheatPolicy.OFF
var wheat_max_price: int = WheatPolicy.NO_LIMIT
var wheat_target_stock: int = 0
var wheat_reserve_minutes: int = -1
# Price before the last repricing, for the panel's trend arrow; -1 until the first repricing.
var wheat_previous_price: int = -1
# Wheat lost to damp and rats accumulates here until it makes a whole unit.
var wheat_decay_fraction: float = 0.0
# Barley (issue #50): walks like wheat with its own parameters. The price is -1 until the simulation
# loads it from data, like the wheat one; the stock lives in stocks[&"barley"].
var barley_price: int = -1
var barley_previous_price: int = -1
var barley_decay_fraction: float = 0.0
# Malt and beer (issue #51) are made, not bought: only their spoilage carries over between ticks.
var malt_decay_fraction: float = 0.0
var beer_decay_fraction: float = 0.0
# Share of the wharf's unloading capacity left after the flour that goes to barley, in whole percent; the
# rest is wheat. -1 until the simulation loads the default from data (0 = all wheat).
var unloading_barley_percent: int = -1
# Imported flour is paid for at once, but the wharf has to unload it: the units still owed take the
# capacity of the next ticks before wheat and barley get any (issue #50).
var flour_unloading_debt: float = 0.0
# Imports (D-025, D-026): both are off until the player switches them on (startup data).
var tea_imports_enabled: bool = false
var flour_imports_enabled: bool = false
# Tea eaten but not yet a whole unit, like bread_fraction.
var tea_fraction: float = 0.0
var tea_demand: float = 0.0
var tea_consumed: float = 0.0
var tea_coverage: float = 0.0
# Beer (issue #52) is eaten like tea: the part of a unit already eaten waits in beer_fraction.
var beer_fraction: float = 0.0
var beer_demand: float = 0.0
var beer_consumed: float = 0.0
var beer_coverage: float = 0.0
# Per-tick flows feed the stats window; they are transient and never saved.
var bread_produced_tick: int = 0
var bread_consumed_tick: float = 0.0
var bread_demand_tick: float = 0.0
var taxes_tick: int = 0
var wages_tick: int = 0
var upkeep_tick: int = 0
var wheat_spent_tick: int = 0
var barley_spent_tick: int = 0
# Imports in total (flour and tea), and the tea part of it.
var imports_spent_tick: int = 0
var tea_spent_tick: int = 0
var construction_spent_tick: int = 0
# Head tax each class added to the treasury this tick, before rounding to whole pence (balance probes only).
var class_tax_tick: Dictionary[StringName, float] = {}
# People who rose into another class or fell back from one this tick (issue #53), over every class.
var promotions_tick: int = 0
var demotions_tick: int = 0
# Staffed buildings of each type that ran out of input while they still had capacity this tick (a mill that
# used all its budget on the wheat it had does not count). Transient: never saved.
var input_starved_tick: Dictionary[StringName, int] = {}


func reset_flows() -> void:
	bread_produced_tick = 0
	bread_consumed_tick = 0.0
	bread_demand_tick = 0.0
	taxes_tick = 0
	wages_tick = 0
	upkeep_tick = 0
	wheat_spent_tick = 0
	barley_spent_tick = 0
	imports_spent_tick = 0
	tea_spent_tick = 0
	construction_spent_tick = 0
	class_tax_tick.clear()
	promotions_tick = 0
	demotions_tick = 0
	input_starved_tick.clear()


func to_dict() -> Dictionary:
	var values: Dictionary = {
		"bankruptcy": bankruptcy.to_dict(), "hunger": hunger.to_dict(),
		"depopulation": depopulation.to_dict(), "defeat_initialized": defeat_initialized,
		"defeat_elapsed_seconds": defeat_elapsed_seconds,
		"hunger_smoothed_coverage": hunger_smoothed_coverage,
		"hunger_emigration_active": hunger_emigration_active,
		"satisfaction_departure_age_seconds": satisfaction_departure_age_seconds,
		"population_peak": population_peak, "depopulation_active": depopulation_active,
		"defeat_causes": defeat_causes.duplicate(),
		"wheat_purchases_enabled": wheat_purchases_enabled,
		"wheat_accumulate_price": wheat_accumulate_price, "wheat_max_price": wheat_max_price,
		"wheat_target_stock": wheat_target_stock, "wheat_reserve_minutes": wheat_reserve_minutes,
		"wheat_previous_price": wheat_previous_price,
		"wheat_decay_fraction": wheat_decay_fraction,
		"barley_previous_price": barley_previous_price, "barley_decay_fraction": barley_decay_fraction,
		"malt_decay_fraction": malt_decay_fraction, "beer_decay_fraction": beer_decay_fraction,
		"unloading_barley_percent": unloading_barley_percent,
		"flour_unloading_debt": flour_unloading_debt,
		"tea_imports_enabled": tea_imports_enabled, "flour_imports_enabled": flour_imports_enabled,
		"tea_fraction": tea_fraction, "tea_demand": tea_demand, "tea_consumed": tea_consumed,
		"tea_coverage": tea_coverage,
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
		"class_needs": class_needs.duplicate(true),
		"beer_fraction": beer_fraction, "beer_demand": beer_demand, "beer_consumed": beer_consumed,
		"beer_coverage": beer_coverage,
		"class_states": _class_states_dict(),
	}
	# Missing price means the market has not been initialized; zero remains explicit.
	if wheat_price >= 0:
		values["wheat_price"] = wheat_price
	if barley_price >= 0:
		values["barley_price"] = barley_price
	if tax_rate >= 0.0:
		values["tax_rate"] = tax_rate
	return values


func _class_states_dict() -> Dictionary:
	var result: Dictionary = {}
	for id: StringName in class_states:
		result[id] = class_states[id].to_dict()
	return result


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
	result.satisfaction_departure_age_seconds = int(values.get("satisfaction_departure_age_seconds", -1))
	result.population_peak = float(values.get("population_peak", 0.0))
	result.depopulation_active = values.get("depopulation_active", false)
	result.wheat_purchases_enabled = bool(values.get("wheat_purchases_enabled", true))
	result.wheat_accumulate_price = int(values.get("wheat_accumulate_price", WheatPolicy.OFF))
	result.wheat_max_price = int(values.get("wheat_max_price", WheatPolicy.NO_LIMIT))
	result.wheat_target_stock = int(values.get("wheat_target_stock", 0))
	result.wheat_reserve_minutes = int(values.get("wheat_reserve_minutes", -1))
	result.wheat_previous_price = int(values.get("wheat_previous_price", -1))
	result.wheat_decay_fraction = float(values.get("wheat_decay_fraction", 0.0))
	result.barley_price = int(values.get("barley_price", -1))
	result.barley_previous_price = int(values.get("barley_previous_price", -1))
	result.barley_decay_fraction = float(values.get("barley_decay_fraction", 0.0))
	result.malt_decay_fraction = float(values.get("malt_decay_fraction", 0.0))
	result.beer_decay_fraction = float(values.get("beer_decay_fraction", 0.0))
	result.unloading_barley_percent = int(values.get("unloading_barley_percent", -1))
	result.flour_unloading_debt = float(values.get("flour_unloading_debt", 0.0))
	result.tea_imports_enabled = bool(values.get("tea_imports_enabled", false))
	result.flour_imports_enabled = bool(values.get("flour_imports_enabled", false))
	result.tea_fraction = float(values.get("tea_fraction", 0.0))
	result.tea_demand = float(values.get("tea_demand", 0.0))
	result.tea_consumed = float(values.get("tea_consumed", 0.0))
	result.tea_coverage = float(values.get("tea_coverage", 0.0))
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
	result.class_needs.assign(values.get("class_needs", {}).duplicate(true))
	result.beer_fraction = float(values.get("beer_fraction", 0.0))
	result.beer_demand = float(values.get("beer_demand", 0.0))
	result.beer_consumed = float(values.get("beer_consumed", 0.0))
	result.beer_coverage = float(values.get("beer_coverage", 0.0))
	var saved_classes: Dictionary = values.get("class_states", {})
	for id: Variant in saved_classes:
		result.class_states[StringName(id)] = ClassState.from_dict(saved_classes[id])
	result.buildings.assign(values["buildings"].duplicate(true))
	return result
