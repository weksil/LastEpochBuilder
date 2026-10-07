extends Node

## Engine benchmark and golden output (not part of the suite). For every fixture build it times what the UI recomputes
## after an edit: SkillCalc.compute of every bar slot (stats panel; the Calculations tab reads the selected one),
## the selected one with its breakdowns (an expanded row), CharacterCalc, DefenseCalc, ConfigRelevance, and one item hover diff. Each round changes the enemy armor first, so
## every round is a new build state like a user edit (cached results of an earlier state do not help).
## With `--golden=<path>` every row (label, text, value, breakdown) of the first round is written to <path> so two engine
## versions can be diffed; `--rounds=N` sets the rounds per fixture, `--nocache` turns CalcCache off.
## Run: Godot_console.exe --headless --path client res://tests/perf_bench.tscn -- --golden=out.txt --rounds=3

const FIXTURE_DIR: String = "res://tests/fixtures/"
const FIXTURES: Array[String] = [
	"letools_A83KxJq5.json", "letools_ApbrXYvx.json", "letools_Q0V58LLX.json", "letools_Q0V6XDLG.json",
	"maxroll_char_chudlet.json", "maxroll_char_palading.json",
]

var _golden: PackedStringArray = []
var _times: Dictionary = {}


func _ready() -> void:
	TranslationServer.set_locale("en")
	var golden_path: String = ""
	var rounds: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--golden="):
			golden_path = arg.substr(9)
		elif arg.begins_with("--rounds="):
			rounds = int(arg.substr(9))
		elif arg == "--nocache":
			(load("res://scripts/engine/calc_cache.gd") as GDScript).set("enabled", false)
	# load the game data before timing
	GameData.get_ability("")
	var total_start: int = Time.get_ticks_usec()
	for file_name: String in FIXTURES:
		_run_fixture(file_name, rounds)
	var total: float = (Time.get_ticks_usec() - total_start) / 1000.0
	var keys: Array = _times.keys()
	keys.sort()
	for key: String in keys:
		print("%-40s %10.1f ms" % [key, _times[key]])
	print("TOTAL %.1f ms (%d fixtures × %d rounds)" % [total, FIXTURES.size(), rounds])
	if OS.get_cmdline_user_args().has("--prof"):
		load("res://scripts/engine/prof.gd").dump()
	if golden_path != "":
		var f: FileAccess = FileAccess.open(golden_path, FileAccess.WRITE)
		f.store_string("\n".join(_golden))
		f.close()
		print("golden written: %d lines" % _golden.size())
	get_tree().quit(0)


func _time(key: String, start: int) -> void:
	_times[key] = float(_times.get(key, 0.0)) + (Time.get_ticks_usec() - start) / 1000.0


func _run_fixture(file_name: String, rounds: int) -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_DIR + file_name))
	var doc: Dictionary = MaxrollImport.to_build(raw) if file_name.begins_with("maxroll") else LEToolsImport.to_build(raw)
	LEToolsImport.apply(Build, doc)
	var armour: Variant = Build.enemy.get("armour", 0)
	for r: int in range(rounds):
		Build.enemy["armour"] = armour if r == 0 else int(armour) + r
		_refresh(file_name, r == 0)
	Build.enemy["armour"] = armour


func _refresh(file_name: String, record: bool) -> void:
	if record:
		_golden.append("##### " + file_name)
	# the UI reads lean results (numbers only; breakdowns are built when a row is expanded)
	var t: int = Time.get_ticks_usec()
	for slot: int in range(Build.skills.size()):
		if str(Build.skills[slot].get("ability", "")) != "":
			SkillCalc.compute(Build, slot, false)
	_time("SkillCalc.compute (bar, lean)", t)
	t = Time.get_ticks_usec()
	SkillCalc.compute(Build, Build.selected_skill, true)
	_time("SkillCalc.compute (selected, details)", t)
	if record:
		for slot: int in range(Build.skills.size()):
			if str(Build.skills[slot].get("ability", "")) == "":
				continue
			var r: Dictionary = SkillCalc.compute(Build, slot)
			_golden.append("=== slot %d %s" % [slot, r.get("title", "")])
			_dump_result(r)
	t = Time.get_ticks_usec()
	var saved: Dictionary = EnemyAilments.apply(Build, Build.selected_skill)
	var g: Dictionary = BuildMods.global_store(Build)
	var rows: Array[Dictionary] = CharacterCalc.compute(g["store"], Build)
	EnemyAilments.restore(Build, saved)
	_time("global_store + CharacterCalc", t)
	if record:
		_golden.append("=== character")
		_dump_rows(rows)
	t = Time.get_ticks_usec()
	var d: Dictionary = DefenseCalc.compute(Build)
	_time("DefenseCalc.compute", t)
	if record:
		_golden.append("=== defense")
		_dump_result(d)
	t = Time.get_ticks_usec()
	var rel: Dictionary = ConfigRelevance.compute(Build)
	_time("ConfigRelevance", t)
	if record:
		_golden.append("=== relevance " + JSON.stringify(rel, "", true))
	# one item hover: the diff of emptying the helmet slot
	t = Time.get_ticks_usec()
	var before: Dictionary = ItemCompare.snapshot(Build)
	var after: Dictionary = ItemCompare.snapshot_with_item(Build, "helmet", {})
	_time("ItemCompare (hover)", t)
	if record:
		_golden.append("=== hover helmet")
		var keys: Array = after.keys()
		keys.sort()
		for key: String in keys:
			_golden.append("%s: %s -> %s" % [key, before.get(key, {}).get("value"), after[key]["value"]])


func _dump_result(r: Dictionary) -> void:
	for sec: Dictionary in r.get("sections", []):
		_golden.append("--- " + str(sec.get("title", "")))
		_dump_rows(sec.get("rows", []))
	for n: Variant in r.get("notes", []):
		_golden.append("note: " + str(n))
	for key: String in ["auto_ailments", "auto_buffs", "inputs"]:
		if r.has(key):
			_golden.append("%s: %s" % [key, JSON.stringify(r[key], "", true)])


func _dump_rows(rows: Array) -> void:
	for row: Variant in rows:
		if row is Dictionary:
			_golden.append("%s | %s | %s | %s" % [row.get("label", ""), row.get("text", ""), row.get("value", ""), str(row.get("breakdown", "")).replace("\r", "").replace("\n", " ⏎ ")])
		else:
			_golden.append(str(row))
