class_name DefeatCritical
extends VBoxContainer

# The last step of the defeat warnings (issue #350): one notice per condition in its final seconds, stacked with the
# fewest seconds first. It reads snapshot["defeat_state"] and applies no rule. The look is a plain printed notice
# (paper, ink, double rule) as D-181 asks for an era skin; it states no historical fact.

# Fired once each time a condition enters the critical level; the sound listens to it, tests too.
signal critical_entered(condition: StringName)

const PAPER: Color = Color("e8dcc0")
const INK: Color = Color("2b1d14")
const SEAL: Color = Color("8c1c13")
const OUTER_RULE: int = 4
const INNER_RULE: int = 1
const GAP: int = 2
const MARGIN: int = 6
const SERIF_FONTS: PackedStringArray = ["Georgia", "Times New Roman", "Liberation Serif", "serif"]
const TITLE_SIZE: int = 14
const SECONDS_SIZE: int = 16
const BODY_SIZE: int = 12

var sound: DefeatCriticalSound = DefeatCriticalSound.new()
var _player: AudioStreamPlayer
var _diagnostic: Label
# The "settings pending" line: it shows with or without critical notices and is no notice itself.
var _config_line: Label
var _config_text: String = ""
var _config_details: String = ""
var _font: SystemFont
# Conditions on screen, in order; tests read it with rows().
var _shown: Array[Dictionary] = []
var _built_layout: Array[String] = []


func _init() -> void:
	visible = false
	# Texts arrive translated; auto-translate would look them up again as keys.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_font = SystemFont.new()
	_font.font_names = SERIF_FONTS
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	critical_entered.connect(_play)


# `sound_id` is the raw ui.defeat.critical_sound value; see DefeatCriticalSound.
func configure_sound(sound_id: Variant, loader: Callable = Callable()) -> void:
	sound.configure(sound_id, loader)


func show_state(snapshot: Dictionary) -> void:
	_shown = DefeatCriticalRows.rows(snapshot)
	_config_text = DefeatCriticalConfig.message(snapshot)
	_config_details = DefeatCriticalConfig.details(snapshot)
	for fresh: StringName in sound.entered(DefeatCriticalRows.conditions(_shown)):
		critical_entered.emit(fresh)
	_rebuild()


# A new game or a loaded one: the next entry sounds again.
func reset_sound() -> void:
	sound.reset()


# The settings line on screen, or "" when the settings are complete (or the snapshot says nothing about them).
func config_text() -> String:
	return _config_text


# {condition, seconds_left, cause} of each notice on screen, in order.
func rows() -> Array[Dictionary]:
	return _shown


# The nodes are rebuilt only when the list of notices changes. Seconds and language change the texts in place:
# freeing labels while the engine is passing a translation change through the tree breaks text shaping.
func _rebuild() -> void:
	var layout: Array[String] = _layout()
	if layout == _built_layout:
		_refresh()
		return
	_built_layout = layout
	for child: Node in get_children():
		if child != _player:
			remove_child(child)
			child.queue_free()
	_diagnostic = null
	_config_line = null
	visible = _has_content()
	for row: Dictionary in _shown:
		add_child(_notice(row["condition"], row["cause"], row["seconds_left"]))
	if not _shown.is_empty() and not sound.is_ready():
		_diagnostic = _label(_diagnostic_text(), BODY_SIZE, PAPER)
		add_child(_diagnostic)
	if not _config_text.is_empty():
		_config_line = _label(_config_text, BODY_SIZE, PAPER)
		_config_line.name = "ConfigPending"
		_config_line.tooltip_text = _config_details
		_config_line.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_config_line)


func _layout() -> Array[String]:
	var layout: Array[String] = []
	for row: Dictionary in _shown:
		layout.append("%s|%s" % [row["condition"], row["cause"]])
	if not _shown.is_empty() and not sound.is_ready():
		layout.append("diagnostic")
	if not _config_text.is_empty():
		layout.append("config")
	return layout


func _has_content() -> bool:
	return not _shown.is_empty() or not _config_text.is_empty()


func _diagnostic_text() -> String:
	return Strings.text(Strings.CRITICAL_SOUND_DIAGNOSTICS[sound.status])


func _refresh() -> void:
	visible = _has_content()
	for row: Dictionary in _shown:
		var notice: Node = get_node("Notice_%s" % row["condition"])
		(notice.find_child("Name", true, false) as Label).text = Strings.label(Strings.CONDITION_LABELS, row["cause"])
		(notice.find_child("Left", true, false) as Label).text = Strings.text(Strings.CRITICAL_LEFT) % row["seconds_left"]
		(notice.find_child("Cause", true, false) as Label).text = Strings.label(Strings.CRITICAL_CAUSES, row["cause"])
		(notice.find_child("Icon", true, false) as Control).tooltip_text = Strings.label(Strings.CRITICAL_ICON_LABELS, row["cause"])
	if _diagnostic != null:
		_diagnostic.text = _diagnostic_text()
	if _config_line != null:
		_config_line.text = _config_text
		_config_line.tooltip_text = _config_details


func _notice(condition: StringName, cause_id: StringName, seconds_left: int) -> PanelContainer:
	var notice: PanelContainer = PanelContainer.new()
	notice.name = "Notice_%s" % condition
	notice.add_theme_stylebox_override("panel", _style())
	var line: HBoxContainer = HBoxContainer.new()
	notice.add_child(line)
	var icon: DefeatIcon = DefeatIcon.new()
	icon.name = "Icon"
	icon.setup(cause_id, INK, PAPER)
	icon.tooltip_text = Strings.label(Strings.CRITICAL_ICON_LABELS, cause_id)
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	line.add_child(text)
	# Name and seconds share a line to keep the notice short: three can stack on a 1280x800 screen.
	var head: HBoxContainer = HBoxContainer.new()
	text.add_child(head)
	var name_label: Label = _label(Strings.label(Strings.CONDITION_LABELS, cause_id), TITLE_SIZE, SEAL)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var left: Label = _label(Strings.text(Strings.CRITICAL_LEFT) % seconds_left, SECONDS_SIZE, INK)
	left.name = "Left"
	left.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(left)
	var cause: Label = _label(Strings.label(Strings.CRITICAL_CAUSES, cause_id), BODY_SIZE, INK)
	cause.name = "Cause"
	text.add_child(cause)
	return notice


# A thick seal-red rule with a thin ink edge outside it, like a printed border. One StyleBoxFlat cannot nest two
# borders, so the thin edge is its hard shadow (no blur, no offset).
func _style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = SEAL
	style.set_border_width_all(OUTER_RULE)
	style.set_content_margin_all(MARGIN)
	style.set_corner_radius_all(0)
	style.shadow_color = INK
	style.shadow_size = GAP + INNER_RULE
	return style


func _label(content: String, size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _play(_condition: StringName) -> void:
	if not sound.is_ready():
		return
	_player.stream = sound.stream
	_player.play()
