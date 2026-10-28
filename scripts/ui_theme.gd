class_name UiTheme
extends RefCounted
## Theme, palette, fonts and small widget builders for the clean modern UI.

const BG := Color(0.055, 0.075, 0.07, 0.88)
const BG_SOLID := Color(0.07, 0.095, 0.09, 0.97)
const PANEL_LINE := Color(1, 1, 1, 0.08)
const TEXT := Color(0.94, 0.92, 0.86)
const DIM := Color(0.7, 0.72, 0.68)
const ACCENT := Color(0.93, 0.7, 0.3)
const GREEN := Color(0.45, 0.8, 0.5)
const YELLOW := Color(0.95, 0.8, 0.35)
const RED := Color(0.9, 0.4, 0.35)
const BLUE := Color(0.45, 0.7, 0.95)

static var _body: Font
static var _title: Font
static var _bold: Font


static func body_font() -> Font:
	if _body == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Inter", "Helvetica Neue", "Noto Sans", "DejaVu Sans", "Arial", "Sans-Serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_body = f
	return _body


static func bold_font() -> Font:
	if _bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Inter", "Helvetica Neue", "Noto Sans", "DejaVu Sans", "Arial", "Sans-Serif"])
		f.font_weight = 600
		_bold = f
	return _bold


static func title_font() -> Font:
	if _title == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Cambria", "Palatino Linotype", "Book Antiqua", "DejaVu Serif", "Serif"])
		f.font_weight = 700
		_title = f
	return _title


static func panel_box(bg := BG, radius := 14, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.border_color = PANEL_LINE
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func button_box(bg: Color, radius := 10, border := Color(1, 1, 1, 0.08)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.border_color = border
	sb.set_border_width_all(1)
	return sb


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	t.set_stylebox("normal", "Button", button_box(Color(0.16, 0.2, 0.18, 0.95)))
	t.set_stylebox("hover", "Button", button_box(Color(0.24, 0.3, 0.26, 0.98), 10, Color(ACCENT, 0.5)))
	t.set_stylebox("pressed", "Button", button_box(Color(0.32, 0.26, 0.15, 1.0), 10, ACCENT))
	t.set_stylebox("disabled", "Button", button_box(Color(0.12, 0.14, 0.13, 0.7)))
	t.set_stylebox("focus", "Button", button_box(Color(0, 0, 0, 0), 10, Color(ACCENT, 0.8)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.5))
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", 17)

	var le := button_box(Color(0.1, 0.13, 0.12, 1.0), 8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", button_box(Color(0.12, 0.16, 0.14, 1.0), 8, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_font_size("font_size", "LineEdit", 18)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(5)
	t.set_stylebox("background", "ProgressBar", bg)
	var fg := StyleBoxFlat.new()
	fg.bg_color = GREEN
	fg.set_corner_radius_all(5)
	t.set_stylebox("fill", "ProgressBar", fg)
	t.set_font_size("font_size", "ProgressBar", 1)

	var sbar := StyleBoxFlat.new()
	sbar.bg_color = Color(1, 1, 1, 0.05)
	sbar.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", sbar)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.22)
	grab.set_corner_radius_all(4)
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)

	t.set_stylebox("panel", "TooltipPanel", panel_box(BG_SOLID, 8, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t


# ------------------------------------------------------------------ widget builders

static func label(text: String, size := 17, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 30) -> Label:
	var l := label(text, size, TEXT, title_font())
	return l


static func caps(text: String, color := DIM) -> Label:
	var l := label(text.to_upper(), 12, color, bold_font())
	l.add_theme_constant_override("outline_size", 0)
	return l


static func wrap_label(text: String, size := 17, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 100
	return l


static func button(text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if accent:
		b.add_theme_stylebox_override("normal", button_box(Color(0.78, 0.52, 0.18, 0.98), 10, Color(1, 0.85, 0.5, 0.6)))
		b.add_theme_stylebox_override("hover", button_box(Color(0.88, 0.62, 0.24, 1.0), 10, Color(1, 0.9, 0.6, 0.9)))
		b.add_theme_stylebox_override("pressed", button_box(Color(0.65, 0.42, 0.12, 1.0), 10, Color(1, 0.9, 0.6, 0.9)))
		b.add_theme_color_override("font_color", Color(0.1, 0.07, 0.03))
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.0))
		b.add_theme_color_override("font_pressed_color", Color(0.05, 0.03, 0.0))
	b.pressed.connect(cb)
	return b


static func bar(value: float, color: Color, height := 8.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0
	p.max_value = 100
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(60, height)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(int(height / 2))
	p.add_theme_stylebox_override("fill", fg)
	return p


static func stat_color(v: float, invert := false) -> Color:
	var x := 100.0 - v if invert else v
	if x >= 60.0:
		return GREEN
	if x >= 30.0:
		return YELLOW
	return RED


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(bg := BG, radius := 14, pad := 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box(bg, radius, pad))
	return p


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func separator() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size = Vector2(0, 1)
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
