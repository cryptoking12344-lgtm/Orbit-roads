extends Node
## Sound effects, music and the engine loop.

const NAMES := ["jump", "land", "boost", "slow", "slick", "refill", "crash", "burn", "low_fuel", "low_air", "tap", "unlock", "near", "clear"]
var streams := {}
var pool: Array = []
var music_p: AudioStreamPlayer
var engine_p: AudioStreamPlayer
var cur_music := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		streams[n] = load("res://assets/audio/%s.ogg" % n)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	music_p = AudioStreamPlayer.new()
	music_p.volume_db = -9.0
	add_child(music_p)
	engine_p = AudioStreamPlayer.new()
	var es = load("res://assets/audio/engine.ogg")
	es.loop = true
	engine_p.stream = es
	engine_p.volume_db = -60.0
	add_child(engine_p)

func play(n: String, db := 0.0, pitch := 1.0) -> void:
	if not bool(G.data["sfx"]) or not streams.has(n):
		return
	for p in pool:
		if not p.playing:
			p.stream = streams[n]
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			return
	pool[0].stream = streams[n]
	pool[0].play()

func music(n: String) -> void:
	if not bool(G.data["music"]):
		music_p.stop()
		cur_music = ""
		return
	if n == cur_music and music_p.playing:
		return
	cur_music = n
	var s = load("res://assets/audio/%s.ogg" % n)
	s.loop = true
	music_p.stream = s
	music_p.play()

func refresh_music() -> void:
	var n := cur_music
	cur_music = ""
	if n == "":
		n = "music_menu"
	music(n)

func engine(on: bool, ratio := 0.0) -> void:
	if not on or not bool(G.data["sfx"]):
		if engine_p.playing:
			engine_p.stop()
		return
	if not engine_p.playing:
		engine_p.play()
	engine_p.pitch_scale = 0.7 + ratio * 0.9
	engine_p.volume_db = lerpf(-22.0, -11.0, clampf(ratio, 0.0, 1.0))
