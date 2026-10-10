class_name Strings
extends RefCounted

const PENCE_PER_SHILLING: int = 12
const PENCE_PER_POUND: int = 240

const HELP: String = "1 %s · 2 %s · 3 %s · 4 %s · 5 %s\nClic: seleccionar/construir · Supr: demoler · Esc: seleccionar\nMover: botón central / WASD / flechas · Zoom: rueda / + / −"
const LOADING: String = "Cargando mapa…"
const LEGEND: String = "Terrenos:"
const TERRAIN_LABELS: Dictionary[String, String] = {"land": "Tierra", "river": "Río", "cultivable": "Cultivable"}
const NO_CULTIVABLE_CELLS: String = "Este mapa no tiene casillas cultivables."
const DISABLED_BUILDING: String = "%s (desactivado: %s)"
const SELECT: String = "Selección"
const MODE: String = "Modo: %s · Casilla: %s"
const PENDING: String = "Comando pendiente…"
const SUCCESS: String = "Comando realizado."
const LOAD_ERROR: String = "No se pudo iniciar la partida. Revisá el registro para ver los detalles."
const PANEL_TITLE: String = "Estadísticas"
const TAX_LABEL: String = "Impuestos (%)"
const WHEAT_PURCHASES: String = "Comprar trigo automáticamente"
const PAUSE: String = "Pausa"
const RESUME: String = "Reanudar"
const SPEED_LABELS: Dictionary[int, String] = {1: "1x", 2: "2x", 3: "3x"}
const RESTART: String = "Reiniciar partida"
const POPULATION: String = "Población: %d · empleados %d · desempleados %d"
const SATISFACTION: String = "Satisfacción: %.0f/100 (pan +%.0f · impuestos −%.0f · hacinamiento −%.0f)"
const BREAD_RATE: String = "Pan/min: producido %.1f · consumido %.1f · demanda %.1f"
const BREAD_OK: String = "El pan alcanza."
const BREAD_SHORT: String = "Falta pan porque:"
const BREAD_CAUSE: String = "• %s: %s"
const BREAD_CHAIN_CAUSE: String = "• %s"
const STOCKS: String = "Stocks: trigo %d · harina %d · pan %d"
const TREASURY: String = "Tesoro: %s"
const OPERATING_BALANCE: String = "Balance operativo: %s/min"
const BALANCE_BREAKDOWN: String = "  impuestos %s − salarios %s − mantenimiento %s − trigo %s"
const CONSTRUCTION: String = "Construcción: %s/min (aparte del balance)"
const WHEAT_PRICE: String = "Precio del trigo: %s"
const WINDOW_PARTIAL: String = "Promedios sobre %d de %d s"
const BUILDINGS: String = "Trabajadores por edificio"
const NO_BUILDINGS: String = "Sin edificios con puestos."
const BUILDING_STATUS: String = "%s (%d, %d): %d/%d · %s"
const CRISES: String = "Condiciones de derrota"
const CONDITION: String = "%s: %s · %s"
const TIMER: String = " · %d/%d s (quedan %d s)"
const GRACE: String = "Período de gracia: %d s restantes"
const ALERT_WARNING: String = "⚠ Aviso: %s"
const ALERT_DEFEAT: String = "✖ Derrota: %s. Reiniciá para jugar otra vez."
const METRIC_BANKRUPTCY: String = "tesoro %s (umbral %s)"
const METRIC_HUNGER: String = "pan cubierto %.0f %% (umbral %.0f %%)"
const METRIC_DEPOPULATION: String = "población %d de pico %.0f"
const CONDITION_LABELS: Dictionary[StringName, String] = {
	&"bankruptcy": "Quiebra", &"hunger": "Motín de hambre", &"depopulation": "Despoblación",
}
const STATUS_LABELS: Dictionary[StringName, String] = {&"ok": "estable", &"warning": "aviso", &"defeat": "derrota"}
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
	&"no_money_for_wheat": "Sin dinero para comprar trigo.",
	&"no_building": "No hay edificio para demoler.",
	&"simulation_defeated": "La partida terminó: no se aceptan comandos.",
	&"wheat_purchases_disabled": "Compra de trigo desactivada.",
	&"no_workers": "Sin trabajadores.",
	&"no_input": "Sin insumo.",
	&"missing_building": "No hay ninguno construido.",
	&"understaffed": "Faltan trabajadores para cubrir los puestos.",
	&"insufficient_capacity": "La cadena hace menos pan del que se come: hacen falta más edificios.",
	&"invalid_tax_rate": "Tasa de impuestos inválida.",
	&"ok": "Operativo.",
}


static func command_result(accepted: bool, reason: StringName) -> String:
	return SUCCESS if accepted else REASONS.get(reason, String(reason))


static func building_label(key: String) -> String:
	return BUILDING_LABELS.get(key, "")


# The simulation keeps pence; pre-decimal display is 12d = 1s and 20s = £1.
static func money(pence: int) -> String:
	# Split before negating: absi(INT64_MIN) overflows, but its quotient and remainder do not.
	var sign: int = -1 if pence < 0 else 1
	@warning_ignore("integer_division")
	var pounds: int = sign * (pence / PENCE_PER_POUND)
	var rest: int = sign * (pence % PENCE_PER_POUND)
	@warning_ignore("integer_division")
	var shillings: int = rest / PENCE_PER_SHILLING
	return "%s£%d %ds %dd" % ["-" if sign < 0 else "", pounds, shillings, rest % PENCE_PER_SHILLING]


static func reason(key: StringName) -> String:
	return REASONS.get(key, String(key))
