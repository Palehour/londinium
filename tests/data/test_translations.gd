extends GutTest

# OptimizedTranslation does not list its messages, and the fallback locale would hide a missing
# English line, so completeness is read from the CSV itself.


func after_each() -> void:
	Strings.use_default_locale()


func test_victory_and_streak_explanations_are_translated_in_both_languages() -> void:
	var spanish: String = ""
	for locale: String in ["es", "en"]:
		TranslationServer.set_locale(locale)
		var message: String = Strings.text(Strings.VICTORY_MESSAGE)
		assert_false(message.is_empty())
		assert_ne(message, String(Strings.VICTORY_MESSAGE))
		var cut: String = Strings.text(Strings.VICTORY_WHY) % [7, Strings.money(249), Strings.money(250)]
		assert_string_contains(cut, "7")
		assert_string_contains(cut, Strings.money(249))
		assert_string_contains(cut, Strings.money(250))
		if locale == "es":
			spanish = message
		else:
			assert_ne(message, spanish)


func test_every_key_has_spanish_and_english() -> void:
	var file: FileAccess = FileAccess.open("res://locale/ui.csv", FileAccess.READ)
	assert_not_null(file, "locale/ui.csv must open")
	if file == null:
		return
	var header: PackedStringArray = file.get_csv_line()
	assert_eq(header[0], "keys")
	assert_eq(header[1], "es")
	assert_eq(header[2], "en")
	var csv_keys: Array[StringName] = []
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty() or (row.size() == 1 and row[0].is_empty()):
			continue
		assert_eq(row.size(), 3, str(row))
		assert_false(row[0].is_empty(), "a key is empty")
		assert_false(row[1].is_empty(), row[0] + " has no Spanish")
		assert_false(row[2].is_empty(), row[0] + " has no English")
		var key: StringName = StringName(row[0])
		assert_false(csv_keys.has(key), "duplicate key " + row[0])
		csv_keys.append(key)
	file.close()
	var code_keys: Array[StringName] = Strings.all_keys()
	assert_eq(csv_keys.size(), code_keys.size(), "csv has %d keys and Strings.all_keys has %d" % [csv_keys.size(), code_keys.size()])
	for key: StringName in code_keys:
		assert_true(csv_keys.has(key), "missing from csv: " + String(key))
	for key: StringName in csv_keys:
		assert_true(code_keys.has(key), "missing from Strings.all_keys: " + String(key))


func test_translation_server_serves_both_locales() -> void:
	TranslationServer.set_locale("es")
	assert_eq(Strings.building_label("mill"), "Molino")
	var spanish_title: String = Strings.text(Strings.PANEL_TITLE)
	TranslationServer.set_locale("en")
	assert_eq(Strings.building_label("mill"), "Mill")
	assert_ne(Strings.text(Strings.PANEL_TITLE), spanish_title)
