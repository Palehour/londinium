class_name DifficultyMenu
extends ConfirmationDialog

signal configuration_selected(configuration: Dictionary)

var configuration: Dictionary = {}
var _preset: OptionButton
var _knobs: Dictionary[String, Control] = {}
var _overrides: Dictionary[String, CheckBox] = {}
var _mods: ItemList
var _details: Label
var _definitions: Dictionary


func _ready() -> void:
	title = Strings.text(&"ui.difficulty")
	get_ok_button().text = Strings.text(&"ui.difficulty_start")
	get_cancel_button().text = Strings.text(&"ui.difficulty_cancel")
	var body: VBoxContainer = VBoxContainer.new()
	add_child(body)
	_preset = OptionButton.new()
	for id: String in ["normal", "easy", "hard"]:
		_preset.add_item(Strings.text(StringName("ui.difficulty_" + id)))
	_preset.select(["normal", "easy", "hard"].find(configuration.get("preset", "normal")))
	body.add_child(_preset)
	_definitions = DataLayers.new().read_object("res://data/difficulty/knobs.json")
	for name: String in _definitions:
		var row: HBoxContainer = HBoxContainer.new()
		body.add_child(row)
		var override: CheckBox = CheckBox.new()
		override.text = Strings.text(StringName("ui.knob_" + name))
		override.button_pressed = configuration.get("knobs", {}).has(name)
		_overrides[name] = override
		row.add_child(override)
		var definition: Dictionary = _definitions[name]
		var control: Control
		if definition.get("boolean", false):
			var toggle: CheckBox = CheckBox.new()
			toggle.button_pressed = configuration.get("knobs", {}).get(name, true)
			control = toggle
		else:
			var spin: SpinBox = SpinBox.new()
			spin.min_value = definition["min"]
			spin.max_value = definition["max"]
			spin.step = definition["step"]
			spin.value = configuration.get("knobs", {}).get(name, definition["min"])
			control = spin
		control.mouse_filter = Control.MOUSE_FILTER_STOP
		_knobs[name] = control
		row.add_child(control)
	var caption: Label = Label.new()
	caption.text = Strings.text(&"ui.mods_order")
	body.add_child(caption)
	_mods = ItemList.new()
	_mods.custom_minimum_size = Vector2(460, 110)
	body.add_child(_mods)
	var layers: DataLayers = DataLayers.new()
	var order: Array[String] = layers.mod_order()
	var active: Array = configuration.get("mods", order).duplicate()
	var directory: DirAccess = DirAccess.open("user://mods")
	if directory != null:
		var installed: PackedStringArray = directory.get_directories()
		installed.sort()
		for name: String in installed:
			if not order.has(name):
				order.append(name)
	for name: String in order:
		var index: int = _mods.add_item("")
		_mods.set_item_metadata(index, {"name": name, "enabled": name in active})
		_refresh_mod(index)
	var buttons: HBoxContainer = HBoxContainer.new()
	body.add_child(buttons)
	for direction: int in [-1, 1]:
		var button: Button = Button.new()
		button.text = Strings.text(&"ui.mods_up" if direction < 0 else &"ui.mods_down")
		button.pressed.connect(_move.bind(direction))
		buttons.add_child(button)
	var toggle: Button = Button.new()
	toggle.text = Strings.text(&"ui.mods_toggle")
	toggle.pressed.connect(func() -> void:
		var selected: PackedInt32Array = _mods.get_selected_items()
		if not selected.is_empty():
			var item: Dictionary = _mods.get_item_metadata(selected[0])
			item["enabled"] = not item["enabled"]
			_refresh_mod(selected[0]))
	buttons.add_child(toggle)
	var preview: Button = Button.new()
	preview.text = Strings.text(&"ui.difficulty_validate")
	preview.pressed.connect(_preview)
	buttons.add_child(preview)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(460, 100)
	body.add_child(_details)
	confirmed.connect(_apply)
	# Validation errors stay visible; confirming only closes after a successful load.
	dialog_hide_on_ok = false
	_details.text = "\n".join(layers.errors)


func _move(direction: int) -> void:
	var selected: PackedInt32Array = _mods.get_selected_items()
	if selected.is_empty():
		return
	var index: int = selected[0]
	var target: int = index + direction
	if target < 0 or target >= _mods.item_count:
		return
	_mods.move_item(index, target)
	_mods.select(target)


func selection() -> Dictionary:
	var knobs: Dictionary = {}
	for name: String in _knobs:
		if not _overrides[name].button_pressed:
			continue
		var control: Control = _knobs[name]
		knobs[name] = (control as CheckBox).button_pressed if control is CheckBox else (control as SpinBox).value
	var mods: Array[String] = []
	for index: int in range(_mods.item_count):
		var item: Dictionary = _mods.get_item_metadata(index)
		if item["enabled"]:
			mods.append(item["name"])
	return {"preset": ["normal", "easy", "hard"][_preset.selected], "knobs": knobs, "mods": mods}


func _preview() -> DataLoadResult:
	var loaded: DataLoadResult = DataLoader.new().load_all("res://data", "victorian", selection())
	var lines: Array[String] = []
	if not loaded.is_ok():
		lines.append(Strings.text(&"ui.load_error") + "\n" + "\n".join(loaded.errors))
	else:
		lines.append(Strings.text(&"ui.difficulty_valid"))
		var params: Params = Params.new(loaded.catalog, loaded.catalog.roles[&"neutral_administrator"])
		lines.append(Strings.text(&"ui.difficulty_values") % [params.get_value(&"startup.money"), params.get_value(&"defeat.hunger.duration_seconds"), params.get_value(&"market.wheat.max_price")])
	for conflict: Dictionary in loaded.conflicts:
		lines.append(Strings.text(&"ui.mods_conflict") % [conflict["key"], conflict["previous"], conflict["winner"]])
	_details.text = "\n".join(lines)
	return loaded


func _apply() -> void:
	if not _preview().is_ok():
		return
	var selected: Dictionary = selection()
	DirAccess.make_dir_recursive_absolute("user://mods")
	var file: FileAccess = FileAccess.open("user://mods/load_order.json", FileAccess.WRITE)
	if file == null:
		_details.text = Strings.text(&"ui.mods_save_error")
		return
	file.store_string(JSON.stringify(selected["mods"]))
	file.close()
	hide()
	configuration_selected.emit(selected)


func _refresh_mod(index: int) -> void:
	var item: Dictionary = _mods.get_item_metadata(index)
	_mods.set_item_text(index, Strings.text(&"ui.mods_active" if item["enabled"] else &"ui.mods_inactive") % item["name"])
