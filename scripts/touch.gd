extends Control
## Touch input for both control layouts. Reads multi-touch through _gui_input so
## positions are always in this control's own coordinates.

const UI = preload("res://scripts/ui.gd")
const PANEL_H := 220.0

var steer := 0.0
var throttle := 0.0
var jump := false
var layout := "invisible"
var left_handed := false
var sens := 1.0
var hint_t := 3.0
var enabled := true

var touches := {}      # index -> {"role": String, "start": Vector2, "pos": Vector2}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	layout = String(G.data["controls"])
	left_handed = bool(G.data["left_handed"])
	sens = float(G.data["sens"])

func reset() -> void:
	touches.clear()
	steer = 0.0; throttle = 0.0; jump = false
	hint_t = 3.0
	queue_redraw()

func _process(delta: float) -> void:
	if hint_t > 0.0:
		hint_t -= delta
		queue_redraw()
	_update()

func _buttons() -> Dictionary:
	var w := size.x
	var cy := size.y - PANEL_H * 0.5
	var b := {
		"left": [Vector2(74, cy), 50.0], "right": [Vector2(186, cy), 50.0],
		"up": [Vector2(300, cy - 46), 34.0], "down": [Vector2(300, cy + 46), 34.0],
		"jump": [Vector2(w - 104, cy), 70.0],
	}
	if left_handed:
		for k in b:
			b[k][0].x = w - b[k][0].x
	return b

func _role_at(p: Vector2) -> String:
	if layout == "buttons":
		if p.y < size.y - PANEL_H:
			return ""
		var best := ""
		var bd := 1e9
		var bs := _buttons()
		for k in bs:
			var d: float = p.distance_to(bs[k][0]) - bs[k][1]
			if d < bd:
				bd = d; best = k
		return best if bd < 26.0 else ""
	var on_left := p.x < size.x * 0.5
	if left_handed:
		on_left = not on_left
	return "stick" if on_left else "jump"

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = {"role": _role_at(e.position), "start": e.position, "pos": e.position}
		else:
			touches.erase(e.index)
		queue_redraw()
		accept_event()
	elif e is InputEventScreenDrag:
		if touches.has(e.index):
			touches[e.index]["pos"] = e.position
			if layout == "buttons":
				var r := _role_at(e.position)
				if r in ["left", "right"] and touches[e.index]["role"] in ["left", "right"]:
					touches[e.index]["role"] = r
			queue_redraw()
		accept_event()

func _update() -> void:
	var s := 0.0
	var t := 0.0
	var j := false
	if enabled:
		for i in touches:
			var tc: Dictionary = touches[i]
			match tc["role"]:
				"jump": j = true
				"left": s -= 1.0
				"right": s += 1.0
				"up": t += 1.0
				"down": t -= 1.0
				"stick":
					var d: Vector2 = tc["pos"] - tc["start"]
					var reach := 52.0 / sens
					s = clampf(d.x / reach, -1.0, 1.0)
					if absf(s) < 0.12:
						s = 0.0
					if absf(d.y) > 34.0:
						t = clampf(-(d.y - signf(d.y) * 34.0) / 60.0, -1.0, 1.0)
					# let the stick follow the finger so reversing is instant
					if absf(d.x) > reach * 1.25:
						tc["start"].x = tc["pos"].x - signf(d.x) * reach * 1.25
		# keyboard for desktop testing
		s += Input.get_axis("ui_left", "ui_right")
		t += Input.get_axis("ui_down", "ui_up")
		j = j or Input.is_physical_key_pressed(KEY_SPACE)
	steer = clampf(s, -1.0, 1.0)
	throttle = clampf(t, -1.0, 1.0)
	jump = j

func _held(role: String) -> bool:
	for i in touches:
		if touches[i]["role"] == role:
			return true
	return false

func _chev(c: Vector2, dir: Vector2, s: float, col: Color, w := 4.0) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_polyline([c - dir * s * 0.45 + n * s, c + dir * s * 0.55, c - dir * s * 0.45 - n * s], col, w, true)

func _draw() -> void:
	var f := UI.font("Black")
	if layout == "buttons":
		var top := size.y - PANEL_H
		draw_rect(Rect2(0, top, size.x, PANEL_H), Color("10122a"))
		draw_line(Vector2(0, top), Vector2(size.x, top), UI.LINE, 2.0)
		var bs := _buttons()
		for k in bs:
			var c: Vector2 = bs[k][0]
			var r: float = bs[k][1]
			var held := _held(k)
			if k == "jump":
				draw_circle(c, r, UI.CY.darkened(0.25) if held else UI.CY)
				draw_string(f, c + Vector2(-60, 8), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, UI.DARK)
			else:
				draw_circle(c, r, UI.LINE if held else UI.PANEL)
				draw_arc(c, r, 0, TAU, 48, UI.LINE, 2.0, true)
				var dir: Vector2 = {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}[k]
				_chev(c, dir, r * 0.3, UI.INK)
		var sc: Vector2 = (bs["up"][0] + bs["down"][0]) * 0.5
		draw_string(UI.font("Bold"), sc + Vector2(-40, 4), "SPEED", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, UI.MUTE)
		return
	# invisible layout: live stick while touching, hints for the first seconds
	for i in touches:
		var tc: Dictionary = touches[i]
		if tc["role"] == "stick":
			draw_arc(tc["start"], 56, 0, TAU, 48, Color(1, 1, 1, 0.22), 2.0, true)
			var d: Vector2 = (tc["pos"] - tc["start"]).limit_length(56)
			draw_circle(tc["start"] + d, 24, Color(1, 1, 1, 0.35))
	if hint_t > 0.0:
		var a := clampf(hint_t, 0.0, 1.0)
		var lx := size.x * (0.75 if left_handed else 0.25)
		var rx := size.x - lx
		var y := size.y - 170.0
		draw_dashed_line(Vector2(size.x * 0.5, size.y - 520), Vector2(size.x * 0.5, size.y - 40), Color(1, 1, 1, 0.35 * a), 1.5, 8.0)
		draw_arc(Vector2(lx, y), 60, 0, TAU, 48, Color(1, 1, 1, 0.6 * a), 2.0, true)
		draw_circle(Vector2(lx - 20, y), 26, Color(0.91, 0.93, 1, 0.8 * a))
		_chev(Vector2(lx - 82, y), Vector2.LEFT, 9, Color(1, 1, 1, a), 3.0)
		_chev(Vector2(lx + 82, y), Vector2.RIGHT, 9, Color(1, 1, 1, a), 3.0)
		draw_string(f, Vector2(lx - 100, y + 96), "DRAG TO STEER", HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(0.91, 0.93, 1, a))
		draw_string(UI.font("Medium"), Vector2(lx - 100, y + 116), "up / down = speed", HORIZONTAL_ALIGNMENT_CENTER, 200, 12, Color(0.66, 0.69, 0.84, a))
		draw_arc(Vector2(rx, y), 60, 0, TAU, 48, Color(0.22, 0.88, 1, 0.45 * a), 2.0, true)
		draw_arc(Vector2(rx, y), 38, 0, TAU, 48, Color(0.22, 0.88, 1, 0.8 * a), 2.5, true)
		draw_circle(Vector2(rx, y), 13, Color(0.22, 0.88, 1, a))
		draw_string(f, Vector2(rx - 100, y + 96), "TAP TO JUMP", HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(0.91, 0.93, 1, a))
		draw_string(UI.font("Medium"), Vector2(rx - 100, y + 116), "hold to keep hopping", HORIZONTAL_ALIGNMENT_CENTER, 200, 12, Color(0.66, 0.69, 0.84, a))
