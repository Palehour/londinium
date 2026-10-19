class_name SavesMenu
extends VBoxContainer

# Saved games (issue #57): a button to save now, every save in the folder newest first with a button to load it,
# and the outcome of the last save or load. Both are requests: the map view writes and reads the files.
signal save_requested
signal load_requested(path: String)

var _entries: Array[Dictionary] = []
var _message: String = ""
# On while the player is in the panel with a gamepad (issue #68); then its buttons take the focus.
var focusable: bool = false:
	set(value):
		focusable = value
		for node: Node in find_children("*", "Button", true, false):
			(node as Control).focus_mode = Control.FOCUS_ALL if value else Control.FOCUS_NONE


func show_saves(entries: Array[Dictionary], message: String = "") -> void:
	_entries = entries.duplicate(true)
	_message = message
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
	add_child(_button(Strings.text(Strings.SAVE_GAME), func() -> void: save_requested.emit()))
	if not _message.is_empty():
		add_child(_label(_message))
	add_child(_label(Strings.text(Strings.SAVES_TITLE if not _entries.is_empty() else Strings.SAVES_NONE)))
	for entry: Dictionary in _entries:
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = _label(Strings.save_entry(entry))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_button(Strings.text(Strings.LOAD_GAME), func() -> void: load_requested.emit(entry["path"])))
		add_child(row)


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
