extends Object
## Small helpers for building the menus in code.

const INK := Color("e8ecff")
const MUTE := Color("a9b1d6")
const DIM := Color("8d95bd")
const CY := Color("38e1ff")
const OR := Color("ff8a3d")
const PANEL := Color("151830")
const PANEL2 := Color("0e1022")
const LINE := Color("4a5290")
const LINE2 := Color("2a2f52")
const BG := Color("0a0b14")
const DARK := Color("06121a")

static var _fonts := {}

static func font(w := "Bold") -> Font:
	if not _fonts.has(w):
		_fonts[w] = load("res://assets/fonts/Inter-%s.otf" % w)
	return _fonts[w]

static func place(n: Control, x: float, y: float, w: float, h: float) -> Control:
	n.position = Vector2(x, y)
	n.size = Vector2(w, h)
	return n

static func label(text: String, size: int, col := INK, w := "Bold", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font(w)
	ls.font_size = size
	ls.font_color = col
	l.label_settings = ls
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 12, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(bw)
	s.anti_aliasing = true
	return s

static func panel(bg := PANEL, border := LINE2, radius := 14, bw := 2) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(bg, border, radius, bw))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## kind: "primary" (cyan), "ghost" (dark), "accent" (orange)
static func button(text: String, size := 17, kind := "ghost", radius := 12) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("Black" if kind == "primary" else "Bold"))
	b.add_theme_font_size_override("font_size", size)
	var bg := PANEL
	var bd := LINE
	var fg := INK
	if kind == "primary":
		bg = CY; bd = CY; fg = DARK
	elif kind == "accent":
		bg = OR; bd = OR; fg = Color("1a0b00")
	b.add_theme_stylebox_override("normal", box(bg, bd, radius))
	b.add_theme_stylebox_override("hover", box(bg, bd, radius))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.25), bd, radius))
	b.add_theme_stylebox_override("disabled", box(PANEL2, LINE2, radius))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.pressed.connect(func(): Sfx.play("tap", -6.0))
	return b

static func back_button() -> Button:
	var b := button("‹", 30)
	b.add_theme_font_override("font", font("Medium"))
	return b

static func backdrop(alpha := 0.86) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(BG.r, BG.g, BG.b, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c
