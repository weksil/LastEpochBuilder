extends Node

## Headless MinionCalc check: stat transfer from the player, health, damage components.
## Run: Godot_console.exe --headless --path client res://tests/minion_test.tscn

const MinionCalcScript: GDScript = preload("res://scripts/engine/minion_calc.gd")

var _failed: int = 0


func _ready() -> void:
	_wolf()
	_death_knight()
	_mutators()
	_prefab_armour()
	print("MINION TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _death_knight() -> void:
	var dk: Dictionary = MinionCalcScript.minion_by_actor("Death Knight")  # loads the data
	var harvest: Dictionary = MinionCalcScript._abilities["DeathKnightHarvest"]
	var melee: Dictionary = MinionCalcScript._abilities["Basic Death Knight Melee"]
	_check("Death Knight Harvest: +1 charge and +0.333 charge/s from its hardcoded mutator -> 0.333 uses/s",
		MinionCalcScript._use_cap(dk, harvest, StatStore.new()), 0.333, 0.0001)
	_check("Death Knight melee has no cap", 1.0 if is_inf(MinionCalcScript._use_cap(dk, melee, StatStore.new())) else 0.0, 1.0)


func _mutators() -> void:
	var saber: Dictionary = MinionCalcScript.minion_by_actor("Primal Sabertooth")  # loads the data
	var ab: Dictionary = MinionCalcScript._abilities["PrimalSabertooth 01 Melee"]
	var base: Dictionary = MinionCalcScript._first_damage(ab)
	var hit: Dictionary = MinionCalcScript._mutated_hit(saber, ab, base)
	_check("Sabertooth moreHitDamage 0.65: added damage effectiveness x1.65", float(hit["addedDamageScaling"]),
		float(base["addedDamageScaling"]) * 1.65, 0.0001)
	var base_sum: float = 0.0
	var hit_sum: float = 0.0
	for v: Variant in base["damage"]:
		base_sum += float(v)
	for v: Variant in hit["damage"]:
		hit_sum += float(v)
	_check("Sabertooth moreHitDamage 0.65: base damages x1.65", hit_sum, base_sum * 1.65, 0.001)
	# BasicMeleeMutator calls increaseAllDamage: damage and added damage effectiveness x (1 + increasedDamage)
	var fake: Dictionary = {"mutators": {"BasicMeleeMutator": [{"abilityRef": "X", "nonZero": {"increasedDamage": 0.65}}]}}
	var entry: Dictionary = {"damage": [10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "addedDamageScaling": 0.5}
	var h2: Dictionary = MinionCalcScript._mutated_hit(fake, {"name": "X"}, entry)
	_check("increasedDamage 0.65 on damage 10 -> 16.5", float(h2["damage"][0]), 16.5, 0.0001)
	_check("increasedDamage 0.65 on effectiveness 0.5 -> 0.825", float(h2["addedDamageScaling"]), 0.825, 0.0001)
	_check("another ability is not scaled", float(MinionCalcScript._mutated_hit(fake, {"name": "Y"}, entry)["damage"][0]), 10.0, 0.0001)
	# RaptorBasicMeleeMutator: damage only (its Mutate does not call increaseAllDamage)
	var raptor: Dictionary = {"mutators": {"RaptorBasicMeleeMutator": [{"abilityRef": "X", "nonZero": {"increasedDamage": 0.65}}]}}
	var h3: Dictionary = MinionCalcScript._mutated_hit(raptor, {"name": "X"}, entry)
	_check("Raptor increasedDamage 0.65 on damage 10 -> 16.5", float(h3["damage"][0]), 16.5, 0.0001)
	_check("Raptor increasedDamage: effectiveness stays 0.5", float(h3["addedDamageScaling"]), 0.5, 0.0001)
	# Skeleton Rogue: ComplexGenericMutator increasedCastSpeed 0.2 on its Shurikens only
	var rogue: Dictionary = MinionCalcScript.minion_by_actor("Skeleton Rogue")
	_check("Skeleton Rogue Shurikens: use speed x(1 + 0.2)",
		MinionCalcScript._speed_mutator_factor(rogue, MinionCalcScript._abilities["Skeleton Rogue Shurikens"]), 1.2, 0.0001)
	_check("Skeleton Rogue Melee: no speed mutator",
		MinionCalcScript._speed_mutator_factor(rogue, MinionCalcScript._abilities["Skeleton Rogue Melee"]), 1.0, 0.0001)


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
	_check("wolf rate = 1.3*1.0/1.2 (minion baseUseSpeedMultiplier 1.0, not the player's 1.1)", float(comps[0]["rate"]), 1.3 / 1.2)

	var totem: Dictionary = {"name": "SummonThornTotem", "tags": LE.TOTEM}
	var tstore := StatStore.new()
	tstore.add(StatMod.make(LE.DAMAGE, "increased", 0.25, LE.TOTEM, "test"))
	var plain: StatStore = MinionCalcScript.minion_store(tstore, summon, wolf, [])
	var tot: StatStore = MinionCalcScript.minion_store(tstore, totem, wolf, [])
	_check("totem stat not for non-totem", plain.query(LE.DAMAGE).increased, 0.0)
	_check("totem stat for totem", tot.query(LE.DAMAGE).increased, 0.25)


## BaseStats.ApplyExternalStats overwrites the prefab's serialized armour: the minion's base armour is 0 (Primal Bear 70.05 ignored).
func _prefab_armour() -> void:
	var st := StatStore.new()
	st.add(StatMod.make(LE.ARMOUR, "added", 100.0, 0, "t"))
	st.add(StatMod.make(LE.ARMOUR, "increased", 0.5, 0, "t"))
	var minion: Dictionary = {"health": {"maxHealth": 10.0}, "protection": {"armour": 70.05}}
	var rr: Array[Dictionary] = MinionCalcScript.defence_rows(st, minion)
	_check("minion armour: prefab base ignored (0 + 100) * 1.5", float(rr[1]["value"]), 150.0)
	_check("minion armour text", float(rr[1]["text"]), 150.0)
	st.add(StatMod.make(LE.NEG_ARMOUR, "added", 20.0, 0, "t"))
	rr = MinionCalcScript.defence_rows(st, minion)
	_check("minion armour minus shred: 150 - 20", float(rr[1]["value"]), 130.0)
