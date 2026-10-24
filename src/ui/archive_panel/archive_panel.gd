class_name ArchivePanel
extends PanelContainer

# The Archive (issue #64): a panel inside the game, opened from the side panel's button (D-110). It lists the historic
# cards; a locked one shows only its kind, so nothing is told before its event has passed (D-097). It only reads the
# snapshot and sends no command: the cards have no effect on the game (D-096).

var _catalog: ArchiveCatalog
var _unlocked: Array[StringName] = []
var _list: VBoxContainer


func setup(catalog: ArchiveCatalog) -> void:
	_catalog = catalog
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# Like the side panel: clicks and the wheel over it never reach the map.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	var header: HBoxContainer = HBoxContainer.new()
	root.add_child(header)
	var title: Label = _label(Strings.text(Strings.ARCHIVE_TITLE))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close: Button = Button.new()
	close.text = Strings.text(Strings.ARCHIVE_CLOSE)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	header.add_child(close)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_build_cards()


func apply_style(background: Color, margin: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.set_content_margin_all(margin)
	add_theme_stylebox_override("panel", style)


func update_snapshot(snapshot: Dictionary) -> void:
	var unlocked: Array[StringName] = []
	for card: ArchiveCard in _catalog.cards:
		if ArchiveCatalog.is_unlocked(card, snapshot.get("economy", {})):
			unlocked.append(card.id)
	if unlocked == _unlocked:
		return
	_unlocked = unlocked
	_build_cards()


func _notification(what: int) -> void:
	# Deferred: the tree refuses new children while it is still sending this notification.
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and _list != null:
		_rebuild.call_deferred()


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	setup(_catalog)


func _build_cards() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for card: ArchiveCard in _catalog.cards:
		_list.add_child(HSeparator.new())
		_list.add_child(_label(Strings.text(Strings.ARCHIVE_KIND_LABELS[card.kind])))
		if not _unlocked.has(card.id):
			_list.add_child(_label(Strings.text(Strings.ARCHIVE_LOCKED)))
			continue
		_list.add_child(_label(Strings.text(Strings.archive_key(card.id, Strings.ARCHIVE_TITLE_FIELD))))
		_list.add_child(_label(Strings.text(Strings.archive_key(card.id, Strings.ARCHIVE_DATE_FIELD))))
		_list.add_child(_label(Strings.text(Strings.archive_key(card.id, Strings.ARCHIVE_BODY_FIELD))))
		_list.add_child(_label(Strings.text(Strings.ARCHIVE_SOURCES) %
			Strings.text(Strings.archive_key(card.id, Strings.ARCHIVE_SOURCES_FIELD))))
		_list.add_child(_label(_image_text(card)))


# The credit in the order of ArchiveCatalog.CREDIT_FIELDS, then why the print is only of context.
func _image_text(card: ArchiveCard) -> String:
	if card.image.is_empty():
		return Strings.text(Strings.ARCHIVE_NO_IMAGE)
	var credit: Array[String] = []
	for field: String in ArchiveCatalog.CREDIT_FIELDS:
		credit.append(card.image[field])
	var text: String = Strings.text(Strings.ARCHIVE_IMAGE_CREDIT) % credit
	if card.image_is_context:
		text += "\n" + Strings.text(Strings.ARCHIVE_IMAGE_NOTE) % Strings.text(
			Strings.archive_key(card.id, Strings.ARCHIVE_IMAGE_CONTEXT))
	return text


func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
