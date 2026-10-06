extends Node

## Effective health (DefenseCalc, docs/ENGINE.md §10): pool layers against the research/06c test vectors, boss presets,
## enemy scaling with corruption, and a full calculation of an imported build.
## Run: Godot_console.exe --headless --path client res://tests/defense_test.tscn

const FIXTURE: String = "res://tests/fixtures/letools_A83KxJq5.json"

var _failed: int = 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("DEFENSE TEST TIMEOUT")
		get_tree().quit(1))
	_pool_vectors()
	_scaling()
	_presets()
	_build()
	print("DEFENSE TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		print("FAIL: " + message)


func _near(a: float, b: float, message: String, eps: float = 0.01) -> void:
	_check(absf(a - b) <= eps * maxf(1.0, absf(b)), "%s: %s != %s" % [message, str(a), str(b)])


func _layers(endurance: float, threshold: float, mana_before_health: float = 0.0) -> Dictionary:
	return {"health": 1000.0, "mana": 500.0, "ward": 0.0, "endurance": endurance, "threshold": threshold,
		"mana_before_health": mana_before_health, "mana_before_ward": 0.0}


## research/06c §2.7 and §2.9.
func _pool_vectors() -> void:
	var layers: Dictionary = _layers(0.6, 300.0)
	var pool: Dictionary = {"health": 1000.0, "ward": 0.0, "mana": 0.0}
	_near(DefenseCalc.take_damage(layers, pool, 400.0), 400.0, "endurance above threshold")
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 820.0, "endurance across threshold")
	layers = _layers(0.4, 300.0)
	pool = {"health": 200.0, "ward": 0.0, "mana": 0.0}
	_near(DefenseCalc.take_damage(layers, pool, 500.0), 300.0, "endurance below threshold")
	layers = _layers(0.0, 0.0, 0.3)
	pool = {"health": 2000.0, "ward": 0.0, "mana": 500.0}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 700.0, "mana before health")
	_near(float(pool["mana"]), 440.0, "mana spent")
	pool = {"health": 2000.0, "ward": 0.0, "mana": 20.0}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 900.0, "mana before health, little mana")
	layers = _layers(0.0, 0.0)
	pool = {"health": 1000.0, "ward": 300.0, "mana": 0.0}
	_near(DefenseCalc.take_damage(layers, pool, 200.0), 0.0, "ward absorbs")
	_near(float(pool["ward"]), 100.0, "ward left")
	# lethal damage and hits to die
	layers = _layers(0.0, 0.0)
	_near(DefenseCalc.lethal_damage(layers), 1000.0, "lethal without layers")
	_near(DefenseCalc.hits_to_die(layers, 400.0), 2.5, "hits to die")
	layers = _layers(0.6, 300.0)
	# H − T + (1 − e)·(R − (H − T)) = 1000 → R = 700 + 300 / 0.4 = 1450
	_near(DefenseCalc.lethal_damage(layers), 1450.0, "lethal with endurance")
	layers["ward"] = 500.0
	_near(DefenseCalc.lethal_damage(layers), 1950.0, "lethal with ward")


func _scaling() -> void:
	_near(DefenseCalc.zone_penetration(100), 0.75, "area penetration 100")
	_near(DefenseCalc.zone_penetration(40), 0.4, "area penetration 40")
	var s: Dictionary = DefenseCalc.level_scaling(100, 100)
	_near(float(s["original_more"]), 1.0, "same level")
	_near(float(s["level_more"]), 1.22642, "damageModifier(100)", 0.001)
	s = DefenseCalc.level_scaling(50, 50)
	_near(float(s["level_more"]), 1.0 - 0.0778, "damageModifier(50)", 0.001)
	_check(float(DefenseCalc.level_scaling(100, 54)["original_more"]) > 1.0, "authored lower: damage grows")


func _presets() -> void:
	var presets: Array[Dictionary] = DefenseCalc.presets()
	_check(presets.size() > 100, "boss presets loaded: %d" % presets.size())
	var bosses: Dictionary = {}
	for p: Dictionary in presets:
		bosses[str(p["boss"])] = true
	for boss: String in ["Abomination", "God Hunter Argentus", "Rahyeh, The Black Sun", "Frost Lich Formosus", "Lagon, God of Storms",
			"Harton's Husk", "Emperor of Corpses", "The Husk of Elder Gaspar", "Heorot", "Volcanic Shaman", "Aberroth", "Herald of Oblivion"]:
		_check(bosses.has(boss), "preset boss " + boss)
	var p: Dictionary = DefenseCalc.preset("Uber Aterroth|Uber Aterroth 03 Lingering Damage Projectile|0")
	_check(not p.is_empty(), "Uber Aberroth projectile preset")
	if not p.is_empty():
		_near(float(p["base"][5]), 250.0, "projectile base void")
		_near(float(p["damage"][5]), 250.0 * 6.6, "projectile with the boss's damage more", 0.001)
		_check(bool(p["is_hit"]), "projectile is a hit")


func _build() -> void:
	var doc: Dictionary = LEToolsImport.to_build(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))
	LEToolsImport.apply(Build, doc)
	Build.set_defense("attack", "Uber Aterroth|Uber Aterroth 03 Lingering Damage Projectile|0")
	Build.set_defense("area_level", 100)
	Build.set_enemy("corruption", 0)
	var r0: Dictionary = DefenseCalc.compute(Build)
	var raw0: float = float(r0["attack"]["total"])
	_near(raw0, 250.0 * 6.6 * 1.22642, "raw hit at level 100, corruption 0", 0.001)
	Build.set_enemy("corruption", 300)
	var r1: Dictionary = DefenseCalc.compute(Build)
	_near(float(r1["attack"]["total"]), raw0 * (1.0 + 0.01 * Enemy.corruption_power(300)), "corruption scales the hit", 0.001)
	var s0: Dictionary = r0["summary"]
	var s1: Dictionary = r1["summary"]
	_check(float(s0["max_hit"]) > 0.0 and not is_inf(float(s0["max_hit"])), "max hit is finite")
	_near(float(s0["max_hit"]), float(s1["max_hit"]), "max hit does not depend on corruption")
	_check(float(s1["hits"]) < float(s0["hits"]), "corruption: fewer hits to die")
	_check((r0["sections"] as Array).size() >= 5, "sections")
	for section: Dictionary in r1["sections"]:
		print("== " + str(section["title"]))
		for row: Dictionary in section["rows"]:
			print("  %s: %s" % [row["label"], row["text"]])
	# a DoT preset
	for p: Dictionary in DefenseCalc.presets():
		if not bool(p["is_hit"]) and float(p["interval"]) > 0.0:
			Build.set_defense("attack", str(p["key"]))
			var r: Dictionary = DefenseCalc.compute(Build)
			_check(not bool(r["attack"]["is_hit"]), "DoT preset")
			_check(float(r["summary"]["hits"]) > 0.0, "seconds to die")
			break
	# round trip of the settings through the build code
	Build.set_defense("area_level", 90)
	var decoded: Dictionary = BuildCodec.decode(BuildCodec.encode(Build))
	_check(int(decoded["defense"]["area_level"]) == 90, "defense settings in the build code")
