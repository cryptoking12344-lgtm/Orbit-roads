extends Control
## In-flight HUD: road name, progress, fuel / air / speed gauges.

const UI = preload("res://scripts/ui.gd")
var title := ""
var progress := 0.0
var fuel := 1.0
var air := 1.0
var speed := 0.0
var blink := 0.0
var banner := ""
var banner_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_banner(t: String) -> void:
	banner = t
	banner_t = 0.9

func _process(delta: float) -> void:
	blink += delta
	banner_t = maxf(0.0, banner_t - delta)
	queue_redraw()

var _boxes := {}
func _sb(col: Color, r: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var key := [col, r, border]
	if not _boxes.has(key):
		_boxes[key] = UI.box(col, border, r)
	return _boxes[key]

func _bar(x: float, y: float, w: float, h: float, v: float, col: Color) -> void:
	draw_style_box(_sb(UI.LINE2, int(h / 2)), Rect2(x, y, w, h))
	if v > 0.01:
		draw_style_box(_sb(col, int(h / 2)), Rect2(x, y, maxf(h, w * clampf(v, 0.0, 1.0)), h))

func _draw() -> void:
	var w := size.x
	var fb := UI.font("Bold")
	draw_string(fb, Vector2(84, 62), title, HORIZONTAL_ALIGNMENT_LEFT, w - 170, 13, UI.INK)
	draw_string(fb, Vector2(w - 100, 62), "%d%%" % int(progress * 100), HORIZONTAL_ALIGNMENT_RIGHT, 80, 13, UI.CY)
	_bar(84, 72, w - 104, 7, progress, UI.CY)
	draw_style_box(_sb(Color(0.063, 0.071, 0.165, 0.92), 10, UI.LINE2), Rect2(20, 104, w - 40, 44))
	var cw := (w - 68) / 3.0
	var items := [["FUEL", fuel, UI.OR], ["AIR", air, UI.CY], ["SPEED", speed, UI.INK]]
	for i in 3:
		var x := 34 + i * cw
		var v: float = items[i][1]
		var col: Color = items[i][2]
		var low := i < 2 and v < 0.22
		if low and fmod(blink, 0.5) < 0.25:
			col = Color("ff3a4a")
		draw_string(fb, Vector2(x, 131), items[i][0], HORIZONTAL_ALIGNMENT_LEFT, 50, 11, Color("ff3a4a") if low else UI.MUTE)
		_bar(x + 46, 122, cw - 62, 8, v, col)
	if banner_t > 0.0:
		var a := clampf(banner_t * 3.0, 0.0, 1.0)
		draw_string(UI.font("Black"), Vector2(0, 330), banner, HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 1, 1, a))
