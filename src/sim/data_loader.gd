class_name DataLoader
extends RefCounted

const BUILDING_FIELDS: Dictionary = {
	"cost": "money", "upkeep_per_minute": "money",
	"wage_per_worker_per_minute": "money", "jobs": "integer",
}
const ECONOMY_SCHEMAS: Dictionary = {
	"population": {
		"bread_per_person_per_minute": "positive", "bread_decay_fraction_per_minute": "fraction",
		"satisfaction": {"bread_weight": "number", "tax_weight": "number",
			"overcrowding_weight": "number"},
		"growth": {"immigration_threshold": "percent", "emigration_threshold": "percent",
			"immigration_per_minute": "number", "emigration_per_minute": "number",
			"hunger_emigration_multiplier": "multiplier"},
		"tax": {"rate": "fraction", "base_per_employed_worker_per_minute": "money"},
	},
	"market": {"wheat": {"base_price": "money", "min_price": "money",
		"max_price": "money", "price_update_seconds": "positive_integer"}},
	"defeat": {
		"bankruptcy": {"threshold": "money", "duration_seconds": "positive_integer"},
		"hunger": {"threshold": "fraction", "duration_seconds": "positive_integer"},
		"depopulation": {"warning_fraction": "fraction", "defeat_fraction": "fraction",
			"minimum_population": "integer"},
	},
}

var _errors: Array[String] = []


func load_all(root: String = "res://data") -> DataLoadResult:
	_errors.clear()
	var documents: Dictionary[String, Dictionary] = {}
	for folder: String in ["economy", "roles", "maps"]:
		var directory: DirAccess = DirAccess.open(root.path_join(folder))
		if directory == null:
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
	return _build(documents)


# Also accepts in-memory documents so invalid fixtures never enter the game's data directory.
func load_documents(documents: Dictionary[String, Dictionary]) -> DataLoadResult:
	_errors.clear()
	return _build(documents)


func _build(documents: Dictionary[String, Dictionary]) -> DataLoadResult:
	var catalog: DataCatalog = DataCatalog.new()
	var required: Array[String] = ["economy/goods.json", "economy/buildings.json",
		"roles/neutral_administrator.json", "maps/whitechapel_1850s.json"]
	for section: String in ECONOMY_SCHEMAS:
		required.append("economy/%s.json" % section)
	for path: String in required:
		if not documents.has(path):
			_errors.append("%s: missing file" % path)
	_load_goods(documents.get("economy/goods.json", {}), catalog)
	_load_buildings(documents.get("economy/buildings.json", {}), catalog)
	for path: String in documents:
		var raw: Dictionary = documents[path]
		var section: String = path.get_file().get_basename()
		if path.begins_with("roles/"):
			_load_role(raw, path, catalog)
		elif path.begins_with("maps/"):
			_load_map(raw, path, catalog)
		elif ECONOMY_SCHEMAS.has(section) and path == "economy/%s.json" % section:
			_numbers(raw, ECONOMY_SCHEMAS[section], path, section, catalog)
		elif path not in required:
			_errors.append("%s: unsupported data file" % path)
	# Roles may precede economy files in the dictionary; resolve keys only after registration.
	for role: RoleDef in catalog.roles.values():
		for modifier: Modifier in role.modifiers:
			if not catalog.base_values.has(modifier.key):
				_errors.append("roles/%s.json.modifiers: unknown key '%s'" % [role.id, modifier.key])
	var result: DataLoadResult = DataLoadResult.new()
	result.errors.assign(_errors)
	if _errors.is_empty():
		result.catalog = catalog
	return result


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
	var integral: bool = kind in ["money", "integer", "positive_integer"]
	if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
		_errors.append("%s: expected a finite %s" % [path, kind])
		return false
	var value: float = float(raw)
	# JSON numbers arrive as doubles; reject values outside int64 before conversion.
	if value < 0 or (integral and (value != floor(value) or value >= 9223372036854775808.0)) \
			or (kind.begins_with("positive") and value <= 0) \
			or (kind == "fraction" and value > 1) or (kind == "percent" and value > 100) \
			or (kind == "multiplier" and value < 1):
		_errors.append("%s: invalid %s value %s" % [path, kind, raw])
		return false
	catalog.base_values[StringName(key)] = int(raw) if integral else value
	if kind == "money":
		catalog.money_keys.append(StringName(key))
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
		var is_housing: bool = "housing" in building.tags
		var schema: Dictionary = BUILDING_FIELDS.duplicate()
		schema["capacity" if is_housing else "recipe"] = "integer"
		var fields: Array[String] = []
		fields.assign(schema.keys())
		fields.append("tags")
		if not _object(raw[id], fields, path):
			continue
		var numeric: Dictionary = raw[id].duplicate()
		numeric.erase("tags")
		if not is_housing:
			building.recipe = _recipe(numeric["recipe"], path + ".recipe",
				"building.%s.recipe" % id, catalog)
			numeric.erase("recipe")
			schema.erase("recipe")
		_numbers(numeric, schema, path, "building.%s" % id, catalog)
		catalog.buildings[building.id] = building


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
	if not _object(raw, ["id", "width", "height", "river_cells", "cultivable_cells"], path):
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
	var occupied: Array[Vector2i] = []
	for field: String in ["river_cells", "cultivable_cells"]:
		if raw[field] is not Array:
			_errors.append("%s.%s: expected an array" % [path, field])
			continue
		for cell: Variant in raw[field]:
			var location: String = "%s.%s" % [path, field]
			if cell is not Array or cell.size() != 2:
				_errors.append("%s: expected [x, y]" % location)
				continue
			if not _number(cell[0], "integer", location + ".x", "x", dimensions) \
					or not _number(cell[1], "integer", location + ".y", "y", dimensions):
				continue
			var position: Vector2i = Vector2i(int(cell[0]), int(cell[1]))
			if position.x >= map.width or position.y >= map.height or position in occupied:
				_errors.append("%s: out of bounds or duplicate cell %s" % [location, position])
				continue
			occupied.append(position)
			var cells: Array[Vector2i] = map.river_cells if field == "river_cells" else map.cultivable_cells
			cells.append(position)
	catalog.maps[map.id] = map
