class_name SaveFile
extends RefCounted

# Saved games (issue #57, D-037). A file is one Variant written with store_var and compressed with ZSTD, never with
# objects: an envelope with the format and its version, what the game ran on (scenario, difficulty, knobs, mods) and
# Simulation.to_save(). The statistics history keeps its packed arrays as they are.

const FORMAT: String = "londinium-save"
const VERSION: int = 2
# Format 1 was played on cells of 50 m, before issue #186 (D-086). It still loads, converted (D-087).
const CELLS_OF_50_M_VERSION: int = 1
const CELLS_OF_50_M: int = 50
const BUILDING_CAUSE: String = "building"
const DEFAULT_ROOT: String = "user://saves"
const EXTENSION: String = ".sav"
const KIND_MANUAL: StringName = &"manual"
const KIND_AUTOSAVE: StringName = &"autosave"
const KIND_STAGE: StringName = &"stage"
# Why a file does not load; Strings.save_refusal turns each one into the player's words.
const INVALID_FILE: StringName = &"invalid_file"
const OTHER_VERSION: StringName = &"other_version"
const OTHER_MODS: StringName = &"other_mods"
const SIMULATION_INTS: Array[String] = ["tick_count", "seed", "rng_state", "barley_rng_state"]
const ENVELOPE_NAMES: Array[String] = ["scenario", "difficulty"]
# Economy fields a save from before them may lack: the streets of issue #67 (D-080) load as none.
const OPTIONAL_ECONOMY_FIELDS: Array[String] = ["player_roads", "transport_fraction"]


static func build(session: GameSession) -> Dictionary:
	var mods: Array = []
	mods.assign(session.mods)
	return {"format": FORMAT, "version": VERSION, "saved_at": Time.get_datetime_string_from_system(false, true),
		"scenario": session.scenario_id(), "difficulty": session.difficulty, "knobs": {}, "mods": mods,
		"simulation": session.simulation.to_save()}


# Written beside the target first and then moved over it, so a failed write never leaves half a save behind.
static func write(path: String, data: Dictionary) -> Error:
	var made: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	var partial: String = path + ".tmp"
	var file: FileAccess = FileAccess.open_compressed(partial, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(data)
	file.close()
	return DirAccess.rename_absolute(partial, path)


# {"reason": &"" when it loads or one of the refusals, "args": for its message, "data": the save}.
static func read(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return _refusal(INVALID_FILE)
	var raw: Variant = file.get_var(false)
	file.close()
	return validate(raw)


static func validate(raw: Variant) -> Dictionary:
	if raw is not Dictionary or raw.get("format") != FORMAT or typeof(raw.get("version")) != TYPE_INT:
		return _refusal(INVALID_FILE)
	if raw["version"] not in [VERSION, CELLS_OF_50_M_VERSION]:
		return _refusal(OTHER_VERSION, [raw["version"], VERSION])
	for field: String in ENVELOPE_NAMES:
		if typeof(raw.get(field)) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _refusal(INVALID_FILE)
	if raw.get("mods") is not Array or raw.get("knobs") is not Dictionary \
			or not _valid_simulation(raw.get("simulation")):
		return _refusal(INVALID_FILE)
	for mod: Variant in raw["mods"]:
		if typeof(mod) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _refusal(INVALID_FILE)
	return {"reason": &"", "args": [], "data": raw}


# A valid save still needs the game it was played on: same scenario, a difficulty this data has, same mods in the
# same order (a mod changes the numbers, so another set would not play the saved game).
static func check_compatible(data: Dictionary, session: GameSession, catalog: DataCatalog) -> Dictionary:
	if StringName(data["scenario"]) != session.scenario_id() \
			or not catalog.difficulties.has(StringName(data["difficulty"])):
		return _refusal(INVALID_FILE)
	var mods: Array[StringName] = []
	for mod: Variant in data["mods"]:
		mods.append(StringName(mod))
	if mods != session.mods:
		return _refusal(OTHER_MODS, [mods])
	return {"reason": &"", "args": [], "data": data}


# A save in this format: one of format 1 converted to cells of `cell_size_m` (D-087). Every old cell (x, y) becomes its
# block from (x, y) times the scale, so the buildings, the player's streets and the buildings the causes of the
# statistics name stand where they stood. The rest of the game is the same.
static func upgraded(data: Dictionary, cell_size_m: int) -> Dictionary:
	if data["version"] == VERSION:
		return data
	var scale: int = CELLS_OF_50_M / cell_size_m
	var copy: Dictionary = data.duplicate(true)
	var economy: Dictionary = copy["simulation"]["economy"]
	for field: String in ["buildings", "player_roads"]:
		for entry: Dictionary in economy.get(field, []):
			entry["cell"] = [int(entry["cell"][0]) * scale, int(entry["cell"][1]) * scale]
	var causes: Variant = copy["simulation"].get("stats_history", {}).get("causes")
	if causes is Dictionary:
		_scale_causes(causes, scale)
	copy["version"] = VERSION
	return copy


# A building's cause is kept under "<id>@<x>,<y>" (StatsHistory), as the subject of an event and in the keys
# "building|<subject>" of the causes still being followed.
static func _scale_causes(causes: Dictionary, scale: int) -> void:
	var kinds: Variant = causes.get("kinds")
	var subjects: Variant = causes.get("subjects")
	if kinds is PackedStringArray and subjects is PackedStringArray and kinds.size() == subjects.size():
		for index: int in kinds.size():
			if kinds[index] == BUILDING_CAUSE:
				subjects[index] = _scaled_subject(subjects[index], scale)
		causes["subjects"] = subjects
	var prefix: String = BUILDING_CAUSE + CauseLog.SEPARATOR
	for field: String in ["current_keys", "pending_keys", "flicker_keys"]:
		var keys: Variant = causes.get(field)
		if keys is not PackedStringArray:
			continue
		for index: int in keys.size():
			if keys[index].begins_with(prefix):
				keys[index] = prefix + _scaled_subject(keys[index].trim_prefix(prefix), scale)
		causes[field] = keys


static func _scaled_subject(subject: String, scale: int) -> String:
	var cell: PackedStringArray = subject.get_slice("@", 1).split(",")
	if not subject.contains("@") or cell.size() != 2:
		return subject
	return "%s@%d,%d" % [subject.get_slice("@", 0), cell[0].to_int() * scale, cell[1].to_int() * scale]


static func write_manual(root: String, data: Dictionary) -> String:
	var stem: String = "%s_%d" % [KIND_MANUAL, int(Time.get_unix_time_from_system())]
	var path: String = root.path_join(stem + EXTENSION)
	var copy: int = 1
	while FileAccess.file_exists(path):
		copy += 1
		path = root.path_join("%s_%d%s" % [stem, copy, EXTENSION])
	return path if write(path, data) == OK else ""


static func autosave_path(root: String, slot: int) -> String:
	return root.path_join("%s_%d%s" % [KIND_AUTOSAVE, slot, EXTENSION])


static func stage_path(root: String, stage_id: StringName) -> String:
	return root.path_join("%s_%s%s" % [KIND_STAGE, stage_id, EXTENSION])


# Every save in the folder, newest first: {path, kind, slot (autosaves), tick (-1 if unreadable), saved_at}.
static func list(root: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(root):
		return found
	for file_name: String in DirAccess.get_files_at(root):
		if file_name.ends_with(EXTENSION):
			found.append(_entry(root.path_join(file_name)))
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["modified"] > b["modified"] or (a["modified"] == b["modified"] and a["path"] < b["path"]))
	return found


static func _entry(path: String) -> Dictionary:
	var stem: String = path.get_file().get_basename()
	var kind: StringName = KIND_MANUAL
	for candidate: StringName in [KIND_AUTOSAVE, KIND_STAGE]:
		if stem.begins_with(String(candidate) + "_"):
			kind = candidate
	var read_back: Dictionary = read(path)
	var entry: Dictionary = {"path": path, "kind": kind, "modified": FileAccess.get_modified_time(path),
		"slot": stem.get_slice("_", 1).to_int(), "tick": -1, "saved_at": ""}
	if read_back["reason"] == &"":
		entry["tick"] = int(read_back["data"]["simulation"]["tick_count"])
		entry["saved_at"] = str(read_back["data"].get("saved_at", ""))
	return entry


# The economy must have every field a new state has, with the same kind of value, so EconomyState.from_dict can
# read it; the history and the stats window may be missing.
static func _valid_simulation(simulation: Variant) -> bool:
	if simulation is not Dictionary or simulation.get("economy") is not Dictionary:
		return false
	for field: String in SIMULATION_INTS:
		if typeof(simulation.get(field)) != TYPE_INT:
			return false
	if simulation.get("stats_window", []) is not Array or simulation.get("stats_history", {}) is not Dictionary:
		return false
	var economy: Dictionary = simulation["economy"]
	var expected: Dictionary = EconomyState.new().to_dict()
	for field: String in expected:
		if field in OPTIONAL_ECONOMY_FIELDS and not economy.has(field):
			continue
		if not economy.has(field) or not _same_kind(economy[field], expected[field]):
			return false
	return true


static func _same_kind(value: Variant, expected: Variant) -> bool:
	var numbers: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if typeof(expected) in numbers:
		return typeof(value) in numbers
	return typeof(value) == typeof(expected)


static func _refusal(reason: StringName, args: Array = []) -> Dictionary:
	return {"reason": reason, "args": args, "data": {}}
