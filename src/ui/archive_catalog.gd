class_name ArchiveCatalog
extends RefCounted

# The Archive's cards (issue #64), one file each in data/eras/victorian/archive/. Read-only history with no effect on
# the game (D-096), so the simulation never loads them: the UI reads them here and only looks at the snapshot.

const FOLDER: String = "res://data/eras/victorian/archive"
const KINDS: Array[StringName] = [&"moment", &"character", &"finding"]
# Every image keeps its full credit and the licence of the scan (D-103). No image goes in without all of them.
const CREDIT_FIELDS: Array[String] = ["title", "author", "publication", "date", "held_at", "license", "url"]
# Closing a mission is any of its ends (D-099: met or not).
const CLOSED: Array[StringName] = [MissionSystem.COMPLETED, MissionSystem.FAILED, MissionSystem.ABANDONED]

var cards: Array[ArchiveCard] = []
var errors: Array[String] = []


func load_data() -> void:
	var documents: Dictionary[StringName, Variant] = {}
	var directory: DirAccess = DirAccess.open(FOLDER)
	if directory == null:
		errors.append("%s: missing folder" % FOLDER)
		return
	for file_name: String in directory.get_files():
		if file_name.get_extension() == "json":
			documents[StringName(file_name.get_basename())] = JSON.parse_string(
				FileAccess.get_file_as_string(FOLDER.path_join(file_name)))
	validate(documents)


func validate(documents: Dictionary) -> void:
	cards.clear()
	errors.clear()
	for id: StringName in documents:
		var card: ArchiveCard = _card(id, documents[id])
		if card != null:
			cards.append(card)
	cards.sort_custom(func(a: ArchiveCard, b: ArchiveCard) -> bool: return a.order < b.order)


# Kept apart from validate() so Strings can list the cards' keys without loading the economy data.
func check_missions(mission_ids: Array) -> void:
	for card: ArchiveCard in cards:
		if not mission_ids.has(card.unlock_mission):
			errors.append("%s.unlock.mission_closed: unknown mission %s" % [_path(card.id), card.unlock_mission])


# Reads economy.missions of a snapshot or a save; it never writes.
static func is_unlocked(card: ArchiveCard, economy: Dictionary) -> bool:
	var missions: Dictionary = economy.get("missions", {})
	var entry: Variant = missions.get(String(card.unlock_mission), missions.get(card.unlock_mission))
	return entry is Dictionary and StringName(entry.get("status", "")) in CLOSED


static func text_keys(card: ArchiveCard) -> Array[StringName]:
	var keys: Array[StringName] = []
	for field: StringName in Strings.ARCHIVE_CARD_FIELDS:
		keys.append(Strings.archive_key(card.id, field))
	if card.image_is_context:
		keys.append(Strings.archive_key(card.id, Strings.ARCHIVE_IMAGE_CONTEXT))
	return keys


func _card(id: StringName, raw: Variant) -> ArchiveCard:
	var path: String = _path(id)
	if raw is not Dictionary:
		errors.append("%s: expected an object" % path)
		return null
	var card: ArchiveCard = ArchiveCard.new()
	card.id = id
	card.order = int(raw.get("order", 0))
	card.kind = StringName(String(raw.get("kind", "")))
	if not KINDS.has(card.kind):
		errors.append("%s.kind: expected one of %s" % [path, KINDS])
		return null
	var unlock: Variant = raw.get("unlock")
	if unlock is not Dictionary or unlock.get("mission_closed") is not String or unlock["mission_closed"].is_empty():
		errors.append("%s.unlock.mission_closed: expected a mission id" % path)
		return null
	card.unlock_mission = StringName(unlock["mission_closed"])
	if raw.get("image") != null and not _image(raw["image"], card):
		return null
	return card


func _image(raw: Variant, card: ArchiveCard) -> bool:
	var path: String = _path(card.id) + ".image"
	if raw is not Dictionary:
		errors.append("%s: expected an object or null" % path)
		return false
	for field: String in CREDIT_FIELDS:
		var value: Variant = raw.get(field)
		if value is not String or value.strip_edges().is_empty():
			errors.append("%s.%s: every image needs its full credit (D-103)" % [path, field])
			return false
		card.image[field] = value
	if raw.get("context") is not bool:
		errors.append("%s.context: say whether it is a context image (D-103)" % path)
		return false
	card.image_is_context = raw["context"]
	var note: StringName = Strings.archive_key(card.id, Strings.ARCHIVE_IMAGE_CONTEXT)
	if card.image_is_context and _untranslated(note):
		errors.append("%s.context: a context image needs its note %s in locale/ui.csv (D-103)" % [path, note])
		return false
	return true


static func _untranslated(key: StringName) -> bool:
	var text: String = Strings.text(key)
	return text.strip_edges().is_empty() or text == String(key)


static func _path(id: StringName) -> String:
	return "%s/%s.json" % [FOLDER.trim_prefix("res://"), id]
