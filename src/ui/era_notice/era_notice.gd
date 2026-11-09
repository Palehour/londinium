class_name EraNotice
extends PanelContainer

# A period notice for the alerts of the panel (D-181): a slip of aged paper with ink text, a sepia border and a
# coloured edge, drawn with native Godot controls and system serif fonts, with no art files. Presentation only.
# The look is kept here as constants until it moves into data/ui/ (pending).

enum Tone { LABOR, WARNING }

const PAPER: Color = Color("e6d9b8")
const INK: Color = Color("2a2016")
const SEPIA: Color = Color("6b5232")
const EDGES: Dictionary[int, Color] = {
	Tone.LABOR: Color("5f6f4f"),
	Tone.WARNING: Color("9a2f1c"),
}
const EDGE_WIDTH: int = 5
const MARGIN_X: int = 10
const MARGIN_Y: int = 6
const TITLE_SIZE: int = 12
const BODY_SIZE: int = 14
const SERIF_FONTS: Array[String] = ["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"]

var body: Label
var _title: Label


func _init(tone: Tone = Tone.LABOR, title_text: String = "") -> void:
	visible = false
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = SEPIA
	style.set_border_width_all(1)
	style.border_width_left = EDGE_WIDTH
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1.0, 2.0)
	style.content_margin_left = MARGIN_X
	style.content_margin_right = MARGIN_X
	style.content_margin_top = MARGIN_Y
	style.content_margin_bottom = MARGIN_Y
	add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	add_child(column)
	var serif: SystemFont = SystemFont.new()
	serif.font_names = PackedStringArray(SERIF_FONTS)
	var spaced: FontVariation = FontVariation.new()
	spaced.base_font = serif
	spaced.spacing_glyph = 1
	_title = Label.new()
	_title.text = title_text.to_upper()
	_title.add_theme_font_override("font", spaced)
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.add_theme_color_override("font_color", EDGES[tone])
	column.add_child(_title)
	var rule: HSeparator = HSeparator.new()
	var line: StyleBoxLine = StyleBoxLine.new()
	line.color = SEPIA
	line.thickness = 1
	rule.add_theme_stylebox_override("separator", line)
	column.add_child(rule)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("font", serif)
	body.add_theme_font_size_override("font_size", BODY_SIZE)
	body.add_theme_color_override("font_color", INK)
	column.add_child(body)


func set_title(title_text: String) -> void:
	_title.text = title_text.to_upper()


# Shows the notice with this text, or hides it when there is none.
func show_text(text: String) -> void:
	body.text = text
	body.visible = not text.is_empty()
	visible = body.visible
