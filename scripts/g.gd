extends Node
## Global state: road data, settings, save file.

const SAVE := "user://save.json"
const SHIPS := [
	{"id": "orbit", "name": "Orbit", "unlock": -1, "note": "Starter ship · round body"},
	{"id": "kestrel", "name": "Kestrel", "unlock": -1, "note": "Twin-fin jet"},
	{"id": "bubble", "name": "Bubble", "unlock": 2, "note": "Ball with a ring"},
	{"id": "manta", "name": "Manta", "unlock": 4, "note": "Wide glider"},
	{"id": "halo", "name": "Halo", "unlock": 6, "note": "Ring ship"},
	{"id": "gemini", "name": "Gemini", "unlock": 8, "note": "Twin hull"},
]
const FLAMES := [
	{"name": "Ember", "a": Color("ff5a10"), "b": Color("ffd27a")},
	{"name": "Ion", "a": Color("129cff"), "b": Color("c8f4ff")},
	{"name": "Plasma", "a": Color("ff3fa0"), "b": Color("ffd0ec")},
	{"name": "Toxic", "a": Color("35d05a"), "b": Color("e0ffd0")},
]

var worlds: Array = []
var roads: Array = []
var data := {
	"cleared": [], "best": [],
	"controls": "invisible", "left_handed": false, "sens": 1.0, "vibration": true,
	"fps": 60, "music": true, "sfx": true, "ship": 0, "flame": 0,
}

func _ready() -> void:
	var f := FileAccess.open("res://data/roads.json", FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text())
	worlds = j["worlds"]
	roads = j["roads"]
	for i in roads.size():
		data["cleared"].append(false)
		data["best"].append(0.0)
	_load()
	apply_fps()

func _load() -> void:
	if not FileAccess.file_exists(SAVE):
		return
	var f := FileAccess.open(SAVE, FileAccess.READ)
	if f == null:
		return
	var j = JSON.parse_string(f.get_as_text())
	if typeof(j) != TYPE_DICTIONARY:
		return
	for k in data.keys():
		if not j.has(k):
			continue
		if k == "cleared" or k == "best":
			var arr: Array = j[k]
			for i in min(arr.size(), roads.size()):
				data[k][i] = arr[i]
		else:
			data[k] = j[k]
	data["fps"] = int(data["fps"])
	data["ship"] = int(data["ship"])
	data["flame"] = int(data["flame"])

func save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func apply_fps() -> void:
	Engine.max_fps = int(data["fps"])

func road_unlocked(i: int) -> bool:
	return i == 0 or bool(data["cleared"][i - 1])

func world_cleared(w: int) -> bool:
	for r in 3:
		if not bool(data["cleared"][w * 3 + r]):
			return false
	return true

func ship_unlocked(i: int) -> bool:
	var u: int = SHIPS[i]["unlock"]
	return u < 0 or world_cleared(u)

func cleared_count() -> int:
	var c := 0
	for v in data["cleared"]:
		if v:
			c += 1
	return c

func next_road() -> int:
	for i in roads.size():
		if not bool(data["cleared"][i]):
			return i
	return roads.size() - 1

## Records a cleared road. Returns [is_new_best, newly_unlocked_ship_names].
func record(i: int, t: float) -> Array:
	var before := []
	for s in SHIPS.size():
		before.append(ship_unlocked(s))
	var best: float = data["best"][i]
	var new_best := best <= 0.0 or t < best
	if new_best:
		data["best"][i] = t
	data["cleared"][i] = true
	var unlocked := []
	for s in SHIPS.size():
		if ship_unlocked(s) and not before[s]:
			unlocked.append(SHIPS[s]["name"])
	save()
	return [new_best, unlocked]

func vibrate(ms: int) -> void:
	if bool(data["vibration"]):
		Input.vibrate_handheld(ms)

func fmt_time(t: float) -> String:
	var m := int(t) / 60
	return "%d:%04.1f" % [m, t - m * 60]

func mesh_of(path: String) -> Mesh:
	var sc: Node = (load(path) as PackedScene).instantiate()
	var m := _find_mesh(sc)
	sc.free()
	return m

func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return n.mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m:
			return m
	return null

## Blender exports emission stronger than the phone renderer needs; scale it once per material.
func tame_emission(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		for i in n.mesh.get_surface_count():
			var m = n.mesh.surface_get_material(i)
			if m is BaseMaterial3D and m.emission_enabled and not m.has_meta("tamed"):
				m.emission_energy_multiplier = minf(m.emission_energy_multiplier, 6.0) * 0.4
				m.set_meta("tamed", true)
	for c in n.get_children():
		tame_emission(c)
