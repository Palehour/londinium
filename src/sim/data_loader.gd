class_name DataLoader
extends RefCounted

const BUILDING_FIELDS: Dictionary = {
	"cost": "money", "upkeep_per_minute": "money",
	"wage_per_worker_per_minute": "money", "jobs": "integer",
}
# Every tag a building may carry. Some change rules (housing, river, cultivable, and basic_infrastructure, which keeps
# a building out of construction escalation in BuildingCosts, #118), so a typo must stop loading instead of silently
# changing what a building costs or where it goes. A water building (issue #63, D-089) makes nothing, so it has no recipe.
const BUILDING_TAGS: Array[String] = ["housing", "river", "source", "producer", "cultivable", "basic_infrastructure",
	"water"]
# Distance model (issue #67): a building may hand out goods to the houses within its service radius, in metres since
# issue #186 (D-086), and the wharf may supply goods it brings beyond its recipe. All three are optional.
const BUILDING_SERVICE_FIELDS: Array[String] = ["service_radius_m", "distributes", "supplies"]
const ECONOMY_SCHEMAS: Dictionary = {
	"startup": {"money": "money", "population": "integer", "seed": "integer", "wheat_purchases_enabled": "boolean",
		"tea_imports_enabled": "boolean", "flour_imports_enabled": "boolean", "dense_housing_occupied": "integer"},
	"population": {
		"initial_bread": "integer",
		"bread_per_person_per_minute": "positive", "bread_decay_fraction_per_minute": "fraction",
		"empty_city_bread_lookahead_seconds": "number",
		"stats_window_seconds": "positive_integer",
		"hunger_coverage_snap_epsilon": "positive",
		"satisfaction": {"bread_weight": "number", "tax_weight": "number",
			"overcrowding_weight": "number", "smoothing_per_second": "number", "snap_epsilon": "positive"},
		"growth": {"immigration_threshold": "percent", "emigration_threshold": "percent",
			"immigration_per_minute": "number", "emigration_per_minute": "number",
			"hunger_emigration_threshold": "fraction", "hunger_emigration_recovery": "fraction",
			"hunger_emigration_multiplier": "number", "served_capacity_only": "boolean"},
		"tax": {"rate": "fraction", "base_per_employed_worker_per_minute": "money"},
		"tea": {"per_person_per_minute": "positive", "satisfaction_bonus": "number"},
	},
	"market": {"wheat": {"base_price": "money", "min_price": "money",
		"max_price": "money", "price_update_seconds": "positive_integer",
		"max_step": "positive_integer", "reversion": "fraction", "storage_capacity": "integer",
			"decay_fraction_per_minute": "fraction", "accumulate_factor": "number"},
		"barley": {"base_price": "money", "min_price": "money",
			"max_price": "money", "price_update_seconds": "positive_integer",
			"max_step": "positive_integer", "reversion": "fraction", "storage_capacity": "integer",
			"decay_fraction_per_minute": "fraction"},
		"malt": {"storage_capacity": "integer", "decay_fraction_per_minute": "fraction"},
		"beer": {"storage_capacity": "integer", "decay_fraction_per_minute": "fraction"},
		"imported_flour": {"price_per_lot": "money", "lot_size": "positive_integer",
			"max_debt_lots": "positive_integer"},
		"tea": {"price": "money", "buffer_seconds": "integer"}},
		"policy": {"wheat": {"default_accumulate_price": "optional_price", "default_max_price": "optional_price",
			"default_target_stock": "integer", "default_reserve_minutes": "integer"},
			"unloading": {"default_barley_percent": "integer", "step_percent": "integer"}},
	"demolish": {"refund_ratio": "fraction", "refund_grace_seconds": "number",
		"no_jobs_refund_ratio": "fraction"},
	# Repairing a damaged wharf of the map (issue #177, D-083): the share of a new wharf's cost it takes.
	"repair": {"wharf_cost_ratio": "fraction"},
	# Streets and transport of the distance model (issue #67, D-070, D-080), in metres since issue #186 (D-086).
	"roads": {"cost": "money", "upkeep_per_minute": "money"},
	"transport": {"cost_per_unit_per_m": "number", "expensive_m": "positive_integer"},
	# Side of a map cell (issue #186, D-086).
	"map": {"cell_size_m": "positive_integer"},
	# Public fountain (issue #63, D-089): the houses it covers, centre to centre, not rounded to cells.
	"fountain": {"radius_m": "positive"},
	# Historic events (issue #63): off by default, so the water buildings wait for them. The risk of each water source.
	# The cholera mission's defeat_pause says whether it stops the depopulation timer (D-090).
	"events": {"enabled": "boolean", "source_risk": {"neutral": "fraction", "old_ford": "fraction"},
		"cholera": {"defeat_pause": "boolean"}},
	# Money sinks of issue #118: upkeep grows with the city's size, construction with each copy of a type.
	"economy": {
		"administration": {"per_building": "number", "free_buildings": "integer", "max_multiplier": "number"},
		"construction_escalation": {"free_copies": "integer", "per_building": "number", "max_multiplier": "number"},
	},
	# Statistics history (issue #82, D-066): derived from the state, it never feeds back into the simulation.
	"stats": {
		"fine": {"span_seconds": "positive_integer"},
		"medium": {"bucket_seconds": "positive_integer", "span_seconds": "positive_integer"},
		"chapter": {"bucket_seconds": "positive_integer"},
		"causes": {"max_events": "positive_integer", "min_duration_seconds": "integer"},
	},
	"defeat": {
		# Off only through the defeats knob (D-065): the city can no longer lose, but the timers' inputs still run.
		"enabled": "boolean",
		"bankruptcy": {"threshold": "money", "duration_seconds": "positive_integer"},
		"hunger": {"threshold": "fraction", "duration_seconds": "positive_integer", "smoothing": "number"},
		"depopulation": {"warning_fraction": "fraction", "defeat_fraction": "fraction",
			"minimum_population": "integer", "duration_seconds": "positive_integer",
			"peak_decay_per_minute": "fraction", "stability_window_seconds": "positive_integer"},
		"grace_seconds": "number",
	},
}

# One era's data is loaded: the engine is the same for every era, only these files change.
const DEFAULT_ERA: String = "victorian"
# Difficulty presets and knobs (D-065). Optional: without them the game runs on the base values alone.
const DIFFICULTY_FOLDER: String = "difficulty"
const PRESETS_PATH: String = "difficulty/presets.json"
const KNOBS_PATH: String = "difficulty/knobs.json"
const KNOB_KINDS: Array[String] = ["switch", "value", "price_volatility"]
# Missions (issue #63, D-090): one file each in the era's missions/ folder, optional.
const MISSIONS_FOLDER: String = "missions"
const MISSION_FIELDS: Array[String] = ["duration_min", "goal", "on_completed", "on_failed", "on_abandoned"]
const MISSION_METRICS: Array[String] = ["population"]
const MISSION_EFFECTS: Array[String] = ["money"]
const MAP_IMPORTED_FIELDS: Array[String] = ["dock_cells", "road_cells", "existing_cells", "terrain",
	"dense_housing_cells", "roads_enabled", "road_diagonals", "anchors", "named_sites", "history_notes",
	"period_houses", "damaged_wharves", "lot_styles"]

var _errors: Array[String] = []
# Keys whose value was rejected: their error already names the culprit, so a preset, knob or role that
# targets them does not add a second one (a broken mod value would otherwise read as a broken preset).
var _rejected_keys: Array[StringName] = []
var _era: String = DEFAULT_ERA


# `mods_root` is where the player's mods live (ModLayer.DEFAULT_ROOT in the game); empty loads data/ alone, as
# tests and balance tools do so that nothing on the machine changes their results.
func load_all(root: String = "res://data", era: String = DEFAULT_ERA, mods_root: String = "") -> DataLoadResult:
	_errors.clear()
	_rejected_keys.clear()
	_era = era
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps", "eras".path_join(_era), _missions_folder(), "scenarios",
			DIFFICULTY_FOLDER]:
		var directory: DirAccess = DirAccess.open(root.path_join(folder))
		if directory == null and folder in [DIFFICULTY_FOLDER, _missions_folder()]:
			continue
		if directory == null:
			if folder == "scenarios":
				continue
			_errors.append("%s/%s: cannot open directory" % [root, folder])
			continue
		var files: PackedStringArray = directory.get_files()
		files.sort()
		for file_name: String in files:
			if not file_name.ends_with(".json"):
				continue
			var path: String = folder.path_join(file_name)
			var file: FileAccess = FileAccess.open(root.path_join(path), FileAccess.READ)
			if file == null:
				_errors.append("%s: cannot read file" % path)
				continue
			var json: JSON = JSON.new()
			if json.parse(file.get_as_text()) != OK:
				_errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
			elif json.data is not Dictionary:
				_errors.append("%s: expected an object" % path)
			else:
				documents[path] = json.data
	var mods: ModLayer = ModLayer.new()
	mods.apply(documents, mods_root, era)
	_errors.append_array(mods.errors)
	var result: DataLoadResult = _build(documents)
	result.errors.assign(result.errors.map(mods.blame))
	result.mods = mods.mods
	result.mod_conflicts = mods.conflicts
	return result


# Also accepts in-memory documents so invalid fixtures never enter the game's data directory.
func load_documents(documents: Dictionary[String, Dictionary], era: String = DEFAULT_ERA) -> DataLoadResult:
	_errors.clear()
	_rejected_keys.clear()
	_era = era
	return _build(documents)


func _build(documents: Dictionary[String, Dictionary]) -> DataLoadResult:
	var catalog: DataCatalog = DataCatalog.new()
	var required: Array[String] = ["economy/goods.json", "economy/buildings.json",
		"roles/neutral_administrator.json", "maps/whitechapel_1850s.json", _needs_path(), _classes_path()]
	for section: String in ECONOMY_SCHEMAS:
		required.append("economy/%s.json" % section)
	for path: String in required:
		if not documents.has(path):
			_errors.append("%s: missing file" % path)
	_load_goods(documents.get("economy/goods.json", {}), catalog)
	_load_buildings(documents.get("economy/buildings.json", {}), catalog)
	# Before the maps, whose streets are made of these pieces.
	_load_road_footprint(documents.get("economy/roads.json", {}), catalog)
	for path: String in documents:
		var raw: Dictionary = documents[path]
		var section: String = path.get_file().get_basename()
		if path.begins_with("roles/"):
			_load_role(raw, path, catalog)
		elif path.begins_with("maps/"):
			_load_map(raw, path, catalog)
		elif path.begins_with("scenarios/") or path.begins_with(_missions_folder() + "/") 				or path in [_needs_path(), _classes_path(), PRESETS_PATH, KNOBS_PATH]:
			continue
		elif ECONOMY_SCHEMAS.has(section) and path == "economy/%s.json" % section:
			var numeric: Dictionary = raw.duplicate()
			# The street piece is structure, read above.
			if section == "roads":
				numeric.erase("footprint")
			_numbers(numeric, ECONOMY_SCHEMAS[section], path, section, catalog)
		elif path not in required:
			_errors.append("%s: unsupported data file" % path)
	# Needs and classes refer to goods, buildings and Params keys, so they load after all of those.
	_load_needs(documents.get(_needs_path(), {}), catalog)
	_load_classes(documents.get(_classes_path(), {}), catalog)
	# A mission names the boolean key that pauses the defeat, so it loads once the economy keys exist.
	for path: String in documents:
		if path.begins_with(_missions_folder() + "/"):
			_load_mission(documents[path], path, catalog)
	for path: String in documents:
		if path.begins_with("scenarios/"):
			_load_scenario(documents[path], path, catalog)
	# Roles may precede economy files in the dictionary; resolve keys only after registration.
	for role: RoleDef in catalog.roles.values():
		for modifier: Modifier in role.modifiers:
			if not catalog.base_values.has(modifier.key) and modifier.key not in _rejected_keys:
				_errors.append("roles/%s.json.modifiers: unknown key '%s'" % [role.id, modifier.key])
	var defeat_key: StringName = &"defeat.depopulation.defeat_fraction"
	var warning_key: StringName = &"defeat.depopulation.warning_fraction"
	if catalog.base_values.has(defeat_key) and catalog.base_values.has(warning_key) \
			and float(catalog.base_values[defeat_key]) > float(catalog.base_values[warning_key]):
		_errors.append("economy/defeat.json: defeat.depopulation.defeat_fraction must be <= defeat.depopulation.warning_fraction")
	var threshold_key: StringName = &"population.growth.hunger_emigration_threshold"
	var recovery_key: StringName = &"population.growth.hunger_emigration_recovery"
	if catalog.base_values.has(threshold_key) and catalog.base_values.has(recovery_key) \
			and float(catalog.base_values[recovery_key]) < float(catalog.base_values[threshold_key]):
		_errors.append("economy/population.json: population.growth.hunger_emigration_recovery must be >= population.growth.hunger_emigration_threshold")
	_check_wheat_policy(catalog)
	var bucket_key: StringName = &"stats.medium.bucket_seconds"
	var span_key: StringName = &"stats.medium.span_seconds"
	if catalog.base_values.has(bucket_key) and catalog.base_values.has(span_key) \
			and int(catalog.base_values[span_key]) % int(catalog.base_values[bucket_key]) != 0:
		_errors.append("economy/stats.json: stats.medium.span_seconds must be a multiple of stats.medium.bucket_seconds")
	# Presets and knobs name Params keys, so they load once every key is registered.
	_load_presets(documents.get(PRESETS_PATH, {}), catalog)
	_load_knobs(documents.get(KNOBS_PATH, {}), catalog)
	if _errors.is_empty():
		for preset_id: StringName in catalog.difficulties:
			for message: String in DataLayers.resolve(catalog, preset_id).errors:
				_errors.append("%s.%s: %s" % [PRESETS_PATH, preset_id, message])
	if _errors.is_empty():
		for role: RoleDef in catalog.roles.values():
			for message: String in Params.new(catalog, role).validation_errors():
				var error: String = "roles/%s.json.modifiers: %s" % [role.id, message]
				if error not in _errors:
					_errors.append(error)
	var result: DataLoadResult = DataLoadResult.new()
	result.errors.assign(_errors)
	if _errors.is_empty():
		result.catalog = catalog
	return result


func _check_wheat_policy(catalog: DataCatalog) -> void:
	var values: Array[int] = []
	for key: StringName in Params.WHEAT_POLICY_KEYS:
		if not catalog.base_values.has(key):
			return
		values.append(int(catalog.base_values[key]))
	var message: String = Params.wheat_policy_error(values)
	if not message.is_empty():
		_errors.append("economy/policy.json: %s" % message)


func _object(raw: Variant, fields: Array[String], path: String) -> bool:
	if raw is not Dictionary:
		_errors.append("%s: expected an object" % path)
		return false
	var valid: bool = true
	for field: String in fields:
		if not raw.has(field):
			_errors.append("%s.%s: missing field" % [path, field])
			valid = false
	for field: Variant in raw:
		if field not in fields:
			_errors.append("%s.%s: unknown field" % [path, field])
			valid = false
	return valid


func _numbers(raw: Variant, schema: Dictionary, path: String,
		prefix: String, catalog: DataCatalog) -> void:
	var fields: Array[String] = []
	fields.assign(schema.keys())
	if not _object(raw, fields, path):
		return
	for field: String in schema:
		var location: String = "%s.%s" % [path, field]
		var key: String = "%s.%s" % [prefix, field]
		if schema[field] is Dictionary:
			_numbers(raw[field], schema[field], location, key, catalog)
		else:
			_number(raw[field], schema[field], location, key, catalog)


func _number(raw: Variant, kind: String, path: String, key: String, catalog: DataCatalog) -> bool:
	if kind == "boolean":
		return _boolean(raw, path, key, catalog)
	var integral: bool = kind in ["money", "integer", "positive_integer", "optional_price"]
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
		_errors.append("%s: expected a finite %s" % [path, kind])
		_rejected_keys.append(StringName(key))
		return false
	var value: float = float(raw)
	# JSON numbers arrive as doubles; reject values outside int64 before conversion.
	# An optional price may be -1: "none" (see WheatPolicy), outside the price domain.
	var lowest: float = -1.0 if kind == "optional_price" else 0.0
	if value < lowest or (integral and (value != floor(value) or value >= 9223372036854775808.0)) \
			or (kind.begins_with("positive") and value <= 0) \
			or (kind == "fraction" and value > 1) or (kind == "percent" and value > 100) \
			or not ParameterRanges.is_valid(StringName(key), value):
		_errors.append("%s: invalid %s value %s" % [path, kind, raw])
		_rejected_keys.append(StringName(key))
		return false
	catalog.base_values[StringName(key)] = int(raw) if integral else value
	if integral:
		catalog.integer_keys.append(StringName(key))
	if kind in ["money", "optional_price"]:
		catalog.money_keys.append(StringName(key))
	return true


func _boolean(raw: Variant, path: String, key: String, catalog: DataCatalog) -> bool:
	# JSON true/false only; 0/1 would hide a typo in a switch as a number.
	if typeof(raw) != TYPE_BOOL:
		_errors.append("%s: expected a boolean" % path)
		_rejected_keys.append(StringName(key))
		return false
	catalog.base_values[StringName(key)] = raw
	catalog.boolean_keys.append(StringName(key))
	return true


func _strings(raw: Variant, path: String, target: Array[String]) -> bool:
	if raw is not Array:
		_errors.append("%s: expected an array" % path)
		return false
	for entry: Variant in raw:
		if entry is not String or entry.is_empty():
			_errors.append("%s: expected nonempty strings" % path)
			return false
		target.append(entry)
	return true


func _known_tags(tags: Array[String], path: String) -> bool:
	var valid: bool = true
	for tag: String in tags:
		if tag not in BUILDING_TAGS:
			_errors.append("%s: unknown tag %s" % [path, tag])
			valid = false
	return valid


func _load_goods(raw: Dictionary, catalog: DataCatalog) -> void:
	if raw.is_empty():
		_errors.append("economy/goods.json: expected goods")
	for id: String in raw:
		var path: String = "economy/goods.json.%s" % id
		if not _object(raw[id], ["unit"], path):
			continue
		var unit: Variant = raw[id]["unit"]
		if unit is not String or unit.is_empty():
			_errors.append("%s.unit: expected a nonempty string" % path)
			continue
		var good: GoodDef = GoodDef.new()
		good.id = StringName(id)
		good.unit = unit
		catalog.goods[good.id] = good


func _load_buildings(raw: Dictionary, catalog: DataCatalog) -> void:
	if raw.is_empty():
		_errors.append("economy/buildings.json: expected buildings")
	for id: String in raw:
		var path: String = "economy/buildings.json.%s" % id
		if raw[id] is not Dictionary:
			_errors.append("%s: expected an object" % path)
			continue
		if not raw[id].has("tags"):
			_errors.append("%s.tags: missing field" % path)
			continue
		var building: BuildingDef = BuildingDef.new()
		building.id = StringName(id)
		if not _strings(raw[id]["tags"], path + ".tags", building.tags):
			continue
		if not _known_tags(building.tags, path + ".tags"):
			continue
		if raw[id].has("buildable"):
			if raw[id]["buildable"] is not bool:
				_errors.append("%s.buildable: expected a boolean" % path)
				continue
			building.buildable = raw[id]["buildable"]
		if raw[id].has("footprint") and not _footprint(raw[id]["footprint"], path + ".footprint", building):
			continue
		var is_housing: bool = "housing" in building.tags
		var makes_goods: bool = not is_housing and WaterSystem.WATER_TAG not in building.tags
		var schema: Dictionary = BUILDING_FIELDS.duplicate()
		if is_housing:
			schema["capacity"] = "integer"
		elif makes_goods:
			schema["recipe"] = "integer"
		var fields: Array[String] = []
		fields.assign(schema.keys())
		fields.append("tags")
		for field: String in ["buildable", "footprint"]:
			if raw[id].has(field):
				fields.append(field)
		for field: String in BUILDING_SERVICE_FIELDS:
			if raw[id].has(field):
				fields.append(field)
		if not _object(raw[id], fields, path):
			continue
		var numeric: Dictionary = raw[id].duplicate()
		numeric.erase("tags")
		numeric.erase("buildable")
		numeric.erase("footprint")
		if numeric.has("service_radius_m"):
			schema["service_radius_m"] = "integer"
		for field: String in ["distributes", "supplies"]:
			numeric.erase(field)
		if not _goods_list(raw[id].get("distributes", []), path + ".distributes", building.distributes, catalog) \
				or not _goods_list(raw[id].get("supplies", []), path + ".supplies", building.supplies, catalog):
			continue
		if makes_goods:
			building.recipe = _recipe(numeric["recipe"], path + ".recipe",
				"building.%s.recipe" % id, catalog)
			numeric.erase("recipe")
			schema.erase("recipe")
		_numbers(numeric, schema, path, "building.%s" % id, catalog)
		catalog.buildings[building.id] = building


# Cells the building covers, [w, h] (issue #184, D-086): structure like the tags, not a balance number.
func _footprint(raw: Variant, path: String, building: BuildingDef) -> bool:
	var footprint: Vector2i = _cells_size(raw, path)
	if footprint == Vector2i.ZERO:
		return false
	building.footprint = footprint
	return true


# [w, h] of whole numbers of at least 1, or (0, 0) with the error noted.
func _cells_size(raw: Variant, path: String) -> Vector2i:
	if raw is not Array or raw.size() != 2 \
			or not raw.all(func(side: Variant) -> bool: return _is_whole_number(side) and float(side) >= 1.0):
		_errors.append("%s: expected [w, h] of whole numbers of at least 1" % path)
		return Vector2i.ZERO
	return Vector2i(int(raw[0]), int(raw[1]))


# The piece a street is made of (issue #186, D-086): square, so that a route is measured piece by piece. Without it a
# street is one cell.
func _load_road_footprint(raw: Dictionary, catalog: DataCatalog) -> void:
	if not raw.has("footprint"):
		return
	var footprint: Vector2i = _cells_size(raw["footprint"], "economy/roads.json.footprint")
	if footprint != Vector2i.ZERO and footprint.x != footprint.y:
		_errors.append("economy/roads.json.footprint: expected a square piece")
	elif footprint != Vector2i.ZERO:
		catalog.road_footprint = footprint


func _goods_list(raw: Variant, path: String, target: Array[StringName], catalog: DataCatalog) -> bool:
	var names: Array[String] = []
	if not _strings(raw, path, names):
		return false
	for good: String in names:
		if not catalog.goods.has(StringName(good)):
			_errors.append("%s: unknown good %s" % [path, good])
			return false
		target.append(StringName(good))
	return true


func _recipe(raw: Variant, path: String, prefix: String, catalog: DataCatalog) -> RecipeDef:
	if not _object(raw, ["inputs", "outputs", "seconds"], path):
		return null
	var recipe: RecipeDef = RecipeDef.new()
	_number(raw["seconds"], "positive_integer", path + ".seconds", prefix + ".seconds", catalog)
	for direction: String in ["inputs", "outputs"]:
		if raw[direction] is not Dictionary:
			_errors.append("%s.%s: expected an object" % [path, direction])
			continue
		if direction == "outputs" and raw[direction].is_empty():
			_errors.append("%s.outputs: expected at least one good" % path)
		for good: String in raw[direction]:
			var location: String = "%s.%s.%s" % [path, direction, good]
			if not catalog.goods.has(StringName(good)):
				_errors.append("%s: unknown good" % location)
			_number(raw[direction][good], "positive", location,
				"%s.%s.%s" % [prefix, direction, good], catalog)
			var references: Array[StringName] = recipe.inputs if direction == "inputs" else recipe.outputs
			references.append(StringName(good))
	return recipe


# The files of the selected era; another era is another folder under data/eras/ and no code edit.
func _needs_path() -> String:
	return "eras".path_join(_era).path_join("needs.json")


func _classes_path() -> String:
	return "eras".path_join(_era).path_join("classes.json")


func _missions_folder() -> String:
	return "eras".path_join(_era).path_join(MISSIONS_FOLDER)


# A mission (issue #63, D-090): its structure goes to MissionDef and its numbers to the Params keys `mission.<id>.*`,
# the way the victory stages do.
func _load_mission(raw: Dictionary, path: String, catalog: DataCatalog) -> void:
	var mission: MissionDef = MissionDef.new()
	mission.id = StringName(path.get_file().get_basename())
	var prefix: String = "mission.%s" % mission.id
	var fields: Array[String] = MISSION_FIELDS.duplicate()
	if raw.has("defeat_pause"):
		fields.append("defeat_pause")
	if not _object(raw, fields, path):
		return
	var valid: bool = _number(raw["duration_min"], "positive", path + ".duration_min", prefix + ".duration_min", catalog)
	if raw.has("defeat_pause"):
		mission.defeat_pause = StringName(str(raw["defeat_pause"]))
		if raw["defeat_pause"] is not String or mission.defeat_pause not in catalog.boolean_keys:
			_errors.append("%s.defeat_pause: expected the key of a boolean parameter" % path)
			valid = false
	valid = _mission_goal(raw["goal"], path + ".goal", prefix + ".goal", mission, catalog) and valid
	for outcome: StringName in [MissionSystem.COMPLETED, MissionSystem.FAILED, MissionSystem.ABANDONED]:
		var field: String = "on_%s" % outcome
		valid = _mission_effects(raw[field], "%s.%s" % [path, field], "%s.%s" % [prefix, field], outcome, mission,
			catalog) and valid
	if valid:
		catalog.missions[mission.id] = mission


func _mission_goal(raw: Variant, path: String, prefix: String, mission: MissionDef, catalog: DataCatalog) -> bool:
	if not _object(raw, ["metric", "at_least"], path):
		return false
	if str(raw["metric"]) not in MISSION_METRICS:
		_errors.append("%s.metric: unknown metric %s" % [path, raw["metric"]])
		return false
	mission.goal_metric = StringName(raw["metric"])
	return _number(raw["at_least"], "integer", path + ".at_least", prefix + ".at_least", catalog)


func _mission_effects(raw: Variant, path: String, prefix: String, outcome: StringName, mission: MissionDef,
		catalog: DataCatalog) -> bool:
	if raw is not Array:
		_errors.append("%s: expected an array" % path)
		return false
	var effects: Array[Dictionary] = []
	for index: int in range(raw.size()):
		var where: String = "%s[%d]" % [path, index]
		var entry: Variant = raw[index]
		if entry is not Dictionary or str(entry.get("type", "")) not in MISSION_EFFECTS:
			_errors.append("%s.type: unknown effect" % where)
			return false
		var key: String = "%s.%d.pence" % [prefix, index]
		if not _object(entry, ["type", "pence"], where) 				or not _number(entry["pence"], "money", where + ".pence", key, catalog):
			return false
		effects.append({"type": StringName(entry["type"]), "key": StringName(key)})
	mission.effects[outcome] = effects
	return true


func _load_needs(raw: Dictionary, catalog: DataCatalog) -> void:
	if not _object(raw, ["housing_bonus_per_category", "categories"], _needs_path()):
		return
	_number(raw["housing_bonus_per_category"], "integer", _needs_path() + ".housing_bonus_per_category",
		"needs.housing_bonus_per_category", catalog)
	var categories: Variant = raw["categories"]
	if categories is not Dictionary or categories.is_empty():
		_errors.append("%s.categories: expected categories" % _needs_path())
		return
	for id: String in categories:
		var path: String = "%s.categories.%s" % [_needs_path(), id]
		if _object(categories[id], ["threshold"], path) \
				and _number(categories[id]["threshold"], "percent", path + ".threshold", "needs.%s.threshold" % id, catalog):
			catalog.categories.append(StringName(id))


const CLASS_FIELDS: Array[String] = ["base", "takes_jobs", "housing_building", "housing_max_bonus",
	"satisfaction", "growth", "tax", "needs"]
# Per block of a class: field -> number kind. Each field either points at an existing Params key (a string)
# or is a number that becomes the key class.<id>.<block>.<field>.
const CLASS_SATISFACTION: Dictionary = {"tax_weight": "number", "overcrowding_weight": "number",
	"smoothing_per_second": "number", "snap_epsilon": "positive"}
const CLASS_GROWTH: Dictionary = {"immigration_threshold": "percent", "emigration_threshold": "percent",
	"immigration_per_minute": "number", "emigration_per_minute": "number",
	"hunger_emigration_threshold": "fraction", "hunger_emigration_recovery": "fraction",
	"hunger_emigration_multiplier": "number"}
# Optional field of a class's growth (issue #180, D-085): the need categories that make a house count for immigrants.
const CLASS_SERVED_CATEGORIES: String = "served_categories"
# Optional block of a class (issue #53): how people of another class rise into it and fall back.
const CLASS_MOBILITY_FIELDS: Array[String] = ["from", "promotion", "demotion"]
const CLASS_PROMOTION: Dictionary = {"source_satisfaction": "percent", "per_minute": "number"}
const CLASS_DEMOTION: Dictionary = {"below": "percent", "seconds": "positive_integer", "per_minute": "number"}


func _load_classes(raw: Dictionary, catalog: DataCatalog) -> void:
	if raw.is_empty():
		_errors.append("%s: expected classes" % _classes_path())
	var claimed: Array[StringName] = []
	var bases: int = 0
	var mobility: Dictionary[StringName, Variant] = {}
	for id: String in raw:
		var path: String = "%s.%s" % [_classes_path(), id]
		var fields: Array[String] = CLASS_FIELDS.duplicate()
		if raw[id] is Dictionary and raw[id].has("mobility"):
			fields.append("mobility")
			mobility[StringName(id)] = raw[id]["mobility"]
		if not _object(raw[id], fields, path):
			continue
		var definition: ClassDef = ClassDef.new()
		definition.id = StringName(id)
		if raw[id]["base"] is not bool or raw[id]["takes_jobs"] is not bool:
			_errors.append("%s: base and takes_jobs must be booleans" % path)
		else:
			definition.base = raw[id]["base"]
			definition.takes_jobs = raw[id]["takes_jobs"]
		if definition.base:
			bases += 1
			if not definition.takes_jobs:
				_errors.append("%s: the base class must take jobs" % path)
		_number(raw[id]["housing_max_bonus"], "integer", path + ".housing_max_bonus",
			"class.%s.housing_max_bonus" % id, catalog)
		definition.housing_building = _housing_building(raw[id]["housing_building"], path, claimed, catalog)
		_load_class_blocks(raw[id], path, definition, catalog)
		_load_class_needs(raw[id]["needs"], path + ".needs", definition, catalog)
		_load_served_categories(raw[id]["growth"], path + ".growth", definition)
		catalog.classes[definition.id] = definition
	if not raw.is_empty() and bases != 1:
		_errors.append("%s: exactly one class must be the base class" % _classes_path())
	# Mobility names another class, so it resolves once every class is known.
	for id: StringName in mobility:
		if catalog.classes.has(id):
			_load_class_mobility(mobility[id], "%s.%s.mobility" % [_classes_path(), id], catalog.classes[id], catalog)
	_check_class_hunger(catalog)


func _load_class_blocks(raw: Dictionary, path: String, definition: ClassDef, catalog: DataCatalog) -> void:
	var satisfaction: Dictionary = _class_block(raw["satisfaction"], CLASS_SATISFACTION, path + ".satisfaction",
		"class.%s.satisfaction" % definition.id, catalog)
	# The served categories are names, not numbers: _load_served_categories reads them once the needs are known.
	var growth_numbers: Variant = raw["growth"]
	if growth_numbers is Dictionary:
		growth_numbers = growth_numbers.duplicate()
		growth_numbers.erase(CLASS_SERVED_CATEGORIES)
	var growth: Dictionary = _class_block(growth_numbers, CLASS_GROWTH, path + ".growth",
		"class.%s.growth" % definition.id, catalog)
	definition.tax_weight_key = satisfaction.get("tax_weight", &"")
	definition.overcrowding_weight_key = satisfaction.get("overcrowding_weight", &"")
	definition.smoothing_key = satisfaction.get("smoothing_per_second", &"")
	definition.snap_epsilon_key = satisfaction.get("snap_epsilon", &"")
	definition.immigration_threshold_key = growth.get("immigration_threshold", &"")
	definition.emigration_threshold_key = growth.get("emigration_threshold", &"")
	definition.immigration_per_minute_key = growth.get("immigration_per_minute", &"")
	definition.emigration_per_minute_key = growth.get("emigration_per_minute", &"")
	definition.hunger_threshold_key = growth.get("hunger_emigration_threshold", &"")
	definition.hunger_recovery_key = growth.get("hunger_emigration_recovery", &"")
	definition.hunger_multiplier_key = growth.get("hunger_emigration_multiplier", &"")
	var tax: Variant = raw["tax"]
	if not _object(tax, ["basis", "base"], path + ".tax"):
		return
	if tax["basis"] not in [ClassDef.TAX_EMPLOYED, ClassDef.TAX_RESIDENTS]:
		_errors.append("%s.tax.basis: expected employed or residents" % path)
	else:
		definition.tax_basis = StringName(tax["basis"])
	definition.tax_base_key = _key_or_number(tax["base"], "money", path + ".tax.base",
		"class.%s.tax.base" % definition.id, catalog)


# Resolves every field of a block to the Params key it uses; a missing or bad field is left out and reported.
func _class_block(raw: Variant, schema: Dictionary, path: String, prefix: String, catalog: DataCatalog) -> Dictionary:
	var fields: Array[String] = []
	fields.assign(schema.keys())
	var keys: Dictionary = {}
	if not _object(raw, fields, path):
		return keys
	for field: String in schema:
		var key: StringName = _key_or_number(raw[field], schema[field], "%s.%s" % [path, field],
			"%s.%s" % [prefix, field], catalog)
		if key != &"":
			keys[field] = key
	return keys


# A string is the key of a numeric parameter that already exists; a number is a new parameter under own_key.
func _key_or_number(raw: Variant, kind: String, path: String, own_key: String, catalog: DataCatalog) -> StringName:
	if typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
		return StringName(own_key) if _number(raw, kind, path, own_key, catalog) else &""
	if raw is String and typeof(catalog.base_values.get(StringName(raw))) in [TYPE_INT, TYPE_FLOAT]:
		return StringName(raw)
	_errors.append("%s: expected the key of a numeric parameter" % path)
	return &""


func _load_class_mobility(raw: Variant, path: String, definition: ClassDef, catalog: DataCatalog) -> void:
	if not _object(raw, CLASS_MOBILITY_FIELDS, path):
		return
	var source: StringName = StringName(str(raw["from"]))
	if source == definition.id or not catalog.classes.has(source):
		_errors.append("%s.from: expected another class" % path)
		return
	var own_categories: Array[StringName] = []
	for need: NeedDef in definition.needs:
		own_categories.append(need.category)
	var prefix: String = "class.%s.mobility" % definition.id
	var promotion: Variant = raw["promotion"]
	var promotion_fields: Array[String] = ["min_scores"]
	promotion_fields.append_array(CLASS_PROMOTION.keys())
	if not _object(promotion, promotion_fields, path + ".promotion"):
		return
	# The numeric fields resolve like any class block; the categories are read below.
	var numbers: Dictionary = promotion.duplicate()
	numbers.erase("min_scores")
	var keys: Dictionary = _class_block(numbers, CLASS_PROMOTION, path + ".promotion", prefix + ".promotion", catalog)
	var scores: Variant = promotion["min_scores"]
	if scores is not Dictionary or scores.is_empty():
		_errors.append("%s.promotion.min_scores: expected categories" % path)
		return
	for category: String in scores:
		var location: String = "%s.promotion.min_scores.%s" % [path, category]
		# A category the class has no need in never gets a score, so nobody could ever rise.
		if StringName(category) not in own_categories:
			_errors.append("%s: not a category of this class's needs" % location)
			continue
		var key: StringName = _key_or_number(scores[category], "percent", location,
			"%s.promotion.%s.min_score" % [prefix, category], catalog)
		if key != &"":
			definition.promotion_min_score_keys[StringName(category)] = key
	var demotion: Dictionary = {}
	var demotion_fields: Array[String] = ["category"]
	demotion_fields.append_array(CLASS_DEMOTION.keys())
	if _object(raw["demotion"], demotion_fields, path + ".demotion"):
		var demotion_numbers: Dictionary = raw["demotion"].duplicate()
		demotion_numbers.erase("category")
		demotion = _class_block(demotion_numbers, CLASS_DEMOTION, path + ".demotion", prefix + ".demotion", catalog)
		definition.demotion_category = StringName(str(raw["demotion"]["category"]))
		if definition.demotion_category not in own_categories:
			_errors.append("%s.demotion.category: not a category of this class's needs" % path)
	if keys.size() != CLASS_PROMOTION.size() or demotion.size() != CLASS_DEMOTION.size():
		return
	definition.mobility_from = source
	definition.promotion_source_satisfaction_key = keys["source_satisfaction"]
	definition.promotion_per_minute_key = keys["per_minute"]
	definition.demotion_below_key = demotion["below"]
	definition.demotion_seconds_key = demotion["seconds"]
	definition.demotion_per_minute_key = demotion["per_minute"]


# A category the class has no need in would never be within reach, so no house of the class would ever count.
func _load_served_categories(raw: Variant, path: String, definition: ClassDef) -> void:
	if raw is not Dictionary or not raw.has(CLASS_SERVED_CATEGORIES):
		return
	var location: String = "%s.%s" % [path, CLASS_SERVED_CATEGORIES]
	var categories: Variant = raw[CLASS_SERVED_CATEGORIES]
	if categories is not Array:
		_errors.append("%s: expected a list of categories" % location)
		return
	var own_categories: Array[StringName] = []
	for need: NeedDef in definition.needs:
		own_categories.append(need.category)
	for category: Variant in categories:
		if category is not String or StringName(category) not in own_categories:
			_errors.append("%s: %s is not a category of this class's needs" % [location, str(category)])
		elif StringName(category) not in definition.served_categories:
			definition.served_categories.append(StringName(category))


# Recovery below the threshold would make the hunger flag flip every tick (same rule as the worker's, per class).
func _check_class_hunger(catalog: DataCatalog) -> void:
	for definition: ClassDef in catalog.classes.values():
		if catalog.base_values.has(definition.hunger_threshold_key) and catalog.base_values.has(definition.hunger_recovery_key) 				and float(catalog.base_values[definition.hunger_recovery_key]) < float(catalog.base_values[definition.hunger_threshold_key]):
			_errors.append("%s.%s.growth: hunger_emigration_recovery must be >= hunger_emigration_threshold" % [_classes_path(), definition.id])


func _housing_building(raw: Variant, path: String, claimed: Array[StringName], catalog: DataCatalog) -> StringName:
	var location: String = path + ".housing_building"
	if raw is not String or not catalog.buildings.has(StringName(raw)):
		_errors.append("%s: unknown building" % location)
		return &""
	var id: StringName = StringName(raw)
	if "housing" not in catalog.buildings[id].tags:
		_errors.append("%s: '%s' is not a housing building" % [location, id])
	elif id in claimed:
		_errors.append("%s: '%s' already belongs to another class" % [location, id])
	claimed.append(id)
	return id


func _load_class_needs(raw: Variant, path: String, definition: ClassDef, catalog: DataCatalog) -> void:
	if raw is not Dictionary or raw.is_empty():
		_errors.append("%s: expected needs" % path)
		return
	for good: String in raw:
		var location: String = "%s.%s" % [path, good]
		if not _object(raw[good], ["category", "value", "satisfaction_key", "consumption_key"], location):
			continue
		var need: NeedDef = NeedDef.new()
		need.good = StringName(good)
		if not catalog.goods.has(need.good):
			_errors.append("%s: unknown good" % location)
		need.category = StringName(str(raw[good]["category"]))
		if need.category not in catalog.categories:
			_errors.append("%s.category: unknown category" % location)
		need.satisfaction_key = _key_or_number(raw[good]["satisfaction_key"], "number",
			location + ".satisfaction_key", "class.%s.need.%s.satisfaction_weight" % [definition.id, good], catalog)
		need.consumption_key = _key_or_number(raw[good]["consumption_key"], "positive",
			location + ".consumption_key", "class.%s.need.%s.per_person_per_minute" % [definition.id, good], catalog)
		_number(raw[good]["value"], "percent", location + ".value",
			"class.%s.need.%s.value" % [definition.id, good], catalog)
		definition.needs.append(need)


func _load_role(raw: Dictionary, path: String, catalog: DataCatalog) -> void:
	if not _object(raw, ["id", "modifiers"], path):
		return
	if raw["id"] != path.get_file().get_basename() or raw["modifiers"] is not Array:
		_errors.append("%s: id must match filename; modifiers must be an array" % path)
		return
	var role: RoleDef = RoleDef.new()
	role.id = StringName(raw["id"])
	for index: int in range(raw["modifiers"].size()):
		var entry: Variant = raw["modifiers"][index]
		var location: String = "%s.modifiers[%d]" % [path, index]
		if not _object(entry, ["key", "op", "value"], location):
			continue
		if entry["key"] is not String or entry["op"] not in ["add", "mul", "set"] \
				or typeof(entry["value"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry["value"])):
			_errors.append("%s: expected key string, op add|mul|set and finite numeric value" % location)
			continue
		role.modifiers.append(Modifier.new(StringName(entry["key"]),
			StringName(entry["op"]), float(entry["value"])))
	catalog.roles[role.id] = role


func _load_map(raw: Dictionary, path: String, catalog: DataCatalog) -> void:
	var fields: Array[String] = ["id", "width", "height", "river_cells", "cultivable_cells"]
	# The imported layers (issue #60) are optional, so the 8x8 map and older fixtures stay valid.
	for field: String in MAP_IMPORTED_FIELDS:
		if raw.has(field):
			fields.append(field)
	if not _object(raw, fields, path):
		return
	var dimensions: DataCatalog = DataCatalog.new()
	if raw["id"] != path.get_file().get_basename():
		_errors.append("%s.id: must match filename" % path)
		return
	if not _number(raw["width"], "positive_integer", path + ".width", "width", dimensions) \
			or not _number(raw["height"], "positive_integer", path + ".height", "height", dimensions):
		return
	var map: MapDef = MapDef.new()
	map.id = StringName(raw["id"])
	map.width = int(raw["width"])
	map.height = int(raw["height"])
	# A cell holds one area layer at most; streets are drawn over them, so they only need to be unique.
	var occupied: Array[Vector2i] = []
	var layers: Dictionary[String, Array] = {"river_cells": map.river_cells, "cultivable_cells": map.cultivable_cells,
		"dock_cells": map.dock_cells, "existing_cells": map.existing_cells, "road_cells": map.road_cells}
	for field: String in layers:
		if not raw.has(field):
			continue
		var taken: Array[Vector2i] = occupied
		if field == "road_cells":
			taken = []
		for position: Vector2i in _map_cells(raw[field], "%s.%s" % [path, field], map, taken):
			layers[field].append(position)
	_check_road_pieces(path + ".road_cells", map, catalog.road_footprint)
	if raw.has("terrain"):
		_load_terrain(raw["terrain"], path + ".terrain", map)
	if raw.has("dense_housing_cells"):
		_load_dense_housing_cells(raw["dense_housing_cells"], path + ".dense_housing_cells", map, catalog)
	if raw.has("roads_enabled"):
		if typeof(raw["roads_enabled"]) != TYPE_BOOL:
			_errors.append("%s.roads_enabled: expected a boolean" % path)
		else:
			map.roads_enabled = raw["roads_enabled"]
	if raw.has("road_diagonals"):
		_load_diagonals(raw["road_diagonals"], path + ".road_diagonals", map)
	if raw.has("anchors"):
		_load_anchors(raw["anchors"], path + ".anchors", map, catalog)
	if raw.has("named_sites"):
		for entry: Dictionary in _named_places(raw["named_sites"], path + ".named_sites", map):
			map.named_sites[entry["cell"]] = entry["name"]
	if raw.has("period_houses"):
		_load_period_houses(raw["period_houses"], path + ".period_houses", map, catalog)
	if raw.has("damaged_wharves"):
		_load_damaged_wharves(raw["damaged_wharves"], path + ".damaged_wharves", map, catalog)
	# After the period houses, whose cells carry no lot style.
	if raw.has("lot_styles"):
		_load_lot_styles(raw["lot_styles"], path + ".lot_styles", map, catalog)
	# Liberties of the whole map (issue #152): only checked here, the simulation never reads them.
	if raw.has("history_notes") and (raw["history_notes"] is not Array
			or not raw["history_notes"].all(MapDef.is_history_note)):
		_errors.append("%s.history_notes: expected notes that open with a history tag" % path)
	catalog.maps[map.id] = map


# Historic anchors (issue #152): each stands where its building can, on the river for a wharf and on a standing
# building otherwise; dense housing only on a start cell, so the startup knob of D-075 still decides it. The whole
# footprint counts (issue #186, D-086); an anchor with no use is its one cell.
func _load_anchors(raw: Variant, location: String, map: MapDef, catalog: DataCatalog) -> void:
	for entry: Dictionary in _named_places(raw, location, map):
		var cell: Vector2i = entry["cell"]
		var building: StringName = StringName(str(entry.get("building")))
		var problem: String = ""
		if entry.get("building") is not String or (building != &"" and not catalog.buildings.has(building)):
			problem = "unknown building %s" % building
		elif not _fits(map, _area(catalog, building, cell)):
			problem = "does not fit on the map"
		elif building != &"" and "river" in catalog.buildings[building].tags:
			problem = "" if _all_in(_area(catalog, building, cell), map.river_cells) else "is not on the river"
		elif not _all_in(_area(catalog, building, cell), map.existing_cells):
			problem = "is not a standing building"
		elif building == Simulation.DENSE_HOUSING and cell not in map.dense_housing_cells:
			problem = "is not a dense housing start cell"
		if not problem.is_empty():
			_errors.append("%s: [%d, %d] %s" % [location, cell.x, cell.y, problem])
			continue
		map.anchors[cell] = building


# The 1870 houses (issue #176, D-083): free land with a street on one side, the access every housing needs (D-079).
# The simulation places them as dense housing (#180, D-085) with start_population people, none when it is missing.
# The whole footprint of the house counts (issue #186, D-086).
func _load_period_houses(raw: Variant, location: String, map: MapDef, catalog: DataCatalog) -> void:
	for entry: Dictionary in _named_places(raw, location, map):
		var cell: Vector2i = entry["cell"]
		var area: Rect2i = _area(catalog, Simulation.DENSE_HOUSING, cell)
		var people: Variant = entry.get("start_population", 0)
		if not _fits(map, area) or not EconomyContext.cells_of(area).all(func(other: Vector2i) -> bool:
				return _is_free_land(map, other)):
			_errors.append("%s: [%d, %d] is not free land" % [location, cell.x, cell.y])
		elif not map.beside_road(area):
			_errors.append("%s: [%d, %d] has no street on any side" % [location, cell.x, cell.y])
		elif not _is_whole_number(people) or float(people) < 0.0:
			_errors.append("%s: [%d, %d] start_population must be a whole number of at least 0"
				% [location, cell.x, cell.y])
		else:
			map.period_houses.append(cell)
			map.period_house_population[cell] = int(people)


# Damaged wharves (issue #176, D-083): on the river, where a wharf stands, all of its footprint (D-086). What repairing
# one costs is not the map's: it is repair.wharf_cost_ratio in economy/repair.json (#177).
func _load_damaged_wharves(raw: Variant, location: String, map: MapDef, catalog: DataCatalog) -> void:
	for entry: Dictionary in _named_places(raw, location, map):
		var cell: Vector2i = entry["cell"]
		var area: Rect2i = _area(catalog, RepairWharfCommand.WHARF, cell)
		if not _fits(map, area) or not _all_in(area, map.river_cells):
			_errors.append("%s: [%d, %d] is not on the river" % [location, cell.x, cell.y])
		else:
			map.damaged_wharves.append(cell)


# Lot styles (issue #176, D-083): only drawing, one for each cell of free land that no period house covers and none
# anywhere else.
func _load_lot_styles(raw: Variant, location: String, map: MapDef, catalog: DataCatalog) -> void:
	if raw is not Dictionary or not raw.keys().all(func(style: Variant) -> bool: return style is String):
		_errors.append("%s: expected an object of style to cells" % location)
		return
	var houses: Array[Vector2i] = []
	for cell: Vector2i in map.period_houses:
		houses.append_array(EconomyContext.cells_of(_area(catalog, Simulation.DENSE_HOUSING, cell)))
	var taken: Array[Vector2i] = []
	for style: String in raw:
		for cell: Vector2i in _map_cells(raw[style], "%s.%s" % [location, style], map, taken):
			if not _is_free_land(map, cell) or cell in houses:
				_errors.append("%s.%s: [%d, %d] is not free land" % [location, style, cell.x, cell.y])
			else:
				map.lot_styles[cell] = StringName(style)
	for y: int in range(map.height):
		for x: int in range(map.width):
			var cell: Vector2i = Vector2i(x, y)
			if _is_free_land(map, cell) and cell not in taken and cell not in houses:
				_errors.append("%s: [%d, %d] has no lot style" % [location, cell.x, cell.y])


# The cells a building of the map's lists covers from its cell, the north-west corner (issue #186, D-086). A type the
# data does not have, or an anchor with no use, is its one cell.
static func _area(catalog: DataCatalog, id: StringName, cell: Vector2i) -> Rect2i:
	var definition: BuildingDef = catalog.buildings.get(id)
	return Rect2i(cell, definition.footprint if definition != null else Vector2i.ONE)


static func _fits(map: MapDef, area: Rect2i) -> bool:
	return Rect2i(Vector2i.ZERO, Vector2i(map.width, map.height)).encloses(area)


static func _all_in(area: Rect2i, cells: Array[Vector2i]) -> bool:
	return EconomyContext.cells_of(area).all(func(cell: Vector2i) -> bool: return cell in cells)


# The historic streets are whole pieces of economy/roads.json on the grid of pieces (issue #186, D-086), so a route is
# measured piece by piece like the player's streets.
func _check_road_pieces(location: String, map: MapDef, piece: Vector2i) -> void:
	for cell: Vector2i in map.road_cells:
		var origin: Vector2i = RoadNetwork.piece_origin(cell, piece)
		if not _all_in(Rect2i(origin, piece), map.road_cells):
			_errors.append("%s: [%d, %d] is not part of a whole street piece of %dx%d from [%d, %d]"
				% [location, cell.x, cell.y, piece.x, piece.y, origin.x, origin.y])


static func _is_free_land(map: MapDef, cell: Vector2i) -> bool:
	return cell not in map.river_cells and cell not in map.dock_cells and cell not in map.road_cells 		and cell not in map.existing_cells


# Entries with a name, a source and a cell of the map, each with its cell as a Vector2i.
func _named_places(raw: Variant, location: String, map: MapDef) -> Array[Dictionary]:
	var places: Array[Dictionary] = []
	if raw is not Array:
		_errors.append("%s: expected an array" % location)
		return places
	for entry: Variant in raw:
		if entry is not Dictionary or entry.get("name") is not String or entry.get("source") is not String \
				or entry["name"].is_empty() or entry["source"].is_empty() \
				or not MapDef.is_history_note(entry.get("history")):
			_errors.append("%s: %s needs a name, a source and a history tag" % [location, str(entry)])
			continue
		for cell: Vector2i in _map_cells([entry.get("cell")], location, map, []):
			var place: Dictionary = entry.duplicate()
			place["cell"] = cell
			places.append(place)
	return places


# Diagonal edges of the historic streets (D-058, D-080): listed one by one, never guessed from the cells. Each joins
# two street cells that touch corner to corner.
func _load_diagonals(raw: Variant, location: String, map: MapDef) -> void:
	if raw is not Array:
		_errors.append("%s: expected an array" % location)
		return
	for entry: Variant in raw:
		if entry is not Array or entry.size() != 4 or not entry.all(_is_whole_number):
			_errors.append("%s: expected [x1, y1, x2, y2]" % location)
			continue
		var edge: Vector4i = Vector4i(int(entry[0]), int(entry[1]), int(entry[2]), int(entry[3]))
		var from: Vector2i = Vector2i(edge.x, edge.y)
		var to: Vector2i = Vector2i(edge.z, edge.w)
		if from not in map.road_cells or to not in map.road_cells or absi(from.x - to.x) != 1 \
				or absi(from.y - to.y) != 1:
			_errors.append("%s: [%d, %d, %d, %d] must join two diagonal street cells"
				% [location, edge.x, edge.y, edge.z, edge.w])
			continue
		map.road_diagonals.append(edge)


static func _is_whole_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))


# Where dense housing stands at the start (issue #154): on a standing building with a street on one side, the access
# every housing needs (D-079). The whole footprint of the house counts (issue #186, D-086).
func _load_dense_housing_cells(raw: Variant, location: String, map: MapDef, catalog: DataCatalog) -> void:
	for position: Vector2i in _map_cells(raw, location, map, []):
		var area: Rect2i = _area(catalog, Simulation.DENSE_HOUSING, position)
		if not _fits(map, area) or not _all_in(area, map.existing_cells):
			_errors.append("%s: [%d, %d] is not a standing building" % [location, position.x, position.y])
		elif not map.beside_road(area):
			_errors.append("%s: [%d, %d] has no street on any side" % [location, position.x, position.y])
		else:
			map.dense_housing_cells.append(position)


# Valid cells of one layer, in order; each accepted cell is added to `taken`.
func _map_cells(raw: Variant, location: String, map: MapDef, taken: Array[Vector2i]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if raw is not Array:
		_errors.append("%s: expected an array" % location)
		return cells
	var dimensions: DataCatalog = DataCatalog.new()
	for cell: Variant in raw:
		if cell is not Array or cell.size() != 2:
			_errors.append("%s: expected [x, y]" % location)
			continue
		if not _number(cell[0], "integer", location + ".x", "x", dimensions) \
				or not _number(cell[1], "integer", location + ".y", "y", dimensions):
			continue
		var position: Vector2i = Vector2i(int(cell[0]), int(cell[1]))
		if position.x >= map.width or position.y >= map.height or position in taken:
			_errors.append("%s: out of bounds or duplicate cell %s" % [location, position])
			continue
		taken.append(position)
		cells.append(position)
	return cells


# Basic terrain labels (D-073, D-074) on dry cells, one per cell; firm ground is every cell left out.
func _load_terrain(raw: Variant, location: String, map: MapDef) -> void:
	if raw is not Dictionary:
		_errors.append("%s: expected an object" % location)
		return
	for label: Variant in raw:
		if StringName(str(label)) not in MapDef.TERRAIN_LABELS:
			_errors.append("%s.%s: unknown terrain label" % [location, label])
			continue
		var taken: Array[Vector2i] = []
		for position: Vector2i in _map_cells(raw[label], "%s.%s" % [location, label], map, taken):
			if position in map.river_cells or position in map.dock_cells or map.terrain.has(position):
				_errors.append("%s.%s: water or duplicate cell %s" % [location, label, position])
				continue
			map.terrain[position] = StringName(label)


# Scenario files are optional: a harness or old fixture without victory has no objectives.
func _load_scenario(raw: Dictionary, path: String, catalog: DataCatalog) -> void:
	var id: StringName = StringName(path.get_file().get_basename())
	var stages: Array[Dictionary] = []
	catalog.scenarios[id] = {"stages": stages, "map": MapDef.DEFAULT_ID}
	var scenario_fields: Array[String] = []
	for field: String in ["victory", "map"]:
		if raw.has(field):
			scenario_fields.append(field)
	if not _object(raw, scenario_fields, path):
		return
	if raw.has("map"):
		if raw["map"] is not String or not catalog.maps.has(StringName(raw["map"])):
			_errors.append("%s.map: unknown map %s" % [path, raw["map"]])
		else:
			catalog.scenarios[id]["map"] = StringName(raw["map"])
	if not raw.has("victory"):
		return
	if not _object(raw["victory"], ["stages"], path + ".victory"):
		return
	var entries: Variant = raw["victory"]["stages"]
	if entries is not Array or entries.is_empty():
		_errors.append("%s.victory.stages: expected a nonempty array" % path)
		return
	for entry: Variant in entries:
		var where: String = "%s.victory.stages[%d]" % [path, stages.size()]
		if entry is not Dictionary:
			_errors.append("%s: expected an object" % where)
			continue
		var mode: String = str(entry.get("mode", ""))
		var metric: String = str(entry.get("metric", ""))
		var duration: String = "duration_seconds" if mode == "mean" else "required_minutes"
		var fields: Array[String] = ["id", "metric", "mode", "threshold", duration]
		if metric == "class_population":
			fields.append("class_id")
		if not _object(entry, fields, where):
			continue
		if entry["id"] is not String or not String(entry["id"]).is_valid_identifier():
			_errors.append("%s.id: expected an identifier" % where)
			continue
		var stage_id: StringName = StringName(entry["id"])
		if stages.any(func(stage: Dictionary) -> bool: return stage["id"] == stage_id):
			_errors.append("%s.id: duplicate stage" % where)
			continue
		if not ((mode == "mean" and metric in ["population", "class_population"]) \
				or (mode == "consecutive_minutes" and metric == "revenue")):
			_errors.append("%s: unsupported metric/mode" % where)
			continue
		var prefix: String = "victory.%s.%s" % [id, stage_id]
		var def: Dictionary = {"id": stage_id, "metric": StringName(metric), "mode": StringName(mode), "prefix": prefix}
		if metric == "class_population":
			if entry["class_id"] is not String or not catalog.classes.has(StringName(entry["class_id"])):
				_errors.append("%s.class_id: unknown class" % where)
				continue
			def["class_id"] = StringName(entry["class_id"])
			def["class_base"] = catalog.classes[def["class_id"]].base
		_number(entry["threshold"], "money" if metric == "revenue" else "integer", where + ".threshold", prefix + ".threshold", catalog)
		_number(entry[duration], "positive_integer", where + "." + duration, prefix + "." + duration, catalog)
		stages.append(def)


func _load_presets(raw: Dictionary, catalog: DataCatalog) -> void:
	for id: Variant in raw:
		var location: String = "%s.%s" % [PRESETS_PATH, id]
		if not _object(raw[id], ["modifiers", "events"], location):
			continue
		if raw[id]["modifiers"] is not Array or raw[id]["events"] is not Array or not raw[id]["events"].is_empty():
			_errors.append("%s: modifiers must be an array; events must be an empty array (reserved for #63)" % location)
			continue
		var preset: DifficultyDef = DifficultyDef.new()
		preset.id = StringName(id)
		for index: int in range(raw[id]["modifiers"].size()):
			var modifier: Modifier = _relative_modifier(raw[id]["modifiers"][index],
				"%s.modifiers[%d]" % [location, index], catalog)
			if modifier != null:
				preset.modifiers.append(modifier)
		catalog.difficulties[preset.id] = preset


# A preset is relative to the values below it (D-065): mul or add on a numeric key, never set.
func _relative_modifier(entry: Variant, location: String, catalog: DataCatalog) -> Modifier:
	if not _object(entry, ["key", "op", "value"], location):
		return null
	if entry["key"] is not String or entry["op"] not in ["add", "mul"] 			or typeof(entry["value"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry["value"])):
		_errors.append("%s: expected key string, op add|mul and finite numeric value" % location)
		return null
	var key: StringName = StringName(entry["key"])
	if key in _rejected_keys:
		return null
	if not catalog.base_values.has(key) or key in catalog.boolean_keys:
		_errors.append("%s: unknown or non-numeric key '%s'" % [location, key])
		return null
	return Modifier.new(key, StringName(entry["op"]), float(entry["value"]))


func _load_knobs(raw: Dictionary, catalog: DataCatalog) -> void:
	for id: Variant in raw:
		var location: String = "%s.%s" % [KNOBS_PATH, id]
		var entry: Variant = raw[id]
		var is_switch: bool = entry is Dictionary and entry.get("kind") == "switch"
		var fields: Array[String] = ["kind", "keys"]
		if not is_switch:
			fields.append_array(["min", "max", "step"])
		if not _object(entry, fields, location):
			continue
		var knob: KnobDef = KnobDef.new()
		knob.id = StringName(id)
		if entry["kind"] not in KNOB_KINDS or not _knob_keys(entry["keys"], location, knob):
			_errors.append("%s: kind must be one of %s, with a non-empty list of keys" % [location, KNOB_KINDS])
			continue
		knob.kind = StringName(entry["kind"])
		if not is_switch and not _knob_range(entry, location, knob):
			continue
		if _knob_targets_valid(knob, location, catalog):
			catalog.knobs[knob.id] = knob


func _knob_keys(raw: Variant, location: String, knob: KnobDef) -> bool:
	var keys: Array[String] = []
	if not _strings(raw, location + ".keys", keys) or keys.is_empty():
		return false
	for key: String in keys:
		knob.keys.append(StringName(key))
	return true


func _knob_range(entry: Dictionary, location: String, knob: KnobDef) -> bool:
	for field: String in ["min", "max", "step"]:
		if typeof(entry[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry[field])):
			_errors.append("%s.%s: expected a finite number" % [location, field])
			return false
	knob.minimum = float(entry["min"])
	knob.maximum = float(entry["max"])
	knob.step = float(entry["step"])
	if knob.step <= 0.0 or knob.minimum > knob.maximum:
		_errors.append("%s: step must be positive and min <= max" % location)
		return false
	return true


# Every value the knob can take must be one its keys accept, so the player can never pick an invalid one.
func _knob_targets_valid(knob: KnobDef, location: String, catalog: DataCatalog) -> bool:
	var valid: bool = true
	for target: StringName in knob.keys:
		if target in _rejected_keys or StringName("market.%s.max_step" % target) in _rejected_keys:
			valid = false
			continue
		match knob.kind:
			&"switch":
				if target not in catalog.boolean_keys:
					_errors.append("%s.keys: '%s' is not a switch" % [location, target])
					valid = false
			&"value":
				if not catalog.base_values.has(target) or target in catalog.boolean_keys 						or not ParameterRanges.is_valid(target, knob.minimum) 						or not ParameterRanges.is_valid(target, knob.maximum):
					_errors.append("%s: min and max must be valid values of '%s'" % [location, target])
					valid = false
			&"price_volatility":
				if knob.minimum <= 0.0 or not catalog.base_values.has(StringName("market.%s.max_step" % target)):
					_errors.append("%s: '%s' is not a traded grain, or min is not positive" % [location, target])
					valid = false
	return valid
