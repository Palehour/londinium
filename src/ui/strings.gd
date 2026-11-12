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
# The extra line of the 3D city's camera (issue #65).
const HELP_CITY: StringName = &"ui.help_city"
const HELP_CITY_GAMEPAD: StringName = &"ui.help_city_gamepad"
# The graphics quality switch of the 3D city (issue #65).
const GRAPHICS: StringName = &"ui.graphics"
const GRAPHICS_HIGH: StringName = &"ui.graphics_high"
const GRAPHICS_LOW: StringName = &"ui.graphics_low"
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
# Quarter turn of the building about to be placed (issue #296, D-157).
const BUILD_ROTATION: StringName = &"ui.build_rotation"
# A house in a crisis (issue #222, D-108): the tooltip's price and length of a disinfection, the time left, its button.
const CRISIS_DISINFECTION: StringName = &"ui.crisis.disinfection"
const CRISIS_SECONDS_LEFT: StringName = &"ui.crisis.seconds_left"
const CRISIS_DISINFECT: StringName = &"ui.crisis.disinfect"
const CRISIS_DISINFECT_GAMEPAD: StringName = &"ui.crisis.disinfect_gamepad"
# The service buildings (issue #87, D-118): each attribute's name and its icon on the map, the tooltip's availability,
# one attribute's value, and the district a house stands in (the whole city on a map without districts).
const SERVICE_ATTRIBUTES: Dictionary[StringName, StringName] = {
	&"safety": &"ui.service.safety", &"health": &"ui.service.health", &"order": &"ui.service.order",
}
const SERVICE_ICONS: Dictionary[StringName, StringName] = {
	&"safety": &"ui.service.icon.safety", &"health": &"ui.service.icon.health", &"order": &"ui.service.icon.order",
}
const SERVICE_AVAILABILITY: StringName = &"ui.service.availability"
const SERVICE_VALUE: StringName = &"ui.service.value"
const SERVICE_DISTRICT: StringName = &"ui.service.district"
const SERVICE_WHOLE_CITY: StringName = &"ui.service.whole_city"
# The small incidents (issue #87, D-119): a house's line with its district's pressure by attribute, the attributes the
# district warns about, and the warning's icon on the map.
const INCIDENT_PRESSURE: StringName = &"ui.incident.pressure"
const INCIDENT_WARNING: StringName = &"ui.incident.warning"
const INCIDENT_ICON: StringName = &"ui.incident.icon"
const PENDING: StringName = &"ui.pending"
const SUCCESS: StringName = &"ui.success"
const LOAD_ERROR: StringName = &"ui.load_error"
const PANEL_TITLE: StringName = &"ui.panel_title"
const TAX_LABEL: StringName = &"ui.tax_label"
# The loan section (issue #281). Every %s is Strings.money; the panel does not write a pound sign.
const LOAN_TITLE: StringName = &"ui.loan.title"
const LOAN_CAP: StringName = &"ui.loan.cap"
const LOAN_REQUEST: StringName = &"ui.loan.request"
const LOAN_MAXIMUM: StringName = &"ui.loan.maximum"
const LOAN_INSTALLMENT: StringName = &"ui.loan.installment"
const LOAN_BALANCE: StringName = &"ui.loan.balance"
const LOAN_CANCEL: StringName = &"ui.loan.cancel"
# The quote shown before asking (issue #334). Figures come from the simulation; these only format them.
const LOAN_QUOTE_RATE: StringName = &"ui.loan.quote_rate"
const LOAN_QUOTE_INTEREST: StringName = &"ui.loan.quote_interest"
const LOAN_QUOTE_TERM: StringName = &"ui.loan.quote_term"
const LOAN_QUOTE_SURCHARGE: StringName = &"ui.loan.quote_surcharge"
const LOAN_QUOTE_SHARE: StringName = &"ui.loan.quote_share"
const LOAN_QUOTE_RISK: StringName = &"ui.loan.quote_risk"
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
# Issue #136 (D-117): a save played with other mods, and the option to load it with its own for that session.
const SAVE_MODS_DIFFER: StringName = &"ui.save.mods_differ"
const LOAD_WITH_SAVE_MODS: StringName = &"ui.save.load_with_save_mods"
const MODS_FROM_SAVE: StringName = &"ui.mods.from_save"
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
const PROJECTED_DELTA: StringName = &"ui.projected_delta"
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
# The critical step of the defeat warnings (issue #350).
const CRITICAL_LEFT: StringName = &"ui.defeat_critical.left"
const CRITICAL_CAUSES: Dictionary[StringName, StringName] = {
	&"bankruptcy": &"ui.defeat_critical.cause.bankruptcy", &"hunger": &"ui.defeat_critical.cause.hunger",
	&"depopulation": &"ui.defeat_critical.cause.depopulation",
	&"loan_bankruptcy": &"ui.defeat_critical.cause.loan_bankruptcy",
}
const CRITICAL_ICON_LABELS: Dictionary[StringName, StringName] = {
	&"bankruptcy": &"ui.defeat_critical.icon.bankruptcy", &"hunger": &"ui.defeat_critical.icon.hunger",
	&"depopulation": &"ui.defeat_critical.icon.depopulation",
	&"loan_bankruptcy": &"ui.defeat_critical.icon.loan_bankruptcy",
}
# Why the critical sound is silent, by DefeatCriticalSound status.
const CRITICAL_SOUND_DIAGNOSTICS: Dictionary[StringName, StringName] = {
	&"no_data": &"ui.defeat_critical.sound.no_data", &"invalid_id": &"ui.defeat_critical.sound.invalid_id",
	&"missing_asset": &"ui.defeat_critical.sound.missing_asset",
}
# The settings of the critical notices are not defined yet (issue #350): said once, compactly, without a false warning.
const CRITICAL_CONFIG_PENDING: StringName = &"ui.defeat_critical.config.pending"
const CRITICAL_CONFIG_INVALID: StringName = &"ui.defeat_critical.config.invalid"
const CRITICAL_CONFIG_SOUND: StringName = &"ui.defeat_critical.config.sound"
const METRIC_BANKRUPTCY: StringName = &"ui.metric_bankruptcy"
const METRIC_HUNGER: StringName = &"ui.metric_hunger"
const METRIC_DEPOPULATION: StringName = &"ui.metric_depopulation"
const NEEDS_TITLE: StringName = &"ui.needs_title"
const CLASS_HEADER: StringName = &"ui.class_header"
const COVERAGE_ROW: StringName = &"ui.coverage_row"
const GOOD_COVERAGE: StringName = &"ui.good_coverage"
# The need layers and the "why?" of the map (issue #73, D-038, D-137).
const OVERLAY_CAPTION: StringName = &"ui.overlay_caption"
const OVERLAY_NONE: StringName = &"ui.overlay_none"
const WHY_TITLE: StringName = &"ui.why_title"
const WHY_BUTTON: StringName = &"ui.why_button"
const WHY_BUTTON_GAMEPAD: StringName = &"ui.why_button_gamepad"
const WHY_ROW: StringName = &"ui.why_row"
const WHY_INTERMITTENT: StringName = &"ui.why_intermittent"
const WHY_PRUNED: StringName = &"ui.why_pruned"
const PROMOTION_ACTIVE: StringName = &"ui.promotion_active"
const PROMOTION_BLOCKED: StringName = &"ui.promotion_blocked"
const PROMOTION_BLOCKER: StringName = &"ui.promotion_blocker"
const PROMOTION_CATEGORY_BELOW: StringName = &"ui.promotion_category_below"
const PROMOTION_CATEGORY_REASON: StringName = &"ui.promotion_category_reason"
const PROMOTION_SATISFACTION_LOW: StringName = &"ui.promotion_satisfaction_low"
const BLOCKERS_ROW: StringName = &"ui.blockers.row"
const BLOCKERS_ITEM: StringName = &"ui.blockers.item"
const BLOCKERS_MORE: StringName = &"ui.blockers.more"
const BLOCKERS_NONE: StringName = &"ui.blockers.none"
const BLOCKERS_MISSING: StringName = &"ui.blockers.missing"
const BLOCKERS_CATEGORY_REASON: StringName = &"ui.blockers.category_reason"
const BLOCKERS_MEASURED: StringName = &"ui.blockers.measured"
const BLOCKER_GROUP_LABELS: Dictionary[StringName, StringName] = {
	&"growth": &"ui.blockers.growth", &"promotion": &"ui.blockers.promotion",
}
const NEEDS_MET: StringName = &"ui.needs_met"
const NEEDS_SHORT: StringName = &"ui.needs_short"
const NEEDS_SHORT_REASON: StringName = &"ui.needs_short_reason"
const NEEDS_NO_CLASS: StringName = &"ui.needs_no_class"
const HOUSING_ROW: StringName = &"ui.housing_row"
const MOBILITY_PROMOTED: StringName = &"ui.mobility_promoted"
const MOBILITY_DEMOTED: StringName = &"ui.mobility_demoted"
const MOBILITY_TITLE: StringName = &"ui.mobility_title"
const LABOR_TITLE: StringName = &"ui.labor_title"
const LABOR_NOTICE: StringName = &"ui.labor_notice"
const LABOR_BUILDING: StringName = &"ui.labor_building"
const LABOR_MORE: StringName = &"ui.labor_more"
const DEMOTION_TITLE: StringName = &"ui.demotion_title"
const DEMOTION_COUNTDOWN: StringName = &"ui.demotion_countdown"

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
	&"depopulation": &"ui.condition.depopulation", &"loan_bankruptcy": &"ui.condition.loan_bankruptcy",
}
# The names of the era's factions (issue #84, D-139): data/eras/<era>/factions.json picks one by year from these.
const FACTION_NAMES: Array[StringName] = [&"ui.faction.ratepayers", &"ui.faction.sanitary_reformers",
	&"ui.faction.toynbee_hall", &"ui.faction.vestrymen"]
# Decree player text (issue #71). Titles wait until a decree is named; these are the reasons and the one effect.
const DECREE_EFFECT_RATES_UPKEEP: StringName = &"ui.decree.effect.rates_upkeep"
const DECREE_LAPSED: StringName = &"ui.decree.lapsed"
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
	"health_post": &"ui.building.health_post",
	"fire_station": &"ui.building.fire_station",
	"police_station": &"ui.building.police_station",
	"border": &"ui.building.border",
	"st_mary_atrium": &"ui.building.st_mary_atrium",
	"cemetery": &"ui.building.cemetery",
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
	&"bread_demand": &"ui.stats.bread_demand",
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
	&"debt_balance": &"ui.stats.debt_balance",
	&"debt_payments": &"ui.stats.debt_payments",
}
# Dimension members the history series name needs and that no other label covers. Wheat, barley and tea reuse
# ui.good.*. Hunger here is why someone left, not the riot (ui.condition.hunger).
const STATS_SOURCE_LABELS: Dictionary[StringName, StringName] = {
	&"tax": &"ui.stats.source.tax", &"refund": &"ui.stats.source.refund", &"upkeep": &"ui.stats.source.upkeep",
	&"administration": &"ui.stats.source.administration", &"wages": &"ui.stats.source.wages",
	&"construction": &"ui.stats.source.construction", &"imported_flour": &"ui.stats.source.imported_flour",
	&"wheat": &"ui.good.wheat", &"barley": &"ui.good.barley", &"tea": &"ui.good.tea",
}
const STATS_CAUSE_LABELS: Dictionary[StringName, StringName] = {
	&"hunger": &"ui.stats.cause.hunger", &"satisfaction": &"ui.stats.cause.satisfaction",
}
const STATS_STAGE_LABELS: Dictionary[StringName, StringName] = {
	&"population": &"ui.stats.population", &"artisans": &"ui.class.artisan", &"revenue": &"ui.stats.stage.revenue",
}
# The statistics screen (issue #83): the panel's button that opens it, its hint, back button and summary tab.
const STATS_SCREEN_OPEN: StringName = &"ui.stats_screen.open"
const STATS_SCREEN_HINT: StringName = &"ui.stats_screen.hint"
const STATS_SCREEN_BACK: StringName = &"ui.stats_screen.back"
const STATS_SCREEN_SUMMARY: StringName = &"ui.stats_screen.summary"
const STATS_SCREEN_NO_DATA: StringName = &"ui.stats_screen.no_data"
const STATS_SCREEN_CLASS_VALUE: StringName = &"ui.stats_screen.class_value"
# The summary's cursor (D-170): its hint, the time it is on, and a card's reading where there is none.
const STATS_SCREEN_SUMMARY_HINT: StringName = &"ui.stats_screen.summary.hint"
const STATS_SCREEN_SUMMARY_CURSOR: StringName = &"ui.stats_screen.summary.cursor"
const STATS_SCREEN_NO_READING: StringName = &"ui.stats_screen.no_reading"
# Titles of the summary cards, by StatsSummary.CARDS id.
const STATS_SCREEN_CARDS: Dictionary[StringName, StringName] = {
	&"population": &"ui.stats.population", &"balance": &"ui.stats_screen.card.balance",
	&"satisfaction": &"ui.stats_screen.card.satisfaction", &"coverage": &"ui.stats_screen.card.coverage",
	&"fear": &"ui.stats_screen.card.fear", &"debt": &"ui.stats_screen.card.debt",
}
# The history view (issue #316, D-168): header while that tab shows, the tab hint, the cursor reading, and how a
# bucket value is written when it is not money.
const STATS_SCREEN_HISTORY: StringName = &"ui.stats_screen.history"
const STATS_SCREEN_HISTORY_HEADER: StringName = &"ui.stats_screen.history.header"
const STATS_SCREEN_HISTORY_HINT: StringName = &"ui.stats_screen.history.hint"
const STATS_SCREEN_HISTORY_READING: StringName = &"ui.stats_screen.history.reading"
const STATS_SCREEN_HISTORY_VALUE: StringName = &"ui.stats_screen.history.value"
const STATS_SCREEN_HISTORY_VALUE_RATIO: StringName = &"ui.stats_screen.history.value.ratio"
const STATS_SCREEN_MARKER_POLICY: StringName = &"ui.stats_screen.marker.policy"
const STATS_SCREEN_MARKER_WARNING: StringName = &"ui.stats_screen.marker.warning"
const STATS_SCREEN_MARKER_DEFEAT: StringName = &"ui.stats_screen.marker.defeat"
const STATS_SCREEN_MARKER_STAGE: StringName = &"ui.stats_screen.marker.stage"
const STATS_SCREEN_MARKER_LINE: StringName = &"ui.stats_screen.marker.line"
const STATS_SCREEN_MARKER_STACK: StringName = &"ui.stats_screen.marker.stack"
const STATS_SCREEN_MARKER_KINDS: Dictionary[StringName, StringName] = {
	&"crisis": &"ui.stats_screen.marker.crisis", &"decree": &"ui.stats_screen.marker.decree",
	&"patron": &"ui.stats_screen.marker.patron",
	&"large_construction": &"ui.stats_screen.marker.large_construction",
}
# The classes view (issue #83): its tab, hint and reading at the cursor, the city's and each class's.
# The lessons of each district under the history chart (issue #87, D-120): the title, a district's line, and the
# cholera's severity and deaths there, or that it has not come yet.
const STATS_SCREEN_LESSONS: StringName = &"ui.stats_screen.lessons"
const STATS_SCREEN_LESSONS_ROW: StringName = &"ui.stats_screen.lessons.row"
const STATS_SCREEN_LESSONS_CRISIS: StringName = &"ui.stats_screen.lessons.crisis"
const STATS_SCREEN_LESSONS_NO_CRISIS: StringName = &"ui.stats_screen.lessons.no_crisis"
const STATS_SCREEN_CLASSES: StringName = &"ui.stats_screen.classes"
const STATS_SCREEN_CLASSES_HINT: StringName = &"ui.stats_screen.classes.hint"
const STATS_SCREEN_CLASSES_CITY: StringName = &"ui.stats_screen.classes.city"
const STATS_SCREEN_CLASSES_CLASS: StringName = &"ui.stats_screen.classes.class"
# The chains view (issue #315, D-173): its tab, hint, a link with no building, one column's reading, and the chain names.
# Column titles reuse the series labels except entradas and pérdidas, which are not the Merma label.
const STATS_SCREEN_CHAINS: StringName = &"ui.stats_screen.chains"
const STATS_SCREEN_CHAINS_HINT: StringName = &"ui.stats_screen.chains.hint"
const STATS_SCREEN_CHAINS_ABSENT: StringName = &"ui.stats_screen.chains.absent"
const STATS_SCREEN_CHAINS_VALUE: StringName = &"ui.stats_screen.chains.value"
# Cause line under a chain (issue #353): the link that limits it, or that none does.
const STATS_SCREEN_CHAINS_NO_BOTTLENECK: StringName = &"ui.stats_screen.chains.no_bottleneck"
const STATS_SCREEN_CHAINS_CAUSE: StringName = &"ui.stats_screen.chains.cause"
const STATS_SCREEN_CHAINS_CAUSE_WHARF: StringName = &"ui.stats_screen.chains.cause_wharf"
const STATS_SCREEN_CHAINS_IMPORTS_TAKE: StringName = &"ui.stats_screen.chains.imports_take"
const STATS_SCREEN_CHAINS_IMPORTS_FREE: StringName = &"ui.stats_screen.chains.imports_free"
const STATS_SCREEN_CHAIN_NAMES: Dictionary[StringName, StringName] = {
	&"bread": &"ui.stats_screen.chains.bread", &"beer": &"ui.stats_screen.chains.beer",
}
const STATS_SCREEN_CHAIN_COLUMNS: Dictionary[StringName, StringName] = {
	&"in": &"ui.stats_screen.chains.column.in", &"produced": &"ui.stats.produced",
	&"consumed": &"ui.stats.consumed", &"spoiled": &"ui.stats_screen.chains.column.spoiled",
	&"stock": &"ui.stats.stock",
}
const STATS_SCREEN_RANGES: Dictionary[StringName, StringName] = {
	&"ten_minutes": &"ui.stats_screen.range.ten_minutes", &"hour": &"ui.stats_screen.range.hour",
	&"chapter": &"ui.stats_screen.range.chapter",
}
# The policies the cause log follows (StatsHistory), by subject.
const STATS_SCREEN_POLICIES: Dictionary[StringName, StringName] = {
	&"tax_rate": &"ui.stats_screen.policy.tax_rate", &"wheat_purchases": &"ui.stats_screen.policy.wheat_purchases",
	&"wheat_policy": &"ui.stats_screen.policy.wheat_policy",
	&"unloading_barley_percent": &"ui.stats_screen.policy.unloading_barley_percent",
	&"tea_imports": &"ui.stats_screen.policy.tea_imports", &"flour_imports": &"ui.stats_screen.policy.flour_imports",
}
# Saved games (issue #57): the kind of each file and why one does not load.
const SAVE_KIND_LABELS: Dictionary[StringName, StringName] = {
	&"manual": &"ui.save.kind.manual", &"autosave": &"ui.save.kind.autosave", &"stage": &"ui.save.kind.stage",
}
const SAVE_REFUSALS: Dictionary[StringName, StringName] = {
	&"invalid_file": &"ui.save.invalid_file", &"other_version": &"ui.save.other_version",
	&"other_mods": &"ui.save.other_mods", &"missing_mod": &"ui.save.missing_mod",
	&"other_mod_version": &"ui.save.other_mod_version",
}
const REASONS: Dictionary[StringName, StringName] = {
	&"arriving": &"ui.reason.arriving",
	&"no_free_housing": &"ui.reason.no_free_housing",
	&"unserved_housing": &"ui.reason.unserved_housing",
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
	&"requires_firm": &"ui.reason.requires_firm",
	&"requires_riverbank": &"ui.reason.requires_riverbank",
	&"marsh": &"ui.reason.marsh",
	&"existing_building": &"ui.reason.existing_building",
	&"not_buildable": &"ui.reason.not_buildable",
	&"cannot_rotate": &"ui.reason.cannot_rotate",
	&"events_disabled": &"ui.reason.events_disabled",
	&"water_source_cap": &"ui.reason.water_source_cap",
	&"insufficient_money": &"ui.reason.insufficient_money",
	&"bankruptcy_window": &"ui.reason.bankruptcy_window",
	&"negative_balance": &"ui.reason.negative_balance",
	&"loan_active": &"ui.reason.loan_active",
	&"invalid_loan_amount": &"ui.reason.invalid_loan_amount",
	&"loan_over_cap": &"ui.reason.loan_over_cap",
	&"loan_not_sanctioned": &"ui.reason.loan_not_sanctioned",
	&"no_active_loan": &"ui.reason.no_active_loan",
	&"no_money_for_wheat": &"ui.reason.no_money_for_wheat",
	&"no_building": &"ui.reason.no_building",
	&"simulation_defeated": &"ui.reason.simulation_defeated",
	&"mourning_disabled": &"ui.reason.mourning_disabled",
	&"cemetery_occupied": &"ui.reason.cemetery_occupied",
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
	# A building the cause log has seen demolished (issue #82).
	&"gone": &"ui.reason.gone",
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
	# Houses in a crisis (issue #222).
	&"house_sick": &"ui.reason.house_sick",
	&"house_quarantine": &"ui.reason.house_quarantine",
	&"house_not_sick": &"ui.reason.house_not_sick",
	&"outside_health_post": &"ui.reason.outside_health_post",
	&"disinfection_running": &"ui.reason.disinfection_running",
	# Decrees (issue #71). not_enough_legitimacy is FactionSystem.NOT_ENOUGH_LEGITIMACY.
	&"not_enough_legitimacy": &"ui.decree.reason.not_enough_legitimacy",
	&"not_in_competence": &"ui.decree.reason.not_in_competence",
	&"already_active": &"ui.decree.reason.already_active",
	&"not_active": &"ui.decree.reason.not_active",
	&"unknown_decree": &"ui.decree.reason.unknown_decree",
	&"no_factions": &"ui.decree.reason.no_factions",
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


# args come from SaveFile: the file's version and the one this game reads, the mods the save was played with, or the
# mod that is missing or changed and its versions.
static func save_refusal(reason_id: StringName, args: Array) -> String:
	if reason_id == &"other_mods":
		return text(SAVE_REFUSALS[reason_id]) % _mod_list(args[0])
	if reason_id in [&"other_version", &"missing_mod", &"other_mod_version"]:
		return text(SAVE_REFUSALS[reason_id]) % args
	return text(SAVE_REFUSALS.get(reason_id, SAVE_REFUSALS[&"invalid_file"]))


# The save's mods next to the player's, above the option to load it with its own (issue #136).
static func save_mods_differ(saved: Array, current: Array) -> String:
	return text(SAVE_MODS_DIFFER) % [_mod_list(saved), _mod_list(current)]


static func _mod_list(mods: Array) -> String:
	var names: PackedStringArray = []
	for mod: Variant in mods:
		names.append(String(mod))
	return text(SAVE_NO_MODS) if names.is_empty() else ", ".join(names)


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
		HELP, HELP_GAMEPAD, HELP_CITY, HELP_CITY_GAMEPAD, GRAPHICS, GRAPHICS_HIGH, GRAPHICS_LOW, LOADING, LEGEND, MAP_CREDITS, NO_CULTIVABLE_CELLS, DISABLED_BUILDING, SELECT, MODE, ROAD, TRANSPORT_EXPENSIVE,
		LOTS_LEGEND, DAMAGED_WHARF, REPAIR_HINT, REPAIR_HINT_GAMEPAD, BUILD_ROTATION, CRISIS_DISINFECTION, CRISIS_SECONDS_LEFT,
		CRISIS_DISINFECT, CRISIS_DISINFECT_GAMEPAD, PENDING, SUCCESS,
		LOAD_ERROR, PANEL_TITLE, TAX_LABEL, LOAN_TITLE, LOAN_CAP, LOAN_REQUEST, LOAN_MAXIMUM, LOAN_INSTALLMENT,
		LOAN_BALANCE, LOAN_CANCEL, LOAN_QUOTE_RATE, LOAN_QUOTE_INTEREST, LOAN_QUOTE_TERM, LOAN_QUOTE_SURCHARGE,
		LOAN_QUOTE_SHARE, LOAN_QUOTE_RISK, WHEAT_PURCHASES, ACCUMULATE_LABEL, MAX_PRICE_LABEL, TARGET_LABEL,
		RESERVE_LABEL, WHEAT_ROW, BARLEY_ROW, MALT_BEER_ROW, UNLOADING_LABEL, WHEAT_BLOCKED_NOTE,
		MINUTES_COVERED, PAUSE, RESUME, RESTART, POPULATION, SATISFACTION, BREAD_RATE, BREAD_OK, BREAD_SHORT,
		BREAD_CAUSE, BREAD_CHAIN_CAUSE, STOCKS, TREASURY, OPERATING_BALANCE, PROJECTED_DELTA, BALANCE_BREAKDOWN, CONSTRUCTION,
		WHEAT_PRICE, TEA_IMPORTS, FLOUR_IMPORTS, TEA_ROW, FLOUR_ROW, WINDOW_PARTIAL, BUILDINGS, NO_BUILDINGS,
		BUILDING_STATUS, CRISES, CONDITION, TIMER, GRACE, ALERT_WARNING, ALERT_DEFEAT, METRIC_BANKRUPTCY,
		METRIC_HUNGER, METRIC_DEPOPULATION, NEEDS_TITLE, CLASS_HEADER, COVERAGE_ROW, GOOD_COVERAGE,
		PROMOTION_ACTIVE, PROMOTION_BLOCKED, PROMOTION_BLOCKER, PROMOTION_CATEGORY_BELOW,
		PROMOTION_CATEGORY_REASON, PROMOTION_SATISFACTION_LOW, NEEDS_MET, NEEDS_SHORT, NEEDS_SHORT_REASON,
		BLOCKERS_ROW, BLOCKERS_ITEM, BLOCKERS_MORE, BLOCKERS_NONE, BLOCKERS_MISSING, BLOCKERS_CATEGORY_REASON,
		BLOCKERS_MEASURED,
		NEEDS_NO_CLASS, HOUSING_ROW, MOBILITY_PROMOTED, MOBILITY_DEMOTED, MOBILITY_TITLE, LABOR_TITLE, LABOR_NOTICE,
		LABOR_BUILDING, LABOR_MORE, DEMOTION_TITLE, DEMOTION_COUNTDOWN, DIFFICULTY,
		MODS_TITLE, MODS_NONE, MODS_UP, MODS_DOWN, MODS_CONFLICTS, MODS_CONFLICT, MODS_ERROR, UNLOADING_SPLIT_SHORT,
		SAVES_TITLE, SAVES_NONE, SAVE_GAME, LOAD_GAME, SAVE_ENTRY, SAVE_UNREADABLE, SAVED, SAVED_WITHOUT_QUEUE,
		SAVE_WRITE_ERROR, SAVE_LOADED, SAVE_NO_MODS, SAVE_MODS_DIFFER, LOAD_WITH_SAVE_MODS, MODS_FROM_SAVE,
		ARCHIVE_BUTTON, ARCHIVE_TITLE, ARCHIVE_CLOSE, ARCHIVE_LOCKED, ARCHIVE_SOURCES, ARCHIVE_NO_IMAGE,
		ARCHIVE_IMAGE_CREDIT, ARCHIVE_IMAGE_NOTE,
		STATS_SCREEN_OPEN, STATS_SCREEN_HINT, STATS_SCREEN_BACK, STATS_SCREEN_SUMMARY, STATS_SCREEN_NO_DATA,
		STATS_SCREEN_CLASS_VALUE, STATS_SCREEN_SUMMARY_HINT, STATS_SCREEN_SUMMARY_CURSOR, STATS_SCREEN_NO_READING,
		STATS_SCREEN_HISTORY, STATS_SCREEN_HISTORY_HEADER, STATS_SCREEN_HISTORY_HINT, STATS_SCREEN_HISTORY_READING,
		STATS_SCREEN_HISTORY_VALUE, STATS_SCREEN_HISTORY_VALUE_RATIO,
		STATS_SCREEN_MARKER_POLICY, STATS_SCREEN_MARKER_WARNING, STATS_SCREEN_MARKER_DEFEAT, STATS_SCREEN_MARKER_STAGE,
		STATS_SCREEN_MARKER_LINE, STATS_SCREEN_MARKER_STACK,
		STATS_SCREEN_LESSONS, STATS_SCREEN_LESSONS_ROW, STATS_SCREEN_LESSONS_CRISIS, STATS_SCREEN_LESSONS_NO_CRISIS,
		STATS_SCREEN_CLASSES, STATS_SCREEN_CLASSES_HINT, STATS_SCREEN_CLASSES_CITY, STATS_SCREEN_CLASSES_CLASS,
		STATS_SCREEN_CHAINS, STATS_SCREEN_CHAINS_HINT, STATS_SCREEN_CHAINS_ABSENT, STATS_SCREEN_CHAINS_VALUE,
		STATS_SCREEN_CHAINS_NO_BOTTLENECK, STATS_SCREEN_CHAINS_CAUSE, STATS_SCREEN_CHAINS_CAUSE_WHARF,
		STATS_SCREEN_CHAINS_IMPORTS_TAKE, STATS_SCREEN_CHAINS_IMPORTS_FREE,
		SERVICE_AVAILABILITY, SERVICE_VALUE, SERVICE_DISTRICT, SERVICE_WHOLE_CITY,
		INCIDENT_PRESSURE, INCIDENT_WARNING, INCIDENT_ICON,
		OVERLAY_CAPTION, OVERLAY_NONE, WHY_TITLE, WHY_BUTTON, WHY_BUTTON_GAMEPAD, WHY_ROW, WHY_INTERMITTENT, WHY_PRUNED,
		DECREE_EFFECT_RATES_UPKEEP, DECREE_LAPSED,
	]
	_append_unique(keys, CRITICAL_LEFT)
	for config_key: StringName in [CRITICAL_CONFIG_PENDING, CRITICAL_CONFIG_INVALID, CRITICAL_CONFIG_SOUND]:
		_append_unique(keys, config_key)
	for critical_labels: Dictionary in [CRITICAL_CAUSES, CRITICAL_ICON_LABELS, CRITICAL_SOUND_DIAGNOSTICS]:
		for critical_key: StringName in critical_labels:
			_append_unique(keys, critical_labels[critical_key])
	for attribute: StringName in SERVICE_ATTRIBUTES:
		_append_unique(keys, SERVICE_ATTRIBUTES[attribute])
		_append_unique(keys, SERVICE_ICONS[attribute])
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
	for group_id: StringName in BLOCKER_GROUP_LABELS:
		_append_unique(keys, BLOCKER_GROUP_LABELS[group_id])
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
	for faction_key: StringName in FACTION_NAMES:
		_append_unique(keys, faction_key)
	for reason_id: StringName in REASONS:
		_append_unique(keys, REASONS[reason_id])
	for kind_id: StringName in SAVE_KIND_LABELS:
		_append_unique(keys, SAVE_KIND_LABELS[kind_id])
	for refusal_id: StringName in SAVE_REFUSALS:
		_append_unique(keys, SAVE_REFUSALS[refusal_id])
	for metric_id: StringName in STATS_SERIES_LABELS:
		_append_unique(keys, STATS_SERIES_LABELS[metric_id])
	for source_id: StringName in STATS_SOURCE_LABELS:
		_append_unique(keys, STATS_SOURCE_LABELS[source_id])
	for cause_id: StringName in STATS_CAUSE_LABELS:
		_append_unique(keys, STATS_CAUSE_LABELS[cause_id])
	for stage_id: StringName in STATS_STAGE_LABELS:
		_append_unique(keys, STATS_STAGE_LABELS[stage_id])
	for marker_id: StringName in STATS_SCREEN_MARKER_KINDS:
		_append_unique(keys, STATS_SCREEN_MARKER_KINDS[marker_id])
	for card_id: StringName in STATS_SCREEN_CARDS:
		_append_unique(keys, STATS_SCREEN_CARDS[card_id])
	for range_id: StringName in STATS_SCREEN_RANGES:
		_append_unique(keys, STATS_SCREEN_RANGES[range_id])
	for policy_id: StringName in STATS_SCREEN_POLICIES:
		_append_unique(keys, STATS_SCREEN_POLICIES[policy_id])
	for chain_id: StringName in STATS_SCREEN_CHAIN_NAMES:
		_append_unique(keys, STATS_SCREEN_CHAIN_NAMES[chain_id])
	for column_id: StringName in STATS_SCREEN_CHAIN_COLUMNS:
		_append_unique(keys, STATS_SCREEN_CHAIN_COLUMNS[column_id])
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
