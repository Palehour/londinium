class_name Strings
extends RefCounted

const OBJECTIVES: StringName = &"ui.objectives"
const OBJECTIVE_POPULATION: StringName = &"ui.objective_population"
const OBJECTIVE_CLASS: StringName = &"ui.objective_class"
const OBJECTIVE_REVENUE: StringName = &"ui.objective_revenue"
const OBJECTIVE_MET: StringName = &"ui.objective_met"
const OBJECTIVE_PENDING: StringName = &"ui.objective_pending"
const VICTORY_WHY: StringName = &"ui.victory_why"
const VICTORY_NO_BREAK: StringName = &"ui.victory_no_break"
const VICTORY_MESSAGE: StringName = &"ui.victory_message"
const VICTORY_DISMISS: StringName = &"ui.victory_dismiss"
const ALERT_DEFEAT_AFTER_VICTORY: StringName = &"ui.alert_defeat_after_victory"

const PENCE_PER_SHILLING: int = 12
const PENCE_PER_POUND: int = 240

# Endonyms. The captions stay these words in both languages, so the player can
# find their own from the other one. They are not keys in locale/ui.csv.
const LOCALE_ES: String = "Español"
const LOCALE_EN: String = "English"

# Phrase keys. The words live in locale/ui.csv. Placeholder order is the contract:
# GDScript's % operator cannot reorder them, so every language keeps the same order.
const HELP: StringName = &"ui.help"
const HELP_GAMEPAD: StringName = &"ui.help_gamepad"
const LOADING: StringName = &"ui.loading"
const LEGEND: StringName = &"ui.legend"
const MAP_CREDITS: StringName = &"ui.map_credits"
const NO_CULTIVABLE_CELLS: StringName = &"ui.no_cultivable_cells"
const DISABLED_BUILDING: StringName = &"ui.disabled_building"
const SELECT: StringName = &"ui.select"
const MODE: StringName = &"ui.mode"
# The player's street on the build cycle (issue #168), and the panel's warning for a long transport leg (D-080).
const ROAD: StringName = &"ui.road"
const TRANSPORT_EXPENSIVE: StringName = &"ui.transport_expensive"
# Tierra de época (issue #178, D-083): the legend of the lots, the damaged wharf on the map and its repair.
const LOTS_LEGEND: StringName = &"ui.lots_legend"
const DAMAGED_WHARF: StringName = &"ui.damaged_wharf"
const REPAIR_HINT: StringName = &"ui.repair_hint"
const REPAIR_HINT_GAMEPAD: StringName = &"ui.repair_hint_gamepad"
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
const DIFFICULTY: StringName = &"ui.difficulty"
const MODS_TITLE: StringName = &"ui.mods.title"
const MODS_NONE: StringName = &"ui.mods.none"
const MODS_UP: StringName = &"ui.mods.up"
const MODS_DOWN: StringName = &"ui.mods.down"
const MODS_CONFLICTS: StringName = &"ui.mods.conflicts"
const MODS_CONFLICT: StringName = &"ui.mods.conflict"
const MODS_ERROR: StringName = &"ui.mods.error"
const SAVES_TITLE: StringName = &"ui.save.title"
const SAVES_NONE: StringName = &"ui.save.none"
const SAVE_GAME: StringName = &"ui.save.save"
const LOAD_GAME: StringName = &"ui.save.load"
const SAVE_ENTRY: StringName = &"ui.save.entry"
const SAVE_UNREADABLE: StringName = &"ui.save.unreadable"
const SAVED: StringName = &"ui.save.saved"
const SAVED_WITHOUT_QUEUE: StringName = &"ui.save.saved_without_queue"
const SAVE_WRITE_ERROR: StringName = &"ui.save.write_error"
const SAVE_LOADED: StringName = &"ui.save.loaded"
const SAVE_NO_MODS: StringName = &"ui.save.no_mods"
# The Archive (issue #64, D-110): its button, its panel and the frame of every card. The cards' own words are keys
# archive.<card id>.<field>, written by Chronicler in both languages (D-100).
const ARCHIVE_BUTTON: StringName = &"ui.archive.button"
const ARCHIVE_TITLE: StringName = &"ui.archive.title"
const ARCHIVE_CLOSE: StringName = &"ui.archive.close"
const ARCHIVE_LOCKED: StringName = &"ui.archive.locked"
const ARCHIVE_SOURCES: StringName = &"ui.archive.sources"
const ARCHIVE_NO_IMAGE: StringName = &"ui.archive.no_image"
const ARCHIVE_IMAGE_CREDIT: StringName = &"ui.archive.image_credit"
const ARCHIVE_IMAGE_NOTE: StringName = &"ui.archive.image_note"
const ARCHIVE_TITLE_FIELD: StringName = &"title"
const ARCHIVE_DATE_FIELD: StringName = &"date"
const ARCHIVE_BODY_FIELD: StringName = &"body"
const ARCHIVE_SOURCES_FIELD: StringName = &"sources"
const ARCHIVE_CARD_FIELDS: Array[StringName] = [ARCHIVE_TITLE_FIELD, ARCHIVE_DATE_FIELD, ARCHIVE_BODY_FIELD,
	ARCHIVE_SOURCES_FIELD]
# Only a card whose print is "de contexto" has it (D-103).
const ARCHIVE_IMAGE_CONTEXT: StringName = &"image_context"
const ARCHIVE_KIND_LABELS: Dictionary[StringName, StringName] = {
	&"moment": &"ui.archive.kind.moment", &"character": &"ui.archive.kind.character",
	&"finding": &"ui.archive.kind.finding",
}
const POPULATION: StringName = &"ui.population"
const SATISFACTION: StringName = &"ui.satisfaction"
const BREAD_RATE: StringName = &"ui.bread_rate"
const BREAD_OK: StringName = &"ui.bread_ok"
const BREAD_SHORT: StringName = &"ui.bread_short"
const BREAD_CAUSE: StringName = &"ui.bread_cause"
const BREAD_CHAIN_CAUSE: StringName = &"ui.bread_chain_cause"
const UNLOADING_SPLIT_SHORT: StringName = &"ui.unloading_split_short"
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
	"dock": &"ui.terrain.dock", "road": &"ui.terrain.road", "player_road": &"ui.terrain.player_road",
	"existing": &"ui.terrain.existing",
}
# The lot styles of data/maps (issue #176), in legend order. The simulation never reads them.
const LOT_STYLE_LABELS: Dictionary[StringName, StringName] = {
	&"yard": &"ui.lot.yard", &"timber_yard": &"ui.lot.timber_yard", &"garden": &"ui.lot.garden",
	&"plain": &"ui.lot.plain",
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
	"dense_housing": &"ui.building.dense_housing",
	"public_fountain": &"ui.building.public_fountain",
	"lea_bridge_fountain": &"ui.building.lea_bridge_fountain",
	"well": &"ui.building.well",
}
const CLASS_LABELS: Dictionary[StringName, StringName] = {
	&"worker": &"ui.class.worker", &"artisan": &"ui.class.artisan",
}
const CATEGORY_LABELS: Dictionary[StringName, StringName] = {
	&"sustento": &"ui.category.sustento", &"abrigo": &"ui.category.abrigo", &"salud": &"ui.category.salud",
	&"comunidad": &"ui.category.comunidad", &"estatus": &"ui.category.estatus",
}
# Difficulty presets (D-065), in the order the panel shows them.
const DIFFICULTY_LABELS: Dictionary[StringName, StringName] = {
	&"easy": &"ui.difficulty.easy", &"normal": &"ui.difficulty.normal", &"hard": &"ui.difficulty.hard",
}
const GOOD_LABELS: Dictionary[StringName, StringName] = {
	&"wheat": &"ui.good.wheat", &"barley": &"ui.good.barley", &"flour": &"ui.good.flour", &"bread": &"ui.good.bread",
	&"malt": &"ui.good.malt", &"beer": &"ui.good.beer", &"tea": &"ui.good.tea",
}
# Names of the statistics series (issue #82), by metric; SeriesDef.label_key points here.
const STATS_SERIES_LABELS: Dictionary[StringName, StringName] = {
	&"money": &"ui.stats.money",
	&"income": &"ui.stats.income",
	&"expense": &"ui.stats.expense",
	&"stock": &"ui.stats.stock",
	&"coverage": &"ui.stats.coverage",
	&"produced": &"ui.stats.produced",
	&"consumed": &"ui.stats.consumed",
	&"spoiled": &"ui.stats.spoiled",
	&"bought": &"ui.stats.bought",
	&"price": &"ui.stats.price",
	&"population": &"ui.stats.population",
	&"immigration": &"ui.stats.immigration",
	&"emigration": &"ui.stats.emigration",
	&"satisfaction": &"ui.stats.satisfaction",
	&"housing_capacity": &"ui.stats.housing_capacity",
	&"housing_occupancy": &"ui.stats.housing_occupancy",
	&"need_score": &"ui.stats.need_score",
	&"promotions": &"ui.stats.promotions",
	&"demotions": &"ui.stats.demotions",
	&"jobs_filled": &"ui.stats.jobs_filled",
	&"defeat_timer": &"ui.stats.defeat_timer",
	&"victory_progress": &"ui.stats.victory_progress",
}
# Saved games (issue #57): the kind of each file and why one does not load.
const SAVE_KIND_LABELS: Dictionary[StringName, StringName] = {
	&"manual": &"ui.save.kind.manual", &"autosave": &"ui.save.kind.autosave", &"stage": &"ui.save.kind.stage",
}
const SAVE_REFUSALS: Dictionary[StringName, StringName] = {
	&"invalid_file": &"ui.save.invalid_file", &"other_version": &"ui.save.other_version",
	&"other_mods": &"ui.save.other_mods",
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
	&"existing_building": &"ui.reason.existing_building",
	&"not_buildable": &"ui.reason.not_buildable",
	&"events_disabled": &"ui.reason.events_disabled",
	&"water_source_cap": &"ui.reason.water_source_cap",
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
	# Streets of the distance model (issue #67).
	&"no_road_access": &"ui.reason.no_road_access",
	&"no_route": &"ui.reason.no_route",
	&"road_cell": &"ui.reason.road_cell",
	&"historic_road": &"ui.reason.historic_road",
	# Historic anchors of the traced map (issue #152).
	&"historic_anchor": &"ui.reason.historic_anchor",
	# Repairing a damaged wharf (issue #177).
	&"not_damaged_wharf": &"ui.reason.not_damaged_wharf",
	&"roads_disabled": &"ui.reason.roads_disabled",
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


# args come from SaveFile: the file's version and the one this game reads, or the mods the save was played with.
static func save_refusal(reason_id: StringName, args: Array) -> String:
	if reason_id == &"other_mods":
		var mods: PackedStringArray = []
		for mod: Variant in args[0]:
			mods.append(String(mod))
		return text(SAVE_REFUSALS[reason_id]) % (text(SAVE_NO_MODS) if mods.is_empty() else ", ".join(mods))
	if reason_id == &"other_version":
		return text(SAVE_REFUSALS[reason_id]) % args
	return text(SAVE_REFUSALS.get(reason_id, SAVE_REFUSALS[&"invalid_file"]))


# One line of the saves list: its kind (with the slot of an autosave), the game minute and when it was saved.
static func save_entry(entry: Dictionary) -> String:
	var kind: String = text(SAVE_KIND_LABELS[entry["kind"]])
	if entry["kind"] == &"autosave":
		kind = kind % entry["slot"]
	if int(entry["tick"]) < 0:
		return text(SAVE_UNREADABLE) % [kind, String(entry["path"]).get_file()]
	@warning_ignore("integer_division")
	return text(SAVE_ENTRY) % [kind, int(entry["tick"]) / 60, entry["saved_at"]]


static func archive_key(card_id: StringName, field: StringName) -> StringName:
	return StringName("archive.%s.%s" % [card_id, field])


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
		OBJECTIVES, OBJECTIVE_POPULATION, OBJECTIVE_CLASS, OBJECTIVE_REVENUE, OBJECTIVE_MET, OBJECTIVE_PENDING, VICTORY_WHY, VICTORY_NO_BREAK, VICTORY_MESSAGE, VICTORY_DISMISS, ALERT_DEFEAT_AFTER_VICTORY,
		HELP, HELP_GAMEPAD, LOADING, LEGEND, MAP_CREDITS, NO_CULTIVABLE_CELLS, DISABLED_BUILDING, SELECT, MODE, ROAD, TRANSPORT_EXPENSIVE,
		LOTS_LEGEND, DAMAGED_WHARF, REPAIR_HINT, REPAIR_HINT_GAMEPAD, PENDING, SUCCESS,
		LOAD_ERROR, PANEL_TITLE, TAX_LABEL, WHEAT_PURCHASES, ACCUMULATE_LABEL, MAX_PRICE_LABEL, TARGET_LABEL,
		RESERVE_LABEL, WHEAT_ROW, BARLEY_ROW, MALT_BEER_ROW, UNLOADING_LABEL, WHEAT_BLOCKED_NOTE,
		MINUTES_COVERED, PAUSE, RESUME, RESTART, POPULATION, SATISFACTION, BREAD_RATE, BREAD_OK, BREAD_SHORT,
		BREAD_CAUSE, BREAD_CHAIN_CAUSE, STOCKS, TREASURY, OPERATING_BALANCE, BALANCE_BREAKDOWN, CONSTRUCTION,
		WHEAT_PRICE, TEA_IMPORTS, FLOUR_IMPORTS, TEA_ROW, FLOUR_ROW, WINDOW_PARTIAL, BUILDINGS, NO_BUILDINGS,
		BUILDING_STATUS, CRISES, CONDITION, TIMER, GRACE, ALERT_WARNING, ALERT_DEFEAT, METRIC_BANKRUPTCY,
		METRIC_HUNGER, METRIC_DEPOPULATION, NEEDS_TITLE, CLASS_HEADER, COVERAGE_ROW, GOOD_COVERAGE,
		PROMOTION_ACTIVE, PROMOTION_BLOCKED, PROMOTION_BLOCKER, PROMOTION_CATEGORY_BELOW,
		PROMOTION_CATEGORY_REASON, PROMOTION_SATISFACTION_LOW, NEEDS_MET, NEEDS_SHORT, NEEDS_SHORT_REASON,
		NEEDS_NO_CLASS, HOUSING_ROW, MOBILITY_PROMOTED, MOBILITY_DEMOTED, DIFFICULTY,
		MODS_TITLE, MODS_NONE, MODS_UP, MODS_DOWN, MODS_CONFLICTS, MODS_CONFLICT, MODS_ERROR, UNLOADING_SPLIT_SHORT,
		SAVES_TITLE, SAVES_NONE, SAVE_GAME, LOAD_GAME, SAVE_ENTRY, SAVE_UNREADABLE, SAVED, SAVED_WITHOUT_QUEUE,
		SAVE_WRITE_ERROR, SAVE_LOADED, SAVE_NO_MODS,
		ARCHIVE_BUTTON, ARCHIVE_TITLE, ARCHIVE_CLOSE, ARCHIVE_LOCKED, ARCHIVE_SOURCES, ARCHIVE_NO_IMAGE,
		ARCHIVE_IMAGE_CREDIT, ARCHIVE_IMAGE_NOTE,
	]
	for kind_id: StringName in ARCHIVE_KIND_LABELS:
		_append_unique(keys, ARCHIVE_KIND_LABELS[kind_id])
	var archive: ArchiveCatalog = ArchiveCatalog.new()
	archive.load_data()
	for card: ArchiveCard in archive.cards:
		for key: StringName in ArchiveCatalog.text_keys(card):
			_append_unique(keys, key)
	for terrain_id: String in TERRAIN_LABELS:
		_append_unique(keys, TERRAIN_LABELS[terrain_id])
	for building_id: String in BUILDING_LABELS:
		_append_unique(keys, BUILDING_LABELS[building_id])
	for style_id: StringName in LOT_STYLE_LABELS:
		_append_unique(keys, LOT_STYLE_LABELS[style_id])
	for class_id: StringName in CLASS_LABELS:
		_append_unique(keys, CLASS_LABELS[class_id])
	for category_id: StringName in CATEGORY_LABELS:
		_append_unique(keys, CATEGORY_LABELS[category_id])
	for preset_id: StringName in DIFFICULTY_LABELS:
		_append_unique(keys, DIFFICULTY_LABELS[preset_id])
	for good_id: StringName in GOOD_LABELS:
		_append_unique(keys, GOOD_LABELS[good_id])
	for condition_id: StringName in CONDITION_LABELS:
		_append_unique(keys, CONDITION_LABELS[condition_id])
	for status_id: StringName in STATUS_LABELS:
		_append_unique(keys, STATUS_LABELS[status_id])
	for reason_id: StringName in REASONS:
		_append_unique(keys, REASONS[reason_id])
	for kind_id: StringName in SAVE_KIND_LABELS:
		_append_unique(keys, SAVE_KIND_LABELS[kind_id])
	for refusal_id: StringName in SAVE_REFUSALS:
		_append_unique(keys, SAVE_REFUSALS[refusal_id])
	for metric_id: StringName in STATS_SERIES_LABELS:
		_append_unique(keys, STATS_SERIES_LABELS[metric_id])
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
