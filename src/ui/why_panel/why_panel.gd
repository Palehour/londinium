class_name WhyPanel
extends PanelContainer

# The "why?" (issue #73, D-137): the chain of causes of one subject exactly as the cause log of #82 keeps it, newest
# first, with no filter and nothing left out. Each event's cause is its translated reason, or its id when there is
# no text for it. It only shows what the map view hands it and sends no command.

const SECONDS_PER_MINUTE: int = 60

# One line per event of the chain, in its order, then the note of the dropped ones.
var lines: Array[String] = []
var expanded: bool = false
var _subject: StringName = &""
var _title: Label
var _toggle: Button
var _rows: Label


func setup() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_title)
	_toggle = Button.new()
	# Never the focus, so the gamepad keeps the map.
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(toggle)
	root.add_child(_toggle)
	_rows = Label.new()
	_rows.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_rows)


func apply_style(background: Color, margin: float) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.set_content_margin_all(margin)
	add_theme_stylebox_override("panel", style)


# A subject with no events hides the panel. Another subject starts folded. `pruned`: the log has dropped its
# oldest events, so the chain may begin later than the subject did.
func show_chain(subject: StringName, title: String, chain: Array[Dictionary], pruned: bool, gamepad: bool,
		with_subject: bool = false) -> void:
	if subject != _subject:
		_subject = subject
		expanded = false
	visible = not chain.is_empty()
	lines.clear()
	for event: Dictionary in chain:
		lines.append(line(event, with_subject))
	if pruned and not chain.is_empty():
		lines.append(Strings.text(Strings.WHY_PRUNED))
	_title.text = title
	_toggle.text = Strings.text(Strings.WHY_BUTTON_GAMEPAD if gamepad else Strings.WHY_BUTTON)
	_rows.text = "\n".join(lines)
	_rows.visible = expanded


func toggle() -> void:
	if not visible:
		return
	expanded = not expanded
	_rows.visible = expanded


# Game time as minutes:seconds since the chapter began, and the cause as the log keeps it. `with_subject` adds what the
# event is about, for a list that mixes subjects (the statistics screen, issue #319).
static func line(event: Dictionary, with_subject: bool = false) -> String:
	var second: int = int(event["second"])
	@warning_ignore("integer_division")
	var time: String = "%d:%02d" % [second / SECONDS_PER_MINUTE, second % SECONDS_PER_MINUTE]
	var cause: StringName = StringName(event["cause"])
	var text: String = Strings.text(Strings.WHY_INTERMITTENT) % int(event.get("count", 0)) \
		if cause == CauseLog.INTERMITTENT else Strings.reason(cause)
	if with_subject:
		return Strings.text(Strings.WHY_ROW_SUBJECT) % [time, subject_label(event), text]
	return Strings.text(Strings.WHY_ROW) % [time, text]


# What an event is about, translated where the project has a name for it, and as the log keeps it otherwise.
static func subject_label(event: Dictionary) -> String:
	var subject: StringName = StringName(event["subject"])
	match StringName(event["kind"]):
		&"building":
			var name: String = Strings.building_label(String(subject).get_slice("@", 0))
			return name if not name.is_empty() else String(subject)
		&"policy":
			return Strings.label(Strings.STATS_SCREEN_POLICIES, subject)
		&"defeat":
			return Strings.label(Strings.CONDITION_LABELS, subject)
	return String(subject)
