extends SceneTree
## Headless check that every road can be cleared.
## Run: godot --headless --path . --script res://tests/bot.gd
## A look-ahead bot plays each road with the real game logic.

const SimC = preload("res://scripts/sim.gd")
const Pilot = preload("res://scripts/pilot.gd")
const DT := 1.0 / 60.0

func play(road: Dictionary, tgt: float) -> Dictionary:
	var sim = SimC.new()
	sim.setup(road)
	sim.target = tgt
	var act: Array = Pilot.ACTIONS[0]
	var hold := 0
	var t := 0
	while sim.alive and not sim.finished and t < 60 * 180:
		if t % 4 == 0:
			act = Pilot.plan(sim)
			hold = 3 if act[1] else 0
		sim.step(DT, act[0], 0.0, hold > 0)
		hold -= 1
		t += 1
	return {"ok": sim.finished, "fail": sim.fail, "time": sim.time, "prog": sim.progress(), "fuel": sim.fuel, "air": sim.air}

func _init() -> void:
	var j = JSON.parse_string(FileAccess.open("res://data/roads.json", FileAccess.READ).get_as_text())
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("road="):
			only = int(a.split("=")[1])
	var fails := 0
	for road in j["roads"]:
		if only >= 0 and int(road["id"]) != only:
			continue
		var res := {}
		for tgt in [9.0, 11.0, 13.0, 7.0, 15.0]:
			res = play(road, tgt)
			res["tgt"] = tgt
			if res["ok"]:
				break
		if not res["ok"]:
			fails += 1
		print("road %2d  g=%.1f rows=%3d  %s  speed=%.0f time=%.1f fuel=%.0f%% air=%.0f%% %s" % [
			int(road["id"]) + 1, float(road["gravity"]), road["rows"].size(), "CLEARED" if res["ok"] else "FAILED at %d%%" % int(res["prog"] * 100),
			res["tgt"], res["time"], res["fuel"] * 100, res["air"] * 100, res["fail"]])
	print("RESULT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
