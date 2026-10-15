class_name Strings
extends RefCounted

const PENCE_PER_SHILLING: int = 12
const PENCE_PER_POUND: int = 240

# Endonyms. The captions stay these words in both languages, so the player can
# find their own from the other one. They are not keys in locale/ui.csv.
const LOCALE_ES: String = "Español"
const LOCALE_EN: String = "English"

# Phrase keys. The words live in locale/ui.csv. Placeholder order is the contract:
# GDScript's % operator cannot reorder them, so every language keeps the same order.
const DIFFICULTY_KEYS: Array[StringName] = [
	&"ui.difficulty_values", &"ui.mods_toggle", &"ui.mods_active", &"ui.mods_inactive",
	&"ui.difficulty", &"ui.difficulty_start", &"ui.difficulty_cancel", &"ui.difficulty_normal",
	&"ui.difficulty_easy", &"ui.difficulty_hard", &"ui.knob_defeat_enabled", &"ui.knob_reaction_seconds",
	&"ui.knob_grace_seconds", &"ui.knob_startup_money", &"ui.knob_volatility", &"ui.knob_refund_ratio",
	&"ui.mods_order", &"ui.mods_up", &"ui.mods_down", &"ui.difficulty_validate", &"ui.difficulty_valid",
	&"ui.mods_conflict", &"ui.mods_save_error",
]

const HELP: StringName = &"ui.help"
const LOADING: StringName = &"ui.loading"
const LEGEND: StringName = &"ui.legend"
const NO_CULTIVABLE_CELLS: StringName = &"ui.no_cultivable_cells"
const DISABLED_BUILDING: StringName = &"ui.disabled_building"
const SELECT: StringName = &"ui.select"
const MODE: StringName = &"ui.mode"
const PENDING: StringName = &"ui.pending"
const SUCCESS: StringName = &"ui.success"
const LOAD_ERROR: StringName = &"ui.load_error"
const PANEL_TITLE: StringName = &"ui.panel_title"
const TAX_LABEL: StringName = &"ui.tax_label"
const WHEAT_PURCHASES: StringName = &"ui.wheat_purchases"
const ACCUMULATE_LABEL: StringName = &"ui.accumulate_label"
const MAX_PRICE_LABEL: StringName = &"ui.max_price_label"
const TARGET_LABEL: StringName = &"ui.target_label"
const RESERVE_LABEL: StringName = &"ui.reserve_label"
const WHEAT_ROW: StringName = &"ui.wheat_row"
const BARLEY_ROW: StringName = &"ui.barley_row"
const MALT_BEER_ROW: StringName = &"ui.malt_beer_row"
const UNLOADING_LABEL: StringName = &"ui.unloading_label"
const WHEAT_BLOCKED_NOTE: StringName = &"ui.wheat_blocked_note"
const MINUTES_COVERED: StringName = &"ui.minutes_covered"
const PAUSE: StringName = &"ui.pause"
const RESUME: StringName = &"ui.resume"
const RESTART: StringName = &"ui.restart"
const POPULATION: StringName = &"ui.population"
const SATISFACTION: StringName = &"ui.satisfaction"
const BREAD_RATE: StringName = &"ui.bread_rate"
const BREAD_OK: StringName = &"ui.bread_ok"
const BREAD_SHORT: StringName = &"ui.bread_short"
const BREAD_CAUSE: StringName = &"ui.bread_cause"
const BREAD_CHAIN_CAUSE: StringName = &"ui.bread_chain_cause"
const STOCKS: StringName = &"ui.stocks"
const TREASURY: StringName = &"ui.treasury"
const OPERATING_BALANCE: StringName = &"ui.operating_balance"
const BALANCE_BREAKDOWN: StringName = &"ui.balance_breakdown"
const CONSTRUCTION: StringName = &"ui.construction"
const WHEAT_PRICE: StringName = &"ui.wheat_price"
const TEA_IMPORTS: StringName = &"ui.tea_imports"
const FLOUR_IMPORTS: StringName = &"ui.flour_imports"
const TEA_ROW: StringName = &"ui.tea_row"
const FLOUR_ROW: StringName = &"ui.flour_row"
const WINDOW_PARTIAL: StringName = &"ui.window_partial"
const BUILDINGS: StringName = &"ui.buildings"
const NO_BUILDINGS: StringName = &"ui.no_buildings"
const BUILDING_STATUS: StringName = &"ui.building_status"
const CRISES: StringName = &"ui.crises"
const CONDITION: StringName = &"ui.condition"
const TIMER: StringName = &"ui.timer"
const GRACE: StringName = &"ui.grace"
const ALERT_WARNING: StringName = &"ui.alert_warning"
const ALERT_DEFEAT: StringName = &"ui.alert_defeat"
const METRIC_BANKRUPTCY: StringName = &"ui.metric_bankruptcy"
const METRIC_HUNGER: StringName = &"ui.metric_hunger"
const METRIC_DEPOPULATION: StringName = &"ui.metric_depopulation"
const NEEDS_TITLE: StringName = &"ui.needs_title"
const CLASS_HEADER: StringName = &"ui.class_header"
const COVERAGE_ROW: StringName = &"ui.coverage_row"
const GOOD_COVERAGE: StringName = &"ui.good_coverage"
const PROMOTION_ACTIVE: StringName = &"ui.promotion_active"
const PROMOTION_BLOCKED: StringName = &"ui.promotion_blocked"
const PROMOTION_BLOCKER: StringName = &"ui.promotion_blocker"
const PROMOTION_CATEGORY_BELOW: StringName = &"ui.promotion_category_below"
const PROMOTION_CATEGORY_REASON: StringName = &"ui.promotion_category_reason"
const PROMOTION_SATISFACTION_LOW: StringName = &"ui.promotion_satisfaction_low"
const NEEDS_MET: StringName = &"ui.needs_met"
const NEEDS_SHORT: StringName = &"ui.needs_short"
const NEEDS_SHORT_REASON: StringName = &"ui.needs_short_reason"
const NEEDS_NO_CLASS: StringName = &"ui.needs_no_class"
const HOUSING_ROW: StringName = &"ui.housing_row"
const MOBILITY_PROMOTED: StringName = &"ui.mobility_promoted"
const MOBILITY_DEMOTED: StringName = &"ui.mobility_demoted"

# Same in both languages: currency, arrows, speeds, and the empty-coverage mark.
const PENCE_SUFFIX: String = " d"
const TREND_UP: String = "↑"
const TREND_DOWN: String = "↓"
const TREND_FLAT: String = "→"
const NO_MILL_COVERAGE: String = "—"
const SPEED_LABELS: Dictionary[int, String] = {1: "1x", 2: "2x", 3: "3x"}
const UNIT_PRICE: String = "%.2f d"

const TERRAIN_LABELS: Dictionary[String, StringName] = {
	"land": &"ui.terrain.land", "river": &"ui.terrain.river", "cultivable": &"ui.terrain.cultivable",
}
const CONDITION_LABELS: Dictionary[StringName, StringName] = {
	&"bankruptcy": &"ui.condition.bankruptcy", &"hunger": &"ui.condition.hunger",
	&"depopulation": &"ui.condition.depopulation",
}
const STATUS_LABELS: Dictionary[StringName, StringName] = {
	&"ok": &"ui.status.ok", &"warning": &"ui.status.warning", &"defeat": &"ui.status.defeat",
}
const BUILDING_LABELS: Dictionary[String, StringName] = {
	"wharf": &"ui.building.wharf",
	"mill": &"ui.building.mill",
	"bakery": &"ui.building.bakery",
	"housing": &"ui.building.housing",
	"wheat_field": &"ui.building.wheat_field",
	"malthouse": &"ui.building.malthouse",
	"brewery": &"ui.building.brewery",
	"artisan_housing": &"ui.building.artisan_housing",
}
const CLASS_LABELS: Dictionary[StringName, StringName] = {
	&"worker": &"ui.class.worker", &"artisan": &"ui.class.artisan",
}
const CATEGORY_LABELS: Dictionary[StringName, StringName] = {
	&"sustento": &"ui.category.sustento", &"abrigo": &"ui.category.abrigo", &"salud": &"ui.category.salud",
	&"comunidad": &"ui.category.comunidad", &"estatus": &"ui.category.estatus",
}
const GOOD_LABELS: Dictionary[StringName, StringName] = {
	&"wheat": &"ui.good.wheat", &"barley": &"ui.good.barley", &"flour": &"ui.good.flour", &"bread": &"ui.good.bread",
	&"malt": &"ui.good.malt", &"beer": &"ui.good.beer", &"tea": &"ui.good.tea",
}
const REASONS: Dictionary[StringName, StringName] = {
	&"arriving": &"ui.reason.arriving",
	&"no_free_housing": &"ui.reason.no_free_housing",
	&"satisfaction_below_threshold": &"ui.reason.satisfaction_below_threshold",
	&"hungry_leaving": &"ui.reason.hungry_leaving",
	&"unhappy_leaving": &"ui.reason.unhappy_leaving",
	&"stable": &"ui.reason.stable",
	&"no_source_population": &"ui.reason.no_source_population",
	&"category_below": &"ui.reason.category_below",
	&"source_satisfaction_low": &"ui.reason.source_satisfaction_low",
	&"below_threshold": &"ui.reason.below_threshold",
	&"unreachable_threshold": &"ui.reason.unreachable_threshold",
	&"no_cultivable_cells": NO_CULTIVABLE_CELLS,
	&"unknown_building": &"ui.reason.unknown_building",
	&"outside_map": &"ui.reason.outside_map",
	&"occupied_cell": &"ui.reason.occupied_cell",
	&"not_cultivable": &"ui.reason.not_cultivable",
	&"requires_river": &"ui.reason.requires_river",
	&"requires_land": &"ui.reason.requires_land",
	&"insufficient_money": &"ui.reason.insufficient_money",
	&"no_money_for_wheat": &"ui.reason.no_money_for_wheat",
	&"no_building": &"ui.reason.no_building",
	&"simulation_defeated": &"ui.reason.simulation_defeated",
	&"wheat_purchases_disabled": &"ui.reason.wheat_purchases_disabled",
	&"wheat_price_above_max": WHEAT_BLOCKED_NOTE,
	&"tea_imports_disabled": &"ui.reason.tea_imports_disabled",
	&"flour_imports_disabled": &"ui.reason.flour_imports_disabled",
	&"no_wharf_for_imports": &"ui.reason.no_wharf_for_imports",
	&"no_money_for_imports": &"ui.reason.no_money_for_imports",
	&"wharf_unloading_busy": &"ui.reason.wharf_unloading_busy",
	&"mill_covers_flour": &"ui.reason.mill_covers_flour",
	&"invalid_wheat_policy": &"ui.reason.invalid_wheat_policy",
	&"invalid_unloading_split": &"ui.reason.invalid_unloading_split",
	&"no_workers": &"ui.reason.no_workers",
	&"no_input": &"ui.reason.no_input",
	&"no_barley": &"ui.reason.no_barley",
	&"no_malt": &"ui.reason.no_malt",
	&"storage_full": &"ui.reason.storage_full",
	&"missing_building": &"ui.reason.missing_building",
	&"understaffed": &"ui.reason.understaffed",
	&"insufficient_capacity": &"ui.reason.insufficient_capacity",
	&"invalid_tax_rate": &"ui.reason.invalid_tax_rate",
	&"ok": &"ui.reason.ok",
}


static var _translations_loaded: bool = false


static func text(key: StringName) -> String:
	_ensure_translations()
	return TranslationServer.translate(key)


static func use_default_locale() -> void:
	set_locale("es")


# The generated .translation files are gitignored, so project.godot does not list them:
# a clean --import would log "Cannot open file" before the CSV importer creates them.
static func set_locale(locale: String) -> void:
	_ensure_translations()
	TranslationServer.set_locale(locale)


static func _ensure_translations() -> void:
	if _translations_loaded:
		return
	var spanish: Resource = load("res://locale/ui.es.translation")
	var english: Resource = load("res://locale/ui.en.translation")
	if not (spanish is Translation) or not (english is Translation):
		return
	TranslationServer.add_translation(spanish as Translation)
	TranslationServer.add_translation(english as Translation)
	_translations_loaded = true


static func command_result(accepted: bool, reason_id: StringName) -> String:
	return text(SUCCESS) if accepted else reason(reason_id)


static func building_label(key: String) -> String:
	if not BUILDING_LABELS.has(key):
		return ""
	return text(BUILDING_LABELS[key])


# Label of an id, falling back to the id itself so a new era's data still reads before its text is written.
static func label(labels: Dictionary[StringName, StringName], key: StringName) -> String:
	if not labels.has(key):
		return String(key)
	return text(labels[key])


static func reason(key: StringName) -> String:
	if not REASONS.has(key):
		return String(key)
	return text(REASONS[key])


static func all_keys() -> Array[StringName]:
	var keys: Array[StringName] = [
		HELP, LOADING, LEGEND, NO_CULTIVABLE_CELLS, DISABLED_BUILDING, SELECT, MODE, PENDING, SUCCESS,
		LOAD_ERROR, PANEL_TITLE, TAX_LABEL, WHEAT_PURCHASES, ACCUMULATE_LABEL, MAX_PRICE_LABEL, TARGET_LABEL,
		RESERVE_LABEL, WHEAT_ROW, BARLEY_ROW, MALT_BEER_ROW, UNLOADING_LABEL, WHEAT_BLOCKED_NOTE,
		MINUTES_COVERED, PAUSE, RESUME, RESTART, POPULATION, SATISFACTION, BREAD_RATE, BREAD_OK, BREAD_SHORT,
		BREAD_CAUSE, BREAD_CHAIN_CAUSE, STOCKS, TREASURY, OPERATING_BALANCE, BALANCE_BREAKDOWN, CONSTRUCTION,
		WHEAT_PRICE, TEA_IMPORTS, FLOUR_IMPORTS, TEA_ROW, FLOUR_ROW, WINDOW_PARTIAL, BUILDINGS, NO_BUILDINGS,
		BUILDING_STATUS, CRISES, CONDITION, TIMER, GRACE, ALERT_WARNING, ALERT_DEFEAT, METRIC_BANKRUPTCY,
		METRIC_HUNGER, METRIC_DEPOPULATION, NEEDS_TITLE, CLASS_HEADER, COVERAGE_ROW, GOOD_COVERAGE,
		PROMOTION_ACTIVE, PROMOTION_BLOCKED, PROMOTION_BLOCKER, PROMOTION_CATEGORY_BELOW,
		PROMOTION_CATEGORY_REASON, PROMOTION_SATISFACTION_LOW, NEEDS_MET, NEEDS_SHORT, NEEDS_SHORT_REASON,
		NEEDS_NO_CLASS, HOUSING_ROW, MOBILITY_PROMOTED, MOBILITY_DEMOTED,
	]
	keys.append_array(DIFFICULTY_KEYS)
	for terrain_id: String in TERRAIN_LABELS:
		_append_unique(keys, TERRAIN_LABELS[terrain_id])
	for building_id: String in BUILDING_LABELS:
		_append_unique(keys, BUILDING_LABELS[building_id])
	for class_id: StringName in CLASS_LABELS:
		_append_unique(keys, CLASS_LABELS[class_id])
	for category_id: StringName in CATEGORY_LABELS:
		_append_unique(keys, CATEGORY_LABELS[category_id])
	for good_id: StringName in GOOD_LABELS:
		_append_unique(keys, GOOD_LABELS[good_id])
	for condition_id: StringName in CONDITION_LABELS:
		_append_unique(keys, CONDITION_LABELS[condition_id])
	for status_id: StringName in STATUS_LABELS:
		_append_unique(keys, STATUS_LABELS[status_id])
	for reason_id: StringName in REASONS:
		_append_unique(keys, REASONS[reason_id])
	return keys


static func _append_unique(keys: Array[StringName], key: StringName) -> void:
	if not keys.has(key):
		keys.append(key)


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
