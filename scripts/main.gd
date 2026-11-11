extends Node
## Menus (home, roads, ships, controls, settings) and switching in and out of play.

const UI = preload("res://scripts/ui.gd")
const PlayC = preload("res://scripts/play.gd")

class ArchIcon extends Control:
	var col := Color.WHITE
	func _draw() -> void:
		draw_arc(Vector2(8, 9), 7, PI, TAU, 16, col, 2.2, true)
		draw_line(Vector2(1, 9), Vector2(1, 14), col, 2.2)
		draw_line(Vector2(15, 9), Vector2(15, 14), col, 2.2)

class Mini extends Control:
	var kind := "invisible"
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.box(UI.PANEL2, UI.LINE, 14), r)
		var w := size.x
		var h := size.y
		draw_colored_polygon([Vector2(w * 0.4, h * 0.12), Vector2(w * 0.6, h * 0.12), Vector2(w * 0.8, h * 0.66), Vector2(w * 0.2, h * 0.66)], Color("2c3260"))
		draw_circle(Vector2(w * 0.5, h * 0.5), 7, UI.INK)
		draw_circle(Vector2(w * 0.5 - 3, h * 0.5 + 9), 2.5, UI.OR)
		draw_circle(Vector2(w * 0.5 + 3, h * 0.5 + 9), 2.5, UI.OR)
		if kind == "invisible":
			draw_rect(Rect2(5, 5, w * 0.5 - 6, h - 10), Color(0.22, 0.88, 1, 0.14))
			draw_rect(Rect2(w * 0.5 + 1, 5, w * 0.5 - 6, h - 10), Color(1, 0.54, 0.24, 0.14))
			draw_dashed_line(Vector2(w * 0.5, 8), Vector2(w * 0.5, h - 8), Color(1, 1, 1, 0.6), 1.5, 5.0)
			draw_arc(Vector2(w * 0.25, h * 0.82), 12, 0, TAU, 24, UI.INK, 2.0, true)
			draw_circle(Vector2(w * 0.25 - 4, h * 0.82), 5, UI.INK)
			draw_arc(Vector2(w * 0.75, h * 0.82), 11, 0, TAU, 24, UI.CY, 2.0, true)
			draw_circle(Vector2(w * 0.75, h * 0.82), 4, UI.CY)
		else:
			draw_rect(Rect2(2, h * 0.74, w - 4, h * 0.26 - 2), Color("1b1f3d"))
			draw_line(Vector2(2, h * 0.74), Vector2(w - 2, h * 0.74), UI.LINE, 1.5)
			draw_arc(Vector2(w * 0.18, h * 0.87), 10, 0, TAU, 24, UI.INK, 1.5, true)
			draw_arc(Vector2(w * 0.42, h * 0.87), 10, 0, TAU, 24, UI.INK, 1.5, true)
			draw_circle(Vector2(w * 0.78, h * 0.87), 14, UI.CY)

var play: Node3D = null
var layer: CanvasLayer
var root: Control
var stage: Control
var screen := "home"
var view_ship := 0
var spin_model: Node3D
var spin_drag := false
var shot := ""
var shot_path := ""
var shot_t := 0.0

func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	view_ship = int(G.data["ship"])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.split("=")[1]
		elif a.begins_with("out="):
			shot_path = a.split("=")[1]
		elif a.begins_with("unlock="):
			for i in int(a.split("=")[1]):
				G.data["cleared"][i] = true
				G.data["best"][i] = 11.0 + i * 0.37
		elif a.begins_with("layout="):
			G.data["controls"] = a.split("=")[1]
	Sfx.music("music_menu")
	if shot == "":
		show_screen("home")
	else:
		_run_shot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "play" and play:
			play.toggle_pause()
		elif screen != "home":
			show_screen("home")
		else:
			get_tree().quit()

func _process(delta: float) -> void:
	if spin_model and is_instance_valid(spin_model) and not spin_drag:
		spin_model.rotation.y += delta * 0.7
	if shot != "":
		shot_t += delta
		var ready := shot_t > 1.2
		if shot.begins_with("soak"):
			ready = play.panel_shown and shot_t > 0.0
			if ready and shot_t > 0.0:
				print("SOAK road=%d state=%s fail=%s time=%.1f events_ok" % [play.road_i + 1, play.state, play.sim.fail, play.sim.time])
		if shot == "touchtest":
			ready = false
			_touch_test()
		if play and not play.demo and shot.begins_with("play"):
			ready = play.sim.time > 0.75
		if ready and shot_path != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
			shot = ""

# ------------------------------------------------------------------ flow

func _demo() -> void:
	if play and is_instance_valid(play) and play.demo:
		return
	if play and is_instance_valid(play):
		play.free()
	play = PlayC.new()
	play.setup(G.next_road(), true)
	add_child(play)
	move_child(play, 0)

func start_road(i: int) -> void:
	_clear()
	if play and is_instance_valid(play):
		play.free()
	screen = "play"
	play = PlayC.new()
	play.setup(i, false)
	play.exit.connect(func(dest): _go.call_deferred(dest, i))
	add_child(play)
	move_child(play, 0)

func _go(dest: String, i: int) -> void:
	match dest:
		"retry":
			start_road(i)
		"next":
			start_road(mini(i + 1, G.roads.size() - 1))
		_:
			Sfx.music("music_menu")
			show_screen("roads")

func _clear() -> void:
	spin_model = null
	for c in root.get_children():
		c.queue_free()

func show_screen(name: String) -> void:
	_clear()
	_demo()
	screen = name
	if name != "home":
		root.add_child(UI.backdrop(0.9))
	stage = Control.new()
	var vp := get_viewport().get_visible_rect().size
	stage.position = Vector2((vp.x - 540.0) * 0.5, (vp.y - 1170.0) * 0.5)
	stage.size = Vector2(540, 1170)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	match name:
		"home": _home()
		"roads": _roads()
		"ships": _ships()
		"controls": _controls()
		"settings": _settings()

func _add(n: Control, x: float, y: float, w: float, h: float) -> Control:
	stage.add_child(UI.place(n, x, y, w, h))
	return n

func _header(title: String) -> void:
	var b := UI.back_button()
	b.pressed.connect(func(): show_screen("home"))
	_add(b, 20, 44, 48, 48)
	_add(UI.label(title, 26, UI.INK, "Black"), 84, 46, 300, 44)

func _nav(text: String, x: float, y: float, w: float, h: float, dest: String, size := 15) -> void:
	var b := UI.button(text, size)
	b.pressed.connect(func(): show_screen(dest))
	_add(b, x, y, w, h)

# ------------------------------------------------------------------ home

func _home() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.039, 0.043, 0.078, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	root.move_child(shade, 0)
	_add(UI.label("ORBIT", 84, UI.INK, "Black", HORIZONTAL_ALIGNMENT_CENTER), 0, 96, 540, 90)
	_add(UI.label("ROADS", 84, UI.CY, "Black", HORIZONTAL_ALIGNMENT_CENTER), 0, 176, 540, 90)
	_add(UI.label("STAY ON THE ROAD  ·  MIND THE GAPS  ·  WATCH YOUR AIR", 12, UI.MUTE, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, 272, 540, 20)
	var i := G.next_road()
	var r: Dictionary = G.roads[i]
	_add(UI.label("%s  ·  ROAD %d-%d  ·  %s" % ["CONTINUE" if G.cleared_count() > 0 else "START", int(r["world"]) + 1, i % 3 + 1, String(r["name"]).to_upper()],
		12, UI.INK, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, 846, 540, 20)
	var p := UI.button("PLAY", 28, "primary", 14)
	p.pressed.connect(func(): start_road(i))
	_add(p, 40, 874, 460, 74)
	_nav("ROADS", 40, 962, 460, 58, "roads", 17)
	_nav("SHIPS", 40, 1034, 148, 58, "ships", 14)
	_nav("CONTROLS", 196, 1034, 148, 58, "controls", 14)
	_nav("SETTINGS", 352, 1034, 148, 58, "settings", 14)

# ------------------------------------------------------------------ roads

func _roads() -> void:
	_header("ROADS")
	_add(UI.label("%d / %d" % [G.cleared_count(), G.roads.size()], 16, UI.CY, "Black", HORIZONTAL_ALIGNMENT_RIGHT), 380, 46, 140, 22)
	_add(UI.label("CLEARED", 10, UI.MUTE, "Bold", HORIZONTAL_ALIGNMENT_RIGHT), 380, 68, 140, 16)
	for w in G.worlds.size():
		var y := 112.0 + w * 98.0
		var open: bool = G.road_unlocked(w * 3)
		_add(UI.label("%02d" % (w + 1), 26, UI.INK if open else UI.DIM, "Black"), 20, y + 6, 60, 34)
		_add(UI.label(String(G.worlds[w]["name"]).to_upper(), 11, UI.MUTE if open else UI.DIM), 20, y + 42, 128, 18)
		for r in 3:
			var i := w * 3 + r
			var road: Dictionary = G.roads[i]
			var done := bool(G.data["cleared"][i])
			var unlocked: bool = G.road_unlocked(i)
			var is_next := unlocked and not done
			var b := UI.button("", 12, "primary" if is_next else "ghost")
			b.disabled = not unlocked
			b.pressed.connect(func(): start_road(i))
			_add(b, 150 + r * 126, y, 116, 86)
			var fg := UI.DARK if is_next else (UI.INK if unlocked else UI.DIM)
			b.add_child(UI.place(UI.label("%d-%d" % [w + 1, r + 1], 21, fg, "Black"), 12, 8, 70, 28))
			b.add_child(UI.place(UI.label("Gravity %.1f g" % float(road["gravity"]), 11, fg, "Bold"), 12, 38, 100, 16))
			var status := "LOCKED"
			if done:
				status = "BEST " + G.fmt_time(float(G.data["best"][i]))
			elif is_next:
				status = "PLAY"
			b.add_child(UI.place(UI.label(status, 10, fg, "Black"), 12, 60, 100, 16))
			if bool(road["tunnels"]):
				var ic := ArchIcon.new()
				ic.col = fg
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(UI.place(ic, 90, 12, 16, 16))
	var ic2 := ArchIcon.new()
	ic2.col = UI.MUTE
	_add(ic2, 150, 1100, 16, 16)
	_add(UI.label("road has tunnels", 12, UI.MUTE, "Medium"), 174, 1098, 200, 18)
	_add(UI.label("Crash = restart the road", 12, UI.MUTE, "Medium", HORIZONTAL_ALIGNMENT_RIGHT), 320, 1098, 200, 18)

# ------------------------------------------------------------------ ships

func _ships() -> void:
	_header("SHIPS")
	var cur := int(G.data["ship"])
	var ship: Dictionary = G.SHIPS[view_ship]
	var unlocked: bool = G.ship_unlocked(view_ship)
	_add(UI.panel(UI.PANEL, UI.CY, 16, 3), 20, 116, 500, 300)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	_add(svc, 28, 124, 270, 284)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	svc.add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a6cc8")
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.light_energy = 1.6
	sv.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2, 0.5, -1.5)
	rim.light_color = UI.CY
	rim.light_energy = 2.0
	rim.omni_range = 6.0
	sv.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 40.0
	sv.add_child(cam)
	cam.position = Vector3(0, 2.0, 4.2)
	cam.look_at(Vector3(0, -0.05, 0), Vector3.UP)
	spin_model = (load("res://assets/models/%s.glb" % ship["id"]) as PackedScene).instantiate()
	spin_model.rotation.y = 2.4
	G.tame_emission(spin_model)
	sv.add_child(spin_model)
	svc.gui_input.connect(func(e):
		if e is InputEventScreenTouch:
			spin_drag = e.pressed
		elif e is InputEventScreenDrag and spin_model:
			spin_model.rotation.y += e.relative.x * 0.012)
	_add(UI.label(String(ship["name"]).to_upper(), 30, UI.INK, "Black"), 306, 176, 210, 40)
	_add(UI.label(String(ship["note"]), 13, UI.MUTE, "Medium"), 306, 216, 210, 20)
	if not unlocked:
		_add(UI.label("Clear world %d to unlock" % (int(ship["unlock"]) + 1), 14, UI.OR, "Bold"), 306, 256, 210, 22)
	elif view_ship == cur:
		var sel := UI.button("SELECTED", 13, "primary", 21)
		sel.disabled = false
		sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_add(sel, 306, 250, 136, 42)
	else:
		var use := UI.button("USE THIS SHIP", 13, "accent", 21)
		use.pressed.connect(func():
			G.data["ship"] = view_ship
			G.save()
			_refresh_demo()
			show_screen("ships"))
		_add(use, 306, 250, 160, 42)
	_add(UI.label("Drag to spin", 12, UI.MUTE, "Medium"), 306, 320, 200, 18)
	var count := 0
	for i in G.SHIPS.size():
		if G.ship_unlocked(i):
			count += 1
	_add(UI.label("HANGAR", 11, UI.CY), 20, 438, 200, 18)
	_add(UI.label("%d / %d UNLOCKED" % [count, G.SHIPS.size()], 11, UI.MUTE, "Bold", HORIZONTAL_ALIGNMENT_RIGHT), 320, 438, 200, 18)
	for i in G.SHIPS.size():
		var s: Dictionary = G.SHIPS[i]
		var ok: bool = G.ship_unlocked(i)
		var x := 20.0 + (i % 3) * 170.0
		var y := 466.0 + (i / 3) * 200.0
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var sbx := UI.box(UI.PANEL if ok else UI.PANEL2, UI.CY if i == view_ship else (UI.LINE if ok else UI.LINE2), 14, 3 if i == view_ship else 2)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sbx)
		b.pressed.connect(func():
			Sfx.play("tap", -6.0)
			view_ship = i
			show_screen("ships"))
		_add(b, x, y, 160, 188)
		var tr := TextureRect.new()
		tr.texture = load("res://assets/thumbs/%s.png" % s["id"])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(1, 1, 1, 1.0 if ok else 0.4)
		b.add_child(UI.place(tr, 8, 4, 144, 140))
		b.add_child(UI.place(UI.label(String(s["name"]).to_upper(), 14, UI.INK if ok else UI.DIM, "Black", HORIZONTAL_ALIGNMENT_CENTER), 0, 140, 160, 20))
		var sub := "Tap to view"
		if i == cur:
			sub = "In use"
		elif not ok:
			sub = "Clear world %d" % (int(s["unlock"]) + 1)
		b.add_child(UI.place(UI.label(sub, 11, UI.CY if i == cur else (UI.MUTE if ok else UI.DIM), "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, 160, 160, 18))
	_add(UI.label("FLAME COLOUR", 11, UI.CY), 20, 882, 200, 18)
	_add(UI.panel(), 20, 906, 500, 92)
	for i in G.FLAMES.size():
		var fl: Dictionary = G.FLAMES[i]
		var on := i == int(G.data["flame"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var sb := UI.box(fl["a"], UI.INK if on else Color(0, 0, 0, 0), 22, 3)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		b.pressed.connect(func():
			Sfx.play("tap", -6.0)
			G.data["flame"] = i
			G.save()
			_refresh_demo()
			show_screen("ships"))
		_add(b, 58 + i * 126, 918, 44, 44)
		_add(UI.label(String(fl["name"]), 12, UI.INK if on else UI.MUTE, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 30 + i * 126, 968, 100, 18)
	var note := UI.label("Ships change the look only. Every ship flies the same, so road times stay fair.", 13, UI.MUTE, "Medium", HORIZONTAL_ALIGNMENT_CENTER)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(note, 60, 1020, 420, 44)

func _refresh_demo() -> void:
	if play and is_instance_valid(play):
		play.free()
	play = null

# ------------------------------------------------------------------ controls + settings

func _toggle(text: String, y: float, key: String, after := Callable()) -> void:
	_add(UI.panel(), 20, y, 500, 54)
	_add(UI.label(text, 15, UI.INK, "Bold"), 40, y + 16, 320, 22)
	var on := bool(G.data[key])
	var b := UI.button("ON" if on else "OFF", 13, "primary" if on else "ghost", 18)
	b.pressed.connect(func():
		G.data[key] = not bool(G.data[key])
		G.save()
		if after.is_valid():
			after.call()
		show_screen(screen))
	_add(b, 432, y + 9, 72, 36)

func _controls() -> void:
	_header("CONTROLS")
	var opts := [
		["invisible", "INVISIBLE", [["LEFT HALF", "Drag left / right to steer"], ["LEFT HALF, UP / DOWN", "Push up to speed up, down to brake"], ["RIGHT HALF", "Tap anywhere to jump"]]],
		["buttons", "BUTTONS", [["BOTTOM SECTION", "Left and right steer buttons"], ["MIDDLE", "Speed up / slow down"], ["RIGHT", "Big jump button"]]],
	]
	for k in opts.size():
		var o: Array = opts[k]
		var y := 116.0 + k * 322.0
		var sel: bool = String(G.data["controls"]) == o[0]
		_add(UI.panel(UI.PANEL, UI.CY if sel else UI.LINE, 16, 3 if sel else 2), 20, y, 500, 308)
		var m := Mini.new()
		m.kind = o[0]
		_add(m, 40, y + 24, 136, 260)
		_add(UI.label(o[1], 22, UI.INK, "Black"), 198, y + 26, 300, 30)
		for li in 3:
			_add(UI.label(o[2][li][0], 11, UI.CY if sel else UI.MUTE), 198, y + 72 + li * 52, 300, 16)
			_add(UI.label(o[2][li][1], 14, UI.INK, "Medium"), 198, y + 90 + li * 52, 310, 20)
		var b := UI.button("SELECTED" if sel else "USE THIS", 13, "primary" if sel else "ghost", 20)
		var key: String = o[0]
		b.pressed.connect(func():
			G.data["controls"] = key
			G.save()
			show_screen("controls"))
		_add(b, 198, y + 240, 130, 42)
	_toggle("Vibration on jump and crash", 772, "vibration")
	_toggle("Left-handed (swap sides)", 836, "left_handed")
	_add(UI.panel(), 20, 900, 500, 54)
	_add(UI.label("Steering sensitivity", 15, UI.INK, "Bold"), 40, 916, 220, 22)
	var sl := HSlider.new()
	sl.min_value = 0.6
	sl.max_value = 1.8
	sl.step = 0.05
	sl.value = float(G.data["sens"])
	sl.focus_mode = Control.FOCUS_NONE
	var trk := UI.box(UI.LINE2, Color(0, 0, 0, 0), 3)
	trk.content_margin_top = 3
	trk.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", trk)
	var fill := UI.box(UI.CY, Color(0, 0, 0, 0), 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.value_changed.connect(func(v):
		G.data["sens"] = v
		G.save())
	_add(sl, 300, 912, 200, 30)

func _settings() -> void:
	_header("SETTINGS")
	_add(UI.label("FRAME RATE", 11, UI.CY), 20, 122, 200, 18)
	_add(UI.panel(), 20, 144, 500, 128)
	for k in 3:
		var fps: int = [30, 60, 120][k]
		var on := int(G.data["fps"]) == fps
		var b := UI.button("%d FPS" % fps, 16, "primary" if on else "ghost")
		b.pressed.connect(func():
			G.data["fps"] = fps
			G.apply_fps()
			G.save()
			show_screen("settings"))
		_add(b, 36 + k * 158, 160, 150, 56)
	_add(UI.label("Steering and jumps feel the same at every setting. 120 needs a 120 Hz screen.", 12, UI.MUTE, "Medium"), 36, 228, 470, 30)
	_add(UI.label("SOUND", 11, UI.CY), 20, 296, 200, 18)
	_toggle("Music", 318, "music", func(): Sfx.refresh_music())
	_toggle("Sound effects", 382, "sfx")
	_add(UI.label("GAME", 11, UI.CY), 20, 462, 200, 18)
	_toggle("Vibration", 484, "vibration")
	_add(UI.panel(), 20, 566, 500, 150)
	_add(UI.label("ORBIT ROADS", 18, UI.INK, "Black"), 40, 584, 300, 26)
	var about := UI.label("10 worlds · 30 roads · 6 ships. Fully offline, no ads, no purchases. Progress and best times are saved on this phone.", 13, UI.MUTE, "Medium")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add(about, 40, 616, 460, 80)

# ------------------------------------------------------------------ screenshots for testing

func _run_shot() -> void:
	var parts := shot.split(":")
	var kind := parts[0]
	var idx := int(parts[1]) if parts.size() > 1 else 0
	if kind in ["home", "roads", "ships", "controls", "settings"]:
		show_screen(kind)
		return
	start_road(idx)
	if kind == "soak":
		play.autopilot = true
		play.sim.target = 10.0
		for a2 in OS.get_cmdline_user_args():
			if a2.begins_with("tgt="):
				play.sim.target = float(a2.split("=")[1])
	elif kind == "touchtest":
		pass
	elif kind == "tunnel":
		for r in play.sim.n:
			if not play.sim.spans[r].is_empty():
				play.sim.z = (r - 3.2) * 1.5
				play.sim.speed = 9.0
				play.cur = Vector3(0, 0, play.sim.z)
				play.prev = play.cur
				break
		shot = "play"
	elif kind == "pause":
		play.toggle_pause.call_deferred()
	elif kind == "clear":
		play.sim.time = 14.2
		play.sim.fuel = 0.46
		play.sim.air = 0.61
		play._clear.call_deferred()
		shot_t = -1.2
	elif kind == "fail":
		play.sim.fail = "burn"
		play.sim.z = 40.0
		play._crash.call_deferred()
		shot_t = -1.5

var _tt := 0
func _tev(i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i; e.position = pos; e.pressed = pressed
	Input.parse_input_event(e)

func _touch_test() -> void:
	_tt += 1
	var t = play.touch
	var btn: bool = t.layout == "buttons"
	var a := Vector2(186, 1060) if btn else Vector2(110, 900)
	var b := Vector2(436, 1060) if btn else Vector2(420, 700)
	if _tt == 4:
		_tev(0, Vector2(44, 68), true)
		_tev(0, Vector2(44, 68), false)
	elif _tt == 8:
		print("PAUSE state=%s (expect paused)" % play.state)
		play.toggle_pause()
	elif _tt == 12:
		_tev(0, a, true)
	elif _tt == 14:
		if not btn:
			var d := InputEventScreenDrag.new(); d.index = 0; d.position = a + Vector2(60, -60); d.relative = Vector2(60, -60)
			Input.parse_input_event(d)
		_tev(1, b, true)
	elif _tt == 17:
		print("TOUCH %s steer=%.2f throttle=%.2f jump=%s (expect steer 1.00, jump true)" % [t.layout, t.steer, t.throttle, t.jump])
		_tev(0, a, false)
		_tev(1, b, false)
	elif _tt == 21:
		print("TOUCH released steer=%.2f jump=%s (expect 0, false)" % [t.steer, t.jump])
		get_tree().quit()
