extends Node3D
## One road: builds the 3D world from road data, runs the fixed-tick simulation,
## and draws it interpolated so 30 / 60 / 120 fps all feel the same.

signal exit(dest: String)   # "roads", "retry", "next"

const SimC = preload("res://scripts/sim.gd")
const UI = preload("res://scripts/ui.gd")
const TouchC = preload("res://scripts/touch.gd")
const HudC = preload("res://scripts/hud.gd")
const Pilot = preload("res://scripts/pilot.gd")
const TL := 1.5
const FOV := 71.5
const SPECIAL := {
	"B": [Color("12c8ff"), 2.4], "S": [Color("8a4fff"), 2.2], "I": [Color("dce4ff"), 1.0],
	"F": [Color("ff5a10"), 2.8], "O": [Color("2f6bff"), 2.8],
}
const FAIL_TEXT := {
	"hit": ["CRASHED", "You hit a wall head-on. Steer around it or jump earlier."],
	"burn": ["BURNED", "Orange tiles destroy the ship. Jump over them or go around."],
	"fell": ["FELL OFF", "You missed the road. Line up before you jump."],
	"fuel": ["OUT OF FUEL", "Slow down to save fuel, and grab blue refill tiles."],
	"air": ["OUT OF AIR", "Air runs out with time. Speed up, and grab blue refill tiles."],
}

var road_i := 0
var demo := false
var autopilot := false
var _act: Array = [0.0, false]
var _tick := 0
var _hold := 0
var road: Dictionary
var sim
var state := "play"
var prev := Vector3.ZERO
var cur := Vector3.ZERO

var ship_root: Node3D
var ship_tilt: Node3D
var flames: Array = []
var flame_mats: Array = []
var cam: Camera3D
var sky_quad: MeshInstance3D
var sky_mat: ShaderMaterial
var planet: MeshInstance3D
var moon: MeshInstance3D
var shadow: MeshInstance3D
var ship_light: OmniLight3D
var boom_light: OmniLight3D

var layer: CanvasLayer
var hud
var touch
var overlay: Control
var flash: ColorRect
var pause_btn: Button

var shake := 0.0
var slow_until := 0
var near_cool := 0.0
var clock := 0.0
var end_t := 0.0
var beep_t := 0.0
var last_ms := 0
var panel_shown := false
var record_res: Array = [false, []]

func setup(i: int, is_demo := false) -> void:
	road_i = i
	demo = is_demo

func _ready() -> void:
	road = G.roads[road_i]
	sim = SimC.new()
	sim.setup(road)
	_build_env()
	_build_road()
	_build_ship()
	if not demo:
		_build_ui()
		Sfx.music("music_%d" % (int(road["world"]) % 3 + 1))
	cur = Vector3(sim.x, sim.y, sim.z)
	prev = cur
	last_ms = Time.get_ticks_msec()
	if not demo:
		_prewarm()
	_process(0.0)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Sfx.engine(false)

# ------------------------------------------------------------------ building

func _theme() -> Dictionary:
	return G.worlds[int(road["world"])]

func _build_env() -> void:
	var seam := Color(String(_theme()["seam"]))
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = seam.darkened(0.55)
	psm.sky_horizon_color = seam.lerp(Color.WHITE, 0.25)
	psm.ground_horizon_color = seam.darkened(0.3)
	psm.ground_bottom_color = Color(0.01, 0.01, 0.03)
	psm.sun_angle_max = 0.0
	sky.sky_material = psm
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.05
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(0.92, 0.95, 1.0)
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 900.0
	add_child(cam)
	cam.make_current()

	var w := int(road["world"]) + 1
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D tex : source_color, repeat_enable, filter_linear;
uniform vec2 off = vec2(0.0);
void fragment() {
	ALBEDO = texture(tex, UV * 0.9 + vec2(0.05) + off).rgb;
}"""
	sky_mat.shader = sh
	sky_mat.render_priority = -20
	sky_mat.set_shader_parameter("tex", load("res://assets/sky/w%02d.jpg" % w))
	sky_quad = MeshInstance3D.new()
	sky_quad.mesh = QuadMesh.new()
	sky_quad.material_override = sky_mat
	sky_quad.position = Vector3(0, 0, -600)
	cam.add_child(sky_quad)
	planet = _billboard("res://assets/planet/p%02d.png" % w, -560.0)
	moon = _billboard("res://assets/planet/m%02d.png" % w, -570.0)

func _billboard(path: String, z: float) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load(path)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 5
	var q := MeshInstance3D.new()
	q.mesh = QuadMesh.new()
	q.material_override = m
	q.position = Vector3(0, 0, z)
	cam.add_child(q)
	return q

func _metal(col: Color, metallic := 0.55, rough := 0.42) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	return m

func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m

func _mm(mesh: Mesh, mat: Material, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)

func _arch(rad: float, cx: float, z0: float, z1: float, mat: Material, segs := 24) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var n0 := Vector3(cos(a0), sin(a0), 0)
		var n1 := Vector3(cos(a1), sin(a1), 0)
		var c := Vector3(cx, 0, 0)
		var v := [c + n0 * rad + Vector3(0, 0, -z0), c + n1 * rad + Vector3(0, 0, -z0),
			c + n1 * rad + Vector3(0, 0, -z1), c + n0 * rad + Vector3(0, 0, -z1)]
		var ns := [n0, n1, n1, n0]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(ns[k])
			st.add_vertex(v[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

func _build_road() -> void:
	var th := _theme()
	var seam := Color(String(th["seam"]))
	var tile_mesh := G.mesh_of("res://assets/models/tile.glb")
	var block_mesh := G.mesh_of("res://assets/models/block.glb")
	var a: Array = []
	var b: Array = []
	var seams: Array = []
	var blocks: Array = []
	var spec := {}
	for k in SPECIAL:
		spec[k] = []
	for r in sim.n:
		var zc: float = -(r + 0.5) * TL
		for lane in 7:
			var c: String = sim.rows[r][lane]
			if c == ".":
				continue
			var x := lane - 3.0
			(a if (lane + r) % 2 == 0 else b).append(Transform3D(Basis(), Vector3(x, -0.15, zc)))
			seams.append(Transform3D(Basis(), Vector3(x, -0.12, zc)))
			if spec.has(c):
				spec[c].append(Transform3D(Basis(), Vector3(x, 0.004, zc)))
			if c == "X":
				blocks.append(Transform3D(Basis().scaled(Vector3(1, SimC.BLOCK_H / 0.9, 1)), Vector3(x, SimC.BLOCK_H * 0.5, zc)))
	_mm(tile_mesh, _metal(Color(String(th["tile"][0]))), a)
	_mm(tile_mesh, _metal(Color(String(th["tile"][1]))), b)
	var seam_mesh := BoxMesh.new()
	seam_mesh.size = Vector3(1.0, 0.04, TL)
	_mm(seam_mesh, _glow(seam, 1.7), seams)
	var sp_mesh := BoxMesh.new()
	sp_mesh.size = Vector3(0.8, 0.02, TL - 0.22)
	for k in SPECIAL:
		_mm(sp_mesh, _glow(SPECIAL[k][0], SPECIAL[k][1]), spec[k])
	_mm(block_mesh, _metal(Color("5b64a8"), 0.8, 0.3), blocks)

	# tunnels: merge consecutive rows that share a span
	var shell := _metal(Color("39406f"), 0.85, 0.35)
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rib_dark := _metal(Color("3a4170"), 0.9, 0.3)
	rib_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rib_glow := _glow(Color("12c8ff"), 2.6)
	rib_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var open := {}
	for r in sim.n + 1:
		var here := {}
		if r < sim.n:
			for s in sim.spans[r]:
				here["%d-%d" % [s.x, s.y]] = s
		for key in open.keys():
			if not here.has(key):
				var s: Vector2i = open[key][0]
				var r0: int = open[key][1]
				var rad := (s.y - s.x + 1) * 0.5
				var cx := (s.x + s.y + 1) * 0.5 - 3.5
				_arch(rad, cx, r0 * TL, r * TL, shell)
				for k in range(r0, r + 1):
					var edge: bool = k == r0 or k == r
					_arch(rad + 0.07, cx, k * TL - (0.1 if edge else 0.06), k * TL + (0.1 if edge else 0.06), rib_glow if edge else rib_dark)
				open.erase(key)
		for key in here:
			if not open.has(key):
				open[key] = [here[key], r]
	# finish gate
	var gate := _glow(Color("eaffff"), 3.0)
	gate.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arch(3.75, 0.0, sim.finish_z - 0.15, sim.finish_z + 0.15, gate, 40)
	_arch(4.0, 0.0, sim.finish_z - 0.06, sim.finish_z + 0.06, _glow(seam, 3.0), 40)

func _build_ship() -> void:
	ship_root = Node3D.new()
	add_child(ship_root)
	ship_tilt = Node3D.new()
	ship_root.add_child(ship_tilt)
	var id: String = G.SHIPS[int(G.data["ship"])]["id"]
	var model: Node3D = (load("res://assets/models/%s.glb" % id) as PackedScene).instantiate()
	model.scale = Vector3.ONE * 0.6
	G.tame_emission(model)
	ship_tilt.add_child(model)
	var fl: Dictionary = G.FLAMES[int(G.data["flame"])]
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col_a : source_color;
uniform vec4 col_b : source_color;
uniform float power = 1.0;
varying float k;
void vertex() { k = clamp(0.5 - VERTEX.y, 0.0, 1.0); }
void fragment() {
	float f = k * k;
	ALBEDO = mix(col_a.rgb, col_b.rgb, f) * (0.6 + 0.55 * f) * power;
	ALPHA = clamp(k * 1.4, 0.0, 1.0);
}"""
	for ex in _find_exhausts(model):
		var holder := Node3D.new()
		ex.add_child(holder)
		for spec in [[0.115, 1.0, 1.0], [0.06, 0.62, 1.8]]:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = spec[0]
			cone.height = spec[1]
			cone.radial_segments = 14
			cone.rings = 1
			var mat := ShaderMaterial.new()
			mat.shader = sh
			mat.set_shader_parameter("col_a", fl["a"])
			mat.set_shader_parameter("col_b", fl["b"])
			mat.set_shader_parameter("power", spec[2])
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = mat
			mi.rotation_degrees = Vector3(90, 0, 0)
			mi.position = Vector3(0, 0, spec[1] * 0.5)
			holder.add_child(mi)
			flame_mats.append(mat)
		flames.append(holder)
	ship_light = OmniLight3D.new()
	ship_light.light_color = fl["a"]
	ship_light.light_energy = 1.6
	ship_light.omni_range = 3.2
	ship_light.position = Vector3(0, 0.1, 1.1)
	ship_root.add_child(ship_light)

	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	shadow.mesh = q
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	var sm := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float a = 0.5;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = a * smoothstep(1.0, 0.25, d);
}"""
	sm.shader = ssh
	shadow.material_override = sm
	add_child(shadow)

func _find_exhausts(n: Node) -> Array:
	var out: Array = []
	if String(n.name).begins_with("Exhaust"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_exhausts(c))
	return out

func _build_ui() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	touch = TouchC.new()
	layer.add_child(touch)
	hud = HudC.new()
	hud.title = "ROAD %d-%d · %s" % [int(road["world"]) + 1, road_i % 3 + 1, String(road["name"]).to_upper()]
	layer.add_child(hud)
	pause_btn = UI.button("II", 20)
	UI.place(pause_btn, 20, 44, 48, 48)
	pause_btn.pressed.connect(toggle_pause)
	layer.add_child(pause_btn)
	flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)

# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if demo or state != "play":
		return
	prev = cur
	var s := 0.0
	var t := 0.0
	var j := false
	if touch:
		s = touch.steer; t = touch.throttle; j = touch.jump
	if autopilot:
		if _tick % 4 == 0:
			_act = Pilot.plan(sim)
			_hold = 3 if _act[1] else 0
		_tick += 1
		s = _act[0]
		j = _hold > 0
		_hold -= 1
	sim.step(delta, s, t, j)
	cur = Vector3(sim.x, sim.y, sim.z)
	for e in sim.events:
		_on_event(e)

func _on_event(e: String) -> void:
	match e:
		"jump":
			Sfx.play("jump", -5.0)
		"land":
			Sfx.play("land", -4.0)
			G.vibrate(12)
		"boost":
			Sfx.play("boost", -3.0)
			hud.show_banner("BOOST")
		"slow":
			Sfx.play("slow", -5.0)
		"slick":
			Sfx.play("slick", -6.0)
		"refill":
			Sfx.play("refill", -2.0)
			hud.show_banner("REFILL")
		"near":
			if near_cool <= 0.0:
				near_cool = 5.0
				slow_until = Time.get_ticks_msec() + 280
				Sfx.play("near", -4.0)
				hud.show_banner("CLOSE!")
		"die":
			_crash()
		"finish":
			_clear()

func _crash() -> void:
	state = "dead"
	end_t = 0.0
	Engine.time_scale = 1.0
	slow_until = 0
	touch.enabled = false
	if sim.fail != "fell":
		ship_tilt.visible = false
		ship_light.visible = false
		_explode()
		shake = 1.0
		Sfx.play("burn" if sim.fail == "burn" else "crash")
		G.vibrate(320)
	else:
		Sfx.play("slow", -2.0, 0.7)
		G.vibrate(120)

## Draw the explosion once, out of sight, so its shaders are compiled before the first crash.
func _prewarm() -> void:
	var here := ship_root.position
	ship_root.position = Vector3(0, -40, -sim.z - 30)
	_explode()
	ship_root.position = here
	boom_light.queue_free()
	boom_light = null

func _explode() -> void:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	p.mesh = sm
	p.material_override = _glow(Color("ff7a1a"), 4.0)
	p.amount = 80
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 1.1
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -7, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.position = ship_root.position
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)
	boom_light = OmniLight3D.new()
	boom_light.light_color = Color("ff9a3a")
	boom_light.light_energy = 9.0
	boom_light.omni_range = 9.0
	boom_light.position = ship_root.position + Vector3(0, 0.6, 0)
	add_child(boom_light)

func _clear() -> void:
	state = "clear"
	end_t = 0.0
	Engine.time_scale = 1.0
	slow_until = 0
	touch.enabled = false
	record_res = G.record(road_i, sim.time)
	Sfx.play("clear")
	G.vibrate(70)
	flash.color = Color(1, 1, 1, 0.85)
	var tw := create_tween()
	tw.tween_property(flash, "color", Color(1, 1, 1, 0), 0.7)

func toggle_pause() -> void:
	if state == "play":
		state = "paused"
		Engine.time_scale = 1.0
		slow_until = 0
		_show_pause()
	elif state == "paused":
		_clear_overlay()
		touch.reset()
		touch.hint_t = 0.0
		state = "play"

# ------------------------------------------------------------------ frame update

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real := (now - last_ms) / 1000.0
	last_ms = now
	clock += real
	near_cool = maxf(0.0, near_cool - real)
	if slow_until > 0 and now >= slow_until:
		slow_until = 0
	if state == "play":
		# ease in and out of slow motion so it never feels like a freeze
		Engine.time_scale = move_toward(Engine.time_scale, 0.6 if slow_until > 0 else 1.0, real * 4.0)

	var f := Engine.get_physics_interpolation_fraction() if state == "play" and not demo else 1.0
	var p := prev.lerp(cur, f)
	var steer := 0.0
	if touch and state == "play":
		steer = touch.steer
	ship_root.position = Vector3(p.x, p.y + 0.34 + sin(clock * 3.0) * 0.03, -p.z)
	ship_tilt.rotation.z = lerpf(ship_tilt.rotation.z, -steer * 0.38, minf(1.0, real * 10.0))
	ship_tilt.rotation.x = lerpf(ship_tilt.rotation.x, clampf(sim.vy * 0.035, -0.3, 0.3), minf(1.0, real * 10.0))
	if demo:
		ship_tilt.rotation.y = sin(clock * 0.5) * 0.25

	var sp: float = sim.speed / SimC.MAXSPD
	if demo:
		sp = 0.35
	var flen := 0.45 + sp * 1.25
	for i in flames.size():
		var fl := flen * (0.9 + 0.14 * sin(clock * 47.0 + i * 1.7) + 0.06 * sin(clock * 91.0))
		flames[i].scale = Vector3(1.0, 1.0, fl)
	ship_light.light_energy = 1.0 + sp * 1.6

	# blob shadow on whatever is under the ship
	var floor_y := -100.0
	for s in sim.solids(p.x, p.z):
		if s.y <= p.y + 0.2:
			floor_y = maxf(floor_y, s.y)
	shadow.visible = floor_y > -50.0 and ship_tilt.visible
	if shadow.visible:
		shadow.position = Vector3(p.x, floor_y + 0.02, -p.z)
		(shadow.material_override as ShaderMaterial).set_shader_parameter("a", clampf(0.6 - (p.y - floor_y) * 0.25, 0.1, 0.6))

	# camera
	var buttons: bool = touch != null and touch.layout == "buttons"
	var cx := p.x * 0.8
	var cpos := Vector3(cx, 4.3, -p.z + 5.6)
	var look := Vector3(cx, -1.6 if buttons else 0.0, -p.z - (3.6 if buttons else 5.2))
	if demo:
		cpos = Vector3(sin(clock * 0.25) * 1.6, 3.3, -p.z + 5.2)
		look = Vector3(0, 0.6, -p.z - 4.0)
	if p.y < -0.2 and not demo:
		# follow a fall so the ship stays in view
		look.y += maxf(p.y, -3.5) * 0.9
		cpos.y += maxf(p.y, -3.5) * 0.35
	if shake > 0.0:
		cpos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.35
		shake = maxf(0.0, shake - real * 1.8)
	cam.position = cpos
	cam.look_at(look, Vector3.UP)
	cam.fov = FOV + sp * 7.0
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / vp.y
	var hh := tan(deg_to_rad(cam.fov * 0.5))
	var sky_h := 600.0 * hh * 2.0 * 1.04
	sky_quad.scale = Vector3(maxf(sky_h * 0.5625, 600.0 * hh * 2.0 * aspect * 1.04), sky_h, 1.0)
	sky_mat.set_shader_parameter("off", Vector2(sin(clock * 0.031) * 0.03 + sim.progress() * 0.012, cos(clock * 0.023) * 0.025))
	var ph := 560.0 * hh
	var pw := ph * aspect
	planet.position = Vector3(pw * 0.48 - sim.progress() * pw * 0.12, ph * (0.2 if demo else 0.6) + sin(clock * 0.1) * 3.0, -560.0)
	planet.scale = Vector3.ONE * pw * 1.04
	moon.position = Vector3(-pw * 0.74 - sim.progress() * pw * 0.05, ph * (0.05 if demo else 0.31), -570.0)
	moon.scale = Vector3.ONE * pw * 0.4
	if boom_light:
		boom_light.light_energy = maxf(0.0, boom_light.light_energy - real * 14.0)

	if demo:
		return
	hud.progress = sim.progress()
	hud.fuel = sim.fuel
	hud.air = sim.air
	hud.speed = sim.speed / 21.0
	Sfx.engine(state == "play", sp)
	if state == "play" and (sim.fuel < 0.22 or sim.air < 0.22):
		beep_t -= real
		if beep_t <= 0.0:
			beep_t = 1.1
			Sfx.play("low_air" if sim.air < 0.22 else "low_fuel", -8.0)
	if state == "dead" or state == "clear":
		end_t += real
		var wait := 0.75
		if state == "dead":
			wait = 0.45 if sim.fail == "fell" else 1.2
		if not panel_shown and end_t > wait:
			panel_shown = true
			if state == "dead":
				_show_fail()
			else:
				_show_clear()

# ------------------------------------------------------------------ overlays

func _clear_overlay() -> void:
	for c in overlay.get_children():
		c.queue_free()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _stage(alpha := 0.8) -> Control:
	_clear_overlay()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(UI.backdrop(alpha))
	var st := Control.new()
	var vp := get_viewport().get_visible_rect().size
	st.position = Vector2((vp.x - 540.0) * 0.5, (vp.y - 1170.0) * 0.5)
	st.size = Vector2(540, 1170)
	overlay.add_child(st)
	return st

func _btn(st: Control, text: String, y: float, kind: String, dest: String, h := 58.0) -> Button:
	var b := UI.button(text, 19 if kind == "primary" else 16, kind)
	UI.place(b, 60, y, 420, h)
	if dest == "resume":
		b.pressed.connect(toggle_pause)
	else:
		b.pressed.connect(func(): exit.emit(dest))
	st.add_child(b)
	return b

func _head(st: Control, small: String, big: String, col: Color, y: float) -> void:
	st.add_child(UI.place(UI.label(small, 13, UI.MUTE, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, y, 540, 20))
	st.add_child(UI.place(UI.label(big, 40, col, "Black", HORIZONTAL_ALIGNMENT_CENTER), 0, y + 26, 540, 52))

func _show_pause() -> void:
	var st := _stage()
	_head(st, hud.title, "PAUSED", UI.INK, 360)
	_btn(st, "RESUME", 480, "primary", "resume", 64)
	_btn(st, "RESTART ROAD", 558, "ghost", "retry")
	_btn(st, "ALL ROADS", 630, "ghost", "roads")

func _show_fail() -> void:
	var st := _stage()
	var ft: Array = FAIL_TEXT.get(sim.fail, FAIL_TEXT["hit"])
	_head(st, hud.title, ft[0], UI.OR, 330)
	var tip := UI.label(ft[1], 14, UI.MUTE, "Medium", HORIZONTAL_ALIGNMENT_CENTER)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.add_child(UI.place(tip, 70, 420, 400, 48))
	st.add_child(UI.place(UI.label("You got %d%% of the way" % int(sim.progress() * 100), 14, UI.INK, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, 476, 540, 22))
	_btn(st, "RETRY", 530, "primary", "retry", 64)
	_btn(st, "ALL ROADS", 608, "ghost", "roads")

func _stat(st: Control, x: float, y: float, name: String, value: String, sub: String, bar := -1.0, col := UI.CY) -> void:
	st.add_child(UI.place(UI.panel(), x, y, 140, 104))
	st.add_child(UI.place(UI.label(name, 11, UI.MUTE), x + 14, y + 12, 120, 16))
	st.add_child(UI.place(UI.label(value, 26, UI.INK, "Black"), x + 14, y + 32, 120, 34))
	if bar >= 0.0:
		var bg := Panel.new()
		bg.add_theme_stylebox_override("panel", UI.box(UI.LINE2, Color(0, 0, 0, 0), 3))
		st.add_child(UI.place(bg, x + 14, y + 78, 112, 6))
		var fg := Panel.new()
		fg.add_theme_stylebox_override("panel", UI.box(col, Color(0, 0, 0, 0), 3))
		st.add_child(UI.place(fg, x + 14, y + 78, maxf(6.0, 112 * bar), 6))
	else:
		st.add_child(UI.place(UI.label(sub, 12, UI.CY if sub == "New best" else UI.MUTE, "Medium"), x + 14, y + 72, 120, 18))

func _show_clear() -> void:
	var st := _stage(0.72)
	_head(st, hud.title, "ROAD CLEARED", UI.CY, 300)
	var best: float = G.data["best"][road_i]
	_stat(st, 50, 400, "TIME", G.fmt_time(sim.time), "New best" if record_res[0] else "Best " + G.fmt_time(best))
	_stat(st, 200, 400, "FUEL LEFT", "%d%%" % int(sim.fuel * 100), "", sim.fuel, UI.OR)
	_stat(st, 350, 400, "AIR LEFT", "%d%%" % int(sim.air * 100), "", sim.air, UI.CY)
	var y := 530.0
	for nm in record_res[1]:
		Sfx.play("unlock")
		st.add_child(UI.place(UI.label("New ship unlocked: %s" % nm, 15, UI.OR, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, y, 540, 24))
		y += 30.0
	y += 14.0
	if road_i + 1 < G.roads.size():
		_btn(st, "NEXT ROAD", y, "primary", "next", 64)
	else:
		st.add_child(UI.place(UI.label("Every road cleared. Well flown.", 16, UI.INK, "Bold", HORIZONTAL_ALIGNMENT_CENTER), 0, y + 16, 540, 24))
	_btn(st, "RETRY", y + 78, "ghost", "retry")
	_btn(st, "ALL ROADS", y + 150, "ghost", "roads")
