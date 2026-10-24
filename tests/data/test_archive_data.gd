extends GutTest

# The Archive (issue #64): read-only historic cards in data/eras/victorian/archive/. Each image carries its full credit
# and licence (D-103); one that is only "de contexto" says why in both languages (D-100, D-103).

const MISSIONS: Array[StringName] = [&"oldford"]


func after_each() -> void:
	Strings.use_default_locale()


func _catalog() -> ArchiveCatalog:
	var catalog: ArchiveCatalog = ArchiveCatalog.new()
	catalog.load_data()
	catalog.check_missions(MISSIONS)
	return catalog


func _image() -> Dictionary:
	return {"title": "A print", "author": "An engraver", "publication": "A paper", "date": "1859",
		"held_at": "A library", "license": "Public domain", "url": "https://example.org/print", "context": false}


func _card(image: Variant) -> Dictionary:
	return {"order": 1, "kind": "moment", "unlock": {"mission_closed": "oldford"}, "image": image}


func _errors(id: StringName, raw: Dictionary) -> Array[String]:
	var catalog: ArchiveCatalog = ArchiveCatalog.new()
	catalog.validate({id: raw})
	catalog.check_missions(MISSIONS)
	return catalog.errors


func test_the_four_cards_load_in_order() -> void:
	var catalog: ArchiveCatalog = _catalog()
	assert_true(catalog.errors.is_empty(), str(catalog.errors))
	var ids: Array[StringName] = []
	for card: ArchiveCard in catalog.cards:
		ids.append(card.id)
	assert_eq(ids, [&"stink", &"bazalgette", &"oldford", &"inquiry"] as Array[StringName])
	assert_eq(catalog.cards[0].kind, &"moment")
	assert_eq(catalog.cards[1].kind, &"character")
	assert_eq(catalog.cards[2].kind, &"finding")
	assert_eq(catalog.cards[3].kind, &"moment")


# D-097 and D-099: all four open together when the Old Ford mission closes.
func test_every_card_opens_with_the_old_ford_mission() -> void:
	for card: ArchiveCard in _catalog().cards:
		assert_eq(card.unlock_mission, &"oldford", String(card.id))


# Only the images Chronicler listed with every credit field (PR #229): INQUIRY stays out while its credit is
# [A VERIFICAR]; STINK and BAZALGETTE until the doc says where the original is kept (Cristian, 2026-10-24).
func test_only_old_ford_has_an_image_and_it_is_context() -> void:
	for card: ArchiveCard in _catalog().cards:
		assert_eq(not card.image.is_empty(), card.id == &"oldford", String(card.id))
		assert_eq(card.image_is_context, card.id == &"oldford", String(card.id))


func test_every_image_has_its_full_credit_and_licence() -> void:
	for card: ArchiveCard in _catalog().cards:
		for field: String in ArchiveCatalog.CREDIT_FIELDS:
			if not card.image.is_empty():
				assert_false(String(card.image.get(field, "")).strip_edges().is_empty(), "%s %s" % [card.id, field])


func test_an_image_missing_any_credit_field_is_an_error() -> void:
	assert_eq(_errors(&"probe", _card(_image())), [] as Array[String])
	for field: String in ArchiveCatalog.CREDIT_FIELDS:
		var missing: Dictionary = _image()
		missing.erase(field)
		assert_eq(_errors(&"probe", _card(missing)).size(), 1, field + " missing")
		var blank: Dictionary = _image()
		blank[field] = " "
		assert_eq(_errors(&"probe", _card(blank)).size(), 1, field + " blank")


func test_a_context_image_without_its_note_is_an_error() -> void:
	var context: Dictionary = _image()
	context["context"] = true
	var errors: Array[String] = _errors(&"probe", _card(context))
	assert_eq(errors.size(), 1)
	if not errors.is_empty():
		assert_string_contains(errors[0], "archive.probe.image_context")
	var unsaid: Dictionary = _image()
	unsaid.erase("context")
	assert_eq(_errors(&"probe", _card(unsaid)).size(), 1, "context must be said, true or false")


func test_every_context_image_explains_itself_in_both_languages() -> void:
	for locale: String in ["es", "en"]:
		Strings.set_locale(locale)
		var catalog: ArchiveCatalog = _catalog()
		assert_true(catalog.errors.is_empty(), "%s: %s" % [locale, catalog.errors])
		for card: ArchiveCard in catalog.cards:
			if card.image_is_context:
				var note: String = Strings.text(Strings.archive_key(card.id, Strings.ARCHIVE_IMAGE_CONTEXT))
				assert_false(note.strip_edges().is_empty(), "%s %s" % [locale, card.id])


func test_unknown_kind_or_mission_is_an_error() -> void:
	var raw: Dictionary = _card(null)
	raw["kind"] = "bonus"
	assert_eq(_errors(&"probe", raw).size(), 1)
	raw = _card(null)
	raw["unlock"] = {"mission_closed": "nowhere"}
	assert_eq(_errors(&"probe", raw).size(), 1)
	raw = _card(null)
	raw.erase("unlock")
	assert_eq(_errors(&"probe", raw).size(), 1)


func test_every_card_text_is_in_the_csv() -> void:
	var keys: Array[StringName] = Strings.all_keys()
	for card: ArchiveCard in _catalog().cards:
		for key: StringName in ArchiveCatalog.text_keys(card):
			assert_true(keys.has(key), String(key))
