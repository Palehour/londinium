class_name ModLayer
extends RefCounted

# Mods (D-049, D-065): folders `<root>/<name>/data/` whose JSON files overlay the file with the same path in data/.
# They merge before validation, so a mod passes the same schemas and ParameterRanges as data/ itself.
const DEFAULT_ROOT: String = "user://mods"
const LOAD_ORDER_FILE: String = "load_order.json"
# Reading limits for files the player drops in, so a huge or absurdly nested one is an error, not a stall.
# data/ files are a few KB and five levels deep; these leave ample room for any real mod.
const MAX_FILE_BYTES: int = 65536
const MAX_DEPTH: int = 16

var errors: Array[String] = []
# Active mods in load order, for the save (#57) and the mods menu.
var mods: Array[StringName] = []
# {key, mods, winner} for every value more than one mod sets; the last one wins.
var conflicts: Array[Dictionary] = []
# Location of every value a mod set ("economy/startup.json.money") → the mods that set it, in order.
var _sources: Dictionary[String, Array] = {}
var _files: Dictionary[String, Array] = {}


# Merges every active mod into `documents` in place. An empty or missing root means no mods.
func apply(documents: Dictionary[String, Dictionary], root: String, era: String) -> void:
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return
	for mod_name: String in _load_order(root):
		mods.append(StringName(mod_name))
		_apply_mod(documents, root.path_join(mod_name).path_join("data"), mod_name, era)
	for location: String in _sources:
		var setters: Array = _sources[location]
		if setters.size() > 1:
			conflicts.append({"key": location, "mods": setters.duplicate(), "winner": setters.back()})


# Names the mod behind a validation error, so the player knows which folder to fix.
func blame(message: String) -> String:
	var best: String = ""
	for location: String in _sources:
		if location.length() > best.length() and (message.begins_with(location + ":")
				or message.begins_with(location + ".")):
			best = location
	if not best.is_empty():
		return "mod '%s': %s" % [_sources[best].back(), message]
	for path: String in _files:
		if message.begins_with(path):
			return "mod '%s': %s" % ["', '".join(_files[path]), message]
	return message


# Writes the order the mods menu chose (D-065: load_order.json is editable there).
static func save_load_order(root: String, order: Array[StringName]) -> Error:
	var file: FileAccess = FileAccess.open(root.path_join(LOAD_ORDER_FILE), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(order.map(func(mod_name: StringName) -> String: return String(mod_name))))
	file.close()
	return OK


# D-065: load_order.json sets the order; without it, alphabetical. A folder the list leaves out still loads,
# after the listed ones and alphabetically, because the decision orders mods but never switches one off.
func _load_order(root: String) -> Array[String]:
	var available: Array[String] = []
	available.assign(DirAccess.get_directories_at(root))
	available.sort()
	var list_path: String = root.path_join(LOAD_ORDER_FILE)
	if not FileAccess.file_exists(list_path):
		return available
	var order: Array[String] = []
	var raw: Variant = _read_json(list_path, "mods/" + LOAD_ORDER_FILE)
	if raw == null:
		return order
	if raw is not Array:
		errors.append("mods/%s: expected a list of mod names" % LOAD_ORDER_FILE)
		return order
	for entry: Variant in raw:
		if typeof(entry) != TYPE_STRING or entry not in available:
			errors.append("mods/%s: unknown mod '%s'" % [LOAD_ORDER_FILE, entry])
		elif entry in order:
			errors.append("mods/%s: mod '%s' is listed twice" % [LOAD_ORDER_FILE, entry])
		else:
			order.append(entry)
	for mod_name: String in available:
		if mod_name not in order:
			order.append(mod_name)
	return order


func _apply_mod(documents: Dictionary[String, Dictionary], data_dir: String, mod_name: String, era: String) -> void:
	if not DirAccess.dir_exists_absolute(data_dir):
		errors.append("mod '%s': missing data/ folder" % mod_name)
		return
	for path: String in _json_files(data_dir, ""):
		# Another era's files are not loaded this game, so a mod may carry them without error.
		if path.begins_with("eras/") and not path.begins_with("eras/%s/" % era):
			continue
		if not documents.has(path):
			errors.append("mod '%s': %s: no such file in data/" % [mod_name, path])
			continue
		var raw: Variant = _read_json(data_dir.path_join(path), "mod '%s': %s" % [mod_name, path])
		if raw == null:
			continue
		if raw is not Dictionary:
			errors.append("mod '%s': %s: expected an object" % [mod_name, path])
			continue
		_files.get_or_add(path, []).append(mod_name)
		_merge(documents[path], raw, path, mod_name)


# Objects merge field by field; numbers, switches and lists replace what was there.
func _merge(target: Dictionary, overlay: Dictionary, location: String, mod_name: String) -> void:
	for field: Variant in overlay:
		var at: String = "%s.%s" % [location, field]
		if overlay[field] is Dictionary and target.get(field) is Dictionary:
			_merge(target[field], overlay[field], at, mod_name)
			continue
		var value: Variant = overlay[field]
		target[field] = value.duplicate(true) if value is Dictionary or value is Array else value
		_sources.get_or_add(at, []).append(mod_name)


# Relative paths of every .json under `directory`, sorted so the merge order never depends on the file system.
func _json_files(directory: String, prefix: String) -> Array[String]:
	var found: Array[String] = []
	var files: PackedStringArray = DirAccess.get_files_at(directory)
	files.sort()
	for file_name: String in files:
		if file_name.ends_with(".json"):
			found.append(prefix.path_join(file_name))
	var folders: PackedStringArray = DirAccess.get_directories_at(directory)
	folders.sort()
	for folder: String in folders:
		found.append_array(_json_files(directory.path_join(folder), prefix.path_join(folder)))
	return found


func _read_json(path: String, label: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("%s: cannot read file" % label)
		return null
	if file.get_length() > MAX_FILE_BYTES:
		errors.append("%s: file larger than %d bytes" % [label, MAX_FILE_BYTES])
		return null
	var json: JSON = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		errors.append("%s:%d: %s" % [label, json.get_error_line(), json.get_error_message()])
		return null
	if json.data == null:
		errors.append("%s: expected JSON content, found null" % label)
		return null
	if _depth(json.data) > MAX_DEPTH:
		errors.append("%s: nested deeper than %d levels" % [label, MAX_DEPTH])
		return null
	return json.data


# Levels of objects and lists; stops counting once past the limit, so a deep file costs no more than a legal one.
func _depth(value: Variant, level: int = 0) -> int:
	if level > MAX_DEPTH or (value is not Dictionary and value is not Array):
		return level
	var deepest: int = level + 1
	for child: Variant in (value.values() if value is Dictionary else value):
		deepest = maxi(deepest, _depth(child, level + 1))
		if deepest > MAX_DEPTH:
			break
	return deepest
