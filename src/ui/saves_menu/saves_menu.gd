class_name SavesMenu
extends VBoxContainer

# Saved games (issue #57): a button to save now, every save in the folder newest first with a button to load it,
# and the outcome of the last save or load. Both are requests: the map view writes and reads the files.
signal save_requested
signal load_requested(path: String)

var _entries: Array[Dictionary] = []
var _message: String = ""


func show_saves(entries: Array[Dictionary], message: String = "") -> void:
	_entries = entries.duplicate(true)
	_message = message
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
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


# Buttons never keep focus, so map shortcuts keep working after a click (same as the stats panel).
func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
