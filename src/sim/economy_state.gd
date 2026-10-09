class_name EconomyState
extends RefCounted

var stocks: Dictionary[StringName, int] = {}
var money: int = 0
var population: int = 0
var buildings: Array[Dictionary] = []
# Uninitialized market sentinel; zero is a valid saved price.
var wheat_price: int = -1


func to_dict() -> Dictionary:
	var values: Dictionary = {
		"stocks": stocks.duplicate(),
		"money": money,
		"population": population,
		"buildings": buildings.duplicate(true),
	}
	# Missing price means the market has not been initialized; zero remains explicit.
	if wheat_price >= 0:
		values["wheat_price"] = wheat_price
	return values


# Internal conversion: expects the complete value schema produced by to_dict().
static func from_dict(values: Dictionary) -> EconomyState:
	var result: EconomyState = EconomyState.new()
	result.stocks.assign(values["stocks"])
	result.money = values["money"]
	result.population = values["population"]
	result.wheat_price = values.get("wheat_price", -1)
	result.buildings.assign(values["buildings"].duplicate(true))
	return result
