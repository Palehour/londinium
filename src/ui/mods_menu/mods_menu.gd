class_name ModsMenu
extends VBoxContainer

# Mods menu (D-065): the active mods in load order, buttons to move each one, and every value more than one
# of them sets with the mod that wins. Reordering is a request: the map view saves it and starts a new game.
signal order_changed(order: Array[StringName])

var _mods: Array[StringName] = []
var _conflicts: Array[Dictionary] = []
var _error: String = ""
var _folder: String = ""


# `folder` is where the player puts mods, shown when there are none so they know where to look.
func show_mods(mods: Array[StringName], conflicts: Array[Dictionary], folder: String) -> void:
	if mods == _mods and conflicts == _conflicts and folder == _folder:
		return
	_mods = mods.duplicate()
	_conflicts = conflicts.duplicate(true)
	_folder = folder
	_error = ""
	_rebuild()


# A new order that could not be applied; the game keeps running on the previous one.
func show_error(message: String) -> void:
	_error = message
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if _mods.is_empty():
		add_child(_label(Strings.text(Strings.MODS_NONE) % _folder))
		return
	add_child(_label(Strings.text(Strings.MODS_TITLE)))
	for index: int in range(_mods.size()):
		add_child(_mod_row(index))
	if not _conflicts.is_empty():
		add_child(_label(Strings.text(Strings.MODS_CONFLICTS)))
	for conflict: Dictionary in _conflicts:
		var setters: Array[String] = []
		setters.assign(conflict["mods"])
		add_child(_label(Strings.text(Strings.MODS_CONFLICT) % [conflict["key"], ", ".join(setters),
			conflict["winner"]]))
	if not _error.is_empty():
		add_child(_label(Strings.text(Strings.MODS_ERROR) % _error))


func _mod_row(index: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = _label("%d. %s" % [index + 1, _mods[index]])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var up: Button = _button(Strings.text(Strings.MODS_UP), _move.bind(index, -1))
	up.disabled = index == 0
	row.add_child(up)
	var down: Button = _button(Strings.text(Strings.MODS_DOWN), _move.bind(index, 1))
	down.disabled = index == _mods.size() - 1
	row.add_child(down)
	return row


func _move(index: int, offset: int) -> void:
	var order: Array[StringName] = _mods.duplicate()
	var moved: StringName = order[index]
	order[index] = order[index + offset]
	order[index + offset] = moved
	order_changed.emit(order)


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# Buttons never keep focus, so map shortcuts keep working after a click (same as the stats panel).
func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
