class_name EconomyState
extends RefCounted

var stocks: Dictionary[StringName, int] = {}
var money: int = 0
var population: int = 0
var buildings: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {
		"stocks": stocks.duplicate(),
		"money": money,
		"population": population,
		"buildings": buildings.duplicate(true),
	}


static func from_dict(values: Dictionary) -> EconomyState:
	var result: EconomyState = EconomyState.new()
	result.stocks.assign(values["stocks"])
	result.money = values["money"]
	result.population = values["population"]
	result.buildings.assign(values["buildings"].duplicate(true))
	return result
