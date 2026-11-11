extends Object
## Look-ahead autopilot used only by the automated tests (never in normal play).

const DT := 1.0 / 60.0
const ACTIONS := [[0.0, false], [0.0, true], [-1.0, false], [1.0, false], [-1.0, true], [1.0, true]]

static func rollout(s, steer: float, jump: bool, ticks: int) -> void:
	for i in ticks:
		if not s.alive or s.finished:
			return
		s.step(DT, steer, 0.0, jump and i < 3)

static func score(s) -> float:
	if s.finished:
		return 1e6
	if not s.alive:
		return -1e6 + s.z
	var lane_c: float = floor(s.x + 3.5) - 3.0
	var v: float = s.z * 10.0 - absf(s.x - lane_c) * 4.0
	if not s.on_ground:
		v -= 2.0
	if s.cur_tile == "S":
		v -= 6.0
	return v

static func plan(sim) -> Array:
	var best := -INF
	var pick: Array = ACTIONS[0]
	for a in ACTIONS:
		for b in ACTIONS:
			var s = sim.copy()
			rollout(s, a[0], a[1], 14)
			rollout(s, b[0], b[1], 14)
			rollout(s, 0.0, false, 16)
			var v := score(s)
			if s.alive and not s.finished:
				var s2 = s.copy()
				rollout(s2, 0.0, true, 20)
				var s3 = s.copy()
				rollout(s3, 0.0, false, 20)
				if not s2.alive and not s3.alive:
					v -= 5e5
			if v > best:
				best = v
				pick = a
	return pick
