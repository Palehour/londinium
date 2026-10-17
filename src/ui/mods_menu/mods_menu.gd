class_name ModsMenu
extends VBoxContainer

# Mods menu (D-065): the active mods in load order, buttons to move each one, and every value more than one
# of them sets with the mod that wins. Reordering is a request: the map view saves it and starts a new game.
signal order_changed(order: Array[StringName])

var _mods: Array[StringName] = []
var _conflicts: Array[Dictionary] = []
var _error: String = ""
var _folder: String = ""
# On while the player is in the panel with a gamepad (issue #68); then its buttons take the focus.
var focusable: bool = false:
	set(value):
		focusable = value
		for node: Node in find_children("*", "Button", true, false):
			(node as Control).focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE


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
	# Deferred: the tree refuses new children while it is still sending this notification.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_rebuild.call_deferred()


func _rebuild() -> void:
	var focused: int = _focused_button()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build()
	_restore_focus(focused)


# Which button has the focus, so a rebuild (an autosave, a save, a load, a new order) can give it back to the one in
# the same place and a gamepad player is never left without focus.
func _focused_button() -> int:
	var focus_owner: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return find_children("*", "Button", true, false).find(focus_owner) if focus_owner != null else -1


func _restore_focus(index: int) -> void:
	var buttons: Array[Node] = find_children("*", "Button", true, false)
	if index >= 0 and not buttons.is_empty():
		(buttons[mini(index, buttons.size() - 1)] as Control).grab_focus()


func _build() -> void:
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


# Buttons never keep focus after a click, so map shortcuts keep working (same as the stats panel); a gamepad in the
# panel turns it on.
func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
