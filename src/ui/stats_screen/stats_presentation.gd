class_name StatsPresentation
extends RefCounted

# Look of the statistics screen (issue #83), from data/ui/stats.json. The strokes pair a colour from a palette
# readable with colour blindness with a dash length (0 = solid), so two lines differ even without their colour.
# The history view's ranges each read one level of the history over a span (0 = the whole level). The classes
# view fills its layers with the strokes' colours at fill_alpha.

const PATH: String = "res://data/ui/stats.json"
const LAYOUT_KEYS: Array[String] = ["font_size", "margin", "card_columns", "chart_height", "legend_width",
	"line_width", "history_chart_height"]
const COLOR_KEYS: Array[String] = ["background", "card", "marker", "cursor"]
# The fine level holds one value a second, not buckets, so the ranges read only these two.
const RANGE_TIERS: Array[StringName] = [StatsHistory.TIER_MEDIUM, StatsHistory.TIER_CHAPTER]

var summary_span_seconds: int = 0
# {"id", "tier", "span_seconds"}, in the order the triggers go through them.
var history_ranges: Array[Dictionary] = []
var layout: Dictionary[String, float] = {}
var colors: Dictionary[String, Color] = {}
var stroke_colors: Array[Color] = []
var stroke_dashes: PackedFloat32Array = []
# Opacity of a stacked layer, more than 0 and at most 1.
var fill_alpha: float = 1.0
var errors: Array[String] = []


func load_data() -> void:
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(PATH)) != OK:
		errors.append("data/ui/stats.json: invalid JSON")
		return
	validate(json.data)


func validate(raw: Variant) -> void:
	if raw is not Dictionary or raw.get("summary") is not Dictionary or raw.get("layout") is not Dictionary \
			or raw.get("colors") is not Dictionary or raw.get("strokes") is not Array or raw["strokes"].is_empty():
		errors.append("data/ui/stats.json: expected summary, layout, colors and strokes")
		return
	summary_span_seconds = _positive(raw["summary"].get("span_seconds"), "summary.span_seconds")
	for key: String in LAYOUT_KEYS:
		layout[key] = _positive(raw["layout"].get(key), "layout." + key)
	for key: String in COLOR_KEYS:
		colors[key] = _color(raw["colors"].get(key), "colors." + key)
	for index: int in raw["strokes"].size():
		var stroke: Variant = raw["strokes"][index]
		var dash: Variant = stroke.get("dash") if stroke is Dictionary else null
		if (dash is not float and dash is not int) or dash < 0:
			errors.append("data/ui/stats.json.strokes.%d.dash: expected a length of 0 or more" % index)
			continue
		stroke_colors.append(_color(stroke.get("color"), "strokes.%d.color" % index))
		stroke_dashes.append(float(dash))
	_validate_ranges(raw.get("history"))
	_validate_fill(raw.get("classes"))


# Stroke of the index-th line of a chart; they repeat when a chart has more lines than strokes.
func stroke_color(index: int) -> Color:
	return stroke_colors[index % stroke_colors.size()]


func stroke_dash(index: int) -> float:
	return stroke_dashes[index % stroke_dashes.size()]


func _validate_ranges(history: Variant) -> void:
	if history is not Dictionary or history.get("ranges") is not Array or history["ranges"].is_empty():
		errors.append("data/ui/stats.json.history.ranges: expected a list of ranges")
		return
	for index: int in history["ranges"].size():
		var entry: Variant = history["ranges"][index]
		var key: String = "data/ui/stats.json.history.ranges.%d" % index
		if entry is not Dictionary or entry.get("id") is not String or entry.get("tier") is not String \
				or StringName(entry["tier"]) not in RANGE_TIERS:
			errors.append(key + ": expected an id and a tier, medium or chapter")
			continue
		var span: Variant = entry.get("span_seconds")
		if (span is not float and span is not int) or span < 0:
			errors.append(key + ".span_seconds: expected 0 or more")
			continue
		history_ranges.append({"id": StringName(entry["id"]), "tier": StringName(entry["tier"]),
			"span_seconds": int(span)})


func _validate_fill(classes: Variant) -> void:
	var alpha: Variant = classes.get("fill_alpha") if classes is Dictionary else null
	if (alpha is not float and alpha is not int) or alpha <= 0 or alpha > 1:
		errors.append("data/ui/stats.json.classes.fill_alpha: expected more than 0 and at most 1")
		return
	fill_alpha = float(alpha)


func _positive(value: Variant, key: String) -> int:
	if (value is not float and value is not int) or value <= 0:
		errors.append("data/ui/stats.json.%s: invalid positive value" % key)
		return 0
	return int(value)


func _color(value: Variant, key: String) -> Color:
	if value is not String or not Color.html_is_valid(value):
		errors.append("data/ui/stats.json.%s: invalid color" % key)
		return Color.MAGENTA
	return Color.html(value)
