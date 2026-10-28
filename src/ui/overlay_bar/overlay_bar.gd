class_name OverlayBar
extends HBoxContainer

# Picks the need layer of the map (issue #73, D-038): none, or one good some class needs. O and L3 go to the next
# one; the buttons never take the focus, so the gamepad keeps the map.

signal overlay_changed(good: StringName)

var selected: StringName = NeedOverlay.NONE
var _goods: Array[StringName] = []
var _caption: Label
var _buttons: Dictionary[StringName, Button] = {}


func setup(goods: Array[StringName]) -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for child: Node in get_children():
		child.free()
	_buttons.clear()
	_goods = goods.duplicate()
	if selected not in _goods:
		selected = NeedOverlay.NONE
	_caption = Label.new()
	add_child(_caption)
	var group: ButtonGroup = ButtonGroup.new()
	group.allow_unpress = false
	var options: Array[StringName] = [NeedOverlay.NONE]
	options.append_array(_goods)
	for good: StringName in options:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select.bind(good))
		_buttons[good] = button
		add_child(button)
	refresh_labels()


func refresh_labels() -> void:
	_caption.text = Strings.text(Strings.OVERLAY_CAPTION)
	for good: StringName in _buttons:
		_buttons[good].text = Strings.text(Strings.OVERLAY_NONE) if good == NeedOverlay.NONE \
			else Strings.label(Strings.GOOD_LABELS, good)
		_buttons[good].set_pressed_no_signal(good == selected)


func select(good: StringName) -> void:
	if good != NeedOverlay.NONE and good not in _goods:
		return
	selected = good
	for option: StringName in _buttons:
		_buttons[option].set_pressed_no_signal(option == good)
	overlay_changed.emit(good)


func cycle() -> void:
	select(NeedOverlay.next(_goods, selected))
