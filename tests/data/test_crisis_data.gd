extends GutTest

# Issue #222 (D-105 to D-107): each crisis has its response, quarantine and exposure in economy/crisis.json, the
# quarantine within the post's radius is the shorter one, and Chronicler's texts wait as placeholders in the era.

const CRISIS: String = "economy/crisis.json"
const TEXTS: String = "eras/victorian/crisis.json"

var _documents: Dictionary[String, Dictionary] = {}


func before_each() -> void:
	_documents.clear()
	for folder: String in ["economy", "roles", "maps", "eras/victorian", "services"]:
		for name: String in DirAccess.open("res://data/" + folder).get_files():
			if name.ends_with(".json"):
				var path: String = folder.path_join(name)
				_documents[path] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + path))


func _assert_invalid(message: String) -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_false(loaded.is_ok())
	assert_has(loaded.errors, message)


func test_the_real_data_loads_with_the_health_texts() -> void:
	var loaded: DataLoadResult = DataLoader.new().load_documents(_documents)
	assert_true(loaded.is_ok(), str(loaded.errors))
	var texts: Dictionary = loaded.catalog.crisis_texts[CrisisSystem.HEALTH]
	assert_false(String(texts["tooltip"]).is_empty())
	assert_eq(int(texts["card"]["year"]), 1866)


# Cristian (#222): the provisional text speaks of disinfecting, not of whitewashing.
func test_the_provisional_texts_say_disinfect_and_not_whitewash() -> void:
	var raw: String = JSON.stringify(_documents[TEXTS]).to_lower()
	assert_string_contains(raw, "desinfect")
	assert_false(raw.contains("encal"), raw)


func test_a_quarantine_by_the_post_as_long_as_the_full_one_is_rejected() -> void:
	_documents[CRISIS]["health"]["quarantine_post_min"] = _documents[CRISIS]["health"]["quarantine_min"]
	_assert_invalid("%s: crisis.health.quarantine_post_min must be < crisis.health.quarantine_min" % CRISIS)


func test_the_exposure_shape_is_a_switch() -> void:
	_documents[CRISIS]["health"]["exposure_diamond"] = "square"
	_assert_invalid("%s.health.exposure_diamond: expected a boolean" % CRISIS)


func test_texts_for_an_unknown_crisis_are_rejected() -> void:
	_documents[TEXTS]["fire"] = _documents[TEXTS]["health"].duplicate(true)
	_assert_invalid("%s.fire: unknown crisis" % TEXTS)


func test_a_card_without_sources_is_rejected() -> void:
	_documents[TEXTS]["health"]["card"]["sources"] = []
	_assert_invalid("%s.health: expected a tooltip and a card with a year, a title, a text and sources" % TEXTS)
