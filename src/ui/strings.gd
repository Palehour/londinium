class_name Strings
extends RefCounted

const HELP: String = "1 %s · 2 %s · 3 %s · 4 %s · 5 %s\nClic: seleccionar/construir · Supr: demoler · Esc: seleccionar\nMover: botón central / WASD / flechas · Zoom: rueda / + / −"
const LOADING: String = "Cargando mapa…"
const LEGEND: String = "Terrenos: tierra · río · cultivable"
const NO_CULTIVABLE_CELLS: String = "Este mapa no tiene casillas cultivables."
const DISABLED_BUILDING: String = "%s (desactivado: %s)"
const SELECT: String = "Selección"
const MODE: String = "Modo: %s · Casilla: %s"
const PENDING: String = "Comando pendiente…"
const SUCCESS: String = "Comando realizado."
const LOAD_ERROR: String = "No se pudo iniciar la partida. Revisá el registro para ver los detalles."
const BUILDING_LABELS: Dictionary[String, String] = {
	"wharf": "Embarcadero",
	"mill": "Molino",
	"bakery": "Panadería",
	"housing": "Vivienda",
	"wheat_field": "Campo de trigo",
}
const REASONS: Dictionary[StringName, String] = {
	&"no_cultivable_cells": NO_CULTIVABLE_CELLS,
	&"unknown_building": "Tipo de edificio desconocido.",
	&"outside_map": "La ubicación está fuera del mapa.",
	&"occupied_cell": "La casilla está ocupada.",
	&"not_cultivable": "La casilla no es cultivable.",
	&"requires_river": "El edificio requiere una casilla de río.",
	&"requires_land": "El edificio requiere una casilla de tierra.",
	&"insufficient_money": "No hay dinero suficiente.",
	&"no_building": "No hay edificio para demoler.",
	&"simulation_defeated": "La partida terminó: no se aceptan comandos.",
}


static func command_result(accepted: bool, reason: StringName) -> String:
	return SUCCESS if accepted else REASONS.get(reason, String(reason))


static func building_label(key: String) -> String:
	return BUILDING_LABELS.get(key, "")
