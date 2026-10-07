extends Node

## Headless MinionCalc check: stat transfer from the player, health, damage components.
## Run: Godot_console.exe --headless --path client res://tests/minion_test.tscn

const MinionCalcScript: GDScript = preload("res://scripts/engine/minion_calc.gd")

var _failed: int = 0


func _ready() -> void:
	_wolf()
	print("MINION TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: float, want: float, eps: float = 0.0005) -> void:
	if absf(got - want) > eps:
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


func _wolf() -> void:
	var summon: Dictionary = {"name": "SummonWolf", "tags": 0, "abilityIDEnum": {"value": 8, "name": "summonWolf"}}
	var player := StatStore.new()
	player.add(StatMod.make(LE.DAMAGE, "increased", 0.5, LE.MINION, "test"))
	player.add(StatMod.make(LE.DAMAGE, "increased", 0.4, 0, "test"))
	player.add(StatMod.make(LE.HEALTH, "added", 20, LE.MINION, "test"))
	player.add(StatMod.make(38, "added", 5, LE.MINION, "test HealthGain"))
	player.add(StatMod.make(LE.DAMAGE, "increased", 0.2, 0, "test extra", 0, 8))

	var minions: Array[Dictionary] = MinionCalcScript.minions_for("SummonWolf")
	_check("minions_for SummonWolf", minions.size(), 1)
	var wolf: Dictionary = minions[0]
	var store: StatStore = MinionCalcScript.minion_store(player, summon, wolf, [])
	var inc: StatQuery = store.query(LE.DAMAGE, LE.PHYSICAL | LE.MELEE)
	_check("wolf damage inc (0.5 + 0.2 extra, no 0.4)", inc.increased, 0.7)
	_check("wolf health-gain not transferred", store.query(38).mods.size(), 0)
	var rows: Array[Dictionary] = MinionCalcScript.defence_rows(store, wolf)
	for row: Dictionary in rows:
		print("  %s: %s" % [row["label"], row["text"]])
	_check("wolf health", float(rows[0]["text"]), 240)

	var comps: Array[Dictionary] = MinionCalcScript.components(player, summon, [], Build)
	_check("components non-empty", 1.0 if not comps.is_empty() else 0.0, 1.0)
	for comp: Dictionary in comps:
		print("  %s rate=%s note=%s" % [comp["name"], comp["rate"], comp["note"]])
		_check("component rate > 0", 1.0 if float(comp["rate"]) > 0.0 else 0.0, 1.0)
	_check("wolf rate = 1.3*1.1/1.2", float(comps[0]["rate"]), 1.3 * 1.1 / 1.2)

	var totem: Dictionary = {"name": "SummonThornTotem", "tags": LE.TOTEM}
	var tstore := StatStore.new()
	tstore.add(StatMod.make(LE.DAMAGE, "increased", 0.25, LE.TOTEM, "test"))
	var plain: StatStore = MinionCalcScript.minion_store(tstore, summon, wolf, [])
	var tot: StatStore = MinionCalcScript.minion_store(tstore, totem, wolf, [])
	_check("totem stat not for non-totem", plain.query(LE.DAMAGE).increased, 0.0)
	_check("totem stat for totem", tot.query(LE.DAMAGE).increased, 0.25)
