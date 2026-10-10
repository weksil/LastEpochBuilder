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
	_review_fixes()
	_scaling()
	_presets()
	_build()
	_sheet_vectors()
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
	# endurance mode "everything": endurance reduces the whole hit before ward; delayed share: 4 s of direct damage
	layers = _layers(0.5, 0.0)
	layers["endurance_mode"] = 2
	pool = {"health": 2000.0, "ward": 0.0, "mana": 0.0, "slow": []}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 500.0, "endurance mode 2")
	layers = _layers(0.0, 0.0)
	layers["delayed"] = 0.5
	layers["health"] = 2000.0
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	pool = {"health": 2000.0, "ward": 0.0, "mana": 0.0, "slow": []}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 500.0, "delayed: half now")
	DefenseRecovery.recover(layers, [] as Array[Dictionary], pool, 5.0)
	_near(float(pool["health"]), 1000.0, "delayed: the other half over 4 s")
	# damage taken as another type (ConvertDamageTaken, research/07n §1): source order Phys, Lightning, Cold, Fire, …
	var dmg: Array[float] = [1000.0, 500.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var conv_out: Array = DefenseConversions.convert_damage([{"sources": [0], "target": 1, "share": 1.0},
		{"sources": [1], "target": 2, "share": 1.0}], dmg)["damage"]
	_check(conv_out == [0.0, 1000.0, 500.0, 0.0, 0.0, 0.0, 0.0], "taken as: no chaining %s" % str(conv_out))
	conv_out = DefenseConversions.convert_damage([{"sources": [0, 1], "target": 5, "share": 0.5}], [1000.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0] as Array[float])["damage"]
	_check(conv_out == [500.0, 1000.0, 0.0, 0.0, 0.0, 500.0, 0.0], "taken as: first source type only %s" % str(conv_out))
	conv_out = DefenseConversions.convert_damage([{"sources": [0], "target": 1, "share": 0.6}, {"sources": [0], "target": 2, "share": 0.6}],
		[1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] as Array[float])["damage"]
	_check(conv_out == [0.0, 600.0, 600.0, 0.0, 0.0, 0.0, 0.0], "taken as: not normalised %s" % str(conv_out))
	# lethal damage and hits to die
	layers = _layers(0.0, 0.0)
	_near(DefenseCalc.lethal_damage(layers), 1000.0, "lethal without layers")
	_near(DefenseCalc.hits_to_die(layers, 400.0), 2.5, "hits to die")
	layers = _layers(0.6, 300.0)
	# H − T + (1 − e)·(R − (H − T)) = 1000 → R = 700 + 300 / 0.4 = 1450
	_near(DefenseCalc.lethal_damage(layers), 1450.0, "lethal with endurance")
	layers["ward"] = 500.0
	_near(DefenseCalc.lethal_damage(layers), 1950.0, "lethal with ward")


## Fixes of the engine review: spec vectors of research/06c §1.
func _review_fixes() -> void:
	# dodge converted to armor: (armour + dodgeRating)·(1 + f2), not armour·(1 + f2) + dodgeRating (step 6)
	_near(DefenseCalc.converted_armour(1000.0, 500.0, 0.5), 2250.0, "dodge → armor goes through the armor more")
	# block converted to glancing blow: min(maxBlock, blockChance) + f1·mult (step 5.2)
	_near(DefenseCalc.glancing_from_block(0.5, 0.4, 0.2), 0.6, "block → glancing: the cap does not reach f1")
	_near(DefenseCalc.glancing_from_block(0.5, 0.0, 0.2), 0.7, "block → glancing: no cap")
	# block converted to parry: parry + min(maxBlock, block), without the conditional block add f1 (GetParryChance)
	_near(DefenseCalc.parry_from_block(0.1, 0.5, 0.4), 0.5, "block → parry: min(maxBlock, block) added, no f1")
	_near(DefenseCalc.parry_from_block(0.1, 0.5, 0.0), 0.6, "block → parry: no cap")
	_near(DefenseCalc.parry_from_block(0.5, 0.5, 0.0), 0.75, "block → parry: capped at 75%")
	# an attack with no crit chance never crits, added chance to be crit or not (step 5.4)
	var crit_layers: Dictionary = {"crit_taken": 0.2, "crit_avoid": 0.0, "crit_reduced": 0.0}
	_near(float(DefenseCalc.crit_against(crit_layers, 0.0, 2.0)["chance"]), 0.0, "no crit chance: no crit")
	_near(float(DefenseCalc.crit_against(crit_layers, 0.1, 2.0)["chance"]), 0.3, "crit chance + chance to be crit")
	# the crit bonus reduction floors the whole hit multiplier at 1 (ProtectionClass.ApplyDamage), not only the crit factor
	var floor_layers: Dictionary = {"crit_taken": 0.0, "crit_avoid": 0.0, "crit_reduced": 0.75, "conv": {"hit_more": 0.5}, "delayed": 0.0}
	_near(float(DefenseCalc.crit_against(floor_layers, 0.1, 3.0)["factor"]), 2.0, "crit floor: f0 0.5, r 0.75: M = max(1, 1.5 x 0.5) = 1 -> x2 over the 0.5 hit")
	floor_layers["conv"] = {"hit_more": 1.0}
	floor_layers["delayed"] = 0.5
	_near(float(DefenseCalc.crit_against(floor_layers, 0.1, 3.0)["factor"]), 2.0, "crit floor: f7 0.5 counts like f0")
	floor_layers["delayed"] = 0.0
	floor_layers["crit_reduced"] = 0.5
	_near(float(DefenseCalc.crit_against(floor_layers, 0.1, 3.0)["factor"]), 2.0, "no floor: 1 + 0.5 x 2")
	floor_layers["crit_reduced"] = 1.5
	floor_layers["conv"] = {"hit_more": 1.2}
	_near(float(DefenseCalc.crit_against(floor_layers, 0.1, 3.0)["factor"]), 1.0 / 1.2, "r > 1, f0 1.2: M = max(1, 0 x 1.2) = 1 -> 1/1.2 of the non-crit hit")
	# the delayed share is queued from the final D: D / (1 − f7) · f7 (step 18), after mana before ward and endurance
	var layers: Dictionary = _layers(0.0, 0.0)
	layers["delayed"] = 0.5
	layers["mana_before_ward"] = 0.5
	var pool: Dictionary = {"health": 1000.0, "ward": 0.0, "mana": 500.0, "slow": []}
	DefenseCalc.take_damage(layers, pool, 1000.0)
	# 500 now, 50 mana absorb 250 → 250 immediate, 250 delayed
	_near(float(pool["mana"]), 450.0, "delayed + mana before ward: mana spent")
	_near(DefenseCalc.pending_slow(pool), 250.0, "delayed share after mana before ward")
	layers = _layers(0.5, 0.0)
	layers["endurance_mode"] = 2
	layers["delayed"] = 0.5
	pool = {"health": 2000.0, "ward": 0.0, "mana": 0.0, "slow": []}
	DefenseCalc.take_damage(layers, pool, 1000.0)
	_near(DefenseCalc.pending_slow(pool), 250.0, "delayed share after endurance mode 2")
	# the delayed share is queued after the endurance threshold absorption (D − (R − R')), not after the ward or mana before health
	layers = _layers(0.4, 800.0)
	layers["delayed"] = 0.5
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0, "slow": []}
	_near(DefenseCalc.take_damage(layers, pool, 600.0), 260.0, "delayed + threshold: health lost now")
	_near(DefenseCalc.pending_slow(pool), 260.0, "delayed share queued after the threshold absorption")
	layers = _layers(0.4, 900.0)
	layers["delayed"] = 0.5
	pool = {"health": 1000.0, "ward": 100.0, "mana": 0.0, "slow": []}
	_near(DefenseCalc.take_damage(layers, pool, 600.0), 160.0, "delayed + ward + threshold: health lost now")
	_near(DefenseCalc.pending_slow(pool), 260.0, "ward absorption is not subtracted from the delayed share")
	# the maximum hit counts the delayed share that lands within 4 s: 50% now + 50% later kill at 1000, not at 2000
	layers = _layers(0.0, 0.0)
	layers["delayed"] = 0.5
	_near(DefenseCalc.lethal_damage(layers), 1000.0, "lethal damage includes the delayed share")
	# the pool holds only when mana does not drain either: mana before health 50%, mana 5000, regen 100/s against 150 per hit
	layers = _layers(0.0, 0.0, 0.5)
	layers["mana"] = 5000.0
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	var regen: Array[Dictionary] = [{"resource": "health", "timing": "rate", "base": "flat", "k": 100.0, "label": "", "text": ""}]
	var hits: float = DefenseRecovery.hits_to_die(layers, regen, 150.0, 1.0)
	_check(hits > 340.0 and hits < 370.0, "mana drains while health holds: finite hits to die (%s)" % str(hits))
	var seconds: float = DefenseRecovery.seconds_to_die(layers, regen, 150.0)
	_check(seconds > 340.0 and seconds < 370.0, "mana drains under DoT: finite seconds to die (%s)" % str(seconds))
	# the minimum ward decay applies when there is no ward regeneration, ward from skills is not regeneration (06c §3.2)
	layers = _layers(0.0, 0.0)
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	layers["ward_regen"] = 0.0
	var ward_src: Array[Dictionary] = [{"resource": "ward", "timing": "rate", "base": "flat", "k": 0.2, "label": "", "text": ""}]
	pool = {"health": 1000.0, "ward": 1.5, "mana": 0.0, "slow": []}
	DefenseRecovery.recover(layers, ward_src, pool, 0.05)
	_near(float(pool["ward"]), 1.5 + 0.2 * 0.05 - 0.5 * 0.05, "minimum ward decay with ward gain from a skill", 0.0001)
	layers["ward_regen"] = 0.2
	pool = {"health": 1000.0, "ward": 1.5, "mana": 0.0, "slow": []}
	DefenseRecovery.recover(layers, ward_src, pool, 0.05)
	_near(float(pool["ward"]), 1.51 - 0.302 * 0.05, "no minimum ward decay with ward regeneration", 0.0001)
	# the simulation limits give an estimate, not ∞, while the pool keeps shrinking
	layers = _layers(0.0, 0.0)
	layers["health"] = 1.0e9
	_near(DefenseCalc.hits_to_die(layers, 1.0), 1.0e9, "hits to die beyond the limit: extrapolated", 0.001)
	layers["health"] = 1.0e6
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	regen = [{"resource": "health", "timing": "rate", "base": "flat", "k": 10.0, "label": "", "text": ""}]
	_near(DefenseRecovery.hits_to_die(layers, regen, 100.0, 1.0), 1.0e6 / 90.0, "hits to die with recovery beyond the limit", 0.01)
	_near(DefenseRecovery.seconds_to_die(layers, [] as Array[Dictionary], 10.0), 1.0e5, "DoT beyond 600 s: extrapolated", 0.01)
	_check(is_inf(DefenseRecovery.seconds_to_die(layers, regen, 5.0)), "DoT outhealed: ∞")
	# no NaN in the results of an attack without damage
	_check(is_inf(DefenseCalc._ehp(INF, 0.0)) and not is_nan(DefenseCalc._ehp(INF, 0.0)), "EHP without damage is ∞, not NaN")
	_check(DefenseCalc._num(NAN) == "—", "NaN is never printed")
	# #68: DamageTaken hit-event stats: specialTag 1 on every hit, 6 only on a blocked hit, none on DoT (HitEvents mask)
	var dt_store := StatStore.new()
	dt_store.add(StatMod.make(LE.DAMAGE_TAKEN, "more", -0.5, 0, "t", 6))
	dt_store.add(StatMod.make(LE.DAMAGE_TAKEN, "increased", 0.10, 0, "t", 1))
	dt_store.add(StatMod.make(LE.DAMAGE_TAKEN, "more", -0.2, 0, "t", 0))
	dt_store.add(StatMod.make(LE.DAMAGE_TAKEN, "added", 0.2, 0, "t", 2))
	_near(DefenseCalc.taken_events(dt_store, 0, 0), 0.8, "damage taken, no events (DoT): special 0 only")
	_near(DefenseCalc.taken_events(dt_store, 0, DefenseCalc.EVENT_HIT), 0.88, "damage taken, hit: 1.1 x 0.8")
	_near(DefenseCalc.taken_events(dt_store, 0, DefenseCalc.EVENT_HIT | DefenseCalc.EVENT_BLOCK), 0.44, "damage taken, blocked hit: 1.1 x 0.8 x 0.5")
	_near(DefenseCalc.taken_events(dt_store, 0, 1 | 2 | 32), 0.528, "damage taken, blocked crit: 1.2 x 1.1 x 0.5 x 0.8")
	# average block factor: (1-B) + B(1-dr)R; R = 1 is the old 1 - B*dr; The Monolith R = 0
	_near(DefenseCalc.block_factor(0.5, 0.4, 1.0), 0.8, "block factor, no block-only stats")
	_near(DefenseCalc.block_factor(0.5, 0.4, 0.0), 0.5, "block factor, blocked hits deal 0")
	_near(DefenseCalc.block_factor(0.5, 0.4, 0.5), 0.65, "block factor, R = 0.5")
	# #75a / #76: events of one enemy hit: dodge 0.2, parry 0.25, glancing 0.5, block 0.4
	var ev: Dictionary = DefenseCalc.enemy_hit_chances(0.2, 0.25, 0.5, 0.4)
	_near(float(ev["land"]), 0.6, "land = (1-dodge)(1-parry)")
	_near(float(ev["block"]), 0.24, "block = land x block chance")
	_near(float(ev["glancing"]), 0.3, "glancing = land x glancing chance")
	# #75b: ward when a hit leaves you below 35% health (strict), flat 50
	var low_layers: Dictionary = {"health": 1000.0}
	var low_src: Array[Dictionary] = [{"resource": "ward", "timing": "enemy_hit", "base": "flat", "k": 50.0, "label": "", "text": "", "below": 0.35}]
	var low_pool: Dictionary = {"health": 349.0, "ward": 10.0}
	DefenseRecovery.on_enemy_hit(low_layers, low_src, low_pool)
	_near(float(low_pool["ward"]), 60.0, "low health after the hit: ward gained")
	low_pool = {"health": 350.0, "ward": 10.0}
	DefenseRecovery.on_enemy_hit(low_layers, low_src, low_pool)
	_near(float(low_pool["ward"]), 10.0, "exactly 35%: not low health (strict)")
	low_pool = {"health": 800.0, "ward": 10.0}
	DefenseRecovery.on_enemy_hit(low_layers, low_src, low_pool)
	_near(float(low_pool["ward"]), 10.0, "healthy after the hit: nothing")
	# #77b: health gained by block / kill / stun: per blocked enemy hit, or the Conditions rates; special 0, tagged and ward stats count nothing
	var gs := StatStore.new()
	gs.add(StatMod.make(38, "added", 10.0, 0, "t", 6))
	gs.add(StatMod.make(39, "added", 20.0, 0, "t", 6))
	gs.add(StatMod.make(38, "added", 15.0, 0, "t", 3))
	gs.add(StatMod.make(38, "added", 8.0, 0, "t", 5))
	gs.add(StatMod.make(38, "added", 99.0, 0, "t", 0))
	gs.add(StatMod.make(38, "added", 50.0, 1, "t", 6))
	var gain: Array[Dictionary] = DefenseRecovery.event_gains(gs, {"kills_per_second": 2.0, "stuns_per_second": 0.5}, {"block": 0.3})
	_check(gain.size() == 3, "event gains: health on block, kill and stun (%d)" % gain.size())
	_near(float(gain[0]["k"]), 3.0, "health on block: 10 x 0.3 per enemy hit")
	_check(gain[0]["timing"] == "enemy_hit" and gain[0]["resource"] == "health", "health on block is an enemy-hit source")
	_near(float(gain[1]["k"]), 30.0, "health on kill: 15 x 2 kills/s")
	_check(gain[1]["timing"] == "rate", "health on kill is a rate source")
	_near(float(gain[2]["k"]), 4.0, "health on stun: 8 x 0.5 stuns/s")
	# #67: more PlayerProperty nodes fold as (1 + f)(1 + m) - 1; minPoints; passives with a stat model are left to UniqueEffects
	var npps: Dictionary = {}
	var conflux: Dictionary = {"effects": [{"op": "add_stat", "stat": {"kind": "more_player_property", "playerPropertyIndex": "252", "value": {"per_point": -0.01, "flat": 0}}}]}
	var aura: Dictionary = {"effects": [{"op": "add_stat", "stat": {"kind": "more_player_property", "playerPropertyIndex": "252", "value": {"per_point": -0.04, "flat": 0}}}]}
	DefenseConversions._add_node_pps(npps, conflux, 8, "t")
	_near(float(npps[252]["value"]), -0.08, "more PP node: 8 x -1%")
	DefenseConversions._add_node_pps(npps, aura, 5, "t")
	_near(float(npps[252]["value"]), -0.264, "two more PP nodes: (1 - 0.08)(1 - 0.20) - 1")
	var singular: Dictionary = {"effects": [{"op": "add_stat", "minPoints": 4, "stat": {"kind": "more_player_property", "playerPropertyIndex": "561", "value": {"per_point": 0, "flat": -0.05}}}]}
	npps = {}
	DefenseConversions._add_node_pps(npps, singular, 3, "t")
	_check(not npps.has(561), "more PP node below minPoints is not counted")
	DefenseConversions._add_node_pps(npps, singular, 4, "t")
	_near(float(npps[561]["value"]), -0.05, "more PP node at minPoints: flat -5%")
	var sphere: Dictionary = {"effects": [{"op": "add_stat", "stat": {"kind": "more_player_property", "playerPropertyIndex": "291", "value": {"per_point": -0.01, "flat": 0}}}]}
	npps = {}
	DefenseConversions._add_node_pps(npps, sphere, 8, "t", true)
	_check(not npps.has(291), "passive PP 291 has a stat model: counted by UniqueEffects, not twice")
	DefenseConversions._add_node_pps(npps, sphere, 8, "t", false)
	_near(float(npps[291]["value"]), -0.08, "skill node PP 291 is collected")
	# #80a: affix MORE PlayerProperty stats fold multiplicatively; Haste DoT: max(-0.75, (1 + inc) x pp)
	var aff: Dictionary = {}
	DefenseConversions._add_pp_more(aff, 275, -0.01, "t")
	DefenseConversions._add_pp_more(aff, 275, -0.01, "t")
	_near(float(aff[275]["value"]), -0.0199, "two affixes of -1%: 0.99 x 0.99 - 1", 0.0001)
	_near(DefenseConversions.haste_dot_more(-0.01, 0.07), -0.0107, "haste DoT: (1 + 7%) x -1%", 0.0001)
	_near(DefenseConversions.haste_dot_more(-0.5, 3.0), -0.75, "haste DoT: clamped at -75%")
	# #69/#123: f8 (PP 525) combines outside the 0.6 cap while the delayed damage left > 10% of max health (strict), base endurance > 0 below the threshold
	layers = _layers(0.5, 300.0)
	layers["endurance_extra"] = 0.3
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0, "slow": [[40.0, 4.0]]}  # 160 left > 100
	# e = 1 - 0.7 x 0.5 = 0.65; H = 1000, T = 300, R = 1000 -> (H - T) + (1 - e)(T - (H - R)) = 700 + 0.35 x 300 = 805
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 805.0, "f8 pending: e = 0.65")
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0, "slow": [[20.0, 4.0]]}  # 80 left
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 850.0, "f8 not pending (80 < 100): e = 0.5 -> 700 + 0.5 x 300")
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0, "slow": [[25.0, 4.0]]}  # exactly 100: strict
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 850.0, "f8 needs MORE than 10%")
	layers = _layers(0.0, 300.0)
	layers["endurance_extra"] = 0.3
	pool = {"health": 2000.0, "ward": 0.0, "mana": 0.0, "slow": [[40.0, 4.0]]}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 1000.0, "f8 without base endurance: no threshold block in mode 0")
	layers["endurance_mode"] = 2
	pool = {"health": 2000.0, "ward": 0.0, "mana": 0.0, "slow": [[40.0, 4.0]]}
	_near(DefenseCalc.take_damage(layers, pool, 1000.0), 700.0, "f8 in mode 2 works without base endurance: x (1 - 0.3)")
	# #78: bypassing hits skip the ward (ward untouched), caps of current health and ward
	layers = _layers(0.0, 0.0)
	layers["ward_bypass"] = true
	pool = {"health": 1000.0, "ward": 300.0, "mana": 0.0}
	_near(DefenseCalc.take_damage(layers, pool, 200.0), 200.0, "ward bypass: the whole hit reaches health")
	_near(float(pool["ward"]), 300.0, "ward bypass: ward untouched")
	layers = _layers(0.0, 0.0)
	layers["health_limit"] = 500.0
	_near(float(DefenseCalc.full_pool(layers)["health"]), 500.0, "current health cap: the pool starts at 50%")
	_near(DefenseCalc.lethal_damage(layers), 500.0, "current health cap: lethal damage")
	layers["ward_threshold"] = 1000.0
	layers["ward_retention"] = 0.0
	var heal_src: Array[Dictionary] = [{"resource": "health", "timing": "rate", "base": "flat", "k": 100.0, "label": "", "text": ""}]
	pool = {"health": 400.0, "ward": 0.0, "mana": 0.0}
	DefenseRecovery.recover(layers, heal_src, pool, 5.0)
	_near(float(pool["health"]), 500.0, "current health cap: regeneration clamps at 500 (min(1000, 400 + 500) -> 500)")
	layers["ward_limit"] = 200.0
	var wsrc: Array[Dictionary] = [{"resource": "ward", "timing": "rate", "base": "flat", "k": 100.0, "label": "", "text": ""}]
	pool = {"health": 1000.0, "ward": 150.0, "mana": 0.0}
	DefenseRecovery.recover(layers, wsrc, pool, 1.0)
	_near(float(pool["ward"]), 200.0, "ward cap: ward gain clamps at 200 (decay is 0 below the threshold 1000)")
	var hit_src: Array[Dictionary] = [{"resource": "ward", "timing": "enemy_hit", "base": "flat", "k": 50.0, "label": "", "text": ""}]
	pool = {"health": 1000.0, "ward": 180.0, "mana": 0.0}
	DefenseRecovery.on_enemy_hit(layers, hit_src, pool)
	_near(float(pool["ward"]), 200.0, "ward cap: ward on hit clamps at 200")
	_near(DefenseConversions.ward_cap_share(0.5, 0.0), 0.5, "ward cap: tree only")
	_near(DefenseConversions.ward_cap_share(0.0, 2.0), 2.0, "ward cap: PP 609 only")
	_near(DefenseConversions.ward_cap_share(0.5, 2.0), 0.5, "ward cap: min of the non-zero (tree smaller)")
	_near(DefenseConversions.ward_cap_share(0.5, 0.3), 0.3, "ward cap: min of the non-zero (PP 609 smaller)")
	_near(DefenseConversions.ward_cap_share(0.0, 0.0), 0.0, "ward cap: none")
	# #79: current health drain: HealthDamage(drain x current health x dt) = exponential decay, no regeneration
	layers = _layers(0.0, 0.0)
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	layers["health_drain"] = 0.1
	pool = {"health": 1000.0, "ward": 0.0, "mana": 0.0}
	DefenseRecovery.recover(layers, [] as Array[Dictionary], pool, 1.0)
	_near(float(pool["health"]), 1000.0 * exp(-0.1), "health drain 10%/s over 1 s: 904.837", 0.00001)
	# 100 per hit every second, drain 10%/s: health before each hit 1000, 814.35, 646.37, 494.38, 356.85, 232.41, 119.81, 17.92 -> the 8th hit kills at 17.92/100
	_near(DefenseRecovery.hits_to_die(layers, [] as Array[Dictionary], 100.0, 1.0), 7.1792, "hits to die with a health drain", 0.0005)
	layers["health_drain"] = 0.0
	_near(DefenseRecovery.hits_to_die(layers, [] as Array[Dictionary], 100.0, 1.0), 10.0, "hits to die without the drain", 0.0005)


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
		if not bool(p["is_hit"]) and float(p["tick"]) > 0.0:
			Build.set_defense("attack", str(p["key"]))
			var r: Dictionary = DefenseCalc.compute(Build)
			_check(not bool(r["attack"]["is_hit"]), "DoT preset")
			_check(float(r["summary"]["hits"]) > 0.0, "seconds to die")
			break
	# the average monster group: five attacks, the "every type" hit holds all seven types
	var groups: Array[Dictionary] = DefenseCalc.groups()
	_check(str(groups[0]["key"]) == DefenseCalc.AVERAGE_KEY and (groups[0]["attacks"] as Array).size() == 15, "average group first")
	_check(str(groups[-1]["key"]) == DefenseCalc.CUSTOM_KEY, "custom hit last")
	var all_types: Dictionary = DefenseCalc.preset("average|all")
	for i in range(7):
		_check(float(all_types.get("damage", [0, 0, 0, 0, 0, 0, 0])[i]) > 0.0, "average hit has damage type %d" % i)
	_check(not bool(DefenseCalc.preset("average|dot").get("is_hit", true)), "average DoT")
	# boss Damage increased: (1 + Σincreased) x base x Π(1 + more) (DamageStats.buildDamageStats)
	var heorot: Dictionary = DefenseCalc.preset("Heorot Boss|Heorot Boss Melee Attack|0")
	_near(float((heorot["damage"] as Array)[0]), 173.0, "Heorot: Damage increased -13.5% applies (200 x 0.865)")
	var shaman: Dictionary = DefenseCalc.preset("Shamans Boss|Shamans Boss 05 Fireball|0")
	_near(float((shaman["damage"] as Array)[1]), 347.2875, "Volcanic Shaman: increased -10% and more -14.25% (450 x 0.9 x 0.8575)")
	# magic and rare monsters: Damage MORE +60% / +90% (monster_rarity.json)
	var n_hit: Dictionary = DefenseCalc.preset("average|melee")
	var m_hit: Dictionary = DefenseCalc.preset("average|melee|magic")
	var r_hit: Dictionary = DefenseCalc.preset("average|melee|rare")
	_near(float((m_hit["damage"] as Array)[0]), float((n_hit["damage"] as Array)[0]) * 1.6, "magic monster: Damage more +60%")
	_near(float((r_hit["damage"] as Array)[0]), float((n_hit["damage"] as Array)[0]) * 1.9, "rare monster: Damage more +90%")
	_check(str(r_hit.get("rarity", "")) == "rare" and not n_hit.has("rarity"), "rarity key only on variants")
	# recovery between hits: never fewer hits to die than without it; regeneration alone recovers per second
	Build.set_defense("attack", "average|melee")
	Build.set_enemy("corruption", 0)
	Build.set_defense("recovery", false)
	var no_rec: float = float(DefenseCalc.compute(Build)["summary"]["hits"])
	Build.set_defense("recovery", true)
	Build.set_defense("interval", 2.0)
	var with_rec: float = float(DefenseCalc.compute(Build)["summary"]["hits"])
	_check(with_rec >= no_rec, "recovery adds hits: %s < %s" % [with_rec, no_rec])
	var layers: Dictionary = _layers(0.0, 0.0)
	layers["ward_threshold"] = 0.0
	layers["ward_retention"] = 0.0
	var regen: Array[Dictionary] = [{"resource": "health", "timing": "rate", "base": "flat", "k": 100.0, "label": "", "text": ""}]
	_near(DefenseRecovery.hits_to_die(layers, regen, 400.0, 1.0), 3.0, "regen 100/s against 400 every second: 1000 → 700 → 400 → dead on the 3rd hit")
	_check(is_inf(DefenseRecovery.hits_to_die(layers, regen, 90.0, 1.0)), "regen outheals the hits")
	_near(DefenseRecovery.seconds_to_die(layers, regen, 200.0), 10.0, "DoT 200/s vs regen 100/s: 10 s", 0.02)
	# PlayerProperty from a passive: Rogue "Apostasy" converts dodge to glancing blow (07n §2)
	for class_data: Dictionary in GameData.classes:
		if str(class_data["className"]) == "Rogue":
			Build.set_class(int(class_data["classID"]))
	Build.passives[61] = 1
	var conv: Dictionary = DefenseConversions.collect(Build, BuildMods.global_store(Build)["store"], {"is_hit": true})
	_check(int(conv["dodge_conversion"]) == 2, "Apostasy: dodge → glancing blow (%d)" % int(conv["dodge_conversion"]))
	var rogue: Dictionary = DefenseCalc.compute(Build)
	_check(float(rogue["layers"]["dodge"]) == 0.0, "Apostasy: no dodge")
	Build.passives.erase(61)
	# an attack without any damage: no NaN anywhere in the summary
	Build.set_defense("attack", DefenseCalc.CUSTOM_KEY)
	Build.set_defense("custom_damage", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var zero: Dictionary = DefenseCalc.compute(Build)["summary"]
	for key: String in ["ehp", "max_hit", "hits", "taken", "worst"]:
		_check(not is_nan(float(zero[key])), "zero damage attack: %s is not NaN" % key)
	_check(is_inf(float(zero["ehp"])) and is_inf(float(zero["hits"])), "zero damage attack: nothing kills")
	Build.set_defense("custom_damage", DefenseCalc.default_settings()["custom_damage"])
	# round trip of the settings through the build code
	Build.set_defense("area_level", 90)
	var decoded: Dictionary = BuildCodec.decode(BuildCodec.encode(Build))
	_check(int(decoded["defense"]["area_level"]) == 90, "defense settings in the build code")


## Character sheet (CharacterSheet.UpdateSheet, PrecalculatedStatsHolder): the zone level for the percentages, the
## dodge / block conversions, and the Thorns / Crit avoidance formulas.
func _sheet_vectors() -> void:
	TranslationServer.set_locale("en")  # the rows are looked up by their English labels
	Build.passives.clear()
	Build.items.clear()
	Build.set_level(100)
	Build.set_defense("area_level", 50)
	var s := StatStore.new()
	s.add(StatMod.make(LE.DODGE_RATING, "added", 200.0, 0, "t"))
	s.add(StatMod.make(LE.ARMOUR, "added", 1000.0, 0, "t"))
	var rows: Array[Dictionary] = CharacterCalc.compute(s, Build)
	_near(_row_value(rows, "Dodge chance"), 0.129275, "sheet dodge chance at area level 50 (L = 55)", 0.0001)
	_near(_row_value(rows, "Armor physical damage reduction"), 0.323897, "sheet armour mitigation at area level 50 (L = 55)", 0.0001)
	Build.set_defense("area_level", 100)
	rows = CharacterCalc.compute(s, Build)
	_near(_row_value(rows, "Dodge chance"), 0.067209, "sheet dodge chance at area level 100 (L = 105)", 0.0001)

	# conversions as the game's holder reads them
	_near(CharacterCalc.sheet_armour(100.0, 200.0, 1), 300.0, "sheet armour: dodge converted to armor")
	_near(CharacterCalc.sheet_armour(100.0, 200.0, 0), 100.0, "sheet armour: no conversion")
	_near(CharacterCalc.sheet_armour(100.0, 200.0, 2), 100.0, "sheet armour: glancing blow adds nothing")
	_near(CharacterCalc.sheet_threshold(50.0, 200.0, 3), 250.0, "sheet endurance threshold: dodge converted")
	_near(CharacterCalc.sheet_threshold(50.0, 200.0, 1), 50.0, "sheet endurance threshold: no conversion")
	_near(CharacterCalc.sheet_dodge_rating(200.0, 0), 200.0, "sheet dodge rating: no conversion")
	_near(CharacterCalc.sheet_dodge_rating(200.0, 1), 0.0, "sheet dodge rating: converted to armor shows 0")
	_near(CharacterCalc.sheet_dodge_rating(200.0, 3), 0.0, "sheet dodge rating: converted to endurance threshold shows 0")
	_near(CharacterCalc.sheet_block_chance(0.5, 0, 0.0), 0.5, "sheet block chance: no cap")
	_near(CharacterCalc.sheet_block_chance(0.5, 0, 0.4), 0.4, "sheet block chance: capped at the maximum")
	_near(CharacterCalc.sheet_block_chance(0.5, 0, 0.6), 0.5, "sheet block chance: below the maximum")
	_near(CharacterCalc.sheet_block_chance(0.5, 1, 0.4), 0.0, "sheet block chance: converted to glancing blow shows 0")
	_near(CharacterCalc.sheet_block_chance(0.5, 2, 0.0), 0.0, "sheet block chance: converted to parry shows 0")

	# Thorns: (1 + increased) x added, no more; Crit avoidance: added x more, no increased
	var t := StatStore.new()
	t.add(StatMod.make(LE.THORNS, "added", 10.0, 0, "t"))
	t.add(StatMod.make(LE.THORNS, "increased", 0.5, 0, "t"))
	t.add(StatMod.make(LE.THORNS, "more", 0.2, 0, "t"))
	_near(_row_value(CharacterCalc.compute(t, Build), "Thorns"), 15.0, "sheet thorns: (1 + 0.5) x 10, no more")
	var c := StatStore.new()
	c.add(StatMod.make(LE.CRIT_AVOIDANCE, "added", 0.4, 0, "t"))
	c.add(StatMod.make(LE.CRIT_AVOIDANCE, "increased", 0.5, 0, "t"))
	c.add(StatMod.make(LE.CRIT_AVOIDANCE, "more", -0.25, 0, "t"))
	_near(_row_value(CharacterCalc.compute(c, Build), "Crit avoidance"), 0.30, "sheet crit avoidance: 0.4 x 0.75, no increased")

	# Knight "Iron Reflexes" (kn-1 node 42, 5 points): PP 177 dodge converted to armor
	var kn: int = _class_with_tree("kn-1")
	_check(kn >= 0, "a class with the kn-1 tree exists")
	Build.set_class(kn)
	Build.passives = {42: 5}
	var k := StatStore.new()
	k.add(StatMod.make(LE.ARMOUR, "added", 100.0, 0, "t"))
	k.add(StatMod.make(LE.DODGE_RATING, "added", 200.0, 0, "t"))
	rows = CharacterCalc.compute(k, Build)
	_near(_row_value(rows, "Armor"), 300.0, "Knight: dodge converted to armor on the sheet")
	_near(_row_value(rows, "Dodge rating"), 0.0, "Knight: dodge rating shows 0")
	_near(_row_value(rows, "Dodge chance"), 0.0, "Knight: dodge chance 0")

	# Rogue "Deflect and Weave" (rg-1 node 95, 5 points): PP 392 block chance converted to glancing blow
	var rg: int = _class_with_tree("rg-1")
	_check(rg >= 0, "a class with the rg-1 tree exists")
	Build.set_class(rg)
	Build.passives = {95: 5}
	var r := StatStore.new()
	r.add(StatMod.make(LE.BLOCK_CHANCE, "added", 0.5, 0, "t"))
	_near(_row_value(CharacterCalc.compute(r, Build), "Block chance"), 0.0, "Rogue: block chance shows 0 when converted")
	Build.passives.clear()


func _row_value(rows: Array[Dictionary], label: String) -> float:
	for row: Dictionary in rows:
		if str(row["label"]) == LE.t(label):
			return float(row["value"])
	return NAN


func _class_with_tree(tree_id: String) -> int:
	for class_data: Dictionary in GameData.classes:
		if str(GameData.get_passive_tree(int(class_data["classID"])).get("treeID", "")) == tree_id:
			return int(class_data["classID"])
	return -1
