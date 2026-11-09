class_name DefeatCriticalSound
extends RefCounted

# The sound of the critical banner (issue #350): once per entry of each condition, rearmed when it leaves.
# The id comes from the parameter ui.defeat.critical_sound, which has no value yet ("sin dato"): until it has one,
# the status says why nothing plays and the banner shows that line. No sound is chosen or made up here.

const STATUS_OK: StringName = &"ok"
const STATUS_NO_DATA: StringName = &"no_data"
const STATUS_INVALID_ID: StringName = &"invalid_id"
const STATUS_MISSING_ASSET: StringName = &"missing_asset"
# Where an id is looked up: res://assets/audio/ui/<id>.<extension>.
const SOUND_FOLDER: String = "res://assets/audio/ui/"
const EXTENSIONS: Array[String] = ["ogg", "wav"]
const NO_DATA_WORDS: Array[String] = ["", "sin dato"]

var status: StringName = STATUS_NO_DATA
var stream: AudioStream
var _active: Dictionary[StringName, bool] = {}
var _id_pattern: RegEx = RegEx.create_from_string("^[a-z0-9_-]+$")


# `sound_id` is the raw parameter value. `loader` takes a path and returns a Resource or null; tests inject their own.
func configure(sound_id: Variant, loader: Callable = Callable()) -> void:
	stream = null
	if sound_id == null or (sound_id is String or sound_id is StringName) and NO_DATA_WORDS.has(String(sound_id).strip_edges().to_lower()):
		status = STATUS_NO_DATA
		return
	if sound_id is not String and sound_id is not StringName or not _id_pattern.search(String(sound_id)):
		status = STATUS_INVALID_ID
		return
	for extension: String in EXTENSIONS:
		var path: String = "%s%s.%s" % [SOUND_FOLDER, sound_id, extension]
		var loaded: Variant = _load(path, loader)
		if loaded is AudioStream:
			stream = loaded
			status = STATUS_OK
			return
	status = STATUS_MISSING_ASSET


func is_ready() -> bool:
	return status == STATUS_OK


# The conditions that were not critical on the last call and are now. Calling it again with the same list returns
# nothing, so a pause, a language change or a repeated snapshot never repeats the sound.
func entered(critical: Array[StringName]) -> Array[StringName]:
	var fresh: Array[StringName] = []
	for condition: StringName in critical:
		if not _active.has(condition):
			fresh.append(condition)
	_active.clear()
	for condition: StringName in critical:
		_active[condition] = true
	return fresh


# A new game, a loaded one or a new difficulty: the next critical entry sounds again.
func reset() -> void:
	_active.clear()


func _load(path: String, loader: Callable) -> Variant:
	if loader.is_valid():
		return loader.call(path)
	if not ResourceLoader.exists(path):
		return null
	return load(path)
