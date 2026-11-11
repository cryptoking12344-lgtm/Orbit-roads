extends RefCounted
## Pure game logic for one road. Runs at a fixed 60 Hz tick, no nodes involved,
## so it can also be simulated headless by the test bot.
##
## Coordinates: x = lanes from the centre (-3.5 .. 3.5), y = height of the ship's
## underside, z = distance travelled. One tile is 1 wide and TL long.

const TL := 1.5
const MAXSPD := 15.0
const MINSPD := 4.5   # the ship can slow down but never stops dead
const HW := 0.3      # half width used for collisions
const H := 0.42      # ship height
const NOSE := 0.45
const STEP := 0.14   # how high a ledge the ship rides over without crashing
const BLOCK_H := 0.6

var rows := PackedStringArray()
var spans: Array = []
var n := 0
var gravity := 1.0
var finish_z := 0.0
var tank := 260.0
var air_time := 45.0

var x := 0.0
var y := 0.0
var z := 0.0
var vy := 0.0
var speed := 0.0
var target := 8.0
var fuel := 1.0
var air := 1.0
var time := 0.0
var on_ground := true
var alive := true
var finished := false
var fail := ""
var coyote := 0.0
var jump_buf := 0.0
var cur_tile := ""
var last_fx := ""
var events: Array = []

func setup(road: Dictionary) -> void:
	rows = PackedStringArray()
	spans = []
	for r in road["rows"]:
		var parts := String(r).split("|")
		rows.append(parts[0])
		var sp: Array = []
		if parts.size() > 1:
			for s in parts[1].split(","):
				var ab := s.split("-")
				sp.append(Vector2i(int(ab[0]), int(ab[1])))
		spans.append(sp)
	n = rows.size()
	gravity = float(road["gravity"])
	finish_z = (n - 3) * TL
	tank = maxf(240.0, n * TL * 1.3)
	air_time = maxf(38.0, n * TL / 9.0 * 1.9)
	reset()

func reset() -> void:
	x = 0.0; y = 0.0; z = TL * 2.5; vy = 0.0
	speed = 0.0; target = 8.0; fuel = 1.0; air = 1.0; time = 0.0
	on_ground = true; alive = true; finished = false; fail = ""
	coyote = 0.0; jump_buf = 0.0; cur_tile = ""; last_fx = ""
	events = []

func copy():
	var s = get_script().new()
	s.rows = rows; s.spans = spans; s.n = n; s.gravity = gravity
	s.finish_z = finish_z; s.tank = tank; s.air_time = air_time
	s.x = x; s.y = y; s.z = z; s.vy = vy; s.speed = speed; s.target = target
	s.fuel = fuel; s.air = air; s.time = time; s.on_ground = on_ground
	s.alive = alive; s.finished = finished; s.fail = fail
	s.coyote = coyote; s.jump_buf = jump_buf; s.cur_tile = cur_tile; s.last_fx = last_fx
	return s

func tile(lane: int, row: int) -> String:
	if row < 0 or row >= n or lane < 0 or lane > 6:
		return "."
	return rows[row][lane]

## Solid height intervals (bottom, top) at a point.
func solids(px: float, pz: float) -> Array:
	var out: Array = []
	var row := int(floor(pz / TL))
	if row < 0 or row >= n:
		return out
	var lane := int(floor(px + 3.5))
	if lane >= 0 and lane <= 6:
		var c := rows[row][lane]
		if c != ".":
			out.append(Vector2(-0.3, BLOCK_H if c == "X" else 0.0))
	for s in spans[row]:
		var left: float = s.x - 3.5
		var right: float = s.y + 1 - 3.5
		if px > left and px < right:
			var rad := (right - left) * 0.5
			var dx := px - (left + right) * 0.5
			var a := sqrt(maxf(0.0, rad * rad - dx * dx))
			out.append(Vector2(maxf(0.0, a - 0.1), a + 0.12))
	return out

func overlap(px: float, pz: float, lo: float, hi: float) -> bool:
	for s in solids(px, pz):
		if s.y > lo and s.x < hi:
			return true
	return false

func _die(reason: String) -> void:
	alive = false
	fail = reason
	events.append("die")

func progress() -> float:
	return clampf(z / finish_z, 0.0, 1.0)

func step(dt: float, steer: float, throttle: float, jump: bool) -> void:
	events = []
	if not alive or finished:
		return
	time += dt
	target = clampf(target + throttle * 9.0 * dt, MINSPD, MAXSPD)
	var st := clampf(steer, -1.0, 1.0)
	if on_ground and cur_tile == "I":
		st = 0.0

	# speed
	if fuel > 0.0:
		if speed < target:
			speed = minf(target, speed + 8.0 * dt)
		elif speed > target:
			speed = maxf(target, speed - (12.0 if throttle < -0.2 else 4.0) * dt)
	else:
		speed = maxf(0.0, speed - 3.0 * dt)
		if speed <= 0.05 and on_ground:
			_die("fuel")
			return

	# sideways
	var nx := clampf(x + st * 5.2 * dt, -3.9, 3.9)
	if nx != x:
		# check both wing tips and the centre so the ship can never slide into a wall
		for ox in [-HW, 0.0, HW]:
			if overlap(nx + ox, z, y + STEP, y + H) or overlap(nx + ox, z + NOSE * 0.8, y + STEP, y + H):
				nx = x
				break

	# forward
	var nz := z + speed * dt
	for ox in [0.0, -HW * 0.8, HW * 0.8]:
		if overlap(nx + ox, nz + NOSE, y + STEP, y + H):
			x = nx; z = nz
			_die("hit")
			return

	# vertical
	vy -= 20.0 * gravity * dt
	var ny := y + vy * dt
	var floor_y := -1000.0
	var ceil_y := 1000.0
	for ox in [0.0, -HW * 0.7, HW * 0.7]:
		for s in solids(nx + ox, nz):
			if s.y <= y + STEP:
				floor_y = maxf(floor_y, s.y)
			elif s.x >= y + H - 0.05:
				ceil_y = minf(ceil_y, s.x)
	if ny <= floor_y:
		if not on_ground and vy < -2.5:
			events.append("land")
			# landed right on the lip of a tile after a gap
			if solids(nx, nz - 0.28).is_empty() and floor_y < 0.01:
				events.append("near")
		ny = floor_y
		vy = 0.0
		on_ground = true
		coyote = 0.1
	else:
		on_ground = false
		coyote -= dt
	if ny + H > ceil_y:
		ny = ceil_y - H
		vy = minf(vy, 0.0)

	# jump (held = keeps hopping, like the original)
	jump_buf = 0.12 if jump else jump_buf - dt
	if jump_buf > 0.0 and coyote > 0.0:
		vy = 7.0
		on_ground = false
		coyote = 0.0
		jump_buf = 0.0
		events.append("jump")
		if solids(nx, nz + 0.22).is_empty():
			events.append("near")

	x = nx; y = ny; z = nz

	# tile effects
	cur_tile = ""
	if on_ground and absf(y) < 0.01:
		cur_tile = tile(int(floor(x + 3.5)), int(floor(z / TL)))
		match cur_tile:
			"B":
				speed = minf(21.0, speed + 22.0 * dt)
			"S":
				speed = maxf(3.5, speed - 16.0 * dt)
			"F":
				_die("burn")
				return
			"O":
				fuel = 1.0
				air = 1.0
		if cur_tile != last_fx and cur_tile in ["B", "S", "I", "O"]:
			events.append({"B": "boost", "S": "slow", "I": "slick", "O": "refill"}[cur_tile])
	if on_ground:
		last_fx = cur_tile

	fuel = maxf(0.0, fuel - speed * dt / tank)
	air = maxf(0.0, air - dt / air_time)
	if air <= 0.0:
		_die("air")
		return
	if y < -3.2:
		_die("fell")
		return
	if z >= finish_z:
		finished = true
		events.append("finish")
