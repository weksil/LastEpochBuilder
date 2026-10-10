extends Node

## Headless engine check: test vectors from research/06a–06c, 07a and a sample build.
## Run: Godot_console.exe --headless --path client res://tests/engine_test.tscn

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")
const CURSE_SECTION: String = "Damage per hit on the cursed target (before enemy)"

var _failed: int = 0


func _ready() -> void:
	TranslationServer.set_locale("en")  # the checks compare English engine texts, whatever language the user chose
	_vectors()
	_sample_build()
	_idol_altar()
	_blessing_rolls()
	_larger_above_smaller()
	_passive_field_models()
	_dodge_per_int_cap()
	_buff_skills()
	_buff_skill_base_models()
	_sustain()
	_gain_events()
	_curse_hits()
	_high_health_vs_dummy()
	_detonations_and_maintained_dot()
	_item_compare()
	_projectiles()
	_item_triggers()
	_passive_granted_skill()
	_shadows_echoes_buffs()
	_review_damage_fixes()
	_speed_audit()
	_mana_cost_audit()
	_review_mod_fixes()
	_skill_conversions()
	_hit_damage_fixes()
	_ailment_fixes()
	_buff_group_fixes()
	_passive_set_fixes()
	_lean_and_cache()
	_runtime_zones()
	_zone_ticks_and_ailment_fixes()
	print("ENGINE TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


## Granted skills of the build without the basic attack entry (always present).
func _granted_skills() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in GrantedCalc.skills(Build):
		if not bool(entry.get("basic", false)):
			out.append(entry)
	return out


## Flame Walker (Mage passive 38), game code CharacterMutator.OnUpdateTick: a 1 s tick, one roll (10% per point, doubled while fewer
## than 3 Fire Auras are active, at most 100%), the cast happens while the character moves or a Melee ability is in use. Fire Aura is not
## on the bar: a character event, counted in the first skill that deals damage; the virtual slots (GrantedCalc) are views of it.
func _passive_granted_skill() -> void:
	Build.set_class(1)
	Build.set_mastery(3)
	Build.set_level(100)
	Build.set_skill(0, "fr11mv")  # Flame Reave: melee
	Build.set_skill(1, "fi9")  # Fireball: a spell
	Build.passives[38] = 8
	var melee: Dictionary = SkillCalc.compute(Build, 0)
	var spell: Dictionary = SkillCalc.compute(Build, 1)
	var aura_sections: int = 0
	for sec: Dictionary in melee["sections"]:
		if str(sec["title"]).begins_with("Fire Aura"):
			aura_sections += 1
	_check("Flame Walker: Fire Aura sections on the first damaging skill", 1.0 if aura_sections >= 3 else 0.0, 1.0)
	_check("Flame Walker: a character event is counted once (not in the second skill)", float((spell["granted"] as Array).size()), 0.0)
	var granted: Array[Dictionary] = _granted_skills()
	_check("Flame Walker: one granted skill", float(granted.size()), 1.0)
	var aura_id: String = str(granted[0]["id"]) if not granted.is_empty() else ""
	_check("Flame Walker: granted skill is Fire Aura, owned by slot 1", 1.0 if (not granted.is_empty() and str(granted[0]["name"]) == "Fire Aura" and int(granted[0]["owner"]) == 0) else 0.0, 1.0)
	var view: Dictionary = GrantedCalc.compute(Build, aura_id, true)
	var view_dps: float = _row_value(view, "DPS vs enemy", "Against enemy")
	var part_dps: float = 0.0
	for part: Dictionary in melee["granted"]:
		part_dps += float(part["hit_enemy"]) + float(part["ail_dps"])
	_check("Flame Walker: virtual Fire Aura DPS = its component in the owner skill", view_dps, part_dps)
	_check("Flame Walker: virtual Fire Aura DPS is positive", 1.0 if view_dps > 0.0 else 0.0, 1.0)
	# one roll per second: 8 x 10% = 80%; the estimated active auras 0.8 x 4 s = 3.2 are not under 3: no doubling
	_check("Flame Walker: 0.8 casts per second (one 1 s tick, 80%)", CalcSummary.find_row(view, "Uses per second")["text"].to_float(), 0.8, 0.0005)
	Build.set_skill_input(0, "fire_auras", 1)
	_check("Flame Walker: 1 active aura set by hand: doubled, capped at 100%", CalcSummary.find_row(GrantedCalc.compute(Build, aura_id, true), "Uses per second")["text"].to_float(), 1.0, 0.0005)
	Build.set_skill_input(0, "fire_auras", 3)
	_check("Flame Walker: 3 active auras: no doubling", CalcSummary.find_row(GrantedCalc.compute(Build, aura_id, true), "Uses per second")["text"].to_float(), 0.8, 0.0005)
	Build.set_skill_input(0, "fire_auras", 0)
	# a spell bar that neither moves nor uses a Melee ability: no cast (the game checks IsMoving or a Melee ability in use)
	Build.set_skill(0, "fi9")
	_check("Flame Walker: a stationary spell bar casts no Fire Aura", float(_granted_skills().size()), 0.0)
	Build.player_state["moving"] = true
	_check("Flame Walker: the same bar while moving casts it", float(_granted_skills().size()), 1.0)
	Build.player_state["moving"] = false
	Build.set_skill(0, "fr11mv")
	# the temporary slot of the basic attack is never "the first slot": a buff skill does not own character events
	Build.set_skill(2, "sb44eQ")
	_check("first_skill_slot ignores a temporary slot after the bar", float(UniqueEffects.first_skill_slot(Build)), 0.0)
	Build.set_skill(2, "")
	# channelled skills drain channelCost per second on top of the one-off manaCost (BaseMana.getManaCost, channelCost = true)
	Build.set_skill(2, "dig5")
	_check("Disintegrate: channel cost 18 mana/s", _section_value(SkillCalc.compute(Build, 2), "Speed and mana", "Channel cost, mana/s"), 18.0)
	Build.set_skill(2, "dl73")
	_check("Drain Life: channel cost 23 mana/s", _section_value(SkillCalc.compute(Build, 2), "Speed and mana", "Channel cost, mana/s"), 23.0)
	Build.set_skill(2, "fi9")
	_check("Fireball: no channel cost row", _section_value(SkillCalc.compute(Build, 2), "Speed and mana", "Channel cost, mana/s"), -1.0)
	Build.set_skill(2, "")
	var lean: Dictionary = GrantedCalc.compute(Build, aura_id, false)
	_check("Flame Walker: lean virtual DPS equals the detailed one", _row_value(lean, "DPS vs enemy", "Against enemy"), view_dps)
	_check("Flame Walker: lean view has lazy rows", 1.0 if (bool(lean.get("lean", false)) and bool(lean["sections"][0]["rows"][0].get("lazy", false))) else 0.0, 1.0)
	# the owner keeps counting the component: its total is unchanged by looking at the view
	_check("Flame Walker: owner total unchanged", _row_value(SkillCalc.compute(Build, 0), "DPS vs enemy", "Against enemy"), _row_value(melee, "DPS vs enemy", "Against enemy"))
	var gone: Dictionary = GrantedCalc.compute(Build, "no such skill", true)
	_check("Flame Walker: unknown granted id gives an empty view", float((gone["sections"] as Array).size()), 0.0)
	# basic attack: always listed, a full calculation on a temporary slot, the bar is left as it was
	var basic: Dictionary = GrantedCalc.compute(Build, GrantedCalc.BASIC_ID, true)
	_check("Basic attack: listed first", 1.0 if bool(GrantedCalc.skills(Build)[0].get("basic", false)) else 0.0, 1.0)
	_check("Basic attack: has its own DPS", 1.0 if _row_value(basic, "DPS vs enemy", "Against enemy") > 0.0 else 0.0, 1.0)
	_check("Basic attack: the temporary slot is gone", float(Build.skills.size()), 5.0)
	# Fire Aura on the bar: it is a real slot, no virtual entry
	GameData._abilities["test_fire_aura"] = GameData.ability_by_name("FireAura")
	Build.set_skill(2, "test_fire_aura")
	_check("Fire Aura on the bar: no granted skills", float(_granted_skills().size()), 0.0)
	Build.set_skill(2, "")
	GameData._abilities.erase("test_fire_aura")
	Build.passives.erase(38)
	_check("Flame Walker removed: no granted skills", float(_granted_skills().size()), 0.0)
	_check("Flame Walker removed: the view is gone", float((GrantedCalc.compute(Build, aura_id, true)["sections"] as Array).size()), 0.0)
	Build.set_skill(0, "")
	Build.set_skill(1, "")


func _check(label: String, got: float, want: float, eps: float = 0.0005) -> void:
	if absf(got - want) > eps:
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


## Element-wise check of a count list (MinionCount.pick_counts).
func _check_counts(label: String, got: Array[float], want: Array) -> void:
	var same: float = 1.0 if got.size() == want.size() else 0.0
	for i: int in range(mini(got.size(), want.size())):
		same = minf(same, 1.0 if absf(got[i] - float(want[i])) < 0.0005 else 0.0)
	_check("%s (%s)" % [label, str(got)], same, 1.0)


## Trigger frequency and cooldown (docs/ENGINE.md §9.6).
func _triggers_cooldown() -> void:
	var trig: Dictionary = {"ability": "x", "on": "hit", "chance": 0.5, "count": 1.0, "icd": 1.0}
	_check("trigger on hit: min(0.75, 1/icd)", float(SkillCalc.trigger_rate(trig, 1.5, 1.0, 0.0, 0.0)["rate"]), 0.75)
	_check("trigger on hit: capped by icd", float(SkillCalc.trigger_rate(trig, 4.0, 1.0, 0.0, 0.0)["rate"]), 1.0)
	trig["on"] = "kill"
	_check("trigger on kill: events input", float(SkillCalc.trigger_rate(trig, 1.5, 1.0, 0.0, 3.0)["rate"]), 1.0)
	trig["icd"] = 0.0
	_check("trigger on kill: no icd", float(SkillCalc.trigger_rate(trig, 1.5, 1.0, 0.0, 3.0)["rate"]), 1.5)
	var store := StatStore.new()
	store.add(StatMod.make(LE.CDR, "increased", 1.0, 0, "test"))
	var cd: Dictionary = SkillCalc.cooldown_info({"cooldown": 4.0}, store, 0, {})
	_check("cooldown 4 s with +100% recovery", float(cd["cd"]), 2.0)
	_check("cooldown limits uses to 1/cd", minf(3.0, 1.0 / float(cd["cd"])), 0.5)
	var cd2: Dictionary = SkillCalc.cooldown_info({}, store, 0, {"cooldown_base": {"baseCooldownLength": 6.0, "charges": 2.0}, "cooldown": {"length_added": 2.0, "recovery_more": 1.0}})
	_check("cooldown from node: (6+2) / (2 × 2)", float(cd2["cd"]), 2.0)
	_check("cooldown charges", float(cd2["charges"]), 2.0)
	# ADDED SP 70 (gear) sums with the increased part; Minion/Totem-tagged stats are skipped; Smoke Bomb's minimum is a floor
	var cdg := StatStore.new()
	cdg.add(StatMod.make(LE.CDR, "added", 0.5, 0, "gear"))
	cdg.add(StatMod.make(LE.CDR, "increased", 0.5, 0, "passive"))
	cdg.add(StatMod.make(LE.CDR, "added", 1.0, LE.MINION, "minion gear"))
	_check("cooldown: added + increased recovery, Minion-tagged skipped", float(SkillCalc.cooldown_info({"cooldown": 4.0}, cdg, LE.MINION, {})["cd"]), 2.0)
	_check("cooldown: minimum cooldown floor", float(SkillCalc.cooldown_info({"cooldown": 4.0}, cdg, 0, {"params": {"Min": {"param": "min_cooldown", "set": 3.0}}})["cd"]), 3.0)


## Own-rate models (EffectModels.auto_input / use_interval, SkillCalc.skill_rates), Soul Bastion's every-5th kill, the recent-crit share (PP 419 / 89).
func _own_rates_vectors() -> void:
	var und: Dictionary = {"auto": {"rate": "hits", "window": 4.0, "tag": "Melee"}, "max": 51}
	var melee_rates: Dictionary = {"hits": 2.0, "uses": 2.0, "tags": LE.MELEE}
	_check("auto stacks: 2 melee hits/s x 4 s", EffectModels.auto_input(und, melee_rates, 1.0), 8.0)
	_check("auto stacks: bleed uptime 0.5", EffectModels.auto_input(und, melee_rates, 0.5), 4.0)
	_check("auto stacks: capped at 51", EffectModels.auto_input(und, {"hits": 20.0, "uses": 2.0, "tags": LE.MELEE}, 1.0), 51.0)
	_check("auto stacks: no melee tag gives 0", EffectModels.auto_input(und, {"hits": 2.0, "uses": 2.0, "tags": LE.LIGHTNING}, 1.0), 0.0)
	var searing: Dictionary = {"auto": {"rate": "uses", "window": 16.0, "tag": "Melee"}}
	_check("auto Searing Blades: 2 uses/s x 16 s", EffectModels.auto_input(searing, {"hits": 5.0, "uses": 2.0, "tags": LE.MELEE}, 1.0), 32.0)
	_flag("auto model is a skill-phase model", EffectModels.phase({"kind": "stat", "stat": "Damage", "input": {"key": "k", "auto": {"rate": "hits", "window": 4.0}}}) == "skill")
	_flag("use_interval model is a skill-phase model", EffectModels.phase({"use_interval": 2.0}) == "skill")
	_check("use_interval: 200 × 1/(2 × 3 uses/s)", float(EffectModels.value({"factor": 1.0, "use_interval": 2.0}, 200.0, {"skill_rates": {"uses": 3.0}})["x"]), 200.0 / 6.0)
	_check("use_interval: 0.4 uses/s is always enhanced", float(EffectModels.value({"factor": 1.0, "use_interval": 2.0}, 200.0, {"skill_rates": {"uses": 0.4}})["x"]), 200.0)
	_check("use_interval: 0.5 uses/s is always enhanced", float(EffectModels.value({"factor": 1.0, "use_interval": 2.0}, 200.0, {"skill_rates": {"uses": 0.5}})["x"]), 200.0)
	_check("use_interval: 1 use/s is every other use", float(EffectModels.value({"factor": 1.0, "use_interval": 2.0}, 200.0, {"skill_rates": {"uses": 1.0}})["x"]), 100.0)
	_check("use_interval: no rates, no share", float(EffectModels.value({"factor": 1.0, "use_interval": 2.0}, 200.0, {})["x"]), 200.0)
	# Soul Bastion: every 5th kill, the 5 kills within 10 s (4 gaps of 1/k s must fit in the window)
	var soul: Dictionary = {"ability": "x", "on": "kill", "every": 5.0, "window": 10.0, "count": 1.0}
	_check("Soul Bastion: 1 kill/s gives 0.2 casts/s", float(SkillCalc.trigger_rate(soul, 1.5, 1.0, 0.0, 1.0)["rate"]), 0.2)
	_check("Soul Bastion: 0.5 kills/s gives 0.1 casts/s", float(SkillCalc.trigger_rate(soul, 1.5, 1.0, 0.0, 0.5)["rate"]), 0.1)
	_check("Soul Bastion: 0.3 kills/s is too slow: 0", float(SkillCalc.trigger_rate(soul, 1.5, 1.0, 0.0, 0.3)["rate"]), 0.0)
	_check("Soul Bastion: 3 kills/s gives 0.6 casts/s", float(SkillCalc.trigger_rate(soul, 1.5, 1.0, 0.0, 3.0)["rate"]), 0.6)
	# recent-crit share: bisection of r = 1 - exp(-4 × hits × ((1 - r) × a + r × b)), a / b clamped to 0..1
	_check("recent crit share: equal chances", SkillCalc.recent_crit_share(0.5, 0.5, 0.5), 1.0 - exp(-1.0))
	_check("recent crit share: no hits", SkillCalc.recent_crit_share(0.0, 0.5, 0.5), 0.0)
	_check("recent crit share: no crit while not recent", SkillCalc.recent_crit_share(0.5, 0.0, 0.5), 0.0)
	_check("recent crit share: 0.25 hits/s, a 105% clamped to 100%", SkillCalc.recent_crit_share(0.25, 1.05, 0.05), 0.4407970)
	_check("recent crit share: 2 hits/s, 50% / 25%", SkillCalc.recent_crit_share(2.0, 0.5, 0.25), 0.8911424)
	_check("recent crit share: 1 hit/s, 105% / 2.5%", SkillCalc.recent_crit_share(1.0, 1.05, 0.025), 0.7090638)
	var r_mix: float = SkillCalc.recent_crit_share(2.0, 0.5, 0.25)
	_check("recent crit mixture: 50% / 25% chance", (1.0 - r_mix) * 0.5 + r_mix * 0.25, 0.2772144)


func _vectors() -> void:
	_triggers_cooldown()
	_own_rates_vectors()
	_check("round_half_even(2.5)", LE.round_half_even(2.5), 2)
	_check("round_half_even(3.5)", LE.round_half_even(3.5), 4)
	_check("round_half_even(1028.5)", LE.round_half_even(1028.5), 1028)
	_check("affix Integer [5,10] roll 128", AffixMath.roll_value(5, 10, "Integer", "ADDED", 128, 0.0), 8)
	_check("affix Integer [5,10] roll 255", AffixMath.roll_value(5, 10, "Integer", "ADDED", 255, 0.0), 10)
	_check("affix inc [0.10,0.20] roll 200", AffixMath.roll_value(0.10, 0.20, "Hundredth", "INCREASED", 200, 0.0), 0.18)
	_check("affix inc [0.10,0.20] m 0.5 roll 255", AffixMath.roll_value(0.10, 0.20, "Hundredth", "INCREASED", 255, 0.5), 0.30)
	_check("affix [61,90] m 0.5 roll 0", AffixMath.roll_value(61, 90, "Integer", "ADDED", 0, 0.5), 92)
	_check("affix [61,90] m 0.5 roll 255", AffixMath.roll_value(61, 90, "Integer", "ADDED", 255, 0.5), 135)
	_check("affix descending [20,5] roll 0 = first number", AffixMath.roll_value(20, 5, "Integer", "ADDED", 0, 0.0), 20)
	_check("affix descending [20,5] roll 128", AffixMath.roll_value(20, 5, "Integer", "ADDED", 128, 0.0), 12)
	_check("affix descending [20,5] roll 255 = second number", AffixMath.roll_value(20, 5, "Integer", "ADDED", 255, 0.0), 5)
	_check("affix descending [-0.06,-0.20] roll 255", AffixMath.roll_value(-0.06, -0.20, "Hundredth", "INCREASED", 255, 0.0), -0.20)
	_check("affix descending [-0.06,-0.20] roll 0", AffixMath.roll_value(-0.06, -0.20, "Hundredth", "INCREASED", 0, 0.0), -0.06)
	_check("effect_modifier 2H axe", AffixMath.effect_modifier(2.2, 0.75), 0.8286)
	_check("armour 1000 L50 phys", Enemy.armour_mitigation(1000, 50, false), 0.32390)
	_check("armour 1000 L50 non-phys", Enemy.armour_mitigation(1000, 50, true), 0.22673)
	_check("armour 3000 L75", Enemy.armour_mitigation(3000, 75, false), 0.53613)
	_check("armour -500 L75", Enemy.armour_mitigation(-500, 75, false), -0.19396)
	_check("tags Elemental vs Fire", 1.0 if LE.tags_match(LE.ELEMENTAL, LE.FIRE) else 0.0, 1.0)
	_check("tags Elemental|Spell vs Fire|Melee", 1.0 if LE.tags_match(LE.ELEMENTAL | LE.SPELL, LE.FIRE | LE.MELEE) else 0.0, 0.0)
	_check("block 1000 L50", CharacterCalc.block_mitigation(1000, 50), 0.45132)
	_check("block 2000 L75", CharacterCalc.block_mitigation(2000, 75), 0.54069)
	_check("block 500 L100", CharacterCalc.block_mitigation(500, 100), 0.26428)
	_check("fmt_pct 9.8298%", 1.0 if LE.fmt_pct(0.098298) == "9.83%" else 0.0, 1.0)
	_check("level DR boss 75", Enemy.level_dr({"kind": "boss", "level": 75}), 0.7625)
	_check("level DR normal 50", Enemy.level_dr({"kind": "normal", "level": 50}), 0.54)
	# corruption power (06c §7): f(50) = 30, f(100) = 60, f(300) = 280.455; DoT more is half of health/hit
	_check("corruption f(50)", Enemy.corruption_power(50), 30.0)
	_check("corruption f(100)", Enemy.corruption_power(100), 60.0)
	_check("corruption f(300)", Enemy.corruption_power(300), 280.455, 0.01)
	_check("corruption 300 DoT more", float(Enemy.corruption_more({"corruption": 300})["dot"]), 1.402275, 0.0001)

	# 06a T1
	var store := StatStore.new()
	store.add(StatMod.make(LE.DAMAGE, "added", 10, LE.FIRE | LE.SPELL))
	store.add(StatMod.make(LE.DAMAGE, "increased", 0.5, LE.FIRE))
	store.add(StatMod.make(LE.DAMAGE, "increased", 0.3, LE.FIRE | LE.SPELL))
	store.add(StatMod.make(LE.DAMAGE, "more", 0.2, LE.FIRE))
	store.add(StatMod.make(LE.DAMAGE, "more", 0.1, 0))
	store.add(StatMod.make(LE.DAMAGE, "increased", 1.0, LE.COLD))
	_check("06a T1 Fire|Spell", store.query(LE.DAMAGE, LE.FIRE | LE.SPELL).value(), 23.76)
	_check("06a T1 Fire", store.query(LE.DAMAGE, LE.FIRE).value(), 0.0)

	# Movement speed row: Stats.GetTotalModifier = (1 + Σinc) · Πmore - 1, added excluded
	var mv_store := StatStore.new()
	mv_store.add(StatMod.make(LE.MOVESPEED, "increased", 0.4))
	mv_store.add(StatMod.make(LE.MOVESPEED, "increased", 0.1))
	mv_store.add(StatMod.make(LE.MOVESPEED, "more", 0.05))
	mv_store.add(StatMod.make(LE.MOVESPEED, "more", 0.1))
	mv_store.add(StatMod.make(LE.MOVESPEED, "added", 5.0))
	var mv_row: Dictionary = {}
	for mv_r: Dictionary in CharacterCalc._compute_other(mv_store):
		if mv_r["label"] == "Movement speed":
			mv_row = mv_r
	_check("Movement speed: (1 + Σinc) · Πmore - 1, added not counted", float(mv_row["value"]), 0.7325, 0.0001)
	var mv_none: Dictionary = {}
	for mv_r: Dictionary in CharacterCalc._compute_other(StatStore.new()):
		if mv_r["label"] == "Movement speed":
			mv_none = mv_r
	_check("Movement speed: no mods gives 0", float(mv_none["value"]), 0.0, 0.0001)

	# 06a T4 quotient
	_check("quotient 0.25", StatMod.make(LE.DAMAGE, "quotient", 0.25).more[0], -0.2)


func _sample_build() -> void:
	Build.set_class(1)  # Mage
	Build.set_level(100)
	print("--- Mage L100, no gear")
	var g: Dictionary = BuildMods.global_store(Build)
	for row: Dictionary in CharacterCalc.compute(g["store"], Build):
		if row["label"] in ["Health", "Mana", "Intelligence", "Health regen", "Stun avoidance"]:
			print("  %s = %s" % [row["label"], row["text"]])
	_check("Mage L100 health 100+10·100", _row(g, "Health"), 1100)
	_check("Mage L100 mana round(50+0.50506·100)", _row(g, "Mana"), 101)
	_check("Mage intelligence", _row(g, "Intelligence"), 3)

	# Unique: Snowblind (cold res 0.2–0.4, rollID 0) at roll 255 and roll 0
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	g = BuildMods.global_store(Build)
	_check("Snowblind cold res roll 255", Enemy.resistance(g["store"], 2).added, 0.40)
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [0, 255, 255]})
	g = BuildMods.global_store(Build)
	_check("Snowblind cold res roll 0 (fixed value)", Enemy.resistance(g["store"], 2).added, 0.20)
	_check("Snowblind special effects listed", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains("Snowblind") else 0.0, 1.0)
	Build.clear_item("helmet")
	# Set: Isadora's — 2 distinct items enable the 2-piece Damned chance, not the 3-piece bonuses
	var damned: int = GameData.enum_value("AilmentID", "Damned")
	Build.set_item("helmet", {"unique": 5, "base": int(GameData.unique(5)["baseType"]), "sub": 0, "implicit_rolls": [], "unique_rolls": []})
	Build.set_item("ring1", {"unique": 16, "base": int(GameData.unique(16)["baseType"]), "sub": 0, "implicit_rolls": [], "unique_rolls": []})
	g = BuildMods.global_store(Build)
	_check("Isadora 2/3: Damned chance", g["store"].query(LE.AILMENT_CHANCE, LE.NECROTIC | LE.SPELL, damned).added, 1.0)
	_check("Isadora 2/3: no mana efficiency", g["store"].query(LE.MANA_EFFICIENCY, LE.NECROTIC | LE.SPELL).added, 0.0)
	Build.set_item("ring2", {"unique": 16, "base": int(GameData.unique(16)["baseType"]), "sub": 0, "implicit_rolls": [], "unique_rolls": []})
	g = BuildMods.global_store(Build)
	_check("same set item twice still counts once", g["store"].query(LE.MANA_EFFICIENCY, LE.NECROTIC | LE.SPELL).added, 0.0)
	Build.set_item("amulet", {"unique": 423, "base": int(GameData.unique(423)["baseType"]), "sub": 0, "implicit_rolls": [], "unique_rolls": []})
	g = BuildMods.global_store(Build)
	_check("Legends Entwined completes the 3-piece bonus", g["store"].query(LE.MANA_EFFICIENCY, LE.NECROTIC | LE.SPELL).added, 0.3)
	for slot: String in ["helmet", "ring1", "ring2", "amulet"]:
		Build.clear_item(slot)
	_unique_special_effects()
	_minion_skill()

	# Fireball: Fire 25, ADE 1.25, +4% inc per Int (Int 3 → +12%)
	Build.set_skill(0, "fi9")
	Build.selected_skill = 0
	Build.set_enemy("kind", "dummy")
	var r: Dictionary = SkillCalc.compute(Build, 0)
	print("--- %s" % r["title"])
	_print_sections(r)
	_check("Fireball fire hit 25 × 1.12", _section_value(r, "Damage per use (before enemy)", "Fire"), 28.0)
	# Ignite (06d): 40% chance from the Fireball prefab, base 40 fire / 2.5 s, +12% generic damage from Int
	_check("Ignite chance", _section_value(r, "Ailment: Ignite", "Application chance"), 40.0)
	_check("Ignite stack damage 40 × 1.12", _section_value(r, "Ailment: Ignite", "Total damage of one stack"), 44.8)
	_check("Ignite DPS = uses × 0.4 × 44.8", _section_value(r, "Ailment: Ignite", "DPS (without enemy)"), 1.1 / 0.75 * 0.4 * 44.8, 0.01)
	_check("Ignite stacks = rate × 2.5", _section_value(r, "Ailment: Ignite", "Average stacks on target"), 1.1 / 0.75 * 0.4 * 2.5, 0.01)
	# Carrion of Creation: SP 100 converts the Ignite chance into Bleed
	Build.set_item("gloves", {"unique": 431, "base": 4, "sub": 12, "implicit_rolls": [0, 0], "unique_rolls": [0, 0, 0, 0]})
	var conv_r: Dictionary = SkillCalc.compute(Build, 0)
	_check("Carrion: no Ignite left", 1.0 if _section_value(conv_r, "Ailment: Ignite", "Application chance") <= 0.0 else 0.0, 1.0)
	_check("Carrion: Bleed = 100% item + 40% converted", _section_value(conv_r, "Ailment: Bleed", "Application chance"), 140.0)
	Build.clear_item("gloves")
	# Oceareon SP 115: more damage per Shock stack on the target
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 10)
	var no_ring: float = _section_value(SkillCalc.compute(Build, 0), "Against enemy", "Hit DPS vs enemy")
	Build.set_item("ring1", {"unique": 125, "base": 21, "sub": 2, "implicit_rolls": [0, 0], "unique_rolls": [0, 0, 0, 0, 0, 0]})
	var per_stack: float = 0.0
	for umod: Dictionary in GameData.unique(125)["mods"]:
		if int(umod["property"]) == LE.DAMAGE_PER_AILMENT_STACK:
			per_stack = AffixMath.unique_value(umod, 0)
	_check("Oceareon: ×(1 + per stack × 10 shocks)", _section_value(SkillCalc.compute(Build, 0), "Against enemy", "Hit DPS vs enemy") / no_ring, 1.0 + per_stack * 10.0, 0.002)
	Build.clear_item("ring1")
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 0)

	# Wand (Rowan Wand: +3 spell damage), Increased Fire Damage T5 roll 255
	Build.set_item("weapon", {"base": 10, "sub": 1, "implicit_rolls": [255, 255], "affixes": [{"id": 12, "tier": 5, "roll": 255}]})
	Build.set_enemy("kind", "boss")
	Build.set_enemy("level", 75)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 10)
	r = SkillCalc.compute(Build, 0)
	print("--- %s with wand vs boss L75, 10 shock" % r["title"])
	_print_sections(r)
	for n: String in r["notes"]:
		print("  note: " + n)

	# Fill the base Mage tree and Fireball tree greedily, then recompute
	var tree: Dictionary = GameData.get_passive_tree(1)
	for _pass in range(6):
		for node: Dictionary in tree["nodes"]:
			if int(node["mastery"]) == 0:
				while Build.add_point(int(node["id"])):
					pass
	print("--- passives spent: %d" % Build.spent_points())
	var fb_tree: Dictionary = GameData.get_skill_tree("fi9")
	for node_name: String in ["Fireball Projectile Speed And Damage", "Fireball Fire Penetration", "Fireball Cast Speed"]:
		for node: Dictionary in fb_tree["nodes"]:
			if node["name"] == node_name:
				while Build.add_skill_point(0, int(node["id"])):
					pass
	print("--- fireball tree spent: %d" % Build.skill_points_spent(0))
	# Idol: Small Eterran Idol with its first suffix at the first open cell
	var idol_base: Dictionary = GameData.item_base(25)
	var idol_affixes: Array = GameData.affixes_for_type(25, "Mage")
	for affix: Dictionary in idol_affixes:
		if affix["type"] == "SUFFIX":
			Build.set_item(IdolGrid.key(1, 0), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": [{"id": int(affix["affixId"]), "tier": 1, "roll": 255, "index": 2}]})
			print("--- idol %s with %s; fits 2x1 at (1,0) now: %s" % [GameData.display_name(idol_base), affix["name"], IdolGrid.fits(Build.items, 1, 0, 27)])
			break
	_check("idol blocks its cell", 0.0 if IdolGrid.fits(Build.items, 1, 0, 25) else 1.0, 1.0)
	_check("blocked corner cell", 0.0 if IdolGrid.is_open(0, 0) else 1.0, 1.0)
	g = BuildMods.global_store(Build)
	for row: Dictionary in CharacterCalc.compute(g["store"], Build):
		print("  %s / %s = %s" % [row["group"], row["label"], row["text"]])
	r = SkillCalc.compute(Build, 0)
	_print_sections(r)
	for n: String in r["notes"]:
		print("  note: " + n)

	# Conversion: Fireball "Added Lightning Damage" node converts 50% of base fire per point to lightning
	Build.set_skill(0, "fi9")
	for node: Dictionary in fb_tree["nodes"]:
		if node["name"] == "Fireball Added Lightning Damage":
			_allocate_path(fb_tree, int(node["id"]), int(node["maxPoints"]))
	print("--- fireball with lightning conversion node, tree spent %d" % Build.skill_points_spent(0))
	r = SkillCalc.compute(Build, 0)
	_print_sections(r)

	# Components: Meteor has no primary damage, its hit comes from the MeteorAoe sub-ability (Fire 240)
	Build.set_skill(0, "me27")
	r = SkillCalc.compute(Build, 0)
	print("--- %s components" % r["title"])
	_print_sections(r)
	var aoe_breakdown: String = ""
	for section: Dictionary in r["sections"]:
		if section["title"] == "Damage per use (before enemy)":
			for row: Dictionary in section["rows"]:
				if row["label"] == "Fire":
					aoe_breakdown = str(row["breakdown"])
	_check("Meteor: MeteorAoe base fire 240", 1.0 if aoe_breakdown.contains("Base: 240") else 0.0, 1.0)
	_check("Meteor: fire damage >= 240", 1.0 if _section_value(r, "Damage per use (before enemy)", "Fire") >= 240.0 else 0.0, 1.0)
	_check("Meteor: hit vs enemy > 0", 1.0 if _section_value(r, "Against enemy", "Average hit vs enemy") > 0.0 else 0.0, 1.0)
	_check("Meteor: DPS vs enemy > 0", 1.0 if _section_value(r, "Against enemy", "DPS vs enemy") > 0.0 else 0.0, 1.0)

	# Blessings: choose first timeline's first blessing with a non-104 implicit at roll 255
	var timelines: Array = GameData.blessing_timelines()
	for timeline: Dictionary in timelines:
		var timeline_id: int = int(timeline.get("timelineID", -1))
		if timeline_id == 99:  # Skip Activities
			continue
		var blessing_ids: Array[int] = GameData.blessings_for_timeline(timeline_id)
		for blessing_id: int in blessing_ids:
			var blessing: Dictionary = GameData.blessing(blessing_id)
			if blessing.is_empty():
				continue
			var implicits: Array = blessing.get("implicits", [])
			var has_non_104: bool = false
			for implicit: Dictionary in implicits:
				if int(implicit.get("property", 0)) != 104:
					has_non_104 = true
					break
			if has_non_104:
				Build.set_blessing(timeline_id, blessing_id, 255)
				g = BuildMods.global_store(Build)
				var blessing_source_found: bool = false
				for mod: StatMod in g["store"].all_mods():
					if mod.source.begins_with("Blessing"):
						blessing_source_found = true
						break
				_check("Blessing mod in global store", 1.0 if blessing_source_found else 0.0, 1.0)
				Build.set_blessing(timeline_id, -1, 0)
				break
		break

	Build.set_skill(0, "fi9")


## Summon Wolf: the wolf's attack is a minion component with its own DPS (§9.4).
func _minion_skill() -> void:
	Build.set_skill(3, "wo42")
	var r: Dictionary = SkillCalc.compute(Build, 3)
	var wolf_dps: float = -1.0
	for s: Dictionary in r["sections"]:
		for row: Dictionary in s["rows"]:
			if str(row["label"]).begins_with("DPS vs enemy: Primal Wolf") or (str(row["label"]) == "DPS vs enemy" and wolf_dps < 0.0):
				wolf_dps = float(str(row["text"]))
	print("--- Summon Wolf: %s" % str(r["sections"].map(func(x: Dictionary) -> String: return x["title"])))
	_check("Summon Wolf deals minion DPS", 1.0 if wolf_dps > 0.0 else 0.0, 1.0)
	_flag("Summon Wolf: the wolf count is not a skill field (Conditions tab)", not str(r.get("inputs", [])).contains("\"minions\""))
	_check("one wolf by its summon limit", float(MinionCount.count(Build, "wolves")["value"]), 1.0)
	_check("all minions = the summoned wolf", float(MinionCount.count(Build, "minions")["value"]), 1.0)
	Build.set_minion_count("Primal Wolf", 3.0)
	var r3: Dictionary = SkillCalc.compute(Build, 3)
	_check("3 wolves set by hand: wolves count", float(MinionCount.count(Build, "wolves")["value"]), 3.0)
	_check("3 wolves set by hand: triple wolf DPS", _dps(r3), _dps(r) * 3.0, _dps(r) * 0.01)
	Build.set_minion_count("minions", 7.0)
	_check("all minions set by hand win over the sum", float(MinionCount.count(Build, "minions")["value"]), 7.0)
	Build.clear_minion_counts()
	_flag("relevance lists the summoned wolf", ConfigRelevance.compute(Build)["minions"].has("Primal Wolf"))
	Build.set_skill(3, "")
	_minion_limits()


## Summon limits: the base of the code plus passives aimed at the summon's mutator (Unbound Necromancy, Tyrant's Legion:
## SummonSkeletonMutator.additionalSkeletonsFromPassives +1 at 3 points each).
func _minion_limits() -> void:
	var class_id: int = Build.class_id
	var saved_passives: Dictionary = Build.passives.duplicate()
	var saved_skills: Array[Dictionary] = Build.skills.duplicate(true)
	Build.set_class(3)  # Acolyte
	Build.set_skill(0, "ss37kl")  # Summon Skeleton
	_check("Summon Skeleton: base limit 3", _type_limit("Skeletons"), 3.0)
	Build.passives[12] = 3
	Build.passives[61] = 3
	Build.changed.emit()
	_check("Unbound Necromancy + Tyrant's Legion: 3 + 1 + 1", _type_limit("Skeletons"), 5.0)
	_check("all minions follow the raised limit", float(MinionCount.count(Build, "minions")["value"]), 5.0)
	# damage: the 5 skeletons split between warriors and archers (the default rotation), each its own minion component
	var sk: Dictionary = SkillCalc.compute(Build, 0)
	var warrior: float = _section_dps(sk, "Skeleton Warrior")
	var archer: float = _section_dps(sk, "Skeleton Archer")
	_flag("Summon Skeleton: warriors deal damage", warrior > 0.0)
	_flag("Summon Skeleton: archers deal damage", archer > 0.0)
	_flag("Summon Skeleton: no rogues without their node", _section_dps(sk, "Skeleton Rogue") == 0.0)
	var split: Array[Dictionary] = MinionCount.members(Build, "SummonSkeleton")
	_check("warriors and archers share the 5 skeletons", float(split[0]["count"]) + float(split[1]["count"]) if split.size() == 2 else -1.0, 5.0)
	_check("rogues' «per warrior or archer» count", float(MinionCount.count(Build, "warriors_archers")["value"]), 5.0)
	Build.set_minion_count("Skeletons", 10.0)
	_check("10 skeletons by hand: double the skeleton DPS", _section_dps(SkillCalc.compute(Build, 0), "Skeleton Warrior"), warrior * 2.0, warrior * 0.01)
	Build.clear_minion_counts()
	Build.set_skill(1, "sm4g")  # Summon Skeletal Mage
	var mg: Dictionary = SkillCalc.compute(Build, 1)
	_flag("Summon Skeletal Mage: the mage's Dread Bolt is its damage", str(mg["sections"]).contains("Skeleton Mage") and _dps(mg) > 0.0)
	_check("Skeletal Mages: base limit 2", _type_limit("Skeletal Mages"), 2.0)
	# Tyrant's Legion: +4% physical / poison penetration for skeletons per point (AbilityProperty 7, 8)
	var warrior_comp: Dictionary = {}
	for c: Dictionary in SkillComponents.collect(Build, 0, GameData.get_ability("ss37kl"), BuildMods.skill_store(Build, 0, BuildMods.global_store(Build)["store"])):
		if str(c["name"]).begins_with("Skeleton Warrior"):
			warrior_comp = c
	_check("Tyrant's Legion ×3: skeletons' physical penetration", (warrior_comp["store"] as StatStore).query(LE.PENETRATION, LE.PHYSICAL).added if not warrior_comp.is_empty() else -1.0, 0.12, 0.0001)
	_flag("Tyrant's Legion: no «not counted» note for the skeleton penetration", not str(BuildMods.global_store(Build)["notes"]).contains("Tyrant"))
	# minion AI priority: Bone Golem's Big Slam («Maul», 6 s cooldown) when ready, the melee fills the rest, Rampage (after it) never
	var golem_ab: Dictionary = GameData.get_ability("bg36nl")
	var golem: Array[Dictionary] = MinionCalc.components(BuildMods.global_store(Build)["store"], golem_ab, [], Build)
	var names: Array = golem.map(func(c: Dictionary) -> String: return str(c["name"]))
	var slam: float = -1.0
	for c: Dictionary in golem:
		if str(c["name"]).contains("Maul"):
			slam = float(c["rate"])
	_check("Big Slam once per 6 s cooldown", slam, 1.0 / 6.0, 0.001)
	_flag("Bone Golem melee fills the rest of the time", str(names).contains("golemMelee") or names.size() >= 2)
	_flag("Rampage after the melee is never used", not str(names).contains("Rampage"))
	# companion limit: banker's rounding, per-type cap, PlayerProperty 85
	_check("companion limit rounds half to even: 2.5 -> 2", MinionCount.round_companions(2.5), 2.0)
	_check("companion limit rounds half to even: 3.5 -> 4", MinionCount.round_companions(3.5), 4.0)
	_check("companion limit: 5 wolves under a limit of 2 -> 2", MinionCount.companion_cap(5.0, 2.0, false), 2.0)
	_check("companion limit: one companion of each type -> 1", MinionCount.companion_cap(5.0, 2.0, true), 1.0)
	_check("companion limit: below the limit stays", MinionCount.companion_cap(1.0, 3.0, false), 1.0)
	# wolf worth 120 of the shared budget (summonWolfCountAsTwoForLimit): floor(maximum x 60 / 120)
	_check("companion limit: wolf worth 120 under maximum 2 -> 1", MinionCount.companion_cap(5.0, 2.0, false, 120.0), 1.0)
	_check("companion limit: wolf worth 120 under maximum 3 -> 1", MinionCount.companion_cap(5.0, 3.0, false, 120.0), 1.0)
	_check("companion limit: wolf worth 120 under maximum 4 -> 2", MinionCount.companion_cap(5.0, 4.0, false, 120.0), 2.0)
	# shared budget between companion types: the counts with the largest DPS that fit (hand-computed)
	var pick: Array[Dictionary] = [{"max": 2.0, "cost": 60.0, "dps": 10.0}, {"max": 2.0, "cost": 60.0, "dps": 25.0}]
	_check_counts("shared budget: 0 + 2 (50 beats 1 + 1 = 35)", MinionCount.pick_counts(pick, 120.0), [0.0, 2.0])
	pick = [{"max": 2.0, "cost": 60.0, "dps": 30.0}, {"max": 2.0, "cost": 60.0, "dps": 25.0}]
	_check_counts("shared budget: 2 + 0 (60 beats 55 and 50)", MinionCount.pick_counts(pick, 120.0), [2.0, 0.0])
	pick = [{"max": 1.0, "cost": 120.0, "dps": 60.0}, {"max": 2.0, "cost": 60.0, "dps": 25.0}]
	_check_counts("shared budget: wolf 1 + 0 (60 beats 50)", MinionCount.pick_counts(pick, 120.0), [1.0, 0.0])
	pick = [{"max": 1.0, "cost": 120.0, "dps": 40.0}, {"max": 2.0, "cost": 60.0, "dps": 25.0}]
	_check_counts("shared budget: 0 + 2 (50 beats 40)", MinionCount.pick_counts(pick, 120.0), [0.0, 2.0])
	pick = [{"max": 1.0, "cost": 120.0, "dps": 60.0}, {"max": 2.0, "cost": 60.0, "dps": 25.0}]
	_check_counts("shared budget 180: 1 + 1 (85 beats 60 and 50)", MinionCount.pick_counts(pick, 180.0), [1.0, 1.0])
	pick = [{"max": 1.0, "cost": 60.0, "dps": 10.0}, {"max": 1.0, "cost": 60.0, "dps": 10.0}]
	_check_counts("shared budget tie: the earlier item (bar order) keeps it", MinionCount.pick_counts(pick, 60.0), [1.0, 0.0])
	pick = [{"max": 3.0, "cost": 60.0, "dps": 5.0}]
	_check_counts("shared budget: one type capped by the budget", MinionCount.pick_counts(pick, 120.0), [2.0])
	Build.set_class(0)  # Primalist
	_check("two companions by default", float(MinionCount.max_companions(Build)["value"]), 2.0)
	Build.passives[14] = 1  # Artor's Loyalty (PlayerProperty 85, flat 1.0)
	Build.changed.emit()
	_check("Artor's Loyalty: exactly one companion (PlayerProperty 85)", float(MinionCount.max_companions(Build)["value"]), 1.0)
	_flag("PlayerProperty 85 has no 'Maximum Companion' note", not str(BuildMods.global_store(Build)["notes"]).contains("Maximum Companion"))
	Build.set_class(class_id)
	Build.passives = saved_passives
	for i: int in range(saved_skills.size()):
		Build.skills[i] = saved_skills[i]
	Build.changed.emit()


## Sum of the DPS rows of the minion components whose name starts with the actor.
func _section_dps(r: Dictionary, actor: String) -> float:
	var total: float = 0.0
	for sec: Dictionary in r["sections"]:
		for row: Dictionary in sec["rows"]:
			if str(row["label"]).begins_with(LE.t("DPS vs enemy") + ": " + actor):
				total += float(str(row["text"]))
	return total


func _type_limit(actor: String) -> float:
	for t: Dictionary in MinionCount.types(Build):
		if str(t["actor"]) == actor:
			return float(t["limit"])
	return -1.0


## Special effects of uniques (unique_effect_models.json, docs/ENGINE.md §5.4.3).
func _unique_special_effects() -> void:
	var chill: int = GameData.enum_value("AilmentID", "Chill")
	# Snowblind PP 454: 24% more armour against chilled attackers (rollID 2 at 255), only while the enemy is chilled
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	var g: Dictionary = BuildMods.global_store(Build)
	_check("Snowblind armour more without chill", g["store"].query_untagged(LE.ARMOUR).more, 1.0)
	_check("Snowblind condition listed", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains("counted when") else 0.0, 1.0)
	Build.set_enemy_ailment(chill, 1)
	g = BuildMods.global_store(Build)
	_check("Snowblind armour more vs chilled", g["store"].query_untagged(LE.ARMOUR).more, 1.24)
	Build.set_enemy_ailment(chill, 0)
	Build.clear_item("helmet")
	# Apostate's Sanctuary PP 285: +2 health per Vitality (after attributes)
	Build.set_item("amulet", {"unique": 290, "base": 20, "sub": 7, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	g = BuildMods.global_store(Build)
	var per_vit: float = 0.0
	for mod: StatMod in g["store"].query_untagged(LE.HEALTH).mods:
		if mod.source.contains("Health per Vitality"):
			per_vit += mod.added
	_check("Apostate's health = 2 × Vitality", per_vit, 2.0 * _row(g, "Vitality"))
	Build.clear_item("amulet")
	# Haste toggle: +30% increased movement speed
	Build.set_player_state("haste", true)
	g = BuildMods.global_store(Build)
	_check("Haste on you: +30% movespeed", g["store"].query_untagged(LE.MOVESPEED).increased, 0.3)
	Build.set_player_state("haste", false)
	# Eye of Orexia AbilityProperty 78:0: +120% increased Volcanic Orb damage, only for Volcanic Orb
	Build.set_item("relic", {"unique": 182, "base": 22, "sub": 22, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255, 255, 255]})
	Build.set_skill(1, "vo54")
	Build.set_skill(2, "fi9")
	g = BuildMods.global_store(Build)
	var vo: Dictionary = BuildMods.skill_store(Build, 1, g["store"])
	var fb: Dictionary = BuildMods.skill_store(Build, 2, g["store"])
	_check("Eye of Orexia: Volcanic Orb increased damage", vo["store"].query(LE.DAMAGE, LE.FIRE | LE.SPELL).increased - fb["store"].query(LE.DAMAGE, LE.FIRE | LE.SPELL).increased, 1.2)
	Build.clear_item("relic")
	Build.set_skill(1, "")
	Build.set_skill(2, "")
	# Frozen is an enemy flag (CDP 20), not an ailment
	_check("CDP 20 frozen flag", Enemy.has_condition({"flags": {"frozen": true}, "ailments": {}}, 20), 1.0)
	_check("#56 CDP 0 stunned flag", Enemy.has_condition({"flags": {"stunned": true}, "ailments": {}}, 0), 1.0)
	_check("#56 CDP 0 true for frozen", Enemy.has_condition({"flags": {"frozen": true}, "ailments": {}}, 0), 1.0)
	_check("#56 CDP 0 neither flag", Enemy.has_condition({"flags": {}, "ailments": {}}, 0), 0.0)
	_check("#56 CDP 20 frozen not satisfied by stunned only", Enemy.has_condition({"flags": {"stunned": true}, "ailments": {}}, 20), 0.0)
	_unique_component_models()
	_unique_skill_level_models()
	_unique_skill_filters()
	_all_uniques_smoke()


## Component models, player-stat models scaled by an ailment on you, copies of the player's stats, the input slot of
## character-wide models (#109, #113, #114, #117, #118, #120, #121, #122): hand-computed vectors (not run in the wave).
func _unique_component_models() -> void:
	# Hammer Of Lorent is a component effect: an entry with a model, pp 1.0 and no raw class name in its label
	Build.set_item("weapon", {"unique": 41, "base": 13, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255, 255, 255, 255]})
	var comp_count: int = 0
	var comp_pp: float = 0.0
	var comp_label: String = ""
	var comp_kind: String = ""
	for e: Dictionary in UniqueEffects.entries(Build):
		if str(e["effect"].get("source", "")) == "Component:Hammer_Of_Lorent":
			comp_count += 1
			comp_pp = float(e["pp"])
			comp_label = str(e["label"])
			comp_kind = str(e["model"].get("kind", ""))
	_check("#109 Hammer Of Lorent entry count", float(comp_count), 1.0)
	_check("#109 component pp = 1.0", comp_pp, 1.0)
	_flag("#109 component model is a stat", comp_kind == "stat")
	_flag("#109 component label has no raw class name", not comp_label.contains("Component:"))
	Build.clear_item("weapon")
	var st := StatStore.new()
	var ctx: Dictionary = {"build": Build, "store": st, "slot": -1, "item_slot": ""}
	# constants of the component models (pp 1.0)
	st.add(StatMod.make(LE.LIGHTNING_RES, "added", 0.8, 0, "t"))
	_check("#109 Urzil's Pride ManaRegen = 0.5 x lightning res", EffectModels.value(GameData.unique_component_model(10, 0), 1.0, ctx)["x"], 0.4)
	var st2 := StatStore.new()
	st2.add(StatMod.make(LE.MANA, "added", 300.0, 0, "t"))
	var ctx2: Dictionary = {"build": Build, "store": st2, "slot": -1, "item_slot": ""}
	_check("#109 Strong Mind StunAvoidance = 2 x max mana", EffectModels.value(GameData.unique_component_model(54, 0), 1.0, ctx2)["x"], 600.0)
	# level source = the character level
	var saved_level: int = Build.level
	Build.level = 100
	_check("#109 level source", EffectModels.source("level", ctx), 100.0)
	_check("#109 Hammer Of Lorent 41:0 = 1 x level", EffectModels.value(GameData.unique_component_model(41, 0), 1.0, ctx)["x"], 100.0)
	_check("#109 Frozen Ire 32:0 = 0.2 x level", EffectModels.value(GameData.unique_component_model(32, 0), 1.0, ctx)["x"], 20.0)
	Build.level = 50
	_check("#109 Frozen Ire 32:0 at level 50", EffectModels.value(GameData.unique_component_model(32, 0), 1.0, ctx)["x"], 10.0)
	Build.level = saved_level
	# Mourningfrost: 1 x Dexterity, only on Cold skills with Melee, Spell, Throwing or Bow
	var st_dex := StatStore.new()
	st_dex.add(StatMod.make(LE.DEXTERITY, "added", 150.0, 0, "t"))
	var ctx_dex: Dictionary = {"build": Build, "store": st_dex, "slot": -1, "item_slot": ""}
	_check("#109 Mourningfrost = 1 x Dexterity", EffectModels.value(GameData.unique_component_model(19, 0), 1.0, ctx_dex)["x"], 150.0)
	_flag("#109 Mourningfrost applies to a Cold Spell", UniqueEffects._skill_matches(GameData.unique_component_model(19, 0), {}, LE.COLD | LE.SPELL))
	_flag("#109 Mourningfrost not to a Cold Fire skill", not UniqueEffects._skill_matches(GameData.unique_component_model(19, 0), {}, LE.COLD | LE.FIRE))
	# Preparation: above 65% health the Damage model holds, otherwise the leech model
	var saved_health: String = str(Build.player_state.get("health", "full"))
	Build.set_player_state("health", "high")
	_flag("#109 Preparation above 65%: damage holds", EffectModels.blocked(GameData.unique_component_model(12, 0), ctx) == "")
	_flag("#109 Preparation above 65%: leech blocked", EffectModels.blocked(GameData.unique_component_model(12, 1), ctx) != "")
	Build.set_player_state("health", "normal")
	_flag("#109 Preparation at normal health: damage blocked", EffectModels.blocked(GameData.unique_component_model(12, 0), ctx) != "")
	_flag("#109 Preparation at normal health: leech holds", EffectModels.blocked(GameData.unique_component_model(12, 1), ctx) == "")
	Build.set_player_state("health", saved_health)
	# player flags of the Conditions tab
	Build.set_player_state("killed_recently", false)
	_flag("#109 Killed recently off: 70:2 and 26:0 blocked",EffectModels.blocked(GameData.unique_component_model(70, 2), ctx) != "" and EffectModels.blocked(GameData.unique_component_model(26, 0), ctx) != "")
	Build.set_player_state("killed_recently", true)
	_flag("#109 Killed recently on: models hold", EffectModels.blocked(GameData.unique_component_model(70, 2), ctx) == "" and EffectModels.blocked(GameData.unique_component_model(26, 0), ctx) == "")
	Build.set_player_state("killed_recently", false)
	Build.set_player_state("minion_killed_recently", true)
	_flag("#109 Minions killed recently: 28:0 holds", EffectModels.blocked(GameData.unique_component_model(28, 0), ctx) == "")
	Build.set_player_state("minion_killed_recently", false)
	# Soulfire armour: needs 1 ignite stack on you
	Build.set_player_state("ignite_stacks", 0)
	_flag("#109 Soulfire armour blocked without ignite", EffectModels.blocked(GameData.unique_component_model(70, 3), ctx) != "")
	Build.set_player_state("ignite_stacks", 2)
	_flag("#109 Soulfire armour holds while ignited", EffectModels.blocked(GameData.unique_component_model(70, 3), ctx) == "")
	_check("#109 Soulfire armour +1.0 increased", EffectModels.value(GameData.unique_component_model(70, 3), 1.0, ctx)["x"], 1.0)
	Build.set_player_state("ignite_stacks", 0)
	# Disintegrate: spell crit chance (5% base + Spell-tagged added) x (1 + increased), Melee crit ignored
	var st3 := StatStore.new()
	st3.add(StatMod.make(LE.CRIT_CHANCE, "added", 0.10, LE.SPELL, "t"))
	st3.add(StatMod.make(LE.CRIT_CHANCE, "increased", 0.5, 0, "t"))
	st3.add(StatMod.make(LE.CRIT_CHANCE, "added", 0.9, LE.MELEE, "t"))
	var ctx3: Dictionary = {"build": Build, "store": st3, "slot": -1, "item_slot": ""}
	_check("#114 Disintegrate more = (0.05 + 0.10) x 1.5", EffectModels.value(GameData.unique_component_model(74, 2), 1.0, ctx3)["x"], 0.225)
	# Salt the Wound: the crit multiplier converted to Bleed / Poison effect is removed from the added crit multiplier
	Build.set_item("gloves", {"unique": 187, "base": 4, "sub": 9, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255, 255, 255, 255]})
	var gs: Dictionary = BuildMods.global_store(Build)
	var eff_sp: int = GameData.sp_id("IncreasedAilmentEffect")
	var bleed: float = gs["store"].query(eff_sp, 0, GameData.enum_value("AilmentID", "Bleed")).added
	var poison: float = gs["store"].query(eff_sp, 0, GameData.enum_value("AilmentID", "Poison")).added
	var cm_left: float = gs["store"].query_untagged(LE.CRIT_MULTI).added
	_flag("#114 bleed effect > 0", bleed > 0.0)
	_check("#114 poison effect equals bleed", poison, bleed)
	_check("#114 all untagged added crit multi converted", cm_left, 0.0)
	_check("#114 bleed = 0.5 x crit multi total", bleed, 0.5 * (cm_left + bleed + poison))
	Build.clear_item("gloves")
	# Frenzy / Haste: the value is scaled by (1 + increased effect of the ailment on you); Haste DoT taken at most -75%
	var frenzy: int = GameData.enum_value("AilmentID", "Frenzy")
	var haste: int = GameData.enum_value("AilmentID", "Haste")
	var st4 := StatStore.new()
	st4.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 0.5, 0, "t", frenzy))
	var ctx4: Dictionary = {"build": Build, "store": st4, "slot": -1, "item_slot": ""}
	_check("#113 Frenzy-scaled more damage taken x 1.5", EffectModels.value(GameData.unique_player_model(602), 0.12, ctx4)["x"], 0.18)
	_check("#113 Frenzy-scaled flat melee damage x 1.5", EffectModels.value(GameData.unique_player_model(411), 20.0, ctx4)["x"], 30.0)
	_check("#113 Frenzy-scaled area x 1.5", EffectModels.value(GameData.unique_player_model(669), 0.4, ctx4)["x"], 0.6)
	_flag("#113 Frenzy-scaled models are applied late", EffectModels.phase(GameData.unique_player_model(602)) == "late")
	_flag("#113 attribute models stay in the post phase", EffectModels.phase(GameData.unique_player_model(606)) == "post")
	var st5 := StatStore.new()
	st5.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 3.0, 0, "t", haste))
	var ctx5: Dictionary = {"build": Build, "store": st5, "slot": -1, "item_slot": ""}
	_check("#113 Haste DoT taken clamped at -75%", EffectModels.value(GameData.unique_player_model(275), -0.2, ctx5)["x"], -0.75)
	var st6 := StatStore.new()
	st6.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 0.5, 0, "t", haste))
	var ctx6: Dictionary = {"build": Build, "store": st6, "slot": -1, "item_slot": ""}
	_check("#113 Haste DoT taken x 1.5", EffectModels.value(GameData.unique_player_model(275), -0.2, ctx6)["x"], -0.3)
	var st7 := StatStore.new()
	st7.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 9.0, 0, "t", frenzy))
	var ctx7: Dictionary = {"build": Build, "store": st7, "slot": -1, "item_slot": ""}
	_check("#113 Frenzy effect does not scale Haste", EffectModels.value(GameData.unique_player_model(275), -0.2, ctx7)["x"], -0.2)
	# Copies of the player's stats: Poison-tagged Damage mods, scaled by v (Skeleton Rogues, Falcon)
	var pst := StatStore.new()
	pst.add(StatMod.make(LE.DAMAGE, "increased", 0.5, LE.POISON, "a"))
	pst.add(StatMod.make(LE.DAMAGE, "increased", 0.3, LE.POISON | LE.SPELL, "b"))
	pst.add(StatMod.make(LE.DAMAGE, "more", 0.1, LE.POISON, "c"))
	pst.add(StatMod.make(LE.DAMAGE, "increased", 0.2, 0, "untagged"))
	pst.add(StatMod.make(LE.DAMAGE, "increased", 0.4, LE.FIRE, "fire"))
	var child := StatStore.new()
	child.parent = pst
	var cctx: Dictionary = {"build": Build, "store": child, "slot": 0, "item_slot": ""}
	var copies: Array[StatMod] = EffectModels.copied_mods(GameData.unique_ability_model(120, 6), 0.5, cctx, "t")
	_check("#117 three Poison copies", float(copies.size()), 3.0)
	var inc_sum: float = 0.0
	for c: StatMod in copies:
		inc_sum += c.increased
	_check("#117 copied increased = 0.5 x (0.5 + 0.3)", inc_sum, 0.4)
	_check("#117 Falcon copies match the Rogues", float(EffectModels.copied_mods(GameData.unique_ability_model(727, 17), 0.5, cctx, "t").size()), 3.0)
	# Bane of Winter: added Melee damage becomes added Spell damage (Physical kept), for Cold and Void spells
	var bst := StatStore.new()
	bst.add(StatMod.make(LE.DAMAGE, "added", 10.0, LE.MELEE | LE.PHYSICAL, "a"))
	bst.add(StatMod.make(LE.DAMAGE, "added", 4.0, LE.MELEE, "b"))
	bst.add(StatMod.make(LE.DAMAGE, "added", 6.0, LE.SPELL, "c"))
	bst.add(StatMod.make(LE.DAMAGE, "increased", 0.5, LE.MELEE, "d"))
	var bctx: Dictionary = {"build": Build, "store": bst, "slot": 0, "item_slot": ""}
	var bc: Array[StatMod] = EffectModels.copied_mods(GameData.unique_player_model(445), 0.4, bctx, "t")
	_check("#122 two added copies", float(bc.size()), 2.0)
	if bc.size() == 2:
		_check("#122 copy 1 added 10 x 0.4", bc[0].added, 4.0)
		_check("#122 copy 1 tags Physical|Spell", float(bc[0].tags), float(LE.PHYSICAL | LE.SPELL))
		_check("#122 copy 2 added 4 x 0.4", bc[1].added, 1.6)
		_check("#122 copy 2 tags Spell", float(bc[1].tags), float(LE.SPELL))
	_flag("#122 Bane of Winter applies to a Cold Spell", UniqueEffects._skill_matches(GameData.unique_player_model(445), {}, LE.SPELL | LE.COLD))
	_flag("#122 Bane of Winter not to a Fire Spell", not UniqueEffects._skill_matches(GameData.unique_player_model(445), {}, LE.SPELL | LE.FIRE))
	# Runic Invocation: the roll has no Intelligence factor, the amount is 11% / 22% / 33%
	_check("#121 one rune: 0.01 x 0.11", EffectModels.value(GameData.unique_ability_model(689, 24), 0.01, ctx)["x"], 0.0011, 0.00005)
	_check("#121 two runes: 0.02 x 0.22", EffectModels.value(GameData.unique_ability_model(689, 25), 0.02, ctx)["x"], 0.0044, 0.00005)
	_check("#121 three runes: 0.03 x 0.33", EffectModels.value(GameData.unique_ability_model(689, 26), 0.03, ctx)["x"], 0.0099, 0.00005)
	# Falcon bleed chance: a fraction of the Bleed chance (untagged mods with special 0 or Bleed)
	var ast := StatStore.new()
	ast.add(StatMod.make(LE.AILMENT_CHANCE, "added", 0.1, 0, "any"))
	ast.add(StatMod.make(LE.AILMENT_CHANCE, "added", 0.2, 0, "bleed", GameData.enum_value("AilmentID", "Bleed")))
	ast.add(StatMod.make(LE.AILMENT_CHANCE, "added", 0.5, LE.MELEE, "tagged"))
	ast.add(StatMod.make(LE.AILMENT_CHANCE, "added", 0.9, 0, "ignite", GameData.enum_value("AilmentID", "Ignite")))
	var actx: Dictionary = {"build": Build, "store": ast, "slot": -1, "item_slot": ""}
	_check("#118 Bleed chance = 0.1 + 0.2", EffectModels.source("ailment_chance:Bleed", actx), 0.3)
	_check("#118 Falcon bleed fraction 0.5 x 0.3", EffectModels.value(GameData.unique_ability_model(727, 3), 0.5, actx)["x"], 0.15)
	# Warpath axe throws: total physical damage modifier (1 + Σ inc) × Π(1 + more) − 1, untagged and Physical mods
	var tst := StatStore.new()
	tst.add(StatMod.make(LE.DAMAGE, "increased", 0.5, 0, "u"))
	tst.add(StatMod.make(LE.DAMAGE, "increased", 0.5, LE.PHYSICAL, "p"))
	tst.add(StatMod.make(LE.DAMAGE, "increased", 1.0, LE.FIRE, "f"))
	tst.add(StatMod.make(LE.DAMAGE, "more", 0.2, 0, "m"))
	var tctx: Dictionary = {"build": Build, "store": tst, "slot": -1, "item_slot": ""}
	_check("#118 total physical modifier 1.4", EffectModels.source("total_modifier:Damage:1", tctx), 1.4)
	_check("#118 axe throw speed 0.02 x 1.4 x 10", EffectModels.value(GameData.unique_ability_model(97, 3), 0.02, tctx)["x"], 0.28)
	# Character-wide models read their inputs from the first damaging skill (input_slot); a model's own default otherwise
	var m236: Dictionary = GameData.unique_player_model(236)
	var base_ctx: Dictionary = {"build": Build, "store": st, "slot": -1, "item_slot": ""}
	_check("#120 global input default 10 stacks", EffectModels.value(m236, 0.05, base_ctx)["x"], 0.5)
	Build.set_skill_input(0, "gf_stacks", 4)
	var ctx_in: Dictionary = {"build": Build, "store": st, "slot": -1, "item_slot": "", "input_slot": 0}
	_check("#120 global model reads the first skill's input", EffectModels.value(m236, 0.05, ctx_in)["x"], 0.2)
	(Build.skills[0].get("inputs", {}) as Dictionary).erase("gf_stacks")
	var m77: Dictionary = GameData.unique_player_model(77)
	_flag("#120 Deicide off by default", EffectModels.blocked(m77, base_ctx) != "")
	Build.set_skill_input(0, "deicide", true)
	_flag("#120 Deicide read from the first skill", EffectModels.blocked(m77, ctx_in) == "")
	(Build.skills[0].get("inputs", {}) as Dictionary).erase("deicide")
	# Close Call (DodgeRating increased 0.4 per block, the input is declared on the first skill of the bar)
	var saved_ab: String = str(Build.skills[0].get("ability", ""))
	Build.set_skill(0, "fi9")
	Build.set_item("offhand", {"unique": 51, "base": 18, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255, 255, 255, 255]})
	var cg: Dictionary = BuildMods.global_store(Build)
	_check("#120 Close Call: one block counted (0.4)", _mods_sum(cg["store"], LE.DODGE_RATING, "Blocks in last 4 sec", true), 0.4)
	var csk: Dictionary = BuildMods.skill_store(Build, 0, cg["store"])
	_flag("#120 Close Call input declared on the first skill", _has_input(csk, "blocks"))
	Build.set_skill_input(0, "blocks", 3)
	cg = BuildMods.global_store(Build)
	_check("#120 Close Call: 3 blocks x 0.4", _mods_sum(cg["store"], LE.DODGE_RATING, "Blocks in last 4 sec", true), 1.2)
	(Build.skills[0].get("inputs", {}) as Dictionary).erase("blocks")
	Build.clear_item("offhand")
	Build.set_skill(0, saved_ab)


## Skill-level kinds of player-scoped unique models (trigger, param, flag) reach the skill result; fake models are
## swapped into the loaded dictionary for Apostate's Sanctuary PP 285 and removed again.
func _unique_skill_level_models() -> void:
	var player_models: Dictionary = GameData._unique_models.get("player", {})
	var had: bool = player_models.has("285")
	var old: Variant = player_models.get("285")
	var ab: Dictionary = GameData.get_ability("fi9")
	Build.set_item("amulet", {"unique": 290, "base": 20, "sub": 7, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	Build.set_skill(0, "fi9")
	var g: Dictionary = BuildMods.global_store(Build)
	player_models["285"] = {"kind": "trigger", "ability": str(ab.get("abilityName", "")), "on": "hit", "chance": 0.25}
	CalcCache.clear()  # the game data changed under the cached results
	var s: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	_check("global trigger reaches the skill result", float(s["triggers"].size()), 1.0)
	_check("global trigger is not a global stat", BuildMods.global_store(Build)["store"].query_untagged(LE.HEALTH).added, g["store"].query_untagged(LE.HEALTH).added - 2.0 * _row(g, "Vitality"))
	_check("skill with a global trigger computes", 1.0 if not SkillCalc.compute(Build, 0)["sections"].is_empty() else 0.0, 1.0)
	player_models["285"] = {"kind": "param", "param": "projectiles", "label": "Test parameter", "mod": "added"}
	CalcCache.clear()  # the game data changed under the cached results
	s = BuildMods.skill_store(Build, 0, g["store"])
	_check("global param row appears", 1.0 if s["params"].has("Test parameter") else 0.0, 1.0)
	player_models["285"] = {"kind": "flag", "text": "test flag"}
	CalcCache.clear()  # the game data changed under the cached results
	g = BuildMods.global_store(Build)
	_check("flag effect is listed", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains("test flag") else 0.0, 1.0)
	if had:
		player_models["285"] = old
	else:
		player_models.erase("285")
	CalcCache.clear()
	Build.clear_item("amulet")
	Build.set_skill(0, "")


## Unique models limited to skills (skill_all / skill_flag / skill_any), game code in research/11_calc_audit.md #110-#116.
func _unique_skill_filters() -> void:
	var rolls: Array = [255, 255, 255, 255, 255, 255, 255, 255, 255, 255]
	var void_cleave: String = "v01cv"  # Void + Melee
	var cinder: String = "cstri"  # Fire + Melee
	var bow: String = "detar"  # Bow
	var dive: String = "db992"  # Melee + Void? movement ability (countsAsMovementAbility)
	Build.set_skill(0, void_cleave)
	Build.set_skill(1, cinder)
	Build.set_skill(2, bow)
	Build.set_skill(3, dive)
	# Eternal Eclipse (pp 161-164): added Fire|Melee damage only on a Void+Melee use, added Void|Melee only on a Fire+Melee use
	Build.set_item("weapon", {"unique": 212, "base": 16, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": rolls})
	var g: Dictionary = BuildMods.global_store(Build)
	_check("Eternal Eclipse: nothing in the global store", float(_mods_with(g["store"], LE.DAMAGE, "with next")), 0.0)
	var vc: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	var ci: Dictionary = BuildMods.skill_store(Build, 1, g["store"])
	var bw: Dictionary = BuildMods.skill_store(Build, 2, g["store"])
	_check("Eternal Eclipse: Void+Melee use gets Fire|Melee", float(_mods_with(vc["store"], LE.DAMAGE, "with next", LE.FIRE | LE.MELEE)), 1.0)
	_check("Eternal Eclipse: Void+Melee use does not get Void|Melee", float(_mods_with(vc["store"], LE.DAMAGE, "with next", LE.VOID | LE.MELEE)), 0.0)
	_check("Eternal Eclipse: Fire+Melee use gets Void|Melee", float(_mods_with(ci["store"], LE.DAMAGE, "with next", LE.VOID | LE.MELEE)), 1.0)
	_check("Eternal Eclipse: Fire+Melee use does not get Fire|Melee", float(_mods_with(ci["store"], LE.DAMAGE, "with next", LE.FIRE | LE.MELEE)), 0.0)
	_check("Eternal Eclipse: bow use gets nothing", float(_mods_with(bw["store"], LE.DAMAGE, "with next")), 0.0)
	Build.clear_item("weapon")
	# Vaion's Chariot (pp 228): MORE damage only for a movement ability
	Build.set_item("boots", {"unique": 264, "base": 3, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": rolls})
	g = BuildMods.global_store(Build)
	_check("Vaion's Chariot: movement ability gets the more damage", float(_mods_with(BuildMods.skill_store(Build, 3, g["store"])["store"], LE.DAMAGE, "next Movement")), 1.0)
	_check("Vaion's Chariot: other skills do not", float(_mods_with(BuildMods.skill_store(Build, 0, g["store"])["store"], LE.DAMAGE, "next Movement")), 0.0)
	Build.clear_item("boots")
	# Gathering Fury (pp 236): attack speed with the Bow tag, 10 stacks of 5%
	var base_bow: float = BuildMods.skill_store(Build, 2, BuildMods.global_store(Build)["store"])["store"].query(LE.ATTACK_SPEED, LE.BOW).increased
	Build.set_item("weapon", {"unique": 271, "base": 23, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": rolls})
	g = BuildMods.global_store(Build)
	var inc_bow: float = g["store"].query(LE.ATTACK_SPEED, LE.BOW | LE.PHYSICAL).increased
	var inc_melee: float = g["store"].query(LE.ATTACK_SPEED, LE.MELEE | LE.PHYSICAL).increased
	_check("Gathering Fury: Bow skills get the attack speed", inc_bow - base_bow - inc_melee, 0.5)
	Build.clear_item("weapon")
	# Crystalwind (pp 506): MORE damage on a direct Bow use only
	Build.set_item("offhand", {"unique": 378, "base": 17, "sub": 0, "implicit_rolls": [255, 255], "unique_rolls": rolls})
	g = BuildMods.global_store(Build)
	_check("Crystalwind: bow use", float(_mods_with(BuildMods.skill_store(Build, 2, g["store"])["store"], LE.DAMAGE, "Crystalwind")), 1.0)
	_check("Crystalwind: non-bow use", float(_mods_with(BuildMods.skill_store(Build, 0, g["store"])["store"], LE.DAMAGE, "Crystalwind")), 0.0)
	_check("Crystalwind: echoed bow use", float(_mods_with(BuildMods.skill_store(Build, 2, g["store"], "echo")["store"], LE.DAMAGE, "Crystalwind")), 0.0)
	Build.clear_item("offhand")
	# Downfall of the Righteous (pp 521): the source is the increased Damage with exactly the Curse tag
	var st: StatStore = StatStore.new()
	st.add(StatMod.make(LE.DAMAGE, "increased", 0.5, 0, "any"))
	st.add(StatMod.make(LE.DAMAGE, "increased", 0.3, LE.CURSE, "curse"))
	st.add(StatMod.make(LE.DAMAGE, "increased", 0.2, LE.CURSE | LE.SPELL, "curse spell"))
	_check("increased_exact source", EffectModels.source("increased_exact:Damage:%d" % LE.CURSE, {"build": Build, "store": st}), 0.3)
	# Deicide (pp 77): the buff is a MORE multiplier of 0.2
	var deicide: StatMod = EffectModels.make_mod(GameData.unique_player_model(77), 1.0, {"build": Build, "store": st}, "Deicide")
	_check("Deicide: increased part", deicide.increased, 0.0)
	_check("Deicide: more part", deicide.more[0], 0.2)
	for i in range(4):
		Build.set_skill(i, "")


## Mods of the store for the stat whose source contains the text (and, if given, whose tags are exactly the mask).
func _mods_with(store: StatStore, property: int, text: String, mask: int = -1) -> int:
	var n: int = 0
	for mod: StatMod in store.mods_of(property):
		if mod.source.contains(text) and (mask < 0 or mod.tags == mask):
			n += 1
	return n


## Every unique, one at a time, with all player flags on: no script errors, count modelled effects.
func _all_uniques_smoke() -> void:
	const SLOT_BY_TYPE: Dictionary = {0: "helmet", 1: "body", 2: "belt", 3: "boots", 4: "gloves", 17: "offhand", 18: "offhand",
		19: "offhand", 20: "amulet", 21: "ring1", 22: "relic"}
	for key: String in EffectModels.PLAYER_FLAG_NAMES:
		Build.set_player_state(key, true)
	for key: String in EffectModels.PLAYER_VALUE_NAMES:
		Build.set_player_state(key, 20)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Chill"), 1)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Bleed"), 50)
	Build.set_skill(0, "fi9")
	var modelled: int = 0
	var total: int = 0
	for u: Dictionary in GameData.uniques:
		var t: int = int(u["baseType"])
		var slot: String = str(SLOT_BY_TYPE.get(t, "weapon" if GameData.item_base(t).get("isWeapon", false) else ""))
		if slot == "":
			slot = IdolGrid.key(1, 1)
		var sub: int = int(u["subTypes"][0]) if not u.get("subTypes", []).is_empty() else 0
		Build.set_item(slot, {"unique": int(u["uniqueID"]), "base": t, "sub": sub, "implicit_rolls": [255, 255, 255], "unique_rolls": [255, 255, 255, 255, 255, 255, 255, 255, 255, 255]})
		var g: Dictionary = BuildMods.global_store(Build)
		CharacterCalc.compute(g["store"], Build)
		SkillCalc.compute(Build, 0)
		for e: Dictionary in UniqueEffects.entries(Build):
			total += 1
			if not e["model"].is_empty():
				modelled += 1
		Build.clear_item(slot)
	print("--- all uniques: %d special effects, %d modelled" % [total, modelled])
	for key: String in EffectModels.PLAYER_FLAG_NAMES:
		Build.set_player_state(key, false)
	for key: String in EffectModels.PLAYER_VALUE_NAMES:
		Build.set_player_state(key, 0)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Chill"), 0)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Bleed"), 0)
	Build.set_skill(0, "")


## Passive nodes into special lists (statsWhileDualWielding, statsWithWeaponRequirements, §5.2): conditions and sources.
## Illusory Combatant (mg-1 node 75: +2 per Int, capped by addedDodgePerIntCap): the game clamps the one dodge value
## (CharacterMutator.UpdateDynamicStat); the cap field is not a second dodge bonus. Reaper (ac-1 node 35) has no cap field.
func _dodge_per_int_cap() -> void:
	Build.set_class(1)  # Mage tree mg-1
	var saved: Dictionary = Build.passives.duplicate()
	var model: Dictionary = FieldModels.find("CharacterMutator.addedDodgeRatingPerInt")
	Build.passives = {75: 4}
	for int_value: int in [30, 80, 50]:
		var s := StatStore.new()
		s.add(StatMod.make(LE.INTELLIGENCE, "added", float(int_value), 0, "t"))
		var ctx: Dictionary = {"build": Build, "store": s, "slot": -1, "item_slot": ""}
		_check("dodge per Int %d with the cap 100: min(2 * Int, 100)" % int_value, EffectModels.value(model, 2.0, ctx)["x"], minf(2.0 * int_value, 100.0))
	_check("addedDodgePerIntCap is a passive value, not a stat", 1.0 if FieldModels.find("CharacterMutator.addedDodgePerIntCap").get("kind", "") == "param" else 0.0, 1.0)
	Build.passives = {}
	var s_uncapped := StatStore.new()
	s_uncapped.add(StatMod.make(LE.INTELLIGENCE, "added", 80.0, 0, "t"))
	var ctx_uncapped: Dictionary = {"build": Build, "store": s_uncapped, "slot": -1, "item_slot": ""}
	_check("dodge per Int without the cap node: 2 * 80", EffectModels.value(model, 2.0, ctx_uncapped)["x"], 160.0)
	Build.passives = saved


func _passive_field_models() -> void:
	Build.set_class(1)  # Mage
	Build.set_level(100)
	var tree: Dictionary = GameData.get_passive_tree(1)
	var effects: Dictionary = GameData.passive_effects(str(tree["treeID"]))
	var dual_id: int = -1
	var weapon_id: int = -1
	for node: Dictionary in tree["nodes"]:
		for effect: Dictionary in effects.get(int(node["id"]), {}).get("effects", []):
			var target: String = str(effect.get("target", ""))
			if target == "CharacterMutator.statsWhileDualWielding" and dual_id < 0:
				dual_id = int(node["id"])
			elif target == "CharacterMutator.statsWithWeaponRequirements" and weapon_id < 0:
				weapon_id = int(node["id"])
	_check("Mage has a dual-wield and a weapon-requirement passive", 1.0 if dual_id >= 0 and weapon_id >= 0 else 0.0, 1.0)
	# base tree points open the mastery thresholds
	for _pass in range(6):
		for node: Dictionary in tree["nodes"]:
			if int(node["mastery"]) == 0:
				while Build.add_point(int(node["id"])):
					pass
	for id: int in [dual_id, weapon_id]:
		_allocate_passive_path(tree, id, 1)
		_check("passive %d allocated" % id, float(Build.get_points(id)), 1.0)
	var title: String = GameData.display_name(effects[weapon_id])
	var g: Dictionary = BuildMods.global_store(Build)
	var wr_note: String = "Passive \"%s\" — counted when" % title
	_check("statsWithWeaponRequirements without a catalyst: condition note", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains(wr_note) else 0.0, 1.0)
	Build.set_item("offhand", {"base": 19, "sub": 0, "implicit_rolls": [255, 255]})
	g = BuildMods.global_store(Build)
	var found: bool = false
	for mod: StatMod in g["store"].all_mods():
		if mod.source.begins_with("Passive \"%s\"" % title):
			found = true
	_check("statsWithWeaponRequirements with a catalyst: mod with the node title in the global store", 1.0 if found else 0.0, 1.0)
	Build.clear_item("offhand")
	g = BuildMods.global_store(Build)
	var dual_title: String = GameData.display_name(effects[dual_id])
	var dual_note: String = "Passive \"%s\" — counted when" % dual_title
	_check("statsWhileDualWielding without weapons: condition note", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains(dual_note) else 0.0, 1.0)
	Build.set_item("weapon", {"base": 10, "sub": 1, "implicit_rolls": [255, 255]})
	Build.set_item("offhand", {"base": 10, "sub": 1, "implicit_rolls": [255, 255]})
	g = BuildMods.global_store(Build)
	var dual_found: bool = false
	for mod: StatMod in g["store"].all_mods():
		if mod.source.begins_with("Passive \"%s\"" % dual_title):
			dual_found = true
	_check("statsWhileDualWielding with two weapons: mod in the global store", 1.0 if dual_found else 0.0, 1.0)
	_check("statsWhileDualWielding with two weapons: no condition note", 0.0 if "\n".join(PackedStringArray(g["notes"])).contains(dual_note) else 1.0, 1.0)
	Build.clear_item("weapon")
	Build.clear_item("offhand")


## Allocates passive requirements recursively, then `points` into the node.
func _allocate_passive_path(tree: Dictionary, node_id: int, points: int) -> void:
	for node: Dictionary in tree["nodes"]:
		if int(node["id"]) == node_id:
			for req: Dictionary in node.get("requirements", []):
				_allocate_passive_path(tree, int(req["nodeID"]), int(req["requirement"]))
	while Build.get_points(node_id) < points and Build.add_point(node_id):
		pass


## Allocates requirements recursively, then `points` into the node (skill slot 0).
func _allocate_path(tree: Dictionary, node_id: int, points: int) -> void:
	for node: Dictionary in tree["nodes"]:
		if int(node["id"]) == node_id:
			for req: Dictionary in node.get("requirements", []):
				_allocate_path(tree, int(req["nodeID"]), int(req["requirement"]))
	while Build.get_skill_points(0, node_id) < points and Build.add_skill_point(0, node_id):
		pass


func _row(g: Dictionary, label: String) -> float:
	for row: Dictionary in CharacterCalc.compute(g["store"], Build):
		if row["label"] == label:
			return float(row["value"])
	return -1.0


func _section_value(r: Dictionary, section: String, label: String) -> float:
	for s: Dictionary in r["sections"]:
		if s["title"] == section:
			for row: Dictionary in s["rows"]:
				if row["label"] == label:
					return float(str(row["text"]).replace("×", "").replace("%", ""))
	return -1.0


func _print_sections(r: Dictionary) -> void:
	for s: Dictionary in r["sections"]:
		print("  [%s]" % s["title"])
		for row: Dictionary in s["rows"]:
			print("    %s: %s" % [row["label"], row["text"]])
			for line: String in str(row["breakdown"]).split("\n"):
				print("        " + line)


## Sustain section (docs/ENGINE.md §8.7): a HealthLeech mod gives a nonzero leech row (research/06c §5.2).
## #77a: HealthGain / WardGain of the skill's own hits: special 1 on every hit, 7 on melee hits, 2 once per crit; special 0 counts nothing.
func _gain_events() -> void:
	var st := StatStore.new()
	st.add(StatMod.make(38, "added", 5.0, 0, "t", 1))
	st.add(StatMod.make(38, "added", 3.0, 0, "t", 7))
	st.add(StatMod.make(38, "added", 4.0, 0, "t", 2))
	st.add(StatMod.make(38, "added", 2.0, 0, "t", 0))
	st.add(StatMod.make(38, "added", 6.0, 0, "t", 6))
	_check("gain: hit", SkillCalc.gain_by_event(st, 38, 0, 1, 0), 5.0)
	_check("gain: melee hit", SkillCalc.gain_by_event(st, 38, 0, 7, 0), 3.0)
	_check("gain: crit", SkillCalc.gain_by_event(st, 38, 0, 2, 0), 4.0)
	_check("gain: block", SkillCalc.gain_by_event(st, 38, 0, 6, 0), 6.0)
	# the hitEventTag of a node stat becomes the specialTag of SP 38/39/40 only
	var he: Dictionary = {"kind": "added", "property": "HealthGain", "tags": "None", "hitEventTag": "Hit", "added": {"per_point": 5.0, "flat": 0}}
	var m: StatMod = BuildMods.stat_from_effect(he, 2, "t")
	_check("hitEventTag Hit -> special 1", float(m.special), 1.0)
	_check("hitEventTag stat value 5 x 2 points", m.added, 10.0)
	he["property"] = "HealthLeech"
	_check("hitEventTag on HealthLeech stays special 0", float(BuildMods.stat_from_effect(he, 1, "t").special), 0.0)


func _sustain() -> void:
	Build.set_skill(0, "fi9")
	Build.set_enemy("kind", "dummy")
	var r: Dictionary = SkillCalc.compute(Build, 0)
	_check("no leech without a leech mod", _section_value(r, "Sustain", "Health leech per second"), -1.0)
	# Gloves affix 1003: +0.01 added HealthLeech (untagged) and +10% increased
	Build.set_item("gloves", {"base": 4, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 1003, "tier": 1, "roll": 255}]})
	r = SkillCalc.compute(Build, 0)
	_print_sections(r)
	var leech: float = _section_value(r, "Sustain", "Health leech per second")
	_check("HealthLeech mod gives a leech row", 1.0 if leech > 0.0 else 0.0, 1.0)
	Build.clear_item("gloves")


## Sum of `added` / `increased` of the mods of property `prop` whose source contains `needle`.
func _mods_sum(store: StatStore, prop: int, needle: String, increased: bool) -> float:
	var total: float = 0.0
	for mod: StatMod in store.all_mods():
		if mod.property == prop and mod.source.contains(needle):
			total += mod.increased if increased else mod.added
	return total


## Skill buffs on the character and passives on ability mutators (docs/ENGINE.md §9.7).
func _buff_skills() -> void:
	Build.set_class(2)  # Sentinel
	Build.set_level(100)
	# 1. scope-global field model of a skill tree (Flame Ward statsList: +50% fire damage per point) buffs every skill
	Build.set_skill(0, "fw3d")
	Build.set_skill(1, "fi9")
	Build.skills[0]["tree"][2] = 2  # points are written directly: the tree rules are not under test
	_check("Flame Ward node allocated", float(Build.get_skill_points(0, 2)), 2.0)
	var g: Dictionary = BuildMods.global_store(Build)
	var node_src: String = "Skill \"Flame Ward\" (buff): Node \"Flame Ward Increased Fire Damage\" ×2"
	_check("tree global model reaches the global store", _mods_sum(g["store"], LE.DAMAGE, node_src, true), 1.0)
	var fireball: Dictionary = BuildMods.skill_store(Build, 1, g["store"])
	_check("another skill sees the Flame Ward buff", _mods_sum(fireball["store"], LE.DAMAGE, node_src, true), 1.0)
	var own: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	var own_dup: float = 0.0
	for mod: StatMod in own["store"].mods:
		if mod.source.contains("Flame Ward Increased Fire Damage"):
			own_dup += mod.increased
	_check("the skill's own store has no second copy of its global mod", own_dup, 0.0)
	_check("buff input declared", 1.0 if _has_input(own, "buff_active") else 0.0, 1.0)
	Build.set_skill_input(0, "buff_active", false)
	g = BuildMods.global_store(Build)
	_check("buff_active off: no buff in the global store", _mods_sum(g["store"], LE.DAMAGE, node_src, true), 0.0)
	Build.set_skill_input(0, "buff_active", true)

	# read-only list of the skill buffs (UI "Skill buffs on the character") agrees with the global store
	g = BuildMods.global_store(Build)
	var listed: Array[Dictionary] = BuildMods.skill_buffs(Build)
	var fw_entry: Dictionary = listed[0]
	var fw_prefix: String = "Skill \"Flame Ward\" (buff)"
	_check("skill_buffs: first entry is slot 0", float(fw_entry["slot"]), 0.0)
	_check("skill_buffs: Flame Ward is active and has a switch", 1.0 if (fw_entry["active"] and fw_entry["toggle"]) else 0.0, 1.0)
	_check("skill_buffs: listed mods = buff mods of the global store", float(fw_entry["mods"].size()), _count_source_prefix(g["store"], fw_prefix))
	Build.set_skill_input(0, "buff_active", false)
	listed = BuildMods.skill_buffs(Build)
	_check("skill_buffs: switched off skill is listed with its mods, inactive", 1.0 if (not listed[0]["active"] and not listed[0]["mods"].is_empty()) else 0.0, 1.0)
	_check("skill_buffs(only_active): switched off skill has no mods", float(BuildMods.skill_buffs(Build, null, true)[0]["mods"].size()), 0.0)
	_check("skill_buffs: describe_mod names the property", 1.0 if BuildMods.describe_mod(fw_entry["mods"][0]).contains("Damage") else 0.0, 1.0)
	Build.set_skill_input(0, "buff_active", true)

	# 2. Holy Aura on the bar: base buff and tree list × M (Covenant of Light 5/5 → M = 1.2)
	Build.set_skill(0, "ah443")
	Build.skills[0]["tree"][12] = 5  # Shelter from the Storm: +5% elemental resistance and +3% endurance per point
	Build.passives[119] = 5
	g = BuildMods.global_store(Build)
	var holy: String = "Skill \"Holy Aura\" (buff)"
	_check("Holy Aura passive: ElementalResistance (0.15 + 0.25) × 1.2", _mods_sum(g["store"], LE.ELEMENTAL_RES, holy, false), 0.48)
	_check("Holy Aura passive: Damage increased 0.30 × 1.2", _mods_sum(g["store"], LE.DAMAGE, holy, true), 0.36)
	_check("Holy Aura passive: Endurance 0.15 × 1.2", _mods_sum(g["store"], LE.ENDURANCE, holy, false), 0.18)
	fireball = BuildMods.skill_store(Build, 1, g["store"])
	_check("another skill sees the Holy Aura damage buff", _mods_sum(fireball["store"], LE.DAMAGE, holy, true), 0.36)
	Build.set_skill_input(0, "holy_aura_active_cast", true)
	g = BuildMods.global_store(Build)
	_check("Holy Aura active: ElementalResistance (0.30 + 0.50) × 1.2", _mods_sum(g["store"], LE.ELEMENTAL_RES, holy, false), 0.96)
	_check("Holy Aura active: Damage increased 0.60 × 1.2", _mods_sum(g["store"], LE.DAMAGE, holy, true), 0.72)
	Build.passives.erase(119)
	Build.set_skill_input(0, "holy_aura_active_cast", false)
	g = BuildMods.global_store(Build)
	_check("Holy Aura without Covenant: ElementalResistance 0.15 + 0.25", _mods_sum(g["store"], LE.ELEMENTAL_RES, holy, false), 0.40)
	var holy_calc: Dictionary = SkillCalc.compute(Build, 0)
	_check("Holy Aura slot computes", 1.0 if holy_calc.has("sections") else 0.0, 1.0)

	# 3. passive aimed at an ability mutator: Valiant Charge → Lunge cooldown recovery (+6% per point)
	Build.set_skill(0, "lu25ng")
	Build.passives[8] = 3
	g = BuildMods.global_store(Build)
	var lunge: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	_check("Valiant Charge ×3 → Lunge recovery speed +18%", float(lunge["cooldown"].get("recovery_increased", 0.0)), 0.18)
	var notes_with_lunge: int = _count_notes(g["notes"], "Valiant Charge")
	Build.set_skill(0, "fi9")
	g = BuildMods.global_store(Build)
	var not_lunge: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	_check("Valiant Charge does not touch Fireball", float(not_lunge["cooldown"].get("recovery_increased", 0.0)), 0.0)
	_check("passive of an absent skill stays a note (one more note without Lunge)", float(_count_notes(g["notes"], "Valiant Charge") - notes_with_lunge), 1.0)
	Build.passives.erase(8)
	Build.set_skill(0, "")
	Build.set_skill(1, "")
	Build.set_class(1)
	Build.set_level(100)


## Base buffs read from mutator code (docs/ENGINE.md §9.7, buff_skill_models.json): Symbols of Hope (per-symbol input, M from
## passives, activation mode), Enchant Weapon (passive 0.15 more replaced by 0.5 more on activation), Firebrand stacks.
func _buff_skill_base_models() -> void:
	Build.set_class(2)  # Sentinel (Paladin passives: Covenant of Light #119 → M 1.2, Covenant of Protection #95 ≥5 → +5 regen per symbol)
	Build.set_level(100)
	Build.set_skill(0, "si4lgl")
	Build.passives[119] = 5
	Build.passives[95] = 5
	var sigils: String = "Skill \"Symbols of Hope\" (buff)"
	var g: Dictionary = BuildMods.global_store(Build)
	_check("Symbols of Hope ×3: HealthRegen increased 0.2 × 3 × 1.2", _mods_sum(g["store"], LE.HEALTH_REGEN, sigils, true), 0.72)
	_check("Symbols of Hope ×3: HealthRegen added 5 × 3 × 1.2", _mods_sum(g["store"], LE.HEALTH_REGEN, sigils, false), 18.0)
	_check("Symbols of Hope ×3: fire damage added (4 tags × 3 × 3 × 1.2)", _mods_sum(g["store"], LE.DAMAGE, sigils, false), 43.2)
	_check("Symbols of Hope: no damage-taken stat outside the activation", _mods_more_sum(g["store"], LE.DAMAGE_TAKEN, sigils), 0.0)
	Build.set_skill_input(0, "sigils", 2.0)
	g = BuildMods.global_store(Build)
	_check("Symbols of Hope ×2: HealthRegen increased 0.2 × 2 × 1.2", _mods_sum(g["store"], LE.HEALTH_REGEN, sigils, true), 0.48)
	Build.set_skill_input(0, "sigils_active_use", true)
	g = BuildMods.global_store(Build)
	_check("Symbols of Hope activation: symbol stats are gone", _mods_sum(g["store"], LE.HEALTH_REGEN, sigils, true), 0.0)
	_check("Symbols of Hope activation: damage taken more -0.05 × 2 symbols (no M)", _mods_more_sum(g["store"], LE.DAMAGE_TAKEN, sigils), -0.1)
	var own: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	_check("Symbols of Hope declares the symbols input", 1.0 if _has_input(own, "sigils") else 0.0, 1.0)
	Build.passives.erase(119)
	Build.passives.erase(95)
	Build.skills[0].erase("inputs")

	Build.set_skill(0, "sb44eQ")
	var enchant: String = "Skill \"Enchant Weapon\" (buff)"
	g = BuildMods.global_store(Build)
	_check("Enchant Weapon passive: 0.15 more (Elemental|Melee)", _mods_more_sum(g["store"], LE.DAMAGE, enchant), 0.15)
	Build.skills[0]["tree"][2] = 2  # node 2 Melee Shock Chance: +10% per point in the passive list, +20% in the active list
	g = BuildMods.global_store(Build)
	_check("Enchant Weapon passive list: shock chance 0.1 × 2", _mods_sum(g["store"], LE.AILMENT_CHANCE, enchant, false), 0.2)
	Build.set_skill_input(0, "enchant_weapon_active_cast", true)
	g = BuildMods.global_store(Build)
	_check("Enchant Weapon active: 0.5 more replaces the passive 0.15", _mods_more_sum(g["store"], LE.DAMAGE, enchant), 0.5)
	_check("Enchant Weapon active list replaces the passive one: shock chance 0.2 × 2", _mods_sum(g["store"], LE.AILMENT_CHANCE, enchant, false), 0.4)

	Build.set_skill(0, "f1b4d")
	var firebrand: String = "Skill \"Firebrand\" (buff)"
	g = BuildMods.global_store(Build)
	_check("Firebrand default 4 stacks: +5 melee fire damage per stack", _mods_sum(g["store"], LE.DAMAGE, firebrand, false), 20.0)
	Build.set_skill_input(0, "firebrand_stacks", 2.0)
	g = BuildMods.global_store(Build)
	_check("Firebrand 2 stacks: +10", _mods_sum(g["store"], LE.DAMAGE, firebrand, false), 10.0)
	Build.set_skill(0, "")
	Build.set_class(1)
	Build.set_level(100)


## Sum of the `more` values of the mods of property `prop` whose source contains `needle`.
func _mods_more_sum(store: StatStore, prop: int, needle: String) -> float:
	var total: float = 0.0
	for mod: StatMod in store.all_mods():
		if mod.property == prop and mod.source.contains(needle):
			for value: float in mod.more:
				total += value
	return total


func _count_notes(notes: Array, needle: String) -> int:
	var n: int = 0
	for note: Variant in notes:
		if str(note).contains(needle):
			n += 1
	return n


func _has_input(s: Dictionary, key: String) -> bool:
	for inp: Dictionary in s["inputs"]:
		if inp.get("key") == key:
			return true
	return false


## Idol altar (docs/ENGINE.md §5.4.1): altar grid, refracted slots, effect scaling and per-refracted-idol stats.
func _idol_altar() -> void:
	var saved: Dictionary = Build.items.duplicate(true)
	for slot: String in Build.items.keys():
		if IdolGrid.is_idol_key(slot) or slot == IdolGrid.ALTAR_SLOT:
			Build.items.erase(slot)
	_check("no altar: cell (0,1) not refracted", 1.0 if IdolGrid.is_refracted(0, 1, Build.items) else 0.0, 0.0)
	# Twisted Altar (sub 0): (0,1) is refracted (108: unlockMatrix[x=1][y=0]), (1,1) open (4), (0,0) blocked (99)
	var affixes: Array = [{"id": 1089, "tier": 1, "roll": 255, "index": 0}, {"id": 1100, "tier": 1, "roll": 255, "index": 2}]
	Build.set_item(IdolGrid.ALTAR_SLOT, {"base": 41, "sub": 0, "implicit_rolls": [], "affixes": affixes})
	_check("altar grid: (0,1) refracted", 1.0 if IdolGrid.is_refracted(0, 1, Build.items) else 0.0, 1.0)
	_check("altar grid: (1,1) open, not refracted", 1.0 if IdolGrid.is_open(1, 1, Build.items) and not IdolGrid.is_refracted(1, 1, Build.items) else 0.0, 1.0)
	_check("altar grid: (0,0) blocked", 0.0 if IdolGrid.is_open(0, 0, Build.items) else 1.0, 1.0)
	# an idol affix with a big ADDED value, on a Small Eterran Idol in the refracted slot and one beside it
	var idol_aff: Dictionary = {}
	for aff: Dictionary in GameData.affixes_for_type(25, "Mage"):
		var prop: Dictionary = aff["properties"][0]
		if str(prop.get("modType", "")) == "ADDED" and float(aff["tiers"][-1]["rolls"][0][1]) >= 60.0:
			idol_aff = aff
			break
	if idol_aff.is_empty():
		_failed += 1
		print("FAIL altar test: no idol affix found")
		Build.items = saved
		return
	var entry: Dictionary = {"id": int(idol_aff["affixId"]), "tier": idol_aff["tiers"].size(), "roll": 255, "index": 0 if idol_aff["type"] == "PREFIX" else 2}
	Build.set_item(IdolGrid.key(0, 1), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": [entry]})
	var rolls: Array = idol_aff["tiers"][-1]["rolls"][0]
	var prop_id: int = int(idol_aff["properties"][0]["property"])
	var rounding: String = str(idol_aff["properties"][0].get("rounding", "Integer"))
	var aem: float = AffixMath.effect_modifier(float(GameData.item_base(25).get("affixEffectModifier", 0.0)), float(idol_aff.get("standardAffixEffectModifier", 0.0)))
	var plain: float = AffixMath.roll_value(float(rolls[0]), float(rolls[1]), rounding, "ADDED", 255, aem)
	# AffixList.ChangeAffixModifier: the value is rounded with the effect modifier only, then multiplied by 1.08 (no re-rounding).
	# Hand vector: affix 118 'Idol Dodge Rating' (ADDED 26..70) on a Small Idol (base 25, aem -0.83), roll 255: plain 12, scaled 12 * 1.08 = 12.96
	# (the former (1 + aem) * 1.08 - 1 gave 13)
	var scaled: float = AffixMath.f32(AffixMath.f32(plain) * AffixMath.f32(1.08))
	var g: Dictionary = BuildMods.global_store(Build)
	var idol_total: float = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == prop_id and mod.source.contains(idol_aff["name"]):
			idol_total += mod.added
	_check("refracted idol affix scaled by 1+8%% (%s: %s -> %s)" % [idol_aff["name"], plain, scaled], idol_total, scaled)
	# Health per idol in a refracted slot: one idol in (0,1), another at (1,1) does not count
	Build.set_item(IdolGrid.key(1, 1), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": []})
	g = BuildMods.global_store(Build)
	var per_refracted: float = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == LE.HEALTH and mod.source.contains("Altar") and mod.source.contains("in a refracted slot") and not mod.source.contains("—"):
			per_refracted += mod.added
	_check("altar: +2 health per idol in a refracted slot (1 idol)", per_refracted, 2.0)
	# the same idol outside the altar's refracted slot is not scaled
	Build.clear_item(IdolGrid.key(0, 1))
	Build.set_item(IdolGrid.key(1, 1), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": [entry]})
	g = BuildMods.global_store(Build)
	idol_total = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == prop_id and mod.source.contains(idol_aff["name"]):
			idol_total += mod.added
	_check("non-refracted idol affix unscaled", idol_total, plain)
	_weaver_idols()
	Build.items = saved
	# IdolsItemContainer_UpdateStatsFromAltarMods: property 29 goes through Stats_AddedStat(0x2c)
	_check("altar 29: healing effectiveness is an added stat", 1.0 if AltarMods.PER_IDOL[29]["kind"] == "added" else 0.0, 1.0)


## Blessings with two implicits (docs/ENGINE.md §9.5): implicit j reads its own roll byte (ItemList.GetItemImplicits,
## ItemData.implicitRolls); an entry without `rolls` uses its single roll for every implicit. Blessing 44 'Greed of Darkness':
## implicit 0 = WardGain (39, ADDED 6..10), implicit 1 = WardDecayThreshold (119, ADDED 60..100), Integer rounding.
func _blessing_rolls() -> void:
	var saved_bl: Dictionary = Build.blessings.duplicate(true)
	Build.blessings = {1: {"id": 44, "roll": 0, "rolls": [0, 255, 0]}}
	_check("blessing rolls: implicit 0 with rolls[0] = 0 -> 6", _blessing_total(39), 6.0)
	_check("blessing rolls: implicit 1 with rolls[1] = 255 -> 100 (old single roll gave 60)", _blessing_total(119), 100.0)
	Build.blessings = {1: {"id": 44, "roll": 255, "rolls": [255, 0, 0]}}
	_check("blessing rolls: implicit 0 with rolls[0] = 255 -> 10", _blessing_total(39), 10.0)
	_check("blessing rolls: implicit 1 with rolls[1] = 0 -> 60", _blessing_total(119), 60.0)
	# an entry without rolls (older builds, slider edits): one roll 128 for both implicits
	Build.blessings = {1: {"id": 44, "roll": 128}}
	_check("blessing without rolls: implicit 0 at roll 128 -> 8", _blessing_total(39), 8.0)
	_check("blessing without rolls: implicit 1 at roll 128 -> 80", _blessing_total(119), 80.0)
	Build.blessings = {1: {"id": 44, "roll": 128, "rolls": [128, 255, 3]}}
	_check("blessing rolls: implicit 0 at rolls[0] = 128 -> 8", _blessing_total(39), 8.0)
	_check("blessing rolls: implicit 1 at rolls[1] = 255 -> 100", _blessing_total(119), 100.0)
	# the per-implicit rolls survive the build code; an entry without them loads without the key
	Build.blessings = {1: {"id": 44, "roll": 0, "rolls": [0, 255, 0]}}
	var back: Dictionary = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(BuildCodec.to_dict(Build))))
	_flag("blessing rolls survive the build code", str(back["blessings"][1].get("rolls", [])) == "[0, 255, 0]" and int(back["blessings"][1]["roll"]) == 0)
	Build.blessings = {1: {"id": 44, "roll": 128}}
	back = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(BuildCodec.to_dict(Build))))
	_flag("blessing without rolls loads without the key", not back["blessings"][1].has("rolls"))
	Build.blessings = saved_bl


## Property 21 (docs/ENGINE.md §5.4.1): no larger idol may have a higher top edge than a smaller one, any columns
## (IdolsItemContainer.UpdateStatsFromAltarMods). Synthetic idols, only `base` is read; sizes from items.json: 25 Small 1x1,
## 27 Humble 2x1, 28 Stout 1x2, 29 Grand 3x1. The key is the anchor (top-left cell).
func _larger_above_smaller() -> void:
	_flag("altar 21: Grand (area 3) at row 0 above Small (row 3), other columns", AltarMods.larger_above_smaller({"idol_0_0": {"base": 29}, "idol_3_4": {"base": 25}}))
	_flag("altar 21: Small at row 0, Grand below it: no violation", not AltarMods.larger_above_smaller({"idol_0_0": {"base": 25}, "idol_3_4": {"base": 29}}))
	_flag("altar 21: equal top edges: no violation", not AltarMods.larger_above_smaller({"idol_2_0": {"base": 29}, "idol_2_4": {"base": 25}}))
	_flag("altar 21: Stout 1x2 at row 0 above Small at row 1, other column", AltarMods.larger_above_smaller({"idol_0_0": {"base": 28}, "idol_1_3": {"base": 25}}))
	_flag("altar 21: Humble (larger) at the lower row: no violation", not AltarMods.larger_above_smaller({"idol_0_0": {"base": 25}, "idol_1_0": {"base": 27}}))


## Sum of the added values of property `property` from the blessing 'Greed of Darkness' in the global store.
func _blessing_total(property: int) -> float:
	var g: Dictionary = BuildMods.global_store(Build)
	var total: float = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == property and mod.source.contains("Greed of Darkness"):
			total += mod.added
	return total


## Weaver idols (docs/ENGINE.md §5.4.1): refracted scaling by affix kind and the altar's Weaver idol limit.
func _weaver_idols() -> void:
	var scale: Dictionary = {"prefix": 2.0, "suffix": 3.0, "enchant": 5.0}
	_check("weaver prefix (826) scales as a prefix", float(scale.get(ItemMods.scale_key(GameData.affix(826)), 1.0)), 2.0)
	_check("weaver suffix (835) scales as a suffix", float(scale.get(ItemMods.scale_key(GameData.affix(835)), 1.0)), 3.0)
	var enchant: Dictionary = GameData.affix(892)  # IdolEnchantment, grand / large / ornate / huge / adorned idols
	var corrupted: Dictionary = GameData.affix(1029)  # Corrupted, adorned idols
	_check("idol enchantment scales as an enchant", float(scale.get(ItemMods.scale_key(enchant), 1.0)), 5.0)
	_check("corrupted idol affix is not scaled", float(scale.get(ItemMods.scale_key(corrupted), 1.0)), 1.0)
	# idol kinds by the game's tests (ItemData.IsHereticalIdol / IsOmenIdol / isWeaverIdol, the corrupted flag); sub ids from items.json
	_flag("heretical: Grand Heorot (29, sub 5)", AltarMods.idol_kinds({"base": 29, "sub": 5})["heretical"])
	_flag("not heretical: Grand Majasan (29, sub 4)", not AltarMods.idol_kinds({"base": 29, "sub": 4})["heretical"])
	_flag("heretical: Heretical Adorned Heorot (33, sub 7)", AltarMods.idol_kinds({"base": 33, "sub": 7})["heretical"])
	_flag("not heretical: Adorned Volcano (33, sub 6)", not AltarMods.idol_kinds({"base": 33, "sub": 6})["heretical"])
	_flag("weaver: Small Weaver Idol (25, sub 2)", AltarMods.idol_kinds({"base": 25, "sub": 2})["weaver"])
	_flag("weaver: Minor Weaver Idol (26, sub 1)", AltarMods.idol_kinds({"base": 26, "sub": 1})["weaver"])
	_flag("not weaver: Small Lagonian Idol (26, sub 0)", not AltarMods.idol_kinds({"base": 26, "sub": 0})["weaver"])
	_flag("omen: Grand Primal Omen Idol (29, sub 10)", AltarMods.idol_kinds({"base": 29, "sub": 10})["omen"])
	_flag("not omen: Grand Ash Idol (29, sub 15)", not AltarMods.idol_kinds({"base": 29, "sub": 15})["omen"])
	_flag("corrupted: the item flag (29, sub 0)", AltarMods.idol_kinds({"base": 29, "sub": 0, "corrupted": true})["corrupted"])
	for slot: String in Build.items.keys():
		if IdolGrid.is_idol_key(slot) or slot == IdolGrid.ALTAR_SLOT:
			Build.clear_item(slot)
	_check("no altar: no Weaver idol limit", AltarMods.weaver_limit(Build.items), 0.0)
	# Jagged Altar (sub 1): implicit WeaverIdolLimit 2; three Small Weaver Idols (base 25, sub 2) in its open cells
	Build.set_item(IdolGrid.ALTAR_SLOT, ItemCompare.new_item(41, 1, []))
	_check("Jagged Altar: Weaver idol limit 2", AltarMods.weaver_limit(Build.items), 2.0)
	var placed: int = 0
	for row in range(5):
		for col in range(5):
			if placed < 3 and IdolGrid.fits(Build.items, row, col, 25):
				Build.set_item(IdolGrid.key(row, col), ItemCompare.new_item(25, 2, []))
				placed += 1
	_check("three Weaver idols placed", placed, 3.0)
	_check("Weaver idols counted", AltarMods.idol_counts(Build.items)["weaver"], 3.0)
	_check("one Weaver idol above the limit", AltarMods.weaver_excess(Build.items), 1.0)
	var notes: Array[String] = []
	AltarMods.apply(Build, StatStore.new(), notes)
	_check("note about the Weaver idol limit", 1.0 if notes.any(func(n: String) -> bool: return n.contains("above the limit of 2")) else 0.0, 1.0)


## Curse that deals damage when the cursed enemy is hit (Bone Curse, docs/ENGINE.md §9.3): the event rate is own hits × 3 +
## other hits, generic on-hit ailment chances do not apply, the tree's «when the cursed enemy is hit» ailments follow the
## plain hit rate, and the default of «your hits» is the sum of uses per second of the other hitting skills on the bar.
func _curse_hits() -> void:
	print("--- Bone Curse (curse hits) on the sample build")
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	_check("curse test: slot 0 is Bone Curse", 1.0 if str(Build.skills[0]["ability"]) == "bc53" else 0.0, 1.0)
	# relic «Level of Harvest» T3: SP 88 with specialTag 1 and the ability index (185) in tags -> +1 level for Harvest only
	_check("level of Harvest from the relic", Build.skill_level_bonus(4), 1.0)
	_check("level of Harvest does not apply to Bone Curse", Build.skill_level_bonus(0), 0.0)

	# defaults: estimate = sum of uses/s of the other skills that deal hit damage
	Build.skills[0]["inputs"].erase("curse_own_hits")
	Build.skills[0]["inputs"].erase("curse_other_hits")
	var expected: float = 0.0
	var contributors: PackedStringArray = []
	for slot: int in range(1, Build.skills.size()):
		var ab: Dictionary = GameData.get_ability(str(Build.skills[slot]["ability"]))
		if SkillComponents.deals_hit_damage(ab):
			var other: Dictionary = SkillCalc.compute(Build, slot)
			var uses: float = _section_value(other, "Speed and mana", "Uses per second")
			expected += uses
			contributors.append("%s %s" % [ab.get("name"), uses])
	print("  expected own hits/s = %s (%s)" % [expected, ", ".join(contributors)])
	var r: Dictionary = SkillCalc.compute(Build, 0)
	var own_default: float = -1.0
	for inp: Dictionary in r["inputs"]:
		if inp["key"] == "curse_own_hits":
			own_default = float(inp["value"])
	_check("curse default estimate > 0", 1.0 if own_default > 0.0 else 0.0, 1.0)
	_check("curse default estimate = Σ uses/s of the other hitting skills", own_default, expected, 0.02)
	_check("curse events with defaults = estimate × 3", _section_value(r, CURSE_SECTION, "Damage events per second"), own_default * 3.0, 0.01)
	_check("curse inputs are declared", 1.0 if _has_input(r, "curse_own_hits") and _has_input(r, "curse_other_hits") else 0.0, 1.0)

	# explicit inputs: 2 own hits (×3) + 1 other hit = 7 weighted hits per second
	Build.skills[0]["inputs"]["curse_own_hits"] = 2.0
	Build.skills[0]["inputs"]["curse_other_hits"] = 1.0
	r = SkillCalc.compute(Build, 0)
	_print_sections(r)
	_check("curse events = 2×3 + 1", _section_value(r, CURSE_SECTION, "Damage events per second"), 7.0)
	var plain_hit: float = _section_value(r, "Against enemy", "Hit without crit")
	var avg_hit: float = _section_value(r, "Against enemy", "Average hit vs enemy")
	_check("curse average hit = non-crit hit × average crit multiplier", avg_hit, plain_hit * _section_value(r, "Against enemy", "Average crit multiplier"), 0.05)
	_check("curse DPS vs enemy = average hit × 7", _section_value(r, "Against enemy", "Hit DPS vs enemy"), avg_hit * 7.0, 0.1)
	_check("curse: no Poison section from generic on-hit chances", _count_sections(r, "Ailment: Poison"), 0.0)
	# the tree's «when the cursed enemy is hit» ArmourShred: 100% × (2 + 1) hits/s × 4 s
	_check("curse ArmourShred stacks = curse hits 3/s × 100% × 4 s", _section_value(r, "Non-damaging ailments", "ArmourShred: stacks on target"), 12.0, 0.01)
	# the per-cast hits input does not matter
	Build.skills[0]["hits"] = 5.0
	var r5: Dictionary = SkillCalc.compute(Build, 0)
	_check("curse events ignore hits per cast", _section_value(r5, CURSE_SECTION, "Damage events per second"), 7.0)
	Build.skills[0]["hits"] = 1.0
	# another skill of the bar is still calculated per cast
	var plague: Dictionary = SkillCalc.compute(Build, 2)
	_check("other skill (Spirit Plague) still has a DPS", 1.0 if _section_value(plague, "Against enemy", "DPS vs enemy") > 0.0 else 0.0, 1.0)
	Build.skills[0]["inputs"].erase("curse_own_hits")
	Build.skills[0]["inputs"].erase("curse_other_hits")


func _count_sections(r: Dictionary, title: String) -> float:
	var n: int = 0
	for s: Dictionary in r["sections"]:
		if s["title"] == title:
			n += 1
	return float(n)


## Harvest of the sample build against a dummy, no buffs (calibrated in game: non-crit hits 995, crit 2487 within ±20%).
## Swaddling of the Erased «17% more Melee Damage to High Health Enemies» (SP 117, ConditionalDamageProperty 2) applies
## while the target has high (>= 65%) or full health.
func _high_health_vs_dummy() -> void:
	print("--- High Health condition (Harvest vs dummy)")
	EnemyAilments.enabled = false  # measured in game on a dummy without ailments
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	for i in range(Build.skills.size()):
		Build.skills[i]["inputs"]["enemy_cursed"] = false
		Build.skills[i]["inputs"]["buff_active"] = false
	Build.enemy["kind"] = "dummy"
	var flags: Dictionary = Build.enemy["flags"]
	flags["full_health"] = true
	flags["high_health"] = true
	var high: float = _hit_vs_enemy(SkillCalc.compute(Build, 4))
	flags["full_health"] = false
	flags["high_health"] = false
	var low: float = _hit_vs_enemy(SkillCalc.compute(Build, 4))
	flags["full_health"] = true
	flags["high_health"] = true
	# in game (no variance on the dummy): non-crit 995, crit 2487 (= 995 × 2.5 crit multiplier)
	_check("Harvest non-crit hit vs dummy at high health = game 995", high, 995.0, 1.0)
	_check("Harvest crit hit vs dummy = game 2487", high * 2.5, 2487.0, 2.0)
	_check("High Health more is ×1.17", high / low, 1.17, 0.0005)
	var r: Dictionary = SkillCalc.compute(Build, 4)
	_check("Harvest \"Hit without crit\" row = game 995", _section_value(r, "Against enemy", "Hit without crit"), 995.0, 1.0)
	_check("Harvest \"Hit with crit\" row = game 2487", _section_value(r, "Against enemy", "Hit with crit"), 2487.0, 2.0)
	print("  Harvest vs dummy: no crit %s, crit %s, average %s, hit DPS %s, DPS %s" % [
		_section_value(r, "Against enemy", "Hit without crit"), _section_value(r, "Against enemy", "Hit with crit"),
		_section_value(r, "Against enemy", "Average hit vs enemy"), _section_value(r, "Against enemy", "Hit DPS vs enemy"),
		_section_value(r, "Against enemy", "DPS vs enemy")])
	EnemyAilments.enabled = true


## Sum of the per-type rows of the "Against enemy" section (average non-crit hit against the target).
func _hit_vs_enemy(r: Dictionary) -> float:
	var total: float = 0.0
	for s: Dictionary in r["sections"]:
		if s["title"] != "Against enemy":
			continue
		for row: Dictionary in s["rows"]:
			if LE.DT_NAME.has(str(row["label"])):
				total += float(row["text"])
	return total


## Transplant (a sub-ability component collected from the prefab and from the tree node «explodes at arrival» is one
## component with 1 + extras detonations per cast) and Spirit Plague (a maintained DoT: total over 3 s, no crit, 1/3 events per
## second) of the sample build against the training dummy, docs/ENGINE.md §9.3.
func _detonations_and_maintained_dot() -> void:
	print("--- Transplant detonations and Spirit Plague DoT (sample build vs dummy)")
	EnemyAilments.enabled = false  # the node changes the applications: compare the hits without automatic ailments
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	for i in range(Build.skills.size()):
		Build.skills[i]["inputs"]["enemy_cursed"] = false
		Build.skills[i]["inputs"]["buff_active"] = false
	Build.enemy["kind"] = "dummy"
	const HEAD: String = "Damage per use (before enemy)"
	var r: Dictionary = SkillCalc.compute(Build, 3)
	_print_sections(r)
	var uses: float = _section_value(r, "Speed and mana", "Uses per second")
	_check("Transplant: one damage component", _count_sections(r, HEAD), 1.0)
	_check("Transplant: no duplicate DetonateBody sections", _count_prefixed_sections(r, "DetonateBody:"), 0.0)
	# the helmet affix «Chance to cast Marrow Shards when you cast Transplant» adds a trigger component, so the
	# per-component DPS rows are listed: DetonateBody once
	_check("Transplant: no duplicate per-component DPS rows", _count_rows(r, "Against enemy", "DPS vs enemy: DetonateBody"), 1.0)
	var marrow: float = _section_value(r, "Against enemy", "DPS vs enemy: Marrow Shards")
	_check("Transplant: Marrow Shards affix trigger counted", 1.0 if marrow > 0.0 else 0.0, 1.0)
	var avg: float = _section_value(r, "Against enemy", "Average hit vs enemy")
	var ail: float = _section_value(r, "Against enemy", "Ailment DPS vs enemy")
	# the sample build has «Reign of Blood» (explodes at arrival): the prefab detonation + 1 extra per cast
	_check("Transplant: 2 detonations per cast with the node", _section_value(r, HEAD, "Damage events per second"), uses * 2.0, 0.005)
	_check("Transplant: hit DPS = average hit × casts/s × 2", _section_value(r, "Against enemy", "Hit DPS vs enemy"), avg * uses * 2.0, 0.05)
	_check("Transplant: DPS = hit DPS + ailments once + Marrow Shards", _section_value(r, "Against enemy", "DPS vs enemy"), avg * uses * 2.0 + ail + marrow, 0.05)
	# without the node there is one detonation per cast: the same average hit, half the hit DPS
	var tree: Dictionary = Build.skills[3]["tree"]
	var node_points: Variant = tree.get(17)
	tree.erase(17)
	var plain: Dictionary = SkillCalc.compute(Build, 3)
	_check("Transplant without the node: one component", _count_sections(plain, HEAD), 1.0)
	_check("Transplant without the node: same average hit", _section_value(plain, "Against enemy", "Average hit vs enemy"), avg, 0.005)
	_check("Transplant without the node: DPS = average hit × casts/s", _section_value(plain, "Against enemy", "Hit DPS vs enemy"),
		avg * _section_value(plain, "Speed and mana", "Uses per second"), 0.05)
	_check("Transplant without the node: no events row (1 per cast)", _count_rows(plain, HEAD, "Damage events per second"), 0.0)
	if node_points != null:
		tree[17] = node_points

	# Spirit Plague: one maintained instance, total over the base 3 s
	var sp: Dictionary = SkillCalc.compute(Build, 2)
	_print_sections(sp)
	var instance: float = _section_value(sp, "Against enemy", "Damage over the whole duration vs enemy (3 s)")
	var per_second: float = _section_value(sp, "Against enemy", "Damage per second vs enemy")
	_check("Spirit Plague: instance vs dummy > 0", 1.0 if instance > 0.0 else 0.0, 1.0)
	_check("Spirit Plague: damage per second = instance / 3", per_second, instance / 3.0, 0.02)
	_check("Spirit Plague: total DPS = per second + ailments", _section_value(sp, "Against enemy", "DPS vs enemy"),
		per_second + _section_value(sp, "Against enemy", "Ailment DPS vs enemy"), 0.03)
	_check("Spirit Plague: own section total over 3 s", _section_value(sp, "Effect damage over its whole duration (before enemy)", "Damage over the whole duration (3 s)"),
		_section_value(sp, "Effect damage over its whole duration (before enemy)", "Damage per second") * 3.0, 0.05)
	_check("Spirit Plague: no crit section", _count_sections(sp, "Crit"), 0.0)
	_check("Spirit Plague: no crit rows vs enemy", _count_rows(sp, "Against enemy", "Hit with crit") + _count_rows(sp, "Against enemy", "Hit without crit") +
		_count_rows(sp, "Against enemy", "Average crit multiplier"), 0.0)
	_check("Spirit Plague: dummy mitigation = Necrotic penetration x1.18", instance / _section_value(sp, "Effect damage over its whole duration (before enemy)", "Damage over the whole duration (3 s)"), 1.18, 0.005)
	# increased duration does not change the damage per second
	var tree_sp: Dictionary = Build.skills[2]["tree"]
	tree_sp[15] = 2
	var longer: Dictionary = SkillCalc.compute(Build, 2)
	_check("Spirit Plague: increased duration keeps the damage per second", _section_value(longer, "Against enemy", "Damage per second vs enemy"), per_second, 0.005)
	tree_sp.erase(15)
	# the tree's «more damage» node applies to the DoT total
	tree_sp[22] = 5
	var more: Dictionary = SkillCalc.compute(Build, 2)
	_check("Spirit Plague: node More Damage ×5 → ×1.5", _section_value(more, "Against enemy", "Damage over the whole duration vs enemy (3 s)") / instance, 1.5, 0.005)
	tree_sp.erase(22)
	EnemyAilments.enabled = true


func _count_source_prefix(store: StatStore, prefix: String) -> float:
	var n: int = 0
	for mod: StatMod in store.mods:
		if mod.source.begins_with(prefix):
			n += 1
	return float(n)


func _count_prefixed_sections(r: Dictionary, prefix: String) -> float:
	var n: int = 0
	for s: Dictionary in r["sections"]:
		if str(s["title"]).begins_with(prefix):
			n += 1
	return float(n)


func _count_rows(r: Dictionary, section: String, label: String) -> float:
	var n: int = 0
	for s: Dictionary in r["sections"]:
		if s["title"] == section:
			for row: Dictionary in s["rows"]:
				if row["label"] == label:
					n += 1
	return float(n)


func _flag(label: String, ok: bool) -> void:
	_check(label, 1.0 if ok else 0.0, 1.0)


## Stat diff of an item swap (ItemCompare) and the stash swap of Build (docs/UI.md "Items").
func _item_compare() -> void:
	print("--- item compare and stash on the sample build")
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	var slots: Array[String] = []
	for slot: String in BuildMods.SLOTS:
		if Build.items.has(slot):
			slots.append(slot)
	_flag("compare: the sample build has equipped items", not slots.is_empty())
	var items_before: String = var_to_str(Build.items)
	var base: Dictionary = ItemCompare.snapshot(Build)
	_flag("compare: the snapshot has the DPS row", base.has("dps"))
	_flag("compare: the snapshot has character stats", base.size() > 10)

	var same_empty: bool = true
	var removal_changes: bool = false
	for slot: String in slots:
		same_empty = same_empty and ItemCompare.diff(base, ItemCompare.snapshot_with_item(Build, slot, Build.items[slot])).is_empty()
		removal_changes = removal_changes or not ItemCompare.diff(base, ItemCompare.snapshot_with_item(Build, slot, {})).is_empty()
	_flag("compare: the same item gives an empty diff", same_empty)
	_flag("compare: removing equipped items changes the stats", removal_changes)
	_flag("compare: Build.items is unchanged", var_to_str(Build.items) == items_before)
	_flag("compare: an absent slot stays absent", not ItemCompare.snapshot_with_item(Build, "altar", {}).is_empty() and not Build.items.has("altar"))
	_check("format_delta +", 1.0 if ItemCompare.format_delta(12.5, false) == "+12.5" else 0.0, 1.0)
	_check("format_delta −%", 1.0 if ItemCompare.format_delta(-0.03, true) == "−3%" else 0.0, 1.0)

	# stash swap: the old item takes the place of the equipped stash item
	var slot: String = slots[0]
	var old_item: Dictionary = (Build.items[slot] as Dictionary).duplicate(true)
	var new_item: Dictionary = old_item.duplicate(true)
	new_item["affixes"] = []
	new_item["implicit_rolls"] = []
	Build.stash.clear()
	Build.stash_add(new_item)
	Build.stash_add(old_item)
	Build.equip_from_stash(0, slot)
	_flag("stash: the stash item is equipped", var_to_str(Build.items[slot]) == var_to_str(new_item))
	_flag("stash: the old item sits at the same index", Build.stash.size() == 2 and var_to_str(Build.stash[0]) == var_to_str(old_item))
	Build.unequip_to_stash(slot)
	_flag("stash: unequip moves the item to the end", not Build.items.has(slot) and Build.stash.size() == 3)
	Build.equip_from_stash(2, slot)
	_flag("stash: equip into an empty slot removes the entry", Build.items.has(slot) and Build.stash.size() == 2)
	Build.equip_item(slot, old_item)
	_flag("stash: equip_item stashes the replaced item", Build.stash.size() == 3 and var_to_str(Build.items[slot]) == var_to_str(old_item))
	Build.stash_remove(99)
	Build.stash_remove(0)
	_flag("stash: remove is bounds-checked", Build.stash.size() == 2)
	Build.stash_set(0, old_item)
	_flag("stash: stash_set replaces the entry", var_to_str(Build.stash[0]) == var_to_str(old_item))

	# moving between slots: rings swap, an item that does not fit the source slot goes to the stash
	var ring_a: Dictionary = ItemCompare.new_item(_first_base("ring1"), 0, [])
	var ring_b: Dictionary = ring_a.duplicate(true)
	ring_b["implicit_rolls"] = [0]
	Build.set_item("ring1", ring_a)
	Build.set_item("ring2", ring_b)
	var stash_size: int = Build.stash.size()
	var both: Dictionary = ItemCompare.snapshot_with_items(Build, {"ring1": ring_b, "ring2": ring_a})
	_flag("move: swapping two rings changes nothing", ItemCompare.diff(ItemCompare.snapshot(Build), both).is_empty())
	Build.move_item("ring1", "ring2")
	_flag("move: rings swap", var_to_str(Build.items["ring2"]) == var_to_str(ring_a) and var_to_str(Build.items["ring1"]) == var_to_str(ring_b))
	Build.set_item("helmet", ItemCompare.new_item(_first_base("helmet"), 0, []))
	Build.set_item("amulet", ItemCompare.new_item(_first_base("amulet"), 0, []))
	Build.move_item("amulet", "helmet")  # not a real use, but checks the "does not fit back" branch
	_flag("move: the replaced item that does not fit goes to the stash",
		not Build.items.has("amulet") and Build.stash.size() == stash_size + 1)


func _first_base(slot: String) -> int:
	for base: Dictionary in GameData.item_bases:
		if ItemCompare.fits_slot(slot, base):
			return int(base["baseTypeID"])
	return -1


## Projectiles per use and how many hit one target (docs/ENGINE.md §9.7).
func _projectiles() -> void:
	print("--- projectiles")
	Build.set_skill(0, "mush9")  # Multishot: 5 arrows, shared hit list
	var r: Dictionary = SkillCalc.compute(Build, 0)
	_check("Multishot: 5 arrows", float(r["projectiles"]["count"]), 5.0)
	_check("Multishot: no shotgun, 1 arrow hits", float(r["projectiles"]["factor"]), 1.0)
	var ab: Dictionary = GameData.get_ability("mush9")
	var shotgun_node: Dictionary = {"params": {"Arrows can hit one target multiple times": {"param": "shotgun", "added": 0.0,
		"increased": 0.0, "more": 1.0, "set": 1.0, "sources": []},
		"Extra arrows": {"param": "projectiles", "added": 2.0, "increased": 0.0, "more": 1.0, "set": null, "sources": []}}}
	_check("Multishot + shotgun node + 2 arrows, average (1+7)/2", float(SkillCalc.projectile_hits(Build, 0, ab, shotgun_node)["factor"]), 4.0)
	EnemyAilments.enabled = false  # more blades also apply more ailments: compare the hits alone
	Build.set_skill(0, "ub5d9")  # Umbral Blades: 2 blades, can hit one target with both
	var avg: Dictionary = SkillCalc.compute(Build, 0)
	_check("Umbral Blades: shotgun", 1.0 if avg["projectiles"]["shotgun"] else 0.0, 1.0)
	_check("Umbral Blades: average (1+2)/2", float(avg["projectiles"]["factor"]), 1.5)
	Build.set_skill_projectile_mode(0, "one")
	var one: Dictionary = SkillCalc.compute(Build, 0)
	Build.set_skill_projectile_mode(0, "all")
	var all: Dictionary = SkillCalc.compute(Build, 0)
	var dps_one: float = float(CalcSummary.find_row(one, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION).get("value", 0.0))
	var dps_all: float = float(CalcSummary.find_row(all, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION).get("value", 0.0))
	print("  Umbral Blades DPS one %s, all %s" % [dps_one, dps_all])
	_check("Umbral Blades: all / one = 2", dps_all / maxf(dps_one, 0.0001), 2.0, 0.01)
	EnemyAilments.enabled = true
	# the ailment chances roll per hit on the target: the breakdown names the projectiles hitting it and the mode
	var hits_text: String = SkillCalc._hit_events_text({"rate": 0.0, "kind": "primary", "per_use": 1.0}, 2.0, 1.0,
		{"factor": 1.5, "mode": "average"}, 3.0, false)
	_flag("ailment hits text: projectiles × mode", hits_text.contains("1.5") and hits_text.contains(LE.t("Average")))
	_check("mode survives save/load", 1.0 if str(BuildCodec.to_dict(Build)["skills"][0]["projectile_mode"]) == "all" else 0.0, 1.0)
	Build.set_skill(0, "th39")  # Summon Thorn Totem: the totem fires 4 thorns that share one hit list
	var totem: Dictionary = SkillCalc.compute(Build, 0)
	_check("Thorn Totem: minion projectiles found", float(totem["projectiles"].get("count", 0.0)), 4.0)
	_check("Thorn Totem: no shotgun, 1 thorn hits", float(totem["projectiles"].get("factor", 0.0)), 1.0)
	var shotgun_minion: Dictionary = {"params": {"Arrows can hit one target multiple times": {"param": "shotgun", "added": 0.0,
		"increased": 0.0, "more": 1.0, "set": 1.0, "sources": []}}}
	Build.set_skill_projectile_mode(0, "all")
	_check("minion thorns with shotgun, all", float(SkillCalc.projectile_hits(Build, 0, GameData.ability_by_name("ThornTotemAttack"), shotgun_minion)["factor"]), 4.0)
	Build.set_skill(0, "")


## Skills cast by item affixes count in the DPS of the skill that triggers them (docs/ENGINE.md §5.4.3).
func _item_triggers() -> void:
	print("--- item triggers")
	var items_before: Dictionary = Build.items.duplicate(true)
	Build.set_class(4)  # Rogue
	Build.set_skill(0, "mush9")  # Multishot (Bow)
	Build.items.erase("weapon")
	var plain: Dictionary = SkillCalc.compute(Build, 0)
	Build.items["weapon"] = {"base": 23, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 966, "kind": "prefix", "tier": 1, "roll": 255}]}
	var with_bow: Dictionary = SkillCalc.compute(Build, 0)
	var shuriken_row: Dictionary = CalcSummary.find_row(with_bow, "DPS vs enemy: %s" % "Shurikens")
	print("  rows: %s" % [shuriken_row])
	_check("affix 966: Shurikens on bow crit is a DPS component", 0.0 if shuriken_row.is_empty() else 1.0, 1.0)
	var dps_plain: float = float(CalcSummary.find_row(plain, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION).get("value", 0.0))
	var dps_bow: float = float(CalcSummary.find_row(with_bow, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION).get("value", 0.0))
	_check("affix 966: the total DPS grows", 1.0 if dps_bow > dps_plain else 0.0, 1.0)
	# a character-event trigger (Fire Aura when hit) is counted in one slot only
	Build.set_skill(1, "srk21")
	Build.items["helmet"] = {"base": 0, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 396, "kind": "prefix", "tier": 1, "roll": 255}]}
	var keys: Array[String] = []
	for slot: int in [0, 1]:
		var found: bool = false
		for inp: Dictionary in SkillCalc.compute(Build, slot)["inputs"]:
			found = found or str(inp.get("key", "")) == "events_hit_taken"
		keys.append("%d:%s" % [slot, found])
	_check("Fire Aura when hit: only the first slot", 1.0 if keys == ["0:true", "1:false"] else 0.0, 1.0)
	Build.set_skill(0, "")
	Build.set_skill(1, "")
	Build.items = items_before


## Shadows, Void Knight echoes, buffs on the player and combo parts (docs/ENGINE.md §9.10).
func _shadows_echoes_buffs() -> void:
	print("--- shadows, echoes, buffs on the player, combo parts")
	var bd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/letools_Q0V6XDLG.json"))
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(bd))  # Bladedancer: Umbral Blades, Dreamslash, Shadow Cascade
	EnemyAilments.enabled = false
	var ub: Dictionary = SkillCalc.compute(Build, 0)
	# "Only 1 Blade" writes +250% into three combo-part mutators: counted once (it was ×3.5³)
	_check("Umbral Blades throw DPS with the combo parts counted once", _row_value(ub, "DPS vs enemy: Umbral Blades"), 107204.7, 110.0)  # was 68149.37: Jormun's counts the reforged third piece (3 items: x1.2 dual wield, +10 Dexterity, +0.1 crit multiplier) and Agility PP 93 adds 25% increased damage
	# Shadow Daggers strike at 4 stacks: one strike per 4 applications of the skill's own hits
	var daggers: float = _row_value(ub, "Damage events per second", "Shadow Daggers: ")
	_flag("Shadow Daggers strikes counted", daggers > 0.0)
	_check("Umbral Blades DPS with the Shadow Daggers strikes", _dps(ub), 872143.76, 900.0)  # was 614489.05: Jormun's 3 items, Agility PP 93
	EnemyAilments.enabled = true
	_automatic_enemy_ailments()
	_zones()
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(bd))
	_check("no shadow components without shadows", _count_prefixed_sections(ub, "Shadows: "), 0.0)
	_check("max shadows: 3 + Shadow Master + mastery + Doppelganger's", ShadowCalc.max_shadows(Build), 6.0)
	_check("increased damage of shadows (passives, idols, set, Tabi)", float(ShadowCalc.property(Build, 2)["value"]), 3.07, 0.001)
	Build.set_player_state("shadows", 10)
	_check("active shadows clamped to the limit", ShadowCalc.count(Build), 6.0)
	# Net is repeated by every shadow (CreateShadowMutator.startedUsingAbility)
	_flag("shadows imitate Net", ShadowCalc.imitates(GameData.ability_by_name("Falconer 05 Net")))
	Build.set_player_state("shadows", 3)
	# health / ward on shadow creation: 3 shadows × 2.61 uses/s created per second (Skiasynthesis 90, ward affixes 211)
	_check("Umbral Blades: health on shadow creation per second", _row_value(SkillCalc.compute(Build, 0), LE.t("Health on shadow creation per second")), 704.88, 0.5)
	_check("Umbral Blades: ward on shadow creation per second", _row_value(SkillCalc.compute(Build, 0), LE.t("Ward on shadow creation per second")), 1652.55, 0.5)
	# a node of another bar skill's tree aimed at this skill: Umbral Blades «No Recall, Shift Recalls» → Shift mana per blade
	var shift_s: Dictionary = BuildMods.skill_store(Build, 4, BuildMods.global_store(Build)["store"])
	var shift_mana: float = 0.0
	for label: Variant in shift_s["params"]:
		if str(shift_s["params"][label]["param"]) == "mana" and str(shift_s["params"][label]["sources"]).contains("Umbral Blades"):
			shift_mana += float(shift_s["params"][label]["added"])
	_check("Shift gets the Umbral Blades node aimed at it", shift_mana, 2.0)
	var sc: Dictionary = SkillCalc.compute(Build, 3)
	_flag("Shadow Cascade: shadow component", _count_prefixed_sections(sc, "Shadows: Shadow Cascade") > 0.0)
	_flag("Shadow Cascade DPS grows with shadows", _dps(sc) > 62039.3 * 2.0)
	var rel: Dictionary = ConfigRelevance.compute(Build)
	_flag("relevance: active shadows", rel["player_values"].has("shadows"))
	_flag("relevance: Dusk Shroud buff", rel["player_buffs"].has(82))
	Build.set_player_state("shadows", 0)
	var dodge0: float = BuildMods.global_store(Build)["store"].query_untagged(LE.DODGE_RATING).added
	Build.set_player_buff(82, 10)  # Dusk Shroud: +50 dodge rating per stack
	Build.set_player_buff(83, 7)  # Crimson Shroud: at most 3 stacks
	_check("Dusk Shroud ×10: +500 dodge rating", BuildMods.global_store(Build)["store"].query_untagged(LE.DODGE_RATING).added - dodge0, 500.0, 0.01)
	_check("Crimson Shroud clamped to 3", BuildMods.buff_stacks(Build, 83), 3.0)
	var doc: Dictionary = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(BuildCodec.to_dict(Build))))
	_check("buff stacks survive the build code", float(doc["player"]["buffs"].get(82, 0)), 10.0)
	Build.clear_player_buffs()
	var vk: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/maxroll_char_palading.json"))
	LEToolsImportScript.apply(Build, MaxrollImport.to_build(vk))  # Void Knight
	var throw_ab: Dictionary = GameData.get_ability(str(Build.skills[4]["ability"]))
	var s: Dictionary = BuildMods.skill_store(Build, 4, BuildMods.global_store(Build)["store"])
	_check("Void Knight echo chance: mastery 10% + passives", float(EchoCalc.chance(Build, throw_ab, s)["value"]), 0.22)
	# Reclaimed Action (Volatile Reversal node 21): the guaranteed echo after a long jump makes the echo chance 100% (chance 22% > 0)
	var vr_skill: Dictionary = Build.skills[2]
	var vr_tree: Dictionary = (vr_skill.get("tree", {}) as Dictionary).duplicate()
	vr_tree[21] = 1
	Build.skills[2] = {"ability": vr_skill["ability"], "tree": vr_tree, "level": vr_skill.get("level", 20)}
	_check("Reclaimed Action: guaranteed echo = 100% (base 22% > 0)", float(EchoCalc.chance(Build, throw_ab, BuildMods.skill_store(Build, 4, BuildMods.global_store(Build)["store"]))["value"]), 1.0)
	Build.skills[2] = vr_skill
	_flag("Shield Throw: echo component", _count_prefixed_sections(SkillCalc.compute(Build, 4), "Echo: ") > 0.0)
	_flag("Anomaly does not echo", not EchoCalc.eligible(GameData.ability_by_name("Anomaly"), {}))
	# Warpath (channelled) echoes only with its node, rolled once per second: rate = chance, not uses/s × chance
	var wp: Dictionary = GameData.ability_by_name("Warpath")
	var vk_skill: Dictionary = Build.skills[3]
	Build.skills[3] = {"ability": str(wp["playerAbilityID"]), "tree": {}, "level": 20}
	_flag("Warpath without its node does not echo", not EchoCalc.eligible(wp, BuildMods.skill_store(Build, 3, BuildMods.global_store(Build)["store"])))
	Build.skills[3] = {"ability": str(wp["playerAbilityID"]), "tree": {31: 1}, "level": 20}  # Warpath Tree Echoes
	var wr: Dictionary = SkillCalc.compute(Build, 3)
	_check("Warpath echo: (1 + 100%) × 22% rolled once per second", _row_value(wr, LE.t("Damage events per second"), LE.t("Echo: %s") % "WarpathHit"), 0.44, 0.001)
	Build.skills[3] = vk_skill
	# Volatile Reversal: cooldown recovery written into the jump and the return mutator counts once
	EnemyAilments.enabled = false
	_check("Volatile Reversal DPS", _dps(SkillCalc.compute(Build, 2)), 1688563.45, 1700.0)  # was 1694101.45: property 21 (larger idol above a smaller one) tests top edges over all idol pairs, columns do not matter (IdolsItemContainer.UpdateStatsFromAltarMods, #38); earlier, was 43718: Time Rot takes the character damage modifier (CharacterAilmentMutator.GetAilmentDamageModifier: (speed f + 1)(Time Rot chance f + 1)(Slow chance f + 1) - 1 = x75 here, #52), earlier: cooldown recovery sums the ADDED SP 70 of gear/passives with the increased part (was 28007); omen idols use omenIdolAffixEffectModifier (was 27852.5); casts of the character (item properties) are built in the global store, not in the skill's (was 28122); item cooldowns that start after a cast give 1 / (icd + 1 / rate) (was 28079)
	EnemyAilments.enabled = true


## Automatic enemy ailments (EnemyAilments): Umbral Blades keeps its own shreds on the target; a number set on the
## Conditions tab (0 included) wins.
func _automatic_enemy_ailments() -> void:
	print("--- automatic enemy ailments")
	Build.clear_enemy_ailments()
	var shred: int = GameData.ailment_id_by_name("PhysicalResistanceShred")
	var armour: int = GameData.ailment_id_by_name("ArmourShred")
	var auto: Dictionary = EnemyAilments.auto(Build, 0)
	_check("Umbral Blades keeps 10 physical resistance shreds (limit)", float(auto.get(shred, {}).get("stacks", 0.0)), 10.0, 0.001)
	var a: Dictionary = auto.get(armour, {})
	_check("armor shred stacks = applications/s × duration", float(a.get("stacks", 0.0)), float(a.get("rate", 0.0)) * 4.0, 0.001)
	var daggers: int = GameData.ailment_id_by_name("ShadowDaggers")
	_check("Shadow Daggers strike at 4 stacks: on average 1.5 on the target", float(auto.get(daggers, {}).get("stacks", 0.0)), 1.5, 0.001)
	var blind: Dictionary = auto.get(GameData.ailment_id_by_name("Blind"), {})
	_flag("Smoke Bomb (cooldown, other slot) blinds through its zone", str(blind.get("sources", {}).keys()).contains("Smoke Bomb"))
	_check("stacks wiped every 1 s, applied 4/s for 4 s: 4 × 1 / 2", EnemyAilments.consumed_load(4.0, 4.0, 1.0), 2.0)
	_check("stacks wiped every 4 s, applied 1/s for 2 s: 2 − 4 / 8", EnemyAilments.consumed_load(1.0, 2.0, 4.0), 1.5)
	# Rive wipes on its third strike only: strikes [Rive1, Rive2, Rive3] (1/3), skipped second strike [Rive1, Rive3] (1/2), Cadence (1/5)
	_check("Rive third share default [R1,R2,R3]", EnemyAilments.rive_third_share(false, false, false), 1.0 / 3.0, 0.0001)
	_check("Rive third share skip second [R1,R3]", EnemyAilments.rive_third_share(false, false, true), 0.5, 0.0001)
	_check("Rive third share Cadence [R1,R2,R1,R2,R3]", EnemyAilments.rive_third_share(false, true, false), 0.2, 0.0001)
	_check("Rive third share Cadence + skip second [R1,R1,R3]", EnemyAilments.rive_third_share(false, true, true), 1.0 / 3.0, 0.0001)
	_check("Rive third share Double Slash", EnemyAilments.rive_third_share(true, false, false), 0.0, 0.0001)
	_check("Rive third share Cadence + Double Slash", EnemyAilments.rive_third_share(true, true, false), 0.0, 0.0001)
	# 1.5 uses/s x 1/3 = 0.5 wipes/s (period 2 s): applied 1/s for 4 s -> 1 x 2 / 2 (per-use period 1 / 1.5 gave 0.3333)
	_check("Rive wipes every 2 s, applied 1/s for 4 s", EnemyAilments.consumed_load(1.0, 4.0, 2.0), 1.0)
	# gate: the gap between uses (1 / uses) must not exceed the combo timer (3 s by default)
	var rive_plain: Dictionary = {"uses": 2.0, "flag_keys": []}
	_check("Rive wipes 2 uses/s x 1/3 = 2/3 per s", EnemyAilments.consume_events(Build, EnemyAilments.RIVE_THIRD_FLAG, rive_plain), 2.0 / 3.0, 0.0001)
	rive_plain["uses"] = 0.3
	_check("Rive combo falls back to Rive1 (gap 3.33 s > 3 s): no wipe", EnemyAilments.consume_events(Build, EnemyAilments.RIVE_THIRD_FLAG, rive_plain), 0.0, 0.0001)
	var with_auto: float = _dps(SkillCalc.compute(Build, 0))
	_flag("automatic shreds raise the DPS", with_auto > 614489.05 * 1.5)
	# buffs on you from the skill's hits: Dusk Shroud 60% per use of a melee / throwing attack that hits (Veil of Night,
	# Shadow Master), Crimson Shroud 30% (Scarlet Stream) up to its 3 stacks
	var buffs: Dictionary = EnemyAilments.buffs(Build, 0)
	var dusk: Dictionary = buffs.get(GameData.ailment_id_by_name("DuskShroud"), {})
	var uses: float = float(SkillCalc.compute(Build, 0)["rates"]["uses"])
	_check("Dusk Shroud 60% per use of a melee / throwing attack that hits", float(dusk.get("sources", {}).get(
		"Umbral Blades: melee or throwing attack that hits, chance 60%", 0.0)), 0.6 * uses, 0.001)
	_check("Dusk Shroud 12% on use (Umbral Blades node)", float(dusk.get("sources", {}).get(
		"Umbral Blades: Dusk Shroud chance on use: chance 12% per use", 0.0)), 0.12 * uses, 0.001)
	_flag("Dusk Shroud from the Smoke Bomb cloud", str(dusk.get("sources", {}).keys()).contains("Smoke Bomb"))
	_check("Dusk Shroud on you = all gains/s × 4 s", float(dusk.get("stacks", 0.0)), float(dusk.get("rate", 0.0)) * 4.0, 0.001)
	_check("Crimson Shroud on you: its limit of 3", float(buffs.get(GameData.ailment_id_by_name("CrimsonShroud"), {}).get("stacks", 0.0)), 3.0, 0.001)
	_flag("Dusk Shroud is not an enemy ailment", not auto.has(GameData.ailment_id_by_name("DuskShroud")))
	# Smoke Bomb params: Smoke Blades 1 stack/s while in the 4 s cloud, Silver Shroud stacks per use spent by enemy hits
	var smoke_uses: float = float(SkillCalc.compute(Build, 1)["rates"]["uses"])
	_check("Smoke Blades = 1/s × min(1, uses × 4 s) × 4 s", float(buffs.get(GameData.ailment_id_by_name("SmokeBlades"), {}).get("stacks", 0.0)),
		minf(1.0, smoke_uses * 4.0) * 4.0, 0.001)
	_flag("Silver Shroud from Moonlight Bomb", float(buffs.get(GameData.ailment_id_by_name("SilverShroud"), {}).get("stacks", 0.0)) > 0.0)
	# other skill parameters that give buffs on you
	var rates: Dictionary = {"uses": 0.1, "hits": 2.0, "crit": 0.4}
	var g: Array[Dictionary] = EnemyAilments._param_sources(Build, {"Erasing Strike": {"param": "void_essence_crit_chance", "added": 0.5}}, rates)
	_check("Void Essence on crit: hits × crit × chance", float(g[0]["rate"]) if g.size() == 1 else -1.0, 0.4, 0.0001)
	g = EnemyAilments._param_sources(Build, {"Void Cleave": {"param": "molten_stacks", "added": 1.0}}, rates, ["Molten Infusion only on hit vs own minion"])
	_flag("Molten Infusion only on minion hits: no gain", g.is_empty())
	g = EnemyAilments._param_sources(Build, {"A": {"param": "dusk_shroud_interval", "set": 2.0}, "B": {"param": "dusk_shroud_frequency", "increased": 1.0}}, rates)
	_check("Smoke Bomb Dusk Shroud: every 2 / (1 + 100%) s, 40% of the time in the cloud", float(g[0]["rate"]) if g.size() == 1 else -1.0, 0.4, 0.0001)
	g = EnemyAilments._param_sources(Build, {"Drain Life": {"param": "contempt_interval", "set": 0.5}}, rates)
	_check("Contempt: a stack every 0.5 s of channel", float(g[0]["rate"]) if g.size() == 1 else -1.0, 2.0, 0.0001)
	# events the calculation cannot derive: player numbers of the Conditions tab, shown only with a source in the build
	g = EnemyAilments._param_sources(Build, {"Smoke Bomb": {"param": "crimson_shroud_chance", "added": 0.5}}, rates)
	_flag("Crimson Shroud on kill in the cloud: nothing without kills/s", g.is_empty())
	Build.player_state["kills_per_second"] = 2.0
	g = EnemyAilments._param_sources(Build, {"Smoke Bomb": {"param": "crimson_shroud_chance", "added": 0.5}}, rates)
	_check("Crimson Shroud: kills/s × 40% of the time in the cloud × 50%", float(g[0]["rate"]) if g.size() == 1 else -1.0, 0.4, 0.0001)
	Build.player_state["kills_per_second"] = 0.0
	var reasons: Dictionary = EnemyAilments.input_reasons(Build, {})
	_flag("drops below high health/s shown for Cloaked Reaper (Silver Shroud, PP 104)", (reasons["player_values"] as Dictionary).has("health_drops_per_second"))
	_flag("kills, stuns, arrows and Moving not shown without a source", not (reasons["player_values"] as Dictionary).has("kills_per_second")
		and not (reasons["player_values"] as Dictionary).has("stuns_per_second") and not (reasons["player_values"] as Dictionary).has("arrow_pickups_per_second")
		and (reasons["player_flags"] as Dictionary).is_empty())
	Build.player_state["health_drops_per_second"] = 0.5
	var drops: Dictionary = EnemyAilments.buffs(Build, 0).get(GameData.ailment_id_by_name("SilverShroud"), {})
	_flag("Silver Shroud from drops below high health", str(drops.get("sources", {}).keys()).contains("drops below high health"))
	Build.player_state["health_drops_per_second"] = 0.0
	reasons = EnemyAilments.input_reasons(Build, {"crimson_shroud_chance": "Smoke Bomb"})
	_flag("kills/s shown for Smoke Bomb's Crimson Shroud on kill", (reasons["player_values"] as Dictionary).has("kills_per_second"))
	for id: int in buffs:
		Build.set_player_buff(id, 0.0)
	var bdoc: Dictionary = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(BuildCodec.to_dict(Build))))
	_check("a buff set to 0 by hand survives the build code", float(bdoc["player"]["buffs"].get(GameData.ailment_id_by_name("DuskShroud"), -1.0)), 0.0)
	for id: int in auto:
		Build.set_enemy_ailment(id, 0.0)
	_check("all set to 0 on the Conditions tab: the plain DPS", _dps(SkillCalc.compute(Build, 0)), 872143.76, 900.0)
	Build.clear_enemy_ailment(shred)
	_check("one ailment back to auto: physical shred only", _dps(SkillCalc.compute(Build, 0)), 1280151.3, 1300.0)
	var doc: Dictionary = BuildCodec.from_dict(JSON.parse_string(JSON.stringify(BuildCodec.to_dict(Build))))
	_check("an explicit 0 survives the build code", float(doc["enemy"]["ailments"].get(armour, -1.0)), 0.0)
	Build.clear_enemy_ailments()
	Build.clear_player_buffs()
	# presence: a condition «vs X» counts the share of time the ailment is on the target
	var e: Dictionary = EnemyAilments.effective({"ailments": {}}, {7: {"stacks": 0.4, "uptime": 0.33}})
	_check("presence of an automatic ailment = its uptime", Enemy.presence_id(e, 7), 0.33)
	_check("presence of a value set by hand = 1", Enemy.presence_id({"ailments": {7: 2.0}}, 7), 1.0)


## Zones that apply ailments every interval without a hit (RepeatedlyApplyAilmentsInRadius): Aura of Decay poisons every
## 0.25 s; the build's node converts its poison into bleed.
func _zones() -> void:
	print("--- zones")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/maxroll_char_chudlet.json"))
	LEToolsImportScript.apply(Build, MaxrollImport.to_build(d))
	var r: Dictionary = SkillCalc.compute(Build, 3)
	var zone_rate: float = 0.0
	for a: Dictionary in r["ailments_applied"]:
		if str(a.get("kind", "")) == "zone" and int(a["id"]) == GameData.ailment_id_by_name("Bleed"):
			zone_rate += float(a["rate"])
	_check("Aura of Decay: 4 applications per second, poison converted to bleed", zone_rate, 4.0, 0.001)
	_flag("Aura of Decay: the zone has damage sections", _count_prefixed_sections(r, LE.t("Zone \"%s\"") % "AuraOfDecay") > 0.0)


## Value of the first row with this label (in a section whose title starts with `prefix`, when given).
func _row_value(r: Dictionary, label: String, prefix: String = "") -> float:
	for section: Dictionary in r.get("sections", []):
		if prefix != "" and not str(section["title"]).begins_with(prefix):
			continue
		for row: Dictionary in section["rows"]:
			if str(row.get("label", "")) == label:
				return float(row.get("value", str(row.get("text", "0")).to_float()))
	return -1.0


func _dps(r: Dictionary) -> float:
	return float(CalcSummary.find_row(r, CalcSummary.DPS_LABEL, CalcSummary.ENEMY_SECTION).get("value", 0.0))


## Fixes of the damage review: speed pipeline (06e §1.1), cooldown guards, mod guards, minion copy, ailment conversion guards.
func _review_damage_fixes() -> void:
	print("--- damage review fixes")
	var store := StatStore.new()
	store.add(StatMod.make(LE.CAST_SPEED, "added", 1.0, 0, "test"))
	store.add(StatMod.make(LE.CAST_SPEED, "increased", 0.4, 0, "test"))
	store.add(StatMod.make(LE.CAST_SPEED, "added", 5.0, 0, "other skill", 0, 777))
	var s: Dictionary = {"use_speed_inc": 0.0, "use_speed_more": 1.0, "mana_added": 0.0, "mana_inc": 0.0}
	var ab: Dictionary = {"speedScaler": LE.CAST_SPEED, "useDuration": 1.0, "speedMultiplier": 1.0, "abilityIDEnum": {"value": 5}}
	var ctx: Dictionary = {"store": store, "tags": 0, "ab": ab}
	# S = 1.4 → ×1.1 / 1 (the extra of another ability does not count)
	_check("speed: plain", float(SkillCalc._speed(null, ab, ctx, s)["uses"]), 1.4 * 1.1)
	# speedScalerAppliedAsIncrease, eff 0.5, S = 1.4 → (1.4 − 1)·0.5 + 1 = 1.2 (06e table), not 1.4·0.5 + 1
	ab["speedScalerAppliedAsIncrease"] = 1
	ab["speedScalerEffectiveness"] = 0.5
	_check("speed as increase: max(S-1,0)·eff + 1", float(SkillCalc._speed(null, ab, ctx, s)["uses"]), 1.2 * 1.1)
	# S below 1: no negative increase
	store.add(StatMod.make(LE.CAST_SPEED, "increased", -0.8, 0, "slow"))
	_check("speed as increase: S < 1 gives 1", float(SkillCalc._speed(null, ab, ctx, s)["uses"]), 1.1)
	# a non-positive speed becomes 0.1 before the division
	var dead := StatStore.new()
	dead.add(StatMod.make(LE.CAST_SPEED, "added", 1.0, 0, "test"))
	dead.add(StatMod.make(LE.CAST_SPEED, "more", -1.0, 0, "test"))
	var ab2: Dictionary = {"speedScaler": LE.CAST_SPEED, "useDuration": 1.0, "speedMultiplier": 1.0}
	_check("speedScale <= 0 → 0.1", float(SkillCalc._speed(null, ab2, {"store": dead, "tags": 0, "ab": ab2}, s)["uses"]), 0.1)
	# the extra of the ability narrows the cooldown recovery query
	var cdr := StatStore.new()
	cdr.add(StatMod.make(LE.CDR, "increased", 1.0, 0, "this", 0, 5))
	cdr.add(StatMod.make(LE.CDR, "increased", 1.0, 0, "other", 0, 6))
	_check("cooldown: only own ability extra", float(SkillCalc.cooldown_info({"cooldown": 4.0}, cdr, 0, {}, 5)["cd"]), 2.0)
	# a cooldown length of 0 or less gives no cooldown cap
	var cd0: Dictionary = SkillCalc.cooldown_info({"cooldown": 1.0}, StatStore.new(), 0, {"cooldown": {"length_added": -3.0}})
	_check("cooldown never negative", float(cd0["cd"]), 0.0)
	# mod guards
	# quotient: Stats.QuotientStat, 0 at x == -1, no floor
	_check("quotient at -1 is 0 (QuotientStat)", StatMod.make(LE.DAMAGE, "quotient", -1.0, 0, "test").more[0], 0.0)
	_check("quotient 1.0 = 1/2 - 1", StatMod.make(LE.DAMAGE, "quotient", 1.0, 0, "test").more[0], -0.5)
	_check("quotient -0.5 = 1/0.5 - 1", StatMod.make(LE.DAMAGE, "quotient", -0.5, 0, "test").more[0], 1.0)
	_check("quotient -1.5 = 1/(-0.5) - 1", StatMod.make(LE.DAMAGE, "quotient", -1.5, 0, "test").more[0], -3.0)
	# scaled more: multiplyValues, no clamp
	var sc: StatMod = StatMod.make(LE.DAMAGE, "more", -0.4, 0, "test").scaled(5.0)
	_check("scaled more is not clamped: -0.4 x 5 = -2.0 -> factor -1.0", 1.0 + sc.more[0], -1.0)
	_check("scaled more -0.1 x 3", StatMod.make(LE.DAMAGE, "more", -0.1, 0, "test").scaled(3.0).more[0], -0.3)
	_check("scaled more normal", 1.0 + StatMod.make(LE.DAMAGE, "more", 0.1, 0, "test").scaled(2.0).more[0], 1.2)
	# specialTag: base aggregation counts it, the strict GetTotal* query does not (unless the special matches)
	var base_store := StatStore.new()
	base_store.add(StatMod.make(LE.HEALTH, "added", 100.0, 0, "plain"))
	base_store.add(StatMod.make(LE.HEALTH, "added", 50.0, 0, "special", 3))
	base_store.add(StatMod.make(LE.HEALTH, "added", 7.0, LE.FIRE, "tagged"))
	_check("base aggregation counts a specialTag mod, not a tagged one", base_store.query_untagged(LE.HEALTH).added, 150.0)
	_check("GetTotalAdded(property) with special 0 drops the specialTag mod", base_store.query(LE.HEALTH, 0, 0, 0, false).added, 100.0)
	_check("GetTotalAdded(property, special 3) takes both", base_store.query(LE.HEALTH, 0, 3, 0, false).added, 150.0)
	# sheet attributes: Σ added of the attribute and SP 46 with any tags
	var attr_store := StatStore.new()
	attr_store.add(StatMod.make(LE.STRENGTH, "added", 10.0, LE.MELEE, "tagged"))
	attr_store.add(StatMod.make(LE.STRENGTH, "added", 5.0, 0, "plain"))
	attr_store.add(StatMod.make(LE.ALL_ATTRIBUTES, "added", 2.0, 0, "all", 3))
	var attr_rows: Array[Dictionary] = CharacterCalc._compute_attributes(attr_store)
	_check("sheet Strength = round(10 + 5 + 2) any tags", float(attr_rows[0]["value"]), 17.0)
	_check("sheet Vitality gets only the SP 46 mod", float(attr_rows[1]["value"]), 2.0)
	# the minion copy keeps the curse flag
	var flagged: StatMod = StatMod.make(LE.AILMENT_CHANCE, "added", 0.1, 0, "test", 1)
	flagged.on_curse_hit = true
	_check("minion copy keeps on_curse_hit", 1.0 if MinionCalc._copy(flagged, 0, 0, "x").on_curse_hit else 0.0, 1.0)
	# minion transfer without an ability index: Minion-tagged mods with an extra still go through the MINION branch
	var player := StatStore.new()
	player.add(StatMod.make(LE.DAMAGE, "increased", 0.3, LE.MINION, "minion node", 0, 9))
	var ms: StatStore = MinionCalc.minion_store(player, {}, {}, [])
	_check("no ability index: Minion-tagged extra mod is transferred without the tag", ms.query(LE.DAMAGE, 0).increased, 0.3)


## Speed audit: UsingAbility.InitialiseAbilityUse (minimumUseDuration floor, cast delay floor), mutator overrides of the cast
## (DetonatingArrow / LethalMirage / RadiantLance), the stat-kind speed nodes of speedScaler 54 skills and the weapon attack rate tag test
## (CharacterStats.getPropertyMultiplier).

## Mana cost (BaseMana.getManaCost, ISIL lines 463-505): efficiency SP 69 with extra 0, cost SP 66 with the ability index,
## minimumManaCost floor, zero clamp, attribute / level scaling of SP 66 / 69 (BuildMods._mana_scaling_mod). Hand-computed.
func _mana_cost_audit() -> void:
	print("--- mana cost")
	var ab: Dictionary = {"manaCost": 10.0, "minimumManaCost": 0.0, "abilityIDEnum": {"value": 5}}
	var s: Dictionary = {"mana_added": 2.0, "mana_inc": 0.0}
	var store := StatStore.new()
	store.add(StatMod.make(LE.MANA_COST, "increased", -0.2, 0, "gear"))
	store.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.2, 0, "gear"))
	# (10 + 2) x (1 - 0.2) / (1 + 0.2) = 8
	_check("mana: added, increased, efficiency", float(SkillCalc.mana_parts(ab, store, 0, 5, s)["cost"]), 8.0)
	# efficiency increased 0.5: eff = 1.2 x 1.5 = 1.8
	store.add(StatMod.make(LE.MANA_EFFICIENCY, "increased", 0.5, 0, "gear"))
	_check("mana: efficiency increased", float(SkillCalc.mana_parts(ab, store, 0, 5, s)["cost"]), 9.6 / 1.8)
	# efficiency mod with another extra tag (this ability's index too) is not read: the SP 69 query has extra 0 only
	store.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 1.0, 0, "ability-bound", 0, 5))
	_check("mana: efficiency with an extra is ignored", float(SkillCalc.mana_parts(ab, store, 0, 5, s)["cost"]), 9.6 / 1.8)
	# cost mod with this ability's extra counts, another ability's does not: 12 x (1 - 0.2 - 0.5) / 1.8 = 2
	store.add(StatMod.make(LE.MANA_COST, "increased", -0.5, 0, "this ability", 0, 5))
	store.add(StatMod.make(LE.MANA_COST, "increased", -0.9, 0, "other ability", 0, 6))
	_check("mana: cost extra of this ability only", float(SkillCalc.mana_parts(ab, store, 0, 5, s)["cost"]), 12.0 * 0.3 / 1.8)
	# tagged added -2 (Melee) applies to a Melee skill only: (10 + 2 - 2) x 0.8 / 1.2 and (10 + 2) x 0.8 / 1.2
	var t := StatStore.new()
	t.add(StatMod.make(LE.MANA_COST, "increased", -0.2, 0, "gear"))
	t.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.2, 0, "gear"))
	t.add(StatMod.make(LE.MANA_COST, "added", -2.0, LE.MELEE, "passive"))
	_check("mana: tagged added, melee skill", float(SkillCalc.mana_parts(ab, t, LE.MELEE, 5, s)["cost"]), 10.0 * 0.8 / 1.2)
	_check("mana: tagged added, non-melee skill", float(SkillCalc.mana_parts(ab, t, 0, 5, s)["cost"]), 8.0)
	# more -50%: 12 x 0.8 x 0.5 / 1.2 = 4
	t.add(StatMod.make(LE.MANA_COST, "more", -0.5, 0, "more"))
	_check("mana: more", float(SkillCalc.mana_parts(ab, t, 0, 5, s)["cost"]), 12.0 * 0.8 * 0.5 / 1.2)
	# minimumManaCost 9 raises the cost 8 to 9; a negative result is 0
	var ab_min: Dictionary = {"manaCost": 10.0, "minimumManaCost": 9.0, "abilityIDEnum": {"value": 5}}
	var plain := StatStore.new()
	plain.add(StatMod.make(LE.MANA_COST, "increased", -0.2, 0, "gear"))
	plain.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.2, 0, "gear"))
	_check("mana: minimumManaCost", float(SkillCalc.mana_parts(ab_min, plain, 0, 5, s)["cost"]), 9.0)
	var neg := StatStore.new()
	neg.add(StatMod.make(LE.MANA_COST, "increased", -2.0, 0, "x"))
	_check("mana: never negative", float(SkillCalc.mana_parts(ab, neg, 0, 5, s)["cost"]), 0.0)
	# divider nodes are ADDED efficiency: 16 / (1 + 0.4 + 0.2) = 10 (the old increased model gave 16 x 0.6 = 9.6)
	var dv := StatStore.new()
	dv.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.4, 0, "node"))
	dv.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.2, 0, "gear"))
	_check("mana: divider is added efficiency", float(SkillCalc.mana_parts({"manaCost": 16.0, "minimumManaCost": 0.0}, dv, 0, 7, {"mana_added": 0.0, "mana_inc": 0.0})["cost"]), 10.0)
	# scaling stats: SP 69 attribute scaling takes addedValue x n only (increased and more dropped, tags and extra dropped)
	var rec69: StatMod = BuildMods.stat_from_record({"property": 69, "addedValue": 0.02, "increasedValue": 0.02, "moreValues": [0.1], "tags": 5, "extraTag": 3}, "t")
	var m69: StatMod = BuildMods._mana_scaling_mod(rec69, 10.0, false)
	_check("scaling SP69 added x n", m69.added, 0.2)
	_check("scaling SP69 increased ignored", m69.increased, 0.0)
	_check("scaling SP69 more ignored", float(m69.more.size()), 0.0)
	_check("scaling SP69 tags and extra dropped", float(m69.extra + m69.tags), 0.0)
	# SP 66 scaling: level scaling addedValue flat, increasedValue x level (50): 3 and 0.5; attribute scaling x n (10): 30 and 0.1
	var rec66: StatMod = BuildMods.stat_from_record({"property": 66, "addedValue": 3.0, "increasedValue": 0.01}, "t")
	_check("level scaling SP66 added flat", BuildMods._mana_scaling_mod(rec66, 50.0, true).added, 3.0)
	_check("level scaling SP66 increased x level", BuildMods._mana_scaling_mod(rec66, 50.0, true).increased, 0.5)
	_check("attribute scaling SP66 added x n", BuildMods._mana_scaling_mod(rec66, 10.0, false).added, 30.0)
	_check("attribute scaling SP66 increased x n", BuildMods._mana_scaling_mod(rec66, 10.0, false).increased, 0.1)
	# field models: divider nodes are ADDED ManaEfficiency, Javelin's next melee reduction is -f ManaCost, Frost Wall writes no ManaCost
	var mm: Dictionary = FieldModels.find("MeteorMutator.addedManaCostDivider")
	_flag("#100 Meteor divider is added ManaEfficiency", str(mm.get("kind", "")) == "stat" and str(mm.get("stat", "")) == "ManaEfficiency" and str(mm.get("mod", "")) == "added")
	_check("#100 Javelin next melee: x = -f", float(EffectModels.value(FieldModels.find("JavelinMutator.nextMeleeAttackManaCostReduction"), 10.0, {})["x"]), -10.0)
	_flag("#100 Frost Wall writes no ManaCost", str(FieldModels.find("FrostWallMutator.lessManaCostForGlyphOrInvocOnHit").get("kind", "")) == "flag")
	var um: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/unique_effect_models.json"))
	_flag("#100 Decoy unique ManaEfficiency is added", um is Dictionary and str((um as Dictionary)["ability"]["445:0"].get("mod", "")) == "added")

	# #31 Lunge: manaCostPerDistance x the distance input (default 1) is added to the manaCost, then scaled and divided by efficiency
	var lunge: Dictionary = {"manaCost": 8.0, "minimumManaCost": 0.0, "manaCostPerDistance": 1.0}
	var bare := StatStore.new()
	var zero: Dictionary = {"mana_added": 0.0, "mana_inc": 0.0}
	_check("#31 Lunge distance 1 adds 1 mana", float(SkillCalc.mana_parts(lunge, bare, 0, 5, zero, 1.0)["cost"]), 9.0)
	_check("#31 Lunge distance 0 is the base cost", float(SkillCalc.mana_parts(lunge, bare, 0, 5, zero, 0.0)["cost"]), 8.0)
	_check("#31 Lunge distance 2.5 adds 2.5 mana", float(SkillCalc.mana_parts(lunge, bare, 0, 5, zero, 2.5)["cost"]), 10.5)
	_check("#31 Lunge distance is increased by mana cost", float(SkillCalc.mana_parts(lunge, bare, 0, 5, {"mana_added": 0.0, "mana_inc": 0.2}, 2.5)["cost"]), 12.6)
	var lunge_eff := StatStore.new()
	lunge_eff.add(StatMod.make(LE.MANA_EFFICIENCY, "added", 0.2, 0, "gear"))
	_check("#31 Lunge distance is divided by efficiency", float(SkillCalc.mana_parts(lunge, lunge_eff, 0, 5, zero, 2.5)["cost"]), 10.5 / 1.2)
	_check("#31 distance_cost reported", float(SkillCalc.mana_parts(lunge, bare, 0, 5, zero, 2.5)["distance_cost"]), 2.5)
	_check("#31 no manaCostPerDistance: distance ignored", float(SkillCalc.mana_parts({"manaCost": 8.0, "minimumManaCost": 0.0}, bare, 0, 5, zero, 5.0)["cost"]), 8.0)
	_check("#31 negative distance counts as 0", float(SkillCalc.mana_parts(lunge, bare, 0, 5, zero, -3.0)["cost"]), 8.0)
	# #106 current mana (Conditions value, 0 = maximum, never above the maximum): Mana Strike per mana, Storm Bolt more damage and consumption
	var mana400 := StatStore.new()
	mana400.add(StatMod.make(LE.MANA, "added", 400.0, 0, "max mana"))
	var mctx: Dictionary = {"build": Build, "store": mana400, "slot": 0}
	var strike: Dictionary = FieldModels.find("ManaStrikeMutator.addedLightningPerMana")
	Build.set_player_state("current_mana", 0)
	_check("#106 Mana Strike: current 0 is the maximum 400", float(EffectModels.value(strike, 0.15, mctx)["x"]), 60.0)
	Build.set_player_state("current_mana", 250)
	_check("#106 Mana Strike: 250 current mana", float(EffectModels.value(strike, 0.15, mctx)["x"]), 37.5)
	_check("#106 Mana Strike: crit chance per current mana", float(EffectModels.value(FieldModels.find("ManaStrikeMutator.critChancePerMana"), 0.001, mctx)["x"]), 0.25)
	Build.set_player_state("current_mana", 9999)
	_check("#106 current mana above the maximum is cut to 400", float(EffectModels.value(strike, 0.15, mctx)["x"]), 60.0)
	var mana2000 := StatStore.new()
	mana2000.add(StatMod.make(LE.MANA, "added", 2000.0, 0, "max mana"))
	var bctx: Dictionary = {"build": Build, "store": mana2000, "slot": 0}
	var sb_more: Dictionary = FieldModels.find("StormBoltMutator.moreDamagePer10CurrentMana")
	Build.set_player_state("current_mana", 100)
	_check("#106 Storm Bolt: 100 current mana = +30% more", float(EffectModels.value(sb_more, 0.03, bctx)["x"]), 0.3)
	Build.set_player_state("current_mana", 1000)
	_check("#106 Storm Bolt: 1000 current mana = +300% (cap)", float(EffectModels.value(sb_more, 0.03, bctx)["x"]), 3.0)
	Build.set_player_state("current_mana", 1500)
	_check("#106 Storm Bolt: above the cap stays +300%", float(EffectModels.value(sb_more, 0.03, bctx)["x"]), 3.0)
	var sb_cons: Dictionary = FieldModels.find("StormBoltMutator.manaConsumptionPercentage")
	Build.set_player_state("current_mana", 100)
	_check("#106 Storm Bolt consumption: 1% of 100 mana", float(EffectModels.value(sb_cons, 0.01, bctx)["x"]), 1.0)
	Build.set_player_state("current_mana", 2000)
	_check("#106 Storm Bolt consumption capped at 10", float(EffectModels.value(sb_cons, 0.01, bctx)["x"]), 10.0)
	Build.set_player_state("current_mana", 0)
	# #28 / #94 remaining-cooldown recovery on events the calculator cannot count: a parameter row, not a permanent cooldown speed
	FieldModels.find("")
	var permanent_recovery: int = 0
	for key: Variant in FieldModels._models:
		var fm: Dictionary = FieldModels._models[key]
		if str(fm.get("kind", "")) == "cooldown" and str(fm.get("cooldown", "")) == "recovery_increased" and str(fm.get("note", "")).contains("emaining"):
			permanent_recovery += 1
	_check("#28 no remaining-cooldown recovery as a permanent cooldown model", float(permanent_recovery), 0.0)
	_flag("#28 Healing Hands ally heal recovery is a parameter row", str(FieldModels.find("CharacterMutator.healingHandsCooldownRecoveryOnOtherAllyHealed").get("param", "")) == "cooldown_event_recovery")
	# #99 Drain Life: the Damned stack bonus is capped by the node's maxTotalDamageToDamned (0.21 per point), 0.03 per stack
	var damned: int = GameData.enum_value("AilmentID", "Damned")
	var dl_more: Dictionary = FieldModels.find("DrainLifeMutator.moreDamagePerDamnedStack")
	var cap1: Dictionary = {"build": Build, "store": StatStore.new(), "slot": 0, "node_fields": {"DrainLifeMutator.maxTotalDamageToDamned": 0.21}}
	var cap2: Dictionary = {"build": Build, "store": StatStore.new(), "slot": 0, "node_fields": {"DrainLifeMutator.maxTotalDamageToDamned": 0.42}}
	var cap3: Dictionary = {"build": Build, "store": StatStore.new(), "slot": 0, "node_fields": {"DrainLifeMutator.maxTotalDamageToDamned": 0.63}}
	var none_ctx: Dictionary = {"build": Build, "store": StatStore.new(), "slot": 0}
	Build.set_enemy_ailment(damned, 7)
	_check("#99 1 point: 7 stacks = 0.21", float(EffectModels.value(dl_more, 0.03, cap1)["x"]), 0.21)
	Build.set_enemy_ailment(damned, 10)
	_check("#99 1 point: 10 stacks capped at 0.21", float(EffectModels.value(dl_more, 0.03, cap1)["x"]), 0.21)
	Build.set_enemy_ailment(damned, 5)
	_check("#99 1 point: 5 stacks = 0.15", float(EffectModels.value(dl_more, 0.03, cap1)["x"]), 0.15)
	Build.set_enemy_ailment(damned, 20)
	_check("#99 2 points: 20 stacks capped at 0.42", float(EffectModels.value(dl_more, 0.03, cap2)["x"]), 0.42)
	Build.set_enemy_ailment(damned, 10)
	_check("#99 2 points: 10 stacks = 0.30", float(EffectModels.value(dl_more, 0.03, cap2)["x"]), 0.30)
	Build.set_enemy_ailment(damned, 30)
	_check("#99 3 points: 30 stacks capped at 0.63", float(EffectModels.value(dl_more, 0.03, cap3)["x"]), 0.63)
	Build.set_enemy_ailment(damned, 21)
	_check("#99 3 points: 21 stacks = 0.63", float(EffectModels.value(dl_more, 0.03, cap3)["x"]), 0.63)
	Build.set_enemy_ailment(damned, 20)
	_check("#99 3 points: 20 stacks = 0.60", float(EffectModels.value(dl_more, 0.03, cap3)["x"]), 0.60)
	_check("#99 without the node's fields: no cap (20 stacks = 0.60)", float(EffectModels.value(dl_more, 0.03, none_ctx)["x"]), 0.60)
	Build.set_enemy_ailment(damned, 0)

func _speed_audit() -> void:
	print("--- speed audit")
	var gs := GDScript.new()
	gs.source_code = "extends Node
var items: Dictionary = {}
var player_state: Dictionary = {}
"
	gs.reload()
	var fake: Node = gs.new()
	var s: Dictionary = {"use_speed_inc": 0.0, "use_speed_more": 1.0, "mana_added": 0.0, "mana_inc": 0.0, "flag_keys": [], "components": []}
	var store := StatStore.new()
	store.add(StatMod.make(LE.CAST_SPEED, "added", 1.0, 0, "test"))
	# Teleport: castDuration = 0.75 / (1 × 2 × 1.1) = 0.341 s is below minimumUseDuration 0.35 → 1 / 0.35 uses/s
	var tp: Dictionary = {"name": "Teleport", "speedScaler": LE.CAST_SPEED, "useDuration": 0.75, "useDelay": 0.2, "speedMultiplier": 2.0,
		"hasMinimumUseDuration": 1, "minimumUseDuration": 0.35}
	_check("minimumUseDuration floors the cast time", float(SkillCalc._speed(null, tp, {"store": store, "tags": 0, "ab": tp}, s)["uses"]), 1.0 / 0.35)
	# at speed 0.5 the cast time is 0.75 / 1.1 = 0.68 s, above the floor: the plain formula
	var slow := StatStore.new()
	slow.add(StatMod.make(LE.CAST_SPEED, "added", 0.5, 0, "test"))
	_check("minimumUseDuration below the cast time changes nothing", float(SkillCalc._speed(null, tp, {"store": slow, "tags": 0, "ab": tp}, s)["uses"]), 1.1 / 0.75)
	# a duration below the cast delay: castDuration = delay / speedScale + 0.01 = 0.2 / 1.1 + 0.01
	var short_ab: Dictionary = {"speedScaler": LE.CAST_SPEED, "useDuration": 0.1, "useDelay": 0.2, "speedMultiplier": 1.0}
	_check("cast time below the cast delay becomes delay + 0.01", float(SkillCalc._speed(null, short_ab, {"store": store, "tags": 0, "ab": short_ab}, s)["uses"]),
		1.0 / (0.2 / 1.1 + 0.01))
	# Detonating Arrow converted to a melee attack: DetonatingArrowMutator.getUseDuration returns 0.75 (asset 0.9)
	var da: Dictionary = {"name": "DetonatingArrow", "speedScaler": LE.CAST_SPEED, "useDuration": 0.9, "useDelay": 0.2, "speedMultiplier": 1.0}
	_check("Detonating Arrow: asset duration", float(SkillCalc._speed(null, da, {"store": store, "tags": 0, "ab": da}, s)["uses"]), 1.1 / 0.9)
	s["flag_keys"] = ["Detonating Arrow becomes melee attack"]
	_check("Detonating Arrow as melee: duration 0.75", float(SkillCalc._speed(null, da, {"store": store, "tags": 0, "ab": da}, s)["uses"]), 1.1 / 0.75)
	# Lethal Mirage quick attack: speedScaler 2 (AttackSpeed) and duration 0.75 instead of speedScaler 54 and 1.5
	var lm: Dictionary = {"name": "Lethal Mirage", "speedScaler": 54, "useDuration": 1.5, "useDelay": 0.15, "speedMultiplier": 1.0}
	var atk := StatStore.new()
	atk.add(StatMod.make(LE.ATTACK_SPEED, "added", 1.0, 0, "test"))
	atk.add(StatMod.make(LE.ATTACK_SPEED, "increased", 0.5, 0, "test"))
	s["flag_keys"] = []
	_check("Lethal Mirage: speedScaler 54 ignores the stat", float(SkillCalc._speed(fake, lm, {"store": atk, "tags": LE.MELEE, "ab": lm}, s)["uses"]), 1.1 / 1.5)
	s["flag_keys"] = ["Lethal Mirage - fast attack without invulnerability"]
	_check("Lethal Mirage quick attack: attack speed, duration 0.75", float(SkillCalc._speed(fake, lm, {"store": atk, "tags": LE.MELEE, "ab": lm}, s)["uses"]), 1.5 * 1.1 / 0.75)
	fake.items = {"weapon": {"base": 9, "sub": 1}}  # Broadsword, attack rate 1.16
	_check("Lethal Mirage quick attack: × weapon attack rate", float(SkillCalc._speed(fake, lm, {"store": atk, "tags": LE.MELEE, "ab": lm}, s)["uses"]), 1.5 * 1.16 * 1.1 / 0.75)
	# Radiant Lance placing the Reliquary: the use duration of ability 948 (SummonReliquary 0.6) instead of the spear's 0.9
	var rl: Dictionary = {"name": "RadiantLance", "speedScaler": LE.CAST_SPEED, "useDuration": 0.9, "useDelay": 0.55, "speedMultiplier": 1.0}
	s["flag_keys"] = []
	s["components"] = [{"ability": "SummonReliquary", "count": 1.0, "node": "test"}]
	_check("Radiant Lance with the Reliquary: duration 0.6", float(SkillCalc._speed(null, rl, {"store": store, "tags": 0, "ab": rl}, s)["uses"]),
		1.1 / float(GameData.ability_by_name("SummonReliquary")["useDuration"]))
	# speedScaler 54 skills: ShieldBashMutator.getIncreasedCastSpeed (tree value + block chance × f) and BallistaMutator.mutateUseSpeed
	# (× (1 + Dexterity × f)) are use speed nodes, the AttackSpeed / CastSpeed stat is never asked
	var sb: Dictionary = FieldModels.find("ShieldBashMutator.attackSpeedPerBlockChance")
	_check("Shield Bash node is an increased use speed", 1.0 if str(sb.get("kind")) == "speed" and str(sb.get("speed")) == "increased" else 0.0, 1.0)
	var bal: Dictionary = FieldModels.find("BallistaMutator.placementSpeedPerDexterity")
	_check("Ballista node is a more use speed", 1.0 if str(bal.get("kind")) == "speed" and str(bal.get("speed")) == "more" else 0.0, 1.0)
	# Dive Bomb reducedDelay scales the delay timers of the spawned ability object (DiveBombMutator.Mutate): not a use speed
	_check("Dive Bomb reducedDelay is not a speed model", 1.0 if str(FieldModels.find("DiveBombMutator.reducedDelay").get("kind")) == "flag" else 0.0, 1.0)
	_check("Falconry reducedDelayWithDiveBomb is not a speed model", 1.0 if str(FieldModels.find("FalconryMutator.reducedDelayWithDiveBomb").get("kind")) == "flag" else 0.0, 1.0)
	var sb_ab: Dictionary = {"name": "ShieldBash", "speedScaler": 54, "useDuration": 1.0, "useDelay": 0.2, "speedMultiplier": 1.0}
	s["components"] = []
	s["use_speed_inc"] = 0.35 * 0.6  # f 0.35 per 100% block chance × 60% block
	_check("Shield Bash: S = 1 + block-chance speed", float(SkillCalc._speed(null, sb_ab, {"store": atk, "tags": 0, "ab": sb_ab}, s)["uses"]), 1.21 * 1.1)
	s["use_speed_inc"] = 0.0
	# the same through the real nodes: Shield Bash node 34 (Shieldstorm, 0.5 per point) and Ballista node 18 (Agile Engineering, 0.01)
	var g: StatStore = BuildMods.global_store(Build)["store"]
	g.add(StatMod.make(LE.BLOCK_CHANCE, "added", 0.4, 0, "test block"))
	g.add(StatMod.make(LE.DEXTERITY, "added", 100.0, 0, "test dexterity"))
	Build.set_skill(0, "sb4h")
	_check("Shield Bash without the node: no use speed", float(BuildMods.skill_store(Build, 0, g)["use_speed_inc"]), 0.0)
	Build.skills[0]["tree"][34] = 1
	var block: float = g.query_untagged(LE.BLOCK_CHANCE).value()
	_check("Shield Bash Shieldstorm: use speed + 0.5 × block chance", float(BuildMods.skill_store(Build, 0, g)["use_speed_inc"]), 0.5 * block)
	_flag("Shield Bash Shieldstorm: the block chance is not zero", block >= 0.4)
	Build.set_skill(0, "ba1574")
	var ba_base: float = SkillCalc.uses_per_second(Build, 0, g)
	Build.skills[0]["tree"][18] = 1
	var dex: float = float(EffectModels._attribute(g, LE.DEXTERITY))
	_check("Ballista Agile Engineering: uses × (1 + 0.01 × Dexterity)", SkillCalc.uses_per_second(Build, 0, g), ba_base * (1.0 + 0.01 * dex))
	_flag("Ballista Agile Engineering: Dexterity counted (%s)" % dex, dex >= 100.0)
	Build.set_skill(0, "")
	# weapon attack rate: the main hand base type decides which tag is tested (Bow with a bow, Melee otherwise)
	fake.items = {"weapon": {"base": 23, "sub": 0}}  # Shortbow, attack rate 1.05
	_check("bow in hand: Melee skill gets no weapon rate", SkillCalc._weapon_rate(fake, LE.MELEE), 0.0)
	_check("bow in hand: Bow skill gets the weapon rate", SkillCalc._weapon_rate(fake, LE.BOW), 1.05)
	_check("bow in hand: Melee + Bow skill gets the weapon rate", SkillCalc._weapon_rate(fake, LE.MELEE | LE.BOW), 1.05)
	fake.items = {"weapon": {"base": 9, "sub": 1}}
	_check("sword in hand: Melee skill gets the weapon rate", SkillCalc._weapon_rate(fake, LE.MELEE), 1.16)
	_check("sword in hand: Bow skill gets none", SkillCalc._weapon_rate(fake, LE.BOW), 0.0)
	fake.items = {"weapon": {"base": 9, "sub": 1}, "offhand": {"base": 6, "sub": 0}}  # Broadsword 1.16 + Poignard 1.14
	_check("two weapons: the average rate", SkillCalc._weapon_rate(fake, LE.MELEE), 1.15)
	fake.free()


## Skill-tree conversions that are not plain base-damage swaps: Swipe Storm Claw converts only the use that finds its 3 s cooldown ready
## (SwipeMutator.Mutate / OnMutatorUpdate), Dancing Strikes «Bleed to Poison» changes the tags and the ailment, not the hit damage
## (DancingStrikesMutator.GetConversionType 1), Hammer Throw's Void node converts nothing (HammerThrowMutator.Mutate).
func _skill_conversions() -> void:
	print("--- skill conversions")
	Build.set_enemy("kind", "dummy")
	Build.set_skill(0, "sw43")
	var tree: Dictionary = Build.skills[0]["tree"]
	var plain: Dictionary = SkillCalc.compute(Build, 0)
	_check("Swipe: no conversion rows without nodes", _count_rows(plain, "Conversions and tags", "Physical → Lightning"), 0.0)
	tree[9] = 1  # Storm Claw
	var r: Dictionary = SkillCalc.compute(Build, 0)
	var uses: float = _section_value(r, "Speed and mana", "Uses per second")
	var cycle: float = floorf(3.0 * uses) + 1.0
	_check("Storm Claw: one use in floor(3 s × uses/s) + 1 is converted", _section_value(r, "Conversions and tags", "Physical → Lightning"), 100.0 / cycle, 0.05)
	_flag("Storm Claw: not every use (uses/s %.2f)" % uses, cycle > 1.0)
	_flag("Storm Claw: the skill gets the Lightning tag, Physical stays", _tags_text(r).contains("Lightning") and _tags_text(r).contains("Physical"))
	# a slow rate: every use finds the cooldown over
	var slow: float = _periodic_share(0.2)
	_check("Storm Claw: slower than the cooldown → every use", slow, 1.0)
	_check("Storm Claw: 1 use/s → one in four", _periodic_share(1.0), 0.25)
	tree.erase(9)

	Build.set_skill(0, "dacn33")
	var ds_tree: Dictionary = Build.skills[0]["tree"]
	var ds_plain: Dictionary = SkillCalc.compute(Build, 0)
	var ds_node: int = _node_by_name("dacn33", "Dancing Strikes Bleed To Poison")
	ds_tree[ds_node] = 1
	var ds: Dictionary = SkillCalc.compute(Build, 0)
	_check("Dancing Strikes Bleed to Poison: hit stays Physical (no base-damage conversion row)", _count_rows(ds, "Conversions and tags", "Physical → Poison"), 0.0)
	_flag("Dancing Strikes Bleed to Poison: Poison tag added, Physical kept", _tags_text(ds).contains("Poison") and _tags_text(ds).contains("Physical"))
	_flag("Dancing Strikes Bleed to Poison: Bleed → Poison ailment row", _count_rows(ds, "Conversions and tags", "Ailment: Bleed → Poison") > 0.0)
	_check("Dancing Strikes: same base hit with and without the node", _section_value(ds, "Damage per use (before enemy)", "Total per hit (no crit)"),
		_section_value(ds_plain, "Damage per use (before enemy)", "Total per hit (no crit)"), 0.005)
	ds_tree.erase(ds_node)

	Build.set_skill(0, "ht16aw")
	var ht_tree: Dictionary = Build.skills[0]["tree"]
	var ht_plain: Dictionary = SkillCalc.compute(Build, 0)
	var ht_node: int = _node_by_name("ht16aw", "Hammer Throw Tree Void Damage In Aoe")
	ht_tree[ht_node] = 1
	var ht: Dictionary = SkillCalc.compute(Build, 0)
	_check("Hammer Throw Void zone node: no Physical → Void conversion", _count_rows(ht, "Conversions and tags", "Physical → Void"), 0.0)
	_check("Hammer Throw Void zone node: the hit is unchanged", _section_value(ht, "Damage per use (before enemy)", "Total per hit (no crit)"),
		_section_value(ht_plain, "Damage per use (before enemy)", "Total per hit (no crit)"), 0.005)
	ht_tree.erase(ht_node)


## Hit-damage fixes of the audit (research/11_calc_audit.md #2, #3, #10-#16); hand-computed from the game formulas.
func _hit_damage_fixes() -> void:
	print("--- hit damage fixes")
	Build.set_enemy("kind", "dummy")
	var bleed: int = GameData.enum_value("AilmentID", "Bleed")
	var ignite: int = GameData.enum_value("AilmentID", "Ignite")
	# #10: the more values of one per-stack key fold to Π(1+m)−1 first, then × stacks (Stat.getMoreMultiplier, DamageEffectMoreDamagePerAilmentStack)
	var e10: Dictionary = {"kind": "dummy", "flags": {}, "ailments": {bleed: 10.0, ignite: 1.0}}
	var per: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.1, 0, "a", 7), StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.2, 0, "b", 7)]
	_check("#10 per-stack SP 117: 1 + 10 × (1.1 × 1.2 − 1)", SkillCalc._condition_factor(per, e10, 0, 0, PackedStringArray()), 4.2)
	var per115: Array[StatMod] = [StatMod.make(LE.DAMAGE_PER_AILMENT_STACK, "more", 0.01, 0, "a", bleed), StatMod.make(LE.DAMAGE_PER_AILMENT_STACK, "more", 0.02, 0, "b", bleed)]
	_check("#10 per-stack SP 115: 1 + 10 × (1.01 × 1.02 − 1)", SkillCalc._condition_factor(per115, e10, 0, 0, PackedStringArray()), 1.302)
	var plain: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.1, 0, "a", 5), StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.2, 0, "b", 5)]
	_check("#10 plain condition (ignited): 1.1 × 1.2", SkillCalc._condition_factor(plain, e10, 0, 0, PackedStringArray()), 1.32)
	# #62: a plain condition under uptime p folds its more values first: 1 + p·(Π(1+m)−1), the same fold as the per-stack keys
	var e62: Dictionary = {"kind": "dummy", "flags": {}, "ailments": {ignite: 1.0}, "uptime": {ignite: 0.5}}
	_check("#62 plain condition at 50% uptime: 1 + 0.5 × (1.1 × 1.2 − 1)", SkillCalc._condition_factor(plain, e62, 0, 0, PackedStringArray()), 1.16)
	# #62: different keys (other special) stay separate factors: Ignited 50% -> 1.05, Bleeding absent -> 1.0
	var two_keys: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.1, 0, "a", 5), StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.2, 0, "b", 19)]
	_check("#62 different keys are separate", SkillCalc._condition_factor(two_keys, e62, 0, 0, PackedStringArray()), 1.05)
	# #16: conditions whose handler is a plain ailment / compound / count in GlobalDamageConditionals
	var curse_a: int = 17  # MarkedForDeath, isCurse
	var curse_b: int = 58  # BoneCurse, isCurse
	var brand: int = GameData.enum_value("AilmentID", "BrandOfDeception")
	var slow: int = GameData.enum_value("AilmentID", "Slow")
	var fear: int = GameData.enum_value("AilmentID", "Fear")
	var frostbite: int = GameData.enum_value("AilmentID", "Frostbite")
	var shock: int = GameData.enum_value("AilmentID", "Shock")
	_check("#16 PerCurse: two curse ailments", Enemy.has_condition({"kind": "normal", "ailments": {curse_a: 1.0, curse_b: 1.0}}, 23), 2.0)
	_check("#16 PerCurse: none", Enemy.has_condition({"kind": "normal", "ailments": {}}, 23), 0.0)
	_check("#16 Branded: a brand ailment", Enemy.has_condition({"kind": "normal", "ailments": {brand: 1.0}}, 14), 1.0)
	_check("#16 Branded boss or rare: normal enemy", Enemy.has_condition({"kind": "normal", "ailments": {brand: 1.0}}, 15), 0.0)
	_check("#16 Branded boss or rare: rare enemy", Enemy.has_condition({"kind": "rare", "ailments": {brand: 1.0}}, 15), 1.0)
	_check("#16 PerSlow: 3 stacks, no limit", Enemy.has_condition({"kind": "normal", "ailments": {slow: 3.0}}, 30), 3.0)
	_check("#16 PerFrostbite: capped at 30", Enemy.has_condition({"kind": "normal", "ailments": {frostbite: 40.0}}, 38), 30.0)
	_check("#16 PerShock: 12 stacks", Enemy.has_condition({"kind": "normal", "ailments": {shock: 12.0}}, 39), 12.0)
	_check("#16 Feared or slowed: slowed", Enemy.has_condition({"kind": "normal", "ailments": {slow: 1.0}}, 22), 1.0)
	_check("#16 Feared: fear ailment", Enemy.has_condition({"kind": "normal", "ailments": {fear: 1.0}}, 35), 1.0)
	_check("#16 Boss (not rare) or moving: rare enemy standing", Enemy.has_condition({"kind": "rare", "flags": {}, "ailments": {}}, 24), 0.0)
	_check("#16 Boss (not rare) or moving: rare enemy moving", Enemy.has_condition({"kind": "rare", "flags": {"moving": true}, "ailments": {}}, 24), 1.0)
	_check("#16 Boss (not rare) or moving: boss", Enemy.has_condition({"kind": "boss", "flags": {}, "ailments": {}}, 24), 1.0)
	# #16: boss or rare AND the caster's mana >= 50% (GlobalDamageConditionals case 0x28: CasterAboveManaThreshold(0.5) AND Boss(includeRares))
	_check("#16 cond 40: rare, mana ok", Enemy.has_condition({"kind": "rare", "flags": {}, "ailments": {}}, 40, {}), 1.0)
	_check("#16 cond 40: rare, mana below 50%", Enemy.has_condition({"kind": "rare", "flags": {}, "ailments": {}}, 40, {"low_mana": true}), 0.0)
	_check("#16 cond 40: normal enemy", Enemy.has_condition({"kind": "normal", "flags": {}, "ailments": {}}, 40, {}), 0.0)
	var c40: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.15, 0, "u", 40)]
	_check("#16 cond 40 factor: boss, mana ok", SkillCalc._condition_factor(c40, {"kind": "boss", "flags": {}, "ailments": {}}, 0, 0, PackedStringArray(), {}), 1.15)
	_check("#16 cond 40 factor: boss, low mana", SkillCalc._condition_factor(c40, {"kind": "boss", "flags": {}, "ailments": {}}, 0, 0, PackedStringArray(), {"low_mana": true}), 1.0)
	# #16 cond 43 (PerDistance): min(distance, 10) x folded more, every damage type; the distance is a player input (default 1)
	var e43: Dictionary = {"kind": "normal", "flags": {}, "ailments": {}}
	var c43: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.01, 0, "c43", 43)]
	_check("#16 cond 43: default distance 1", Enemy.has_condition(e43, 43, {}), 1.0)
	_check("#16 cond 43: distance 4", Enemy.has_condition(e43, 43, {"target_distance": 4.0}), 4.0)
	_check("#16 cond 43: capped at 10", Enemy.has_condition(e43, 43, {"target_distance": 25.0}), 10.0)
	_check("#16 cond 43 factor: 1 + 4 x 0.01", SkillCalc._condition_factor(c43, e43, 0, 0, PackedStringArray(), {"target_distance": 4.0}), 1.04)
	_check("#16 cond 43 factor: cap 1 + 10 x 0.01", SkillCalc._condition_factor(c43, e43, 0, 0, PackedStringArray(), {"target_distance": 25.0}), 1.10)
	var c43b: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.01, 0, "a", 43), StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.005, 0, "b", 43)]
	_check("#16 cond 43 folded: 1 + 10 x (1.01 x 1.005 - 1)", SkillCalc._condition_factor(c43b, e43, 0, 0, PackedStringArray(), {"target_distance": 10.0}), 1.1505)
	# #16 cond 37 (ToPetrifiedEnemies): StunnedConditional with StunType.Petrify (Stunned.petrified, +0xE6)
	_check("#16 cond 37: petrified flag", Enemy.has_condition({"kind": "normal", "flags": {"petrified": true}, "ailments": {}}, 37), 1.0)
	_check("#16 cond 37: not petrified", Enemy.has_condition({"kind": "normal", "flags": {}, "ailments": {}}, 37), 0.0)
	_check("#16 cond 0: petrified is stunned", Enemy.has_condition({"kind": "normal", "flags": {"petrified": true}, "ailments": {}}, 0), 1.0)
	# #16 cond 41 / 42: bleed damage per poison stack, poison damage per bleed stack (IsAilmentConditional + GetPerAilmentStackEffect, up to 200)
	var poison41: int = GameData.enum_value("AilmentID", "Poison")
	var bleed41: int = GameData.enum_value("AilmentID", "Bleed")
	var c41: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.01, 0, "c41", 41)]
	var c42: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_DAMAGE, "more", 0.01, 0, "c42", 42)]
	var e41: Dictionary = {"kind": "normal", "flags": {}, "ailments": {poison41: 10.0}}
	_check("#16 cond 41: bleed damage, 10 poison stacks", SkillCalc._condition_factor(c41, e41, 0, 0, PackedStringArray(), {}, 2), 1.10)
	_check("#16 cond 41: hit damage is not affected", SkillCalc._condition_factor(c41, e41, 0, 0, PackedStringArray(), {}, 0), 1.0)
	_check("#16 cond 41: poison damage is not affected", SkillCalc._condition_factor(c41, e41, 0, 0, PackedStringArray(), {}, 7), 1.0)
	_check("#16 cond 41: capped at 200 stacks", SkillCalc._condition_factor(c41, {"kind": "normal", "flags": {}, "ailments": {poison41: 250.0}}, 0, 0, PackedStringArray(), {}, 2), 3.0)
	_check("#16 cond 42: poison damage, 5 bleed stacks", SkillCalc._condition_factor(c42, {"kind": "normal", "flags": {}, "ailments": {bleed41: 5.0}}, 0, 0, PackedStringArray(), {}, 7), 1.05)
	# #57 Puncture: a large hit absorbs bleeds only with Every Third Bigger, once per third use
	_check("#57 Puncture: absorb + third bigger, 3 uses/s -> 1 wipe/s", EnemyAilments.consume_events(Build, EnemyAilments.PUNCTURE_ABSORB_FLAG, {"uses": 3.0, "flag_keys": [EnemyAilments.PUNCTURE_ABSORB_FLAG, EnemyAilments.PUNCTURE_THIRD_FLAG]}), 1.0)
	_check("#57 Puncture: absorb without Every Third Bigger -> no wipe", EnemyAilments.consume_events(Build, EnemyAilments.PUNCTURE_ABSORB_FLAG, {"uses": 3.0, "flag_keys": [EnemyAilments.PUNCTURE_ABSORB_FLAG]}), 0.0)
	_check("#57 other consumer unchanged: once per use", EnemyAilments.consume_events(Build, "Hits absorb poison stacks from target", {"uses": 2.5, "flag_keys": []}), 2.5)
	# #65 zone level: the armour formula reads the zone level (ZoneInfoManager.ZoneLevel), 0 = the enemy level
	_check("#65 zone level defaults to the enemy level", float(Enemy.zone_level({"level": 75})), 75.0)
	_check("#65 explicit zone level wins", float(Enemy.zone_level({"level": 75, "area_level": 100})), 100.0)
	_check("#65 armour 3000 at zone 100 (monster 75)", Enemy.armour_mitigation(3000, Enemy.zone_level({"level": 75, "area_level": 100}), false), 0.48441, 0.0001)
	_check("#65 armour 3000 at zone 75 (existing vector)", Enemy.armour_mitigation(3000, Enemy.zone_level({"level": 75}), false), 0.53613, 0.0001)
	# #11: Penetration is not filtered by the Minion mask (DamageStats.buildDamageStats), Damage is
	var minion_mods: Array[StatMod] = [StatMod.make(LE.PENETRATION, "added", 0.1, LE.FIRE, "pen"), StatMod.make(LE.DAMAGE, "increased", 0.5, 0, "player inc")]
	var ds11: Dictionary = SkillCalc._build_damage(_hit_ctx(minion_mods, LE.HIT | LE.SPELL | LE.MINION, LE.MINION))
	_check("#11 penetration without the Minion tag applies to a minion ability", float(ds11["pen"][1]), 0.1)
	_check("#11 Damage without the Minion tag does not", float(ds11["final"][0]), 100.0)
	# #12: conditional crit chance / multiplier (SP 132 / 133) and penetration (SP 131) against a bleeding / chilled enemy
	var chill: int = GameData.enum_value("AilmentID", "Chill")
	var cm: Array[StatMod] = [
		StatMod.make(LE.CONDITIONAL_CRIT_CHANCE, "more", 0.5, 0, "crit chance", 19),
		StatMod.make(LE.CONDITIONAL_CRIT_MULTI, "added", 0.55, LE.MELEE, "crit multi", 19),
		StatMod.make(LE.CONDITIONAL_CRIT_MULTI, "added", 0.25, LE.BOW, "bow crit multi", 19),
		StatMod.make(LE.CONDITIONAL_PEN, "added", 0.1, LE.COLD, "cold pen", 32)]
	Build.enemy["ailments"] = {}
	var speed: Dictionary = {"uses": 1.0}
	SkillCalc._vs_enemy(Build, _hit_ctx(cm, LE.HIT | LE.MELEE), SkillCalc._build_damage(_hit_ctx(cm, LE.HIT | LE.MELEE)), speed, [])
	_check("#12 no bleed: 1 + 0.05 × (2 − 1)", float(speed["enemy_crit"]), 1.05)
	Build.enemy["ailments"] = {bleed: 1.0}
	speed = {"uses": 1.0}
	SkillCalc._vs_enemy(Build, _hit_ctx(cm, LE.HIT | LE.MELEE), SkillCalc._build_damage(_hit_ctx(cm, LE.HIT | LE.MELEE)), speed, [])
	_check("#12 bleeding: crit 5% × 1.5, multiplier 2 + 0.55 (Melee only): 1 + 0.075 × 1.55", float(speed["enemy_crit"]), 1.11625)
	Build.enemy["ailments"] = {chill: 1.0}
	speed = {"uses": 1.0}
	var cold_ctx: Dictionary = _hit_ctx(cm, LE.HIT | LE.MELEE)
	var cold_dmg: Array[float] = [0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 0.0]
	cold_ctx["dmg"] = cold_dmg
	cold_ctx["base_before"] = cold_dmg
	cold_ctx["type_bits"] = LE.COLD
	SkillCalc._vs_enemy(Build, cold_ctx, SkillCalc._build_damage(cold_ctx), speed, [])
	_check("#12 chilled: +10% cold penetration (100 × (1 + 0.1) at 0 resistance)", float(speed["enemy_dps"]) / float(speed["enemy_crit"]), 110.0)
	# #12: a conditional penetration stat needs its tags above the type byte (DamageConditionalEffect.apply, Bow 0x800)
	var pen_mods: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_PEN, "added", 0.1, LE.COLD | LE.BOW, "bow cold pen", 32)]
	var pen_enemy: Dictionary = {"kind": "dummy", "flags": {"frozen": true}, "ailments": {}}
	_check("#12 conditional pen needs its tags: Melee hit", float(SkillCalc._conditional_hit_stats({"src": LE.HIT | LE.MELEE, "mods": pen_mods}, pen_enemy)["pen"][2]), 0.0)
	_check("#12 conditional pen needs its tags: Bow hit", float(SkillCalc._conditional_hit_stats({"src": LE.HIT | LE.BOW, "mods": pen_mods}, pen_enemy)["pen"][2]), 0.1)
	# #59: crit chance on condition 40 (boss or rare while caster mana >= 50%); the Mana below 50% toggle must reach _conditional_hit_stats
	var c40b: Array[StatMod] = [StatMod.make(LE.CONDITIONAL_CRIT_CHANCE, "more", 0.5, 0, "cc40b", 40)]
	var e40: Dictionary = {"kind": "rare", "flags": {}, "ailments": {}}
	_check("#59 cond 40 crit chance, mana ok", float(SkillCalc._conditional_hit_stats({"src": LE.HIT, "mods": c40b}, e40, {})["cc_more"]), 1.5)
	_check("#59 cond 40 crit chance, mana below 50%", float(SkillCalc._conditional_hit_stats({"src": LE.HIT, "mods": c40b}, e40, {"low_mana": true})["cc_more"]), 1.0)
	Build.enemy["ailments"] = {}
	# #12: super crit (Truesight Glass pp 590): Roll(min(crit chance − 1, 0.5)) adds 3.0 to the crit multiplier
	var truesight_ctx: Dictionary = _hit_ctx([], LE.HIT | LE.MELEE, 0, 1.25, 2.0)
	speed = {"uses": 1.0}
	SkillCalc._vs_enemy(Build, truesight_ctx, SkillCalc._build_damage(truesight_ctx), speed, [])
	_check("#12 crit chance 125% without Truesight Glass: 1 + 1 × (2 − 1)", float(speed["enemy_crit"]), 2.0)
	Build.set_item("amulet", {"unique": 439, "base": 20, "sub": 8, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255, 255, 255, 255, 255, 255, 255, 255]})
	speed = {"uses": 1.0}
	SkillCalc._vs_enemy(Build, truesight_ctx, SkillCalc._build_damage(truesight_ctx), speed, [])
	_check("#12 Truesight Glass, crit chance 125%: super crit 25%, multiplier 2 + 0.25 × 3", float(speed["enemy_crit"]), 2.75)
	Build.clear_item("amulet")
	# #13: Healing Hands' code damage (40 Fire) has ADE 0.05 × 40 = 2.0 (setBaseDamage calcADE, isWeapon false)
	var hh_comps: Array[Dictionary] = []
	var hh_notes: Array[String] = []
	SkillComponents._add_code_damage(hh_comps, Build, 0, {}, "HealingHands", GameData.get_ability("hh7pa3"), hh_notes)
	_check("#13 Healing Hands code damage: ADE", float(hh_comps[0]["base"]["addedDamageScaling"]) if not hh_comps.is_empty() else -1.0, 2.0)
	# #2: Stats.GetStatValue adds the health tags to the attack / cast speed query
	var hs := StatStore.new()
	hs.add(StatMod.make(LE.CAST_SPEED, "added", 1.0, 0, "base"))
	hs.add(StatMod.make(LE.CAST_SPEED, "increased", 0.4, 0, "inc"))
	hs.add(StatMod.make(LE.CAST_SPEED, "increased", 0.3, LE.LOW_LIFE, "low life"))
	var hab: Dictionary = {"speedScaler": LE.CAST_SPEED, "useDuration": 1.0, "speedMultiplier": 1.0}
	var hctx: Dictionary = {"store": hs, "tags": 0, "ab": hab}
	var hspeed: Dictionary = {"use_speed_inc": 0.0, "use_speed_more": 1.0, "mana_added": 0.0, "mana_inc": 0.0}
	_check("#2 full health: no low-life speed", float(SkillCalc._speed(Build, hab, hctx, hspeed)["uses"]), 1.4 * 1.1)
	Build.player_state["health"] = "low"
	_check("#2 low health: 1 + 0.4 + 0.3", float(SkillCalc._speed(Build, hab, hctx, hspeed)["uses"]), 1.7 * 1.1)
	Build.player_state["health"] = "full"
	# #2: the other ability queries (cooldown, channel cost, leech) take the health tags of ctx["src"] too
	_check("#2 query tags: ability tags + the health tag", float(SkillCalc._query_tags({"tags": LE.SPELL, "src": LE.HIT | LE.SPELL | LE.LOW_LIFE})), float(LE.SPELL | LE.LOW_LIFE))
	# #3: individual buff stacks multiply their more values ((1 + m·effect)^stacks), grouped ones are stacks × base without the effect on you
	var bs := StatStore.new()
	bs.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 0.5, 0, "effect", 94))
	bs.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 1.0, 0, "effect", 35))
	var saved_buffs: Variant = Build.player_state.get("buffs", {})
	Build.player_state["buffs"] = {94: 4, 35: 5}
	BuildMods._add_player_ailments(Build, bs)
	Build.player_state["buffs"] = saved_buffs
	_check("#3 Totem Armor ×4 with +50% effect: (1 + 0.15 × 1.5)^4", bs.query(LE.DAMAGE, 0).more, pow(1.225, 4.0), 0.001)
	_check("#3 Totem Armor ×4: armour 0.8 × 1.5 × 4", bs.query(LE.ARMOUR, 0).increased, 4.8)
	_check("#3 Swiftness ×5 (grouped): 5 × 1%, no effect on you", bs.query(LE.MOVESPEED, 0).increased, 0.05)
	var bs2 := StatStore.new()
	Build.player_state["buffs"] = {94: 4}
	BuildMods._add_player_ailments(Build, bs2)
	Build.player_state["buffs"] = saved_buffs
	_check("#3 Totem Armor ×4 without effect: 1.15^4", bs2.query(LE.DAMAGE, 0).more, pow(1.15, 4.0), 0.001)
	# #14: Sacrifice «added fire damage» is an AddedStat Fire|Spell (ADE 4) next to the Fire tag
	Build.set_skill(0, "sf31rc")
	var sac_tree: Dictionary = Build.skills[0]["tree"]
	var sac_plain: Dictionary = SkillCalc.compute(Build, 0)
	var sac_node: int = _node_by_name("sf31rc", "Sacrifice Tree Added Fire Damage")
	sac_tree[sac_node] = 1
	var sac: Dictionary = SkillCalc.compute(Build, 0)
	_check("#14 Sacrifice without the node: no Fire damage", _count_rows(sac_plain, "Damage per use (before enemy)", "Fire"), 0.0)
	_flag("#14 Sacrifice with the node: Fire damage = 4 × 6 × (1 + inc) × more", _section_value(sac, "Damage per use (before enemy)", "Fire") >= 24.0)
	sac_tree.erase(sac_node)
	# #15: Shurikens' conversion removes the Physical tag only at 100%
	Build.set_skill(0, "srk21")
	var srk_tree: Dictionary = Build.skills[0]["tree"]
	var srk_node: int = _node_by_name("srk21", "Shurikens Added Lightning Damage")
	srk_tree[srk_node] = 2
	var srk_half: String = _tags_text(SkillCalc.compute(Build, 0))
	_flag("#15 Shurikens 50%: Lightning added, Physical kept", srk_half.contains("Lightning") and srk_half.contains("Physical"))
	srk_tree[srk_node] = 4
	_flag("#15 Shurikens 100%: Physical removed", not _tags_text(SkillCalc.compute(Build, 0)).contains("Physical"))
	srk_tree.erase(srk_node)
	# #15: Fireball's conversion at 50% adds Lightning and keeps Fire (FireballMutator.getTags: 0.05 < f <= 0.95 -> tags | Lightning)
	Build.set_skill(0, "fi9")
	var fb15_tree: Dictionary = Build.skills[0]["tree"]
	var fb15_node: int = _node_by_name("fi9", "Fireball Added Lightning Damage")
	fb15_tree[fb15_node] = 1
	var fb15_tags: String = _tags_text(SkillCalc.compute(Build, 0))
	_flag("#15 Fireball 50%: Lightning added, Fire kept", fb15_tags.contains("Lightning") and fb15_tags.contains("Fire"))
	fb15_tree.erase(fb15_node)
	Build.set_skill(0, "")


## Minimal context of SkillCalc._build_damage / _vs_enemy: 100 Physical, ADE 1.
func _hit_ctx(mods: Array[StatMod], src: int, minion: int = 0, cc: float = 0.05, cm: float = 2.0) -> Dictionary:
	var dmg: Array[float] = [100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	return {"dmg": dmg, "base_before": dmg, "conversion_lines": [[], [], [], [], [], [], []], "ade": 1.0, "src": src, "mods": mods,
		"minion": minion, "hit": true, "type_bits": LE.PHYSICAL, "base": {"critChance": cc, "critMultiplier": cm, "critType": 0}}


func _periodic_share(uses: float) -> float:
	return 1.0 / float(SkillCalc._periodic_cycle(3.0, uses))


func _tags_text(r: Dictionary) -> String:
	for s: Dictionary in r["sections"]:
		if s["title"] == "Conversions and tags":
			for row: Dictionary in s["rows"]:
				if row["label"] == "Resulting skill tags":
					return str(row["text"])
	return ""


## Id of the node with this internal name in a skill tree.
func _node_by_name(tree_id: String, node_name: String) -> int:
	for node: Dictionary in GameData.get_skill_tree(tree_id).get("nodes", []):
		if str(node.get("name", "")) == node_name:
			return int(node.get("id", -1))
	return -1


## Review fixes of the modifier collection (docs/ENGINE.md §5): omen idol affix effect, skill-scoped passives of skills that
## are not on the bar, attributes from post-phase models, unknown ailments, model signatures, Haste / Frenzy counted once,
## extraTag of automatic node stats, attribute sums with tags, re-entrant ConfigRelevance.
func _review_mod_fixes() -> void:
	print("--- review fixes: modifier collection")
	# omen idols: affixEffectModifier = ItemList.omenIdolAffixEffectModifier (0), not the base's value (07a §6)
	var omen_sub: int = -1
	for st: Dictionary in GameData.item_base(29).get("subItems", []):
		if str(st.get("affixEffectiveness", "")) == "OmenIdol":
			omen_sub = int(st["subTypeID"])
			break
	var idol_affixes: Array = GameData.affixes_for_type(29)
	var affix: Dictionary = {}
	for a: Dictionary in idol_affixes:
		if float(a.get("standardAffixEffectModifier", 0.0)) != 0.0 and not (a.get("tiers", []) as Array).is_empty():
			affix = a
			break
	_flag("omen idol: a subtype and an affix with a standard modifier exist", omen_sub >= 0 and not affix.is_empty())
	if omen_sub >= 0 and not affix.is_empty():
		var tier: Dictionary = affix["tiers"][0]
		var prop: Dictionary = affix["properties"][0]
		var lo: float = float(tier["rolls"][0][0])
		var hi: float = float(tier["rolls"][0][1])
		var std: float = float(affix["standardAffixEffectModifier"])
		var item: Dictionary = {"base": 29, "sub": omen_sub, "affixes": [{"id": int(affix["affixId"]), "tier": 1, "roll": 255}]}
		var mods: Array[StatMod] = ItemMods.item_mods("helmet", item)
		var want: float = AffixMath.roll_value(lo, hi, str(prop.get("rounding", "Integer")), str(prop.get("modType", "ADDED")), 255,
			AffixMath.effect_modifier(0.0, std))
		var got: float = mods[0].added + mods[0].increased + (mods[0].more[0] if not mods[0].more.is_empty() else 0.0)
		_check("omen idol affix uses the omen modifier (0)", got, want)
		var plain_sub: int = int(GameData.item_base(29)["subItems"][0]["subTypeID"])
		var plain: Array[StatMod] = ItemMods.item_mods("helmet", {"base": 29, "sub": plain_sub, "affixes": [{"id": int(affix["affixId"]), "tier": 1, "roll": 255}]})
		var plain_want: float = AffixMath.roll_value(lo, hi, str(prop.get("rounding", "Integer")), str(prop.get("modType", "ADDED")), 255,
			AffixMath.effect_modifier(float(GameData.item_base(29)["affixEffectModifier"]), std))
		var plain_got: float = plain[0].added + plain[0].increased + (plain[0].more[0] if not plain[0].more.is_empty() else 0.0)
		_check("non-omen idol affix keeps the base modifier", plain_got, plain_want)

	# a skill-scoped field of a skill that is not on the bar does not reach the character
	var weapon_model: Dictionary = FieldModels.find("SummonWeaponMutator.statListFromPassiveTree")
	_flag("SummonWeaponMutator.statListFromPassiveTree is a skill-scoped model", str(weapon_model.get("scope", "")) == "skill")
	_check("skill-scoped passive of a skill off the bar: no character scope",
		1.0 if BuildMods._passive_scope(weapon_model, "SummonWeaponMutator.statListFromPassiveTree") == "" else 0.0, 1.0)
	var global_model: Dictionary = FieldModels.find("CharacterMutator.adaptiveSpellDamageFromMaxMana")
	_check("character-scoped passive keeps the global scope",
		1.0 if BuildMods._passive_scope(global_model, "CharacterMutator.adaptiveSpellDamageFromMaxMana") == "global" else 0.0, 1.0)

	# attributes given by models applied after the per-point conversion are converted by their delta
	var store_a := StatStore.new()
	store_a.add(StatMod.make(LE.STRENGTH, "added", 20.0, 0, "first"))
	var notes: Array[String] = []
	var done: Dictionary = BuildMods._add_attributes(Build, store_a, notes)
	var size_before: int = store_a.mods.size()
	BuildMods._add_attributes(Build, store_a, notes, done)
	_check("attribute delta: no change, no new mods", float(store_a.mods.size()), float(size_before))
	store_a.add(StatMod.make(LE.STRENGTH, "added", 10.0, 0, "late (post phase / buff)"))
	BuildMods._add_attributes(Build, store_a, notes, done)
	var store_b := StatStore.new()
	store_b.add(StatMod.make(LE.STRENGTH, "added", 30.0, 0, "all at once"))
	BuildMods._add_attributes(Build, store_b, notes)
	var equal: bool = true
	for per_point: Dictionary in GameData.attributes[0].get("perPoint", []):
		var prop_id: int = int(per_point.get("property", 0))
		var qa: StatQuery = store_a.query_untagged(prop_id)
		var qb: StatQuery = store_b.query_untagged(prop_id)
		equal = equal and is_equal_approx(qa.added, qb.added) and is_equal_approx(qa.increased, qb.increased) and is_equal_approx(qa.more, qb.more)
	_flag("attribute delta: 20 + 10 Strength converts like 30 at once", equal and GameData.attributes[0].get("perPoint", []).size() > 0)

	# unknown ailments / numeric special ids
	var ail_stat: Dictionary = {"kind": "added", "property": "AilmentChance", "added": {"per_point": 1, "flat": 0}}
	ail_stat["specialTag"] = "NoSuchAilment"
	_check("unknown specialTag name: the mod is dropped", 1.0 if BuildMods.stat_from_effect(ail_stat, 1, "t") == null else 0.0, 1.0)
	ail_stat["specialTag"] = "Poison"
	var poison: StatMod = BuildMods.stat_from_effect(ail_stat, 2, "t")
	_check("specialTag by name: AilmentID", float(poison.special), float(GameData.enum_value("AilmentID", "Poison")))
	ail_stat["specialTag"] = "3"
	_check("numeric specialTag text: special id as is", float(BuildMods.stat_from_effect(ail_stat, 1, "t").special), 3.0)
	var unknown_model: Dictionary = {"stat": "AilmentChance", "mod": "added", "ailment": "NoSuchAilment"}
	_check("model with an unknown ailment: no mod", 1.0 if EffectModels.make_mod(unknown_model, 1.0, {"build": Build, "store": StatStore.new()}, "t") == null else 0.0, 1.0)

	# model signatures keep apart models that differ in text / count / chance
	var sig_a: String = BuildMods._model_signature({"kind": "flag", "text": "A"})
	_check("signature: flags with different texts differ", 1.0 if sig_a != BuildMods._model_signature({"kind": "flag", "text": "B"}) else 0.0, 1.0)
	_check("signature: components with different counts differ", 1.0 if BuildMods._model_signature({"kind": "component", "ability": "X", "count": 1}) != BuildMods._model_signature({"kind": "component", "ability": "X", "count": 2}) else 0.0, 1.0)
	_check("signature: the same effect in two mutators is equal (scope and note do not count)",
		1.0 if BuildMods._model_signature({"kind": "stat", "stat": "Damage", "scope": "skill", "note": "a"}) == BuildMods._model_signature({"kind": "stat", "stat": "Damage", "scope": "minion", "note": "b"}) else 0.0, 1.0)

	# Haste on you: the flag and the "Buffs on me" stack of the same ailment count once
	var ail_only_flag := StatStore.new()
	var ail_both := StatStore.new()
	var prev_state: Dictionary = Build.player_state.duplicate(true)
	Build.set_player_state("haste", true)
	BuildMods._add_player_ailments(Build, ail_only_flag)
	Build.set_player_state("buffs", {33: 1})
	BuildMods._add_player_ailments(Build, ail_both)
	var move_flag: float = ail_only_flag.query_untagged(LE.MOVESPEED).increased
	_flag("Haste flag adds movement speed", move_flag > 0.0)
	_check("Haste flag + stack: counted once", ail_both.query_untagged(LE.MOVESPEED).increased, move_flag)
	Build.player_state = prev_state

	# expressions that do not run count as 0 (and warn once)
	_check("failing node expression: 0", BuildMods.eval_value({"expr": "NoSuchGameClass.Func(p)"}, 3), 0.0)
	_check("failing node expression: still 0 afterwards", BuildMods.eval_value({"expr": "NoSuchGameClass.Func(p)"}, 3), 0.0)

	# extraTag of automatic node stats pins the stat to the named ability
	_check("ability index of a tag: entanglingRoots", float(BuildMods.ability_index_of("entanglingRoots")), 71.0)
	_check("ability index of a tag: none", float(BuildMods.ability_index_of("none")), 0.0)
	_check("ability index of a tag: unknown", float(BuildMods.ability_index_of("noSuchAbility")), -1.0)
	var auto: StatMod = BuildMods._automatic_stat({"property": "Damage", "modType": "MORE", "value": 0.06, "scaling": "PerPoint",
		"specialTag": 0, "extraTag": "entanglingRoots"}, 2, "t")
	_check("automatic stat with extraTag: mod.extra = ability index", float(auto.extra), 71.0)
	_check("automatic stat with extraTag: value", auto.more[0], 0.12)
	_check("automatic stat with an unknown extraTag: dropped", 1.0 if BuildMods._automatic_stat({"property": "Damage", "modType": "MORE",
		"value": 0.06, "scaling": "PerPoint", "extraTag": "noSuchAbility"}, 2, "t") == null else 0.0, 1.0)

	# attribute values of effect models ignore tags like the per-point conversion
	var tagged := StatStore.new()
	tagged.add(StatMod.make(LE.STRENGTH, "added", 12.0, LE.FIRE, "tagged"))
	tagged.add(StatMod.make(LE.ALL_ATTRIBUTES, "added", 3.0, 0, "all"))
	_check("EffectModels attr: tagged Strength counts", EffectModels.source("attr:str", {"build": Build, "store": tagged}), 15.0)
	_check("EffectModels attr = BuildMods.attribute_value", EffectModels.source("attr:str", {"build": Build, "store": tagged}), float(BuildMods.attribute_value(tagged, LE.STRENGTH)))

	# affix trigger chance: added, increased or more
	var inc_mod: StatMod = StatMod.make(LE.PLAYER_PROPERTY, "increased", 0.05, 0, "t")
	_check("affix trigger value from an increased mod", UniqueEffects._affix_value(inc_mod), 0.05)

	# float32 arithmetic of the affix roll
	_check("AffixMath.f32 rounds to float32", AffixMath.f32(0.1), 0.10000000149011612, 1e-12)

	# ConfigRelevance.compute keeps the recording state of an outer call
	ConfigRelevance._recording = true
	ConfigRelevance._rec = {"marker": 1}
	ConfigRelevance.compute(Build)
	_flag("ConfigRelevance.compute restores the outer recording state", ConfigRelevance._recording and ConfigRelevance._rec.has("marker"))
	ConfigRelevance._recording = false
	ConfigRelevance._rec = {}


## SkillCalc.compute without details (computed for real, not derived from a cached result) equals the result with
## details except the breakdowns; the cached results equal fresh ones.
## Ailment fixes (research/11_calc_audit.md #45, #46, #49, #50a, #51, #52). Vectors are hand-computed from the game formulas.
func _ailment_fixes() -> void:
	print("--- ailment fixes")
	# #45: share paid to a capped stack that is evicted `life` s after its creation (global ticks every 0.5 s, no early tick)
	_check("#45 life 0.25 s of 3 s: ln(3.5/3.25)", AilmentCalc.displaced_share(0.25, 3.0), 0.074108, 0.00001)
	_check("#45 life 0.5 s of 3 s: ln(3.5/3)", AilmentCalc.displaced_share(0.5, 3.0), 0.1541507, 0.00001)
	_check("#45 life 2 s of 3 s: 4 ln(3.5/3)", AilmentCalc.displaced_share(2.0, 3.0), 0.6166027, 0.00001)
	_check("#45 life 1.3 s of 4 s: 3 ln(4.5/4.2) + 2 ln(4.2/4)", AilmentCalc.displaced_share(1.3, 4.0), 0.3045591, 0.00001)
	_check("#45 life 0.75 s of 5 s: 2 ln(5.5/5.25) + ln(5.25/5)", AilmentCalc.displaced_share(0.75, 5.0), 0.1418302, 0.00001)
	_check("#45 life 0.1 s of 0.5 s (Pestilence): ln(1/0.9)", AilmentCalc.displaced_share(0.1, 0.5), 0.1053605, 0.00001)
	# #46: a chance above 100% applies a max-1 ailment once per hit; an ailment with more stacks gets the chance as expected stacks
	var blind46: int = GameData.enum_value("AilmentID", "Blind")
	var slow46: int = GameData.enum_value("AilmentID", "Slow")
	var notes46: Array[String] = []
	var mods46: Array[StatMod] = [StatMod.make(LE.AILMENT_CHANCE, "added", 1.5, 0, "t", blind46), StatMod.make(LE.AILMENT_CHANCE, "added", 1.5, 0, "t", slow46)]
	var ctx46: Dictionary = {"ab": {}, "base": {}, "tags": 0, "mods": mods46, "store": StatStore.new()}
	var r46: Dictionary = AilmentCalc.compute(Build, ctx46, 2.0, notes46)
	var rate46: Dictionary = {}
	for a46: Dictionary in r46["applied"]:
		rate46[int(a46["id"])] = float(a46["rate"])
	_check("#46 Blind (max 1), chance 150%, 2 hits/s: 2 applications/s", float(rate46.get(blind46, -1.0)), 2.0)
	_check("#46 Slow (max 3), chance 150%, 2 hits/s: 3 stacks/s", float(rate46.get(slow46, -1.0)), 3.0)
	# #49: PlayerProperty 521 - more Witchfire damage = v × increased Damage with exactly the Curse tag (specialTag and extraTag 0)
	var curse_store := StatStore.new()
	curse_store.add(StatMod.make(LE.DAMAGE, "increased", 0.30, LE.CURSE, "exact"))
	curse_store.add(StatMod.make(LE.DAMAGE, "increased", 0.50, LE.CURSE | LE.SPELL, "more tags"))
	curse_store.add(StatMod.make(LE.DAMAGE, "increased", 0.20, 0, "generic"))
	curse_store.add(StatMod.make(LE.DAMAGE, "increased", 0.90, LE.CURSE, "one ability", 0, 924))
	var ctx49: Dictionary = {"build": Build, "store": curse_store}
	_check("#49 increased Damage with exactly the Curse tag", EffectModels.source("increased_exact:Damage:16777216", ctx49, {}), 0.30)
	var mod49: StatMod = EffectModels.make_mod({"kind": "stat", "stat": "Damage", "mod": "more", "ailment_only": "Witchfire",
		"per": "increased_exact:Damage:16777216"}, 2.0, ctx49, "unique")
	_check("#49 more Witchfire damage = 2 x 0.30", mod49.more[0], 0.6)
	_flag("#49 the mod belongs to the Witchfire instance", mod49.ailment_only == GameData.enum_value("AilmentID", "Witchfire"))
	# #50a / #52: Stats.GetAilmentChance: stats with an extraTag are not counted; the query tags must contain the stat's tags
	var slow50: int = GameData.enum_value("AilmentID", "Slow")
	var shock50: int = GameData.enum_value("AilmentID", "Shock")
	var chance_mods: Array[StatMod] = [
		StatMod.make(LE.AILMENT_CHANCE, "added", 0.30, LE.VOID, "slow with void", slow50),
		StatMod.make(LE.AILMENT_CHANCE, "added", 0.10, 0, "any ailment"),
		StatMod.make(LE.AILMENT_CHANCE, "increased", 0.50, 0, "inc"),
		StatMod.make(LE.AILMENT_CHANCE, "added", 0.90, 0, "one ability", slow50, 924)]
	_check("#50 Slow chance with Void skills: (0.3 + 0.1) x 1.5, ability-scoped stat ignored", AilmentCalc.stat_chance(chance_mods, slow50, LE.VOID), 0.6)
	_check("#50 Shock chance: only the stat of any ailment", AilmentCalc.stat_chance(chance_mods, shock50, 0), 0.15)
	_check("#50 Slow chance without the Void tag: the Void stat does not count", AilmentCalc.stat_chance(chance_mods, slow50, 0), 0.15)
	var speed52 := StatStore.new()
	speed52.add(StatMod.make(LE.ATTACK_SPEED, "increased", 0.30, 0, "all attacks"))
	speed52.add(StatMod.make(LE.ATTACK_SPEED, "increased", 0.20, LE.MELEE, "melee"))
	speed52.add(StatMod.make(LE.CAST_SPEED, "increased", 0.40, 0, "cast"))
	_check("#52 lowest of melee 50% / throwing 30% / cast 40%", AilmentCalc.lowest_speed_increase(speed52, 0), 0.30)
	var slow52 := StatStore.new()
	slow52.add(StatMod.make(LE.ATTACK_SPEED, "increased", -0.10, 0, "slowed attacks"))
	_check("#52 never below 0", AilmentCalc.lowest_speed_increase(slow52, 0), 0.0)
	# #51: Individual buff ailments: each stack is a Stat × m, m = (1 + boss penalty) × (1 + ailment effect); the more values of the stacks multiply
	var chill51: int = GameData.enum_value("AilmentID", "Chill")
	var shred51: int = GameData.ailment_id_by_name("ArmourShred")
	var e51: Dictionary = {"kind": "dummy", "res": [0, 0, 0, 0, 0, 0, 0], "armour": 0, "flags": {}, "ailments": {chill51: 3.0, shred51: 2.0}}
	var s51: StatStore = Enemy.store(e51)
	_check("#51 Chill x3: attack speed (1 - 0.12)^3", s51.query(LE.ATTACK_SPEED).more, 0.681472, 0.00001)
	_check("#51 Armour Shred x2 without effect: 200 negative armour", s51.query(LE.NEG_ARMOUR).added, 200.0)
	e51["ailment_effect"] = {chill51: 0.5, shred51: 0.5}
	s51 = Enemy.store(e51)
	_check("#51 Chill x3 with +50% ailment effect: (1 - 0.12 x 1.5)^3", s51.query(LE.ATTACK_SPEED).more, 0.551368, 0.00001)
	_check("#51 Armour Shred x2 with +50% effect: 100 x 2 x 1.5", s51.query(LE.NEG_ARMOUR).added, 300.0)
	var boss51: Dictionary = {"kind": "boss", "res": [0, 0, 0, 0, 0, 0, 0], "armour": 0, "flags": {}, "ailments": {chill51: 3.0}}
	_check("#51 Chill x3 on a boss (moreBuffEffectAgainstBosses -50%): (1 - 0.06)^3", Enemy.store(boss51).query(LE.ATTACK_SPEED).more, 0.830584, 0.00001)
	boss51["ailment_effect"] = {chill51: 0.5}
	_check("#51 Chill x3 on a boss with +50% effect: (1 - 0.12 x 0.5 x 1.5)^3", Enemy.store(boss51).query(LE.ATTACK_SPEED).more, 0.753571, 0.00001)
	var eff51: Dictionary = EnemyAilments.effective({"kind": "dummy", "ailments": {}}, {shred51: {"stacks": 2.0, "uptime": 1.0, "effect": 0.25}})
	_check("#51 effective() keeps the average effect", float(eff51["ailment_effect"][shred51]), 0.25)


## Buff group (SerpentStrike venom, buffs on me, stack caps, presence conditions, aura frequency, sacrifice, symbols of hope).
func _buff_group_fixes() -> void:
	print("--- buff group fixes")
	var poison: int = GameData.enum_value("AilmentID", "Poison")
	var ctx: Dictionary = {"build": Build, "store": StatStore.new(), "slot": -1, "item_slot": ""}
	var flags_saved: Dictionary = Build.enemy.get("flags", {}).duplicate()
	var ail_saved: Dictionary = Build.enemy.get("ailments", {}).duplicate()
	var had_uptime: bool = Build.enemy.has("uptime")
	var uptime_saved: Dictionary = Build.enemy.get("uptime", {}).duplicate()
	# #95: Serpent Venom poison bonus, only while the enemy is not on high health (the Inverter of HighHealthConditional)
	var m95: Dictionary = FieldModels.find("SerpentStrikeMutator.moreSerpentVenomDamagePerPoison")
	Build.enemy["flags"] = {"high_health": true, "full_health": true}
	_flag("#95 poison bonus off on a high-health enemy", EffectModels.blocked(m95, ctx) != "")
	Build.enemy["flags"] = {"high_health": false, "full_health": false}
	_flag("#95 poison bonus on below 65% health", EffectModels.blocked(m95, ctx) == "")
	Build.enemy["ailments"] = {poison: 12.0}
	_check("#95 12 poison stacks x 0.01", EffectModels.value(m95, 0.01, ctx)["x"], 0.12)
	Build.enemy["ailments"] = {poison: 150.0}
	_check("#95 stacks capped at 100 (f x 100)", EffectModels.value(m95, 0.01, ctx)["x"], 1.0)
	var mod95: StatMod = EffectModels.make_mod(m95, 0.01, ctx, "t")
	_check("#95 mod.more[0]", mod95.more[0], 1.0)
	_flag("#95 belongs to the SerpentVenom instance", mod95.ailment_only == GameData.enum_value("AilmentID", "SerpentVenom"))
	_check("#95 not an IncreasedAilmentEffect (added) mod", mod95.added, 0.0)
	var vs: StatStore = StatStore.new()
	vs.add(StatMod.make(LE.VITALITY, "added", 100.0, 0, "vit"))
	_check("#95 Vitality 100 x 0.02 = +200% venom", EffectModels.value(FieldModels.find("SerpentStrikeMutator.moreSerpentVenomDamagePerVitality"), 0.02, {"build": Build, "store": vs, "slot": -1, "item_slot": ""})["x"], 2.0)
	# #97: buffs on the player, Individual stacks: (1 + m × effect)^stacks, added linear; grouped: stacks × base
	var ind: Dictionary = {"buffScalingType": 0}
	var grp: Dictionary = {"buffScalingType": 1}
	var m10: StatMod = StatMod.make(LE.DAMAGE, "more", 0.10, 0, "t")
	_check("#97 Individual x5 stacks of +10% more: 1.1^5 - 1", BuildMods._stacked_buff(m10, ind, 1.0, 5.0).more[0], 0.61051, 0.00001)
	_check("#97 Individual x5 with effect 1.5: 1.15^5 - 1", BuildMods._stacked_buff(m10, ind, 1.5, 5.0).more[0], 1.0113572, 0.00001)
	var m15: StatMod = StatMod.make(LE.DAMAGE, "more", 0.15, 0, "t")
	_check("#97 Totem Armor 4 x 15% more: 1.15^4 - 1", BuildMods._stacked_buff(m15, ind, 1.0, 4.0).more[0], 0.74900625, 0.00001)
	var mneg: StatMod = StatMod.make(LE.DAMAGE_TAKEN, "more", -0.05, 0, "t")
	_check("#97 Crimson Shroud 3 x -5%: 0.95^3 - 1", BuildMods._stacked_buff(mneg, ind, 1.0, 3.0).more[0], -0.142625, 0.00001)
	_check("#97 Individual added is linear: 10 x 3 stacks x effect 1.2", BuildMods._stacked_buff(StatMod.make(LE.ARMOUR, "added", 10.0, 0, "t"), ind, 1.2, 3.0).added, 36.0, 0.0001)
	_check("#97 grouped ailment: stacks x base, effect ignored", BuildMods._stacked_buff(m10, grp, 1.0, 5.0).more[0], 0.5, 0.00001)
	# #98: holder_only (DamageConditionalEffect of the skill's DamageStatsHolder) is kept by scaled() and set by the field model
	var hold98: StatMod = StatMod.make(LE.DAMAGE, "more", 0.5, 0, "holder")
	hold98.holder_only = true
	_flag("#98 StatMod.scaled keeps holder_only", hold98.scaled(2.0).holder_only)
	_flag("#98 Dancing Strikes poison more is holder_only", EffectModels.make_mod(FieldModels.find("DancingStrikesMutator.moreMeleeDamagePerPoisonOnTarget"), 0.03, ctx, "t").holder_only)
	_flag("#98 Nova ignited more is holder_only (NovaMutator.Mutate adds a DamageConditionalEffect to the holder)", EffectModels.make_mod(FieldModels.find("NovaMutator.moreDamageAgainstIgnited"), 0.1, ctx, "t").holder_only)
	# #99: stack caps in source units (the cap of the node divided by its per-stack value)
	Build.enemy["ailments"] = {poison: 20.0}
	_check("#99 Serpent 3 points, 20 stacks: 0.03 x 12", EffectModels.value(FieldModels.find("SerpentStrikeMutator.moreMeleeDamagePerPoisonOnTarget"), 0.03, ctx)["x"], 0.36)
	Build.enemy["ailments"] = {poison: 5.0}
	_check("#99 Serpent 3 points, 5 stacks: 0.03 x 5", EffectModels.value(FieldModels.find("SerpentStrikeMutator.moreMeleeDamagePerPoisonOnTarget"), 0.03, ctx)["x"], 0.15)
	Build.enemy["ailments"] = {poison: 50.0}
	_check("#99 Dancing 2 points: 0.06 x 20", EffectModels.value(FieldModels.find("DancingStrikesMutator.moreMeleeDamagePerPoisonOnTarget"), 0.06, ctx)["x"], 1.2)
	var msh: Dictionary = FieldModels.find("ShurikensMutator.moreHitDamagePerPoisonOrBleedOnTarget").duplicate(true)
	msh["input"]["default"] = 30
	_check("#99 Shurikens 3 points, 30 stacks: 0.06 x 15", EffectModels.value(msh, 0.06, ctx)["x"], 0.9)
	var mci: Dictionary = FieldModels.find("CinderStrikeMutator.addedBaseFireDamagePerIgniteRecently").duplicate(true)
	mci["input"]["default"] = 10
	_check("#99 Cinder 4 points, 10 targets: 12 x 3", EffectModels.value(mci, 12.0, ctx)["x"], 36.0)
	var mfl: Dictionary = FieldModels.find("FlayMutator.meleeDamagePerXHealthConsumed").duplicate(true)
	mfl["input"]["default"] = 90
	_check("#99 Flay 2 points, 90 health: 2 x 90 / 30", EffectModels.value(mfl, 2.0, ctx)["x"], 6.0)
	mfl["input"]["default"] = 1000
	_check("#99 Flay capped at 360 consumed: 2 x 360 / 30", EffectModels.value(mfl, 2.0, ctx)["x"], 24.0)
	Build.enemy["ailments"] = {GameData.enum_value("AilmentID", "ArmourShred"): 20.0}
	_check("#99 Glyph: 14 stacks x 2%", EffectModels.value(FieldModels.find("GlyphOfDominionMutator.moreDoTPerArmorShredUpTo14Buff"), 0.02, ctx)["x"], 0.28)
	_check("#99 Runebolt Fire: 14 x 0.5%", EffectModels.value(FieldModels.find("RuneboltFireMutator.moreElemenetalDamagePerRuneweaveStackPerArmorShredOnTarget"), 0.005, ctx)["x"], 0.07)
	# #103: AuraOfDecay increased ailment frequency divides the zone interval by 1 + f
	_check("#103 interval 0.25, f 0.5", AilmentCalc.zone_interval(0.25, 0.5), 0.1666667, 0.000001)
	_check("#103 interval 0.25, f 1", AilmentCalc.zone_interval(0.25, 1.0), 0.125, 0.000001)
	_check("#103 f 0 keeps the interval", AilmentCalc.zone_interval(0.25, 0.0), 0.25, 0.000001)
	_check("#103 f <= -1 counts as -0.99", AilmentCalc.zone_interval(0.25, -1.5), 25.0, 0.0001)
	_flag("#103 the field model feeds the key ailment_frequency", str(FieldModels.find("AuraOfDecayMutator.increasedAilmentFrequency").get("param", "")) == "ailment_frequency")
	# #104: Sacrifice DoT buff is a more (Stats.MoreStat), not an increased
	var mod104: StatMod = EffectModels.make_mod(FieldModels.find("SacrificeMutator.moreDotDamageOnCast"), 0.4, ctx, "t")
	_check("#104 more value", mod104.more[0], 0.4)
	_check("#104 not in the increased bucket", mod104.increased, 0.0)
	_check("#104 DoT tag kept", float(mod104.tags), float(LE.DOT))
	# #105: a stat model with an ailment condition scales by the presence (uptime); other models keep the 50% on/off rule
	var ign: int = GameData.enum_value("AilmentID", "Ignite")
	var shk: int = GameData.enum_value("AilmentID", "Shock")
	Build.enemy["ailments"] = {ign: 2.0, shk: 1.0}
	Build.enemy["uptime"] = {ign: 0.4, shk: 0.5}
	var m1: Dictionary = {"kind": "stat", "stat": "Damage", "mod": "more", "when": ["enemy:Ignite"]}
	var m2: Dictionary = {"kind": "stat", "stat": "Damage", "mod": "more", "when": ["enemy_any:Ignite|Shock"]}
	var m3: Dictionary = {"kind": "trigger", "ability": "x", "on": "hit", "when": ["enemy:Ignite"]}
	_check("#105 presence factor, uptime 40%", EffectModels.presence_factor(m1, ctx), 0.4)
	_check("#105 more 0.3 vs ignited 40% of the time: 0.12", EffectModels.value(m1, 0.3, ctx)["x"], 0.12)
	_flag("#105 counted (not blocked) at 40%", EffectModels.blocked(m1, ctx) == "")
	_check("#105 enemy_any: 1 - 0.6 x 0.5 = 0.7", EffectModels.presence_factor(m2, ctx), 0.7)
	_check("#105 enemy_any value 0.3 x 0.7", EffectModels.value(m2, 0.3, ctx)["x"], 0.21)
	_check("#105 non-stat model: factor 1", EffectModels.presence_factor(m3, ctx), 1.0)
	_flag("#105 non-stat model keeps the 50% rule (40% blocked)", EffectModels.blocked(m3, ctx) != "")
	Build.enemy["uptime"] = {ign: 0.0}
	_flag("#105 uptime 0 blocks the stat model", EffectModels.blocked(m1, ctx) != "")
	Build.enemy["uptime"] = {ign: 1.0}
	_check("#105 full uptime keeps the value", EffectModels.value(m1, 0.3, ctx)["x"], 0.3)
	# #108: Symbols of Hope activation: no damage-taken reduction with the Divine Flare node; AbilityProperty 9 weakens it
	_check("#108 AP9 0 -> factor 1", BuffSkills.less_factor(0.0), 1.0)
	_check("#108 AP9 -0.2 -> factor 1", BuffSkills.less_factor(-0.2), 1.0)
	_check("#108 AP9 0.4 -> factor 0.6", BuffSkills.less_factor(0.4), 0.6)
	_check("#108 AP9 1.5 -> factor -0.5 (game: 1 - f)", BuffSkills.less_factor(1.5), -0.5)
	_check("#108 scaled activation mod: -0.1 x 0.6", StatMod.make(LE.DAMAGE_TAKEN, "more", -0.1, 0, "t").scaled(BuffSkills.less_factor(0.4)).more[0], -0.06, 0.00001)
	Build.set_class(2)
	Build.set_level(100)
	Build.set_skill(0, "si4lgl")
	Build.set_skill_input(0, "sigils", 2.0)
	Build.set_skill_input(0, "sigils_active_use", true)
	var sigils108: String = "Skill \"Symbols of Hope\" (buff)"
	var g108: Dictionary = BuildMods.global_store(Build)
	_check("#108 activation without the node: -0.05 x 2", _mods_more_sum(g108["store"], LE.DAMAGE_TAKEN, sigils108), -0.1)
	Build.skills[0]["tree"][17] = 1  # Sigils Of Hope AOE On Cast: canCastDivineFlare
	g108 = BuildMods.global_store(Build)
	_check("#108 Divine Flare allocated: no damage-taken reduction on activation", _mods_more_sum(g108["store"], LE.DAMAGE_TAKEN, sigils108), 0.0)
	Build.skills[0]["tree"].erase(17)
	Build.skills[0].erase("inputs")
	Build.set_skill(0, "")
	Build.set_class(1)
	Build.set_level(100)

	Build.enemy["flags"] = flags_saved
	Build.enemy["ailments"] = ail_saved
	if had_uptime:
		Build.enemy["uptime"] = uptime_saved
	else:
		Build.enemy.erase("uptime")


## Model fixes of the passives and sets group (#126 #128 #130-#138): hand-computed from the game formulas, not run yet.
func _passive_set_fixes() -> void:
	print("--- passive and set fixes")
	var saved_class: int = Build.class_id
	var saved_items: Dictionary = Build.items.duplicate(true)
	var saved_passives: Dictionary = Build.passives.duplicate(true)
	# #126 Archmage adaptive spell damage: x0 below 300 max mana, x1 from 300, x2 from 1000 (times the points)
	var m126: Dictionary = FieldModels.find("CharacterMutator.adaptiveSpellDamageFromMaxMana")
	for case126: Array in [[299, 0.0], [300, 5.0], [999, 5.0], [1000, 10.0]]:
		var mod126: StatMod = EffectModels.make_mod(m126, 5.0, {"build": Build, "store": _added_store(LE.MANA, float(case126[0]))}, "t")
		_check("#126 max mana %d: Spell damage added" % int(case126[0]), mod126.added, float(case126[1]))
	var mod126_one: StatMod = EffectModels.make_mod(m126, 5.0, {"build": Build, "store": _added_store(LE.MANA, 300.0)}, "t")
	_flag("#126 the mod is Damage tagged Spell", mod126_one.property == LE.DAMAGE and mod126_one.tags == LE.SPELL)
	# #131 more Void damage doubled below 30% block chance (value of the block row, 2 below 0.3, 1 from 0.3)
	var m131: Dictionary = FieldModels.find("CharacterMutator.moreVoidDamageDoubledWithUnder30Block")
	_check("#131 block 25%: more Void damage 0.2", EffectModels.make_mod(m131, 0.1, {"build": Build, "store": _added_store(LE.BLOCK_CHANCE, 0.25)}, "t").more[0], 0.2)
	_check("#131 block 30%: more Void damage 0.1", EffectModels.make_mod(m131, 0.1, {"build": Build, "store": _added_store(LE.BLOCK_CHANCE, 0.3)}, "t").more[0], 0.1)
	_check("#131 no block: more Void damage 0.2", EffectModels.make_mod(m131, 0.1, {"build": Build, "store": StatStore.new()}, "t").more[0], 0.2)
	# #138 more damage per attack mana cost: value x the skill's mana cost, untagged, for Melee (or Throwing) skills
	var m138: Dictionary = FieldModels.find("CharacterMutator.moreDamagePerMeleeAttackCost")
	var ctx138: Dictionary = {"build": Build, "store": StatStore.new(), "mana_cost": 20.0}
	_flag("#138 cost models are applied per skill", EffectModels.phase(m138) == "skill")
	_check("#138 melee, cost 20 x 0.005: more 0.1", EffectModels.make_mod(m138, 0.005, ctx138, "t").more[0], 0.1)
	var m138_throw: Dictionary = FieldModels.find("CharacterMutator.moreDamagePerThrowingAttackCost")
	_check("#138 throwing, cost 20 x 0.005: more 0.1", EffectModels.make_mod(m138_throw, 0.005, ctx138, "t").more[0], 0.1)
	# #132 Flame Drinker: more damage for Melee skills with a mana cost of at least 10
	var m132: Dictionary = FieldModels.find("CharacterMutator.moreDamageWithHighCostMeleeAttacks")
	_flag("#132 cost 9.99 does not apply", EffectModels.blocked(m132, {"build": Build, "store": StatStore.new(), "mana_cost": 9.99, "v": 0.03}) != "")
	var ctx132: Dictionary = {"build": Build, "store": StatStore.new(), "mana_cost": 10.0, "v": 0.03}
	_flag("#132 cost 10 applies", EffectModels.blocked(m132, ctx132) == "")
	var mod132: StatMod = EffectModels.make_mod(m132, 0.03, ctx132, "t")
	_check("#132 more 0.03", mod132.more[0], 0.03)
	_flag("#132 untagged Damage", mod132.tags == 0 and mod132.property == LE.DAMAGE)
	# #133 minion penetration from over-capped resistance: one stat per type, each from its own resistance
	var m133: Dictionary = FieldModels.find("CharacterMutator.minionPenetrationPer5PercentOvercappedResistanceForNecroticOrEle")
	var store133 := StatStore.new()
	store133.add(StatMod.make(LE.FIRE_RES, "added", 1.25, 0, "t"))
	var mods133: Array[StatMod] = EffectModels.make_mods(m133, 0.05, {"build": Build, "store": store133}, "t")
	_check("#133 four penetration mods", float(mods133.size()), 4.0)
	_check("#133 fire overcap 0.5: 0.05 x 0.5 x 20", mods133[1].added, 0.5)
	_flag("#133 the fire mod is tagged Fire", mods133[1].tags == LE.FIRE)
	_check("#133 necrotic without overcap: 0", mods133[0].added, 0.0)
	# #134 Shift: the bleed buff gives IncreasedAilmentDuration (42) and IncreasedAilmentEffect (43), both for Bleed
	var m134: Dictionary = FieldModels.find("CharacterMutator.bleedEffectAndDurationForNextAttackFromShift")
	var mods134: Array[StatMod] = EffectModels.make_mods(m134, 0.25, {"build": Build, "store": StatStore.new()}, "t")
	_check("#134 two mods: duration and effect", float(mods134.size()), 2.0)
	_flag("#134 properties 42 and 43", mods134[0].property == 42 and mods134[1].property == 43)
	_check("#134 both 0.25", mods134[0].added + mods134[1].added, 0.5)
	_flag("#134 special Bleed", mods134[1].special == GameData.enum_value("AilmentID", "Bleed"))
	# #137 stack counts are capped by the maximum stack fields
	var cap_ctx: Dictionary = {"build": Build, "store": StatStore.new()}
	Build.set_class(1)
	Build.passives = {13: 3}
	_check("#137 momentum cap = 3 allocated points", EffectModels.source_cap(FieldModels.find("CharacterMutator.arcaneMomentumStatsPerStack"), cap_ctx), 3.0)
	_check("#137 arcane shield cap 4", EffectModels.source_cap(FieldModels.find("CharacterMutator.arcaneShieldStats"), cap_ctx), 4.0)
	_check("#137 blade conduit cap 6", EffectModels.source_cap(FieldModels.find("CharacterMutator.incManaRegenPerBladeConduit"), cap_ctx), 6.0)
	_flag("#137 no cap without a cap field", is_inf(EffectModels.source_cap(FieldModels.find("CharacterMutator.statsPerMastery1Level"), cap_ctx)))
	# #136 Void Corruption: the source is the points spent in mastery 1 (Sentinel tree, node 56)
	Build.set_class(2)
	Build.passives = {56: 8}
	_check("#136 points in mastery 1: 8", float(Build.points_in_mastery(1)), 8.0)
	_check("#136 mastery_points:1 source", EffectModels.source("mastery_points:1", {"build": Build, "store": StatStore.new()}), 8.0)
	# #128 passives and set bonuses: Agility (Rogue node 8, PP 93 0.2 per point) reaches the planner
	Build.set_class(4)
	Build.passives = {8: 5}
	var agility_pp: float = -1.0
	for e128: Dictionary in UniqueEffects.entries(Build):
		if str(e128["effect"].get("source", "")) == "PassivePlayerProperty" and int(e128["effect"].get("ppIndex", -1)) == 93:
			agility_pp = float(e128["pp"])
	_check("#128 Agility x5: PP 93 value 1.0", agility_pp, 1.0)
	# #128 PP models of passives: the value is the stat of the game formula (attributes, resistances, weapons)
	var s146: StatStore = _added_store(LE.INTELLIGENCE, 100.0)
	var m146: StatMod = _pp_make_mod(146, 1.0, s146)
	_check("#128 PP 146 Int 100 x 0.5: Spell Lightning added 50", m146.added, 50.0)
	_flag("#128 PP 146 tags Spell Lightning", m146.tags == (LE.SPELL | LE.LIGHTNING))
	_check("#128 PP 260 Int 40, 0.03: increased 1.2", _pp_make_mod(260, 0.03, _added_store(LE.INTELLIGENCE, 40.0)).increased, 1.2)
	_check("#128 PP 305 Int 60, 0.01: added 0.1", _pp_make_mod(305, 0.01, _added_store(LE.INTELLIGENCE, 60.0)).added, 0.1, 0.0001)
	_check("#128 PP 420 Str 30, 0.01: added 0.1", _pp_make_mod(420, 0.01, _added_store(LE.STRENGTH, 30.0)).added, 0.1, 0.0001)
	_check("#128 PP 421 Att 20, 0.02: added 0.08", _pp_make_mod(421, 0.02, _added_store(LE.ATTUNEMENT, 20.0)).added, 0.08, 0.0001)
	_check("#128 PP 427 Dex 50, 0.08: increased 4", _pp_make_mod(427, 0.08, _added_store(LE.DEXTERITY, 50.0)).increased, 4.0)
	_check("#128 PP 439 Dex 50, 0.01: added 0.1", _pp_make_mod(439, 0.01, _added_store(LE.DEXTERITY, 50.0)).added, 0.1, 0.0001)
	_check("#128 PP 442 Int 45, 0.01: added 0.03", _pp_make_mod(442, 0.01, _added_store(LE.INTELLIGENCE, 45.0)).added, 0.03, 0.0001)
	_check("#128 PP 689 Str 30, 0.01: Bleed chance 0.3", _pp_make_mod(689, 0.01, _added_store(LE.STRENGTH, 30.0)).added, 0.3, 0.0001)
	_check("#128 PP 690 Att 20, 0.01: Ignite chance 0.2", _pp_make_mod(690, 0.01, _added_store(LE.ATTUNEMENT, 20.0)).added, 0.2, 0.0001)
	_check("#128 PP 487 Str 40, 0.005: fire res shred 0.2", _pp_make_mod(487, 0.005, _added_store(LE.STRENGTH, 40.0)).added, 0.2, 0.0001)
	_check("#128 PP 195 fire res 0.75, 0.01: Poison chance 0.75", _pp_make_mod(195, 0.01, _added_store(LE.FIRE_RES, 0.75)).added, 0.75, 0.0001)
	_check("#128 PP 662 poison res 0.75, 1.0: Fire damage added 15", _pp_make_mod(662, 1.0, _added_store(LE.POISON_RES, 0.75)).added, 15.0, 0.0001)
	var s483 := StatStore.new()
	s483.add(StatMod.make(LE.FIRE_RES, "added", 0.5, 0, "t"))
	s483.add(StatMod.make(LE.COLD_RES, "added", 0.5, 0, "t"))
	s483.add(StatMod.make(LE.LIGHTNING_RES, "added", 0.25, 0, "t"))
	_check("#128 PP 483 elemental res 1.25, 0.5: endurance threshold 62.5", _pp_make_mod(483, 0.5, s483).added, 62.5, 0.0001)
	_check("#128 PP 196 health regen 100, 0.04: increased 0.4", _pp_make_mod(196, 0.04, _added_store(GameData.sp_id("HealthRegen"), 100.0)).increased, 0.4, 0.0001)
	var s488 := StatStore.new()
	var sp_crit_multi: int = GameData.sp_id("CriticalMultiplier")
	s488.add(StatMod.make(sp_crit_multi, "added", 0.5, 0, "t"))
	s488.add(StatMod.make(sp_crit_multi, "added", 0.5, LE.LIGHTNING, "t"))
	s488.add(StatMod.make(sp_crit_multi, "added", 0.5, LE.FIRE, "t"))
	_check("#128 PP 488 lightning crit multi 1.0 x 0.5: more 0.5", _pp_make_mod(488, 0.5, s488).more[0], 0.5, 0.0001)
	_check("#128 PP 489 Increased Healing 1.0, 0.01: Fire penetration 0.01", _pp_make_mod(489, 0.01, _added_store(GameData.sp_id("IncreasedHealing"), 1.0)).added, 0.01, 0.0001)
	var s385 := StatStore.new()
	s385.add(StatMod.make(LE.EFFECT_OF_AILMENT_ON_YOU, "increased", 0.5, 0, "t", GameData.enum_value("AilmentID", "Haste")))
	_check("#128 PP 385 Haste effect +50%, 0.01: more 0.015", _pp_make_mod(385, 0.01, s385).more[0], 0.015, 0.0001)
	var ctx106: Dictionary = {"build": Build, "store": StatStore.new(), "mana_cost": 30.0}
	_check("#128 PP 106 cost 30, 0.1: more 0.03 (bow)", EffectModels.make_mod(GameData.unique_player_model(106), 0.1, ctx106, "t").more[0], 0.03, 0.0001)
	# #128 / #130 weapons: swords and daggers counted from the weapon and offhand base types
	Build.items = {"weapon": _test_gear(9), "offhand": _test_gear(9)}
	_check("#128 PP 94 two swords, 0.08: crit increased 0.16", _pp_make_mod(94, 0.08, StatStore.new()).increased, 0.16, 0.0001)
	_check("#128 PP 98 two swords, 0.05: Bleed chance 0.1", _pp_make_mod(98, 0.05, StatStore.new()).added, 0.1, 0.0001)
	Build.items = {"weapon": _test_gear(6), "offhand": _test_gear(6)}
	_check("#128 PP 99 two daggers, 0.05: Poison chance 0.1", _pp_make_mod(99, 0.05, StatStore.new()).added, 0.1, 0.0001)
	_check("#128 PP 95 two daggers, 0.04: crit increased 0.08", _pp_make_mod(95, 0.04, StatStore.new()).increased, 0.08, 0.0001)
	Build.items = {"weapon": _test_gear(5)}
	var m171: Array[StatMod] = EffectModels.make_mods(GameData.unique_player_model(171), 0.06, {"build": Build, "store": StatStore.new()}, "t")
	_check("#128 PP 171 axe: attack and cast speed mods", float(m171.size()), 2.0)
	_check("#128 PP 171 axe: increased 0.06", m171[0].increased, 0.06, 0.0001)
	_flag("#128 PP 171 gear_any holds with an axe", EffectModels.holds("gear_any:9,5,16,12", {"build": Build, "store": StatStore.new()}))
	Build.items = {"weapon": _test_gear(23), "offhand": _test_gear(17)}
	_flag("#128 PP 171 gear_any not with other weapons", not EffectModels.holds("gear_any:9,5,16,12", {"build": Build, "store": StatStore.new()}))
	Build.items = {"weapon": _test_gear(9), "offhand": _test_gear(6)}
	_flag("#128 PP 632 dual wielding different types holds", EffectModels.holds("gear:dual_wield_diff", {"build": Build, "store": StatStore.new()}))
	Build.items = {"weapon": _test_gear(9), "offhand": _test_gear(9)}
	_flag("#128 PP 632 same types do not hold", not EffectModels.holds("gear:dual_wield_diff", {"build": Build, "store": StatStore.new()}))
	# #130 Corsair's reforged pieces (set 16, two pieces) count like the unique pieces; PP 149 is the 2-piece bonus
	Build.items = {
		"helmet": {"base": 0, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 783, "tier": 1, "roll": 255}]},
		"offhand": {"base": 18, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 784, "tier": 1, "roll": 255}]}}
	_check("#130 two reforged Corsair's pieces: count 2", float(BuildMods.set_counts(Build)[16]), 2.0)
	_check("#130 complete sets 1", float(BuildMods.complete_sets(Build)), 1.0)
	var n149: int = 0
	var pp149: float = 0.0
	for e130: Dictionary in UniqueEffects.entries(Build):
		if str(e130["effect"].get("source", "")) == "PlayerProperty" and int(e130["effect"].get("ppIndex", -1)) == 149:
			n149 += 1
			pp149 = float(e130["pp"])
	_check("#128 Corsair's 2 pieces: PP 149 entry once", float(n149), 1.0)
	_check("#128 Corsair's PP 149 value 1", pp149, 1.0)
	Build.items["body"] = {"base": 1, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 783, "tier": 1, "roll": 255}]}
	_check("#130 the same reforged uniqueId counts once", float(BuildMods.set_counts(Build)[16]), 2.0)
	Build.items = {"helmet": {"base": 0, "sub": 0, "implicit_rolls": [], "affixes": [{"id": 783, "tier": 1, "roll": 255}]}}
	_check("#130 one reforged piece: count 1", float(BuildMods.set_counts(Build)[16]), 1.0)
	# restore the build of the other checks
	Build.set_class(saved_class)
	Build.passives = saved_passives
	Build.items = saved_items


## A store with one added value of a stat (test helper).
func _added_store(sp: int, value: float) -> StatStore:
	var store := StatStore.new()
	store.add(StatMod.make(sp, "added", value, 0, "t"))
	return store


## One PlayerProperty model of the unique models, applied to a value and a store (test helper; first mod of variants).
func _pp_make_mod(index: int, v: float, store: StatStore) -> StatMod:
	return EffectModels.make_mod(GameData.unique_player_model(index), v, {"build": Build, "store": store}, "t")


## A minimal equipped item of one base type (test helper).
func _test_gear(base: int) -> Dictionary:
	return {"base": base, "sub": 0, "implicit_rolls": [], "affixes": []}


func _lean_and_cache() -> void:
	print("--- lean results and the calculation cache")
	for fixture: String in ["letools_Q0V6XDLG.json", "maxroll_char_palading.json", "letools_A83KxJq5.json"]:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + fixture))
		var doc: Dictionary = MaxrollImport.to_build(raw) if fixture.begins_with("maxroll") else LEToolsImportScript.to_build(raw)
		LEToolsImportScript.apply(Build, doc)
		for slot: int in range(Build.skills.size()):
			if str(Build.skills[slot].get("ability", "")) == "":
				continue
			CalcCache.enabled = false
			var full: Dictionary = SkillCalc.compute(Build, slot, true)
			var lean: Dictionary = SkillCalc.compute(Build, slot, false)
			CalcCache.enabled = true
			CalcCache.clear()
			var cached_full: Dictionary = SkillCalc.compute(Build, slot, true)
			var cached_lean: Dictionary = SkillCalc.compute(Build, slot, false)
			_flag("%s slot %d: lean = full without breakdowns" % [fixture, slot], _stripped(lean) == _stripped(full) and bool(lean.get("lean", false)))
			_flag("%s slot %d: cached = fresh" % [fixture, slot], var_to_str(cached_full) == var_to_str(full)
				and var_to_str(cached_lean) == var_to_str(lean))


## The result as text without the row breakdowns and the lean markers.
func _stripped(result: Dictionary) -> String:
	var copy: Dictionary = result.duplicate(true)
	copy.erase("lean")
	for section: Dictionary in copy.get("sections", []):
		for row: Dictionary in section.get("rows", []):
			row.erase("breakdown")
			row.erase("lazy")
	return var_to_str(copy)


## Zones that the mutators add at run time (RepeatedlyApplyAilmentsInRadius, docs/ENGINE.md §9.3): the chance of one tick,
## never a hit chance; interval = applicationInterval / (1 + frequency). Black Hole Chill: 0.5 per second = 0.25 per tick × 2 ticks.
func _runtime_zones() -> void:
	var zm: StatMod = EffectModels.make_mod({"kind": "stat", "stat": "AilmentChance", "mod": "added", "ailment": "Chill",
		"factor": 0.5, "zone": 0.5}, 1.0, {"store": StatStore.new()}, "t")
	_check("zone model: chance of one tick = value × factor", zm.added, 0.5)
	_check("zone model: tick interval", zm.zone_interval, 0.5)
	_check("zone model: Chill special", float(zm.special), float(GameData.enum_value("AilmentID", "Chill")))
	var hit_ctx: Dictionary = {"base": {}, "ab": {}, "mods": [zm], "tags": 0}
	_check("zone chance is no hit chance", float(AilmentCalc._chances(hit_ctx, 0).has(3)), 0.0)
	var zone: Dictionary = {"name": "Black Hole", "interval": 0.5, "ailments": [], "mods": [zm], "runtime": true}
	var empty_ctx: Dictionary = {"base": {}, "ab": {}, "mods": [], "tags": 0}
	var with_mod: Dictionary = AilmentCalc._chances(empty_ctx, 0, false, zone)
	_check("runtime zone: chance per tick 0.5", float(with_mod[3]["chance"]), 0.5)
	_check("runtime zone: applications per second = (1 / 0.5) × 0.5", (1.0 / 0.5) * float(with_mod[3]["chance"]), 1.0)
	var prefab: Dictionary = zone.duplicate()
	prefab.erase("runtime")
	_check("prefab zone ignores the run-time chance", float(AilmentCalc._chances(empty_ctx, 0, false, prefab).has(3)), 0.0)
	var no_mods: Dictionary = zone.duplicate()
	no_mods["mods"] = []
	_check("runtime zone without mods: no chance", float(AilmentCalc._chances(empty_ctx, 0, false, no_mods).has(3)), 0.0)
	_check("zone interval 0.5 with +100% frequency: 0.25 s", AilmentCalc.zone_interval(0.5, 1.0), 0.25)
	var dup: StatMod = zm.scaled(2.0)
	_check("scaled() keeps the zone interval", dup.zone_interval, 0.5)


## Zone objects with several ticks per lifetime (ZoneTicks), Hammer Throw's Void zone, Black Hole ticks, Scathing Light, Divine
## Essence and the Storm Totem frostbite chance (research/11 zones-ailments fixes). Hand-computed from the game code: tick k needs
## an age above k × interval; hammer lifetimes 2.5 s (returning), 0.75 s and 6.0 s with the spiral (no return).
func _zone_ticks_and_ailment_fixes() -> void:
	print("--- zone ticks and zone ailment fixes")
	_check("ticks: 2.0 s at 0.2 s = 10", float(ZoneTicks.ticks(2.0, 0.2, 0.0, false)), 10.0)
	_check("ticks: 2.75 s at 0.3 s with damageAtStart = 10", float(ZoneTicks.ticks(2.75, 0.3, 0.0, true)), 10.0)
	_check("ticks: returning hammer 2.5 s at 0.2 s = 12", float(ZoneTicks.ticks(2.5, 0.2, 0.0, false)), 12.0)
	_check("ticks: exact multiple 6.0 s at 0.2 s = 30", float(ZoneTicks.ticks(6.0, 0.2, 0.0, false)), 30.0)
	_check("ticks: Black Hole +0.8 duration (4.95 s) = 17", float(ZoneTicks.ticks(2.75 * 1.8, 0.3, 0.0, true)), 17.0)
	_check("ticks: Black Hole +1.1 duration (5.775 s) = 20", float(ZoneTicks.ticks(2.75 * 2.1, 0.3, 0.0, true)), 20.0)

	var hz: Dictionary = SkillComponents.hammer_zone_numbers(0.0, false, false, false)
	_check("hammer zone, returning: lifetime 2.5 s", float(hz["lifetime"]), 2.5)
	_check("hammer zone, returning: 12 ticks", float(hz["ticks"]), 12.0)
	_check("hammer zone, Void: 8 base damage", float((hz["damage"] as Array)[5]), 8.0)
	_check("hammer zone, Void: added damage 0.05 × 8 = 0.4", float(hz["ade"]), 0.4)
	hz = SkillComponents.hammer_zone_numbers(1.0, true, false, false)
	_check("hammer zone, no return, inc 1.0: lifetime 0.75 s", float(hz["lifetime"]), 0.75)
	_check("hammer zone, no return, inc 1.0: 3 ticks", float(hz["ticks"]), 3.0)
	_check("hammer zone, no return, inc 1.0: 16 Void", float((hz["damage"] as Array)[5]), 16.0)
	_check("hammer zone, no return, inc 1.0: added damage 0.8", float(hz["ade"]), 0.8)
	hz = SkillComponents.hammer_zone_numbers(0.5, true, true, false)
	_check("hammer zone, no return + spiral: lifetime 6.0 s", float(hz["lifetime"]), 6.0)
	_check("hammer zone, no return + spiral: 30 ticks", float(hz["ticks"]), 30.0)
	_check("hammer zone, no return + spiral, inc 0.5: 12 Void", float((hz["damage"] as Array)[5]), 12.0)
	hz = SkillComponents.hammer_zone_numbers(0.0, false, false, true)
	_check("hammer zone, lightning: 8 Lightning", float((hz["damage"] as Array)[3]), 8.0)
	_check("hammer zone, lightning: no Void", float((hz["damage"] as Array)[5]), 0.0)

	# Scathing Light chance sum S (multiplier f × 100 × S, Holy Prism f = 0.01 per point)
	_check("Scathing Light: Ignite 0.30 + Electrify 0.20 = 0.5", AilmentCalc.scathing_light_chance(0.3, 0.2, 0, 0.0, 0.0, 0.0, false, 0.0, 0.0), 0.5)
	_check("Scathing Light: Holy Prism 1 point on S = 0.5 gives factor 1.5", 1.0 + 0.5 * 0.01 * 100.0, 1.5)
	_check("Scathing Light: + Conduit of Light (res 0.75, 0.01 per point) = 1.25", AilmentCalc.scathing_light_chance(0.3, 0.2, 0, 0.75, 0.01, 0.0, false, 0.0, 0.0), 1.25)
	_check("Scathing Light: + Awestruck (Electrify field 1.0) = 2.25", AilmentCalc.scathing_light_chance(0.3, 0.2, 0, 0.75, 0.01, 1.0, false, 0.0, 0.0), 2.25)
	_check("Scathing Light: fire conversion uses fire res 0.5 = 1.0", AilmentCalc.scathing_light_chance(0.3, 0.2, 1, 0.5, 0.01, 0.0, false, 0.0, 0.0), 1.0)
	_check("Scathing Light: physical conversion has no res or node terms = 0.5", AilmentCalc.scathing_light_chance(0.3, 0.2, 2, 0.75, 0.01, 1.0, false, 0.0, 0.0), 0.5)
	_check("Scathing Light: Shock → Electrify, Shock 0.4 + Lay Bare 0.35 = 1.25", AilmentCalc.scathing_light_chance(0.3, 0.2, 0, 0.0, 0.0, 0.0, true, 0.4, 0.35), 1.25)

	# Hammer Throw: the Void zone is one component per use, with the ticks of its lifetime and no ailments of its own
	Build.set_skill(0, "ht16aw")
	var ht_tree: Dictionary = GameData.get_skill_tree("ht16aw")
	_allocate_path(ht_tree, 7, 1)  # Disintegrating Aura
	_allocate_path(ht_tree, 8, 4)  # Rapid Disintegration ×4: +100% Aura damage
	var ht_s: Dictionary = BuildMods.skill_store(Build, 0, BuildMods.global_store(Build)["store"])
	var ht_comps: Array[Dictionary] = SkillComponents.collect(Build, 0, GameData.get_ability("ht16aw"), ht_s)
	var zone_comp: Dictionary = {}
	for comp: Dictionary in ht_comps:
		if str(comp["name"]) == LE.t("Disintegrating Aura"):
			zone_comp = comp
	_flag("Hammer Throw: the Void zone is a component", not zone_comp.is_empty())
	if not zone_comp.is_empty():
		_check("Hammer Throw zone: 12 ticks per use (returning hammer)", float(zone_comp["per_use"]), 12.0)
		_check("Hammer Throw zone: not a hit", float(zone_comp["base"]["isHit"]), 0.0)
		_check("Hammer Throw zone: Void base 16 (+100% Aura damage)", float((zone_comp["base"]["damage"] as Array)[5]), 16.0)
		_flag("Hammer Throw zone: rolls no ailments of its own", bool(zone_comp.get("no_ailments", false)))

	# Black Hole: the zone is the primary hit, 10 ticks per cast (0.3 s over 2.75 s, damageAtStart)
	Build.set_skill(0, "bh2")
	var bh_s: Dictionary = BuildMods.skill_store(Build, 0, BuildMods.global_store(Build)["store"])
	var bh_comps: Array[Dictionary] = SkillComponents.collect(Build, 0, GameData.get_ability("bh2"), bh_s)
	_check("Black Hole: primary zone = 10 ticks per cast", float(bh_comps[0]["per_use"]), 10.0)
	_check("Black Hole: 48 Cold per tick unchanged", float((bh_comps[0]["base"]["damage"] as Array)[2]), 48.0)

	# Divine Essence: one roll a second while alive (5 points × 0.1 per second)
	var de_target: String = "CharacterMutator.divineEssenceEverySecondChance"
	var saved_level: int = Build.level
	Build.level = 100  # the passive point cap must cover the unlocking points of the base tree
	_flag("Divine Essence: a passive class holds the node", _set_passive_points(de_target, 5) >= 0)
	_check("Divine Essence: 5 points = 0.5 per second", EnemyAilments._passive_field(Build, de_target), 0.5, 0.0001)
	var de_gain: Dictionary = {}
	for g: Dictionary in EnemyAilments._timed_sources(Build):
		if int(g["id"]) == GameData.ailment_id_by_name("DivineEssence"):
			de_gain = g
	_check("Divine Essence: gain rate 0.5 per second", float(de_gain.get("rate", 0.0)), 0.5, 0.0001)
	_check("Divine Essence: 10 s duration, load 5 capped at 3 stacks", minf(float(de_gain.get("rate", 0.0)) * float(de_gain.get("duration", 0.0)), float(de_gain.get("max", 0))), 3.0)

	# Ancestral Speed: 2 points = 0.14 chance per use of a totem skill (1.5 uses/s), haste 3 s; no gain for other skills
	var ha_target: String = "CharacterMutator.chanceToGainHasteWhenYouSummonATotemFromPassives"
	_flag("Ancestral Speed: a passive class holds the node", _set_passive_points(ha_target, 2) >= 0)
	var totem_gain: Dictionary = {}
	for g: Dictionary in EnemyAilments._self_sources(Build, {"name": "TotemTest", "tags": LE.TOTEM}, 1.5, 1.5):
		if int(g["id"]) == GameData.ailment_id_by_name("Haste"):
			totem_gain = g
	_check("totem haste: rate 1.5 × 0.14 per second", float(totem_gain.get("rate", 0.0)), 0.21, 0.0001)
	_check("totem haste: 3 s duration", float(totem_gain.get("duration", 0.0)), 3.0)
	var other_gains: Array[Dictionary] = EnemyAilments._self_sources(Build, {"name": "NotTotem", "tags": 0}, 1.5, 1.5)
	var other_haste: int = 0
	for g: Dictionary in other_gains:
		if int(g["id"]) == GameData.ailment_id_by_name("Haste"):
			other_haste += 1
	_check("totem haste: a skill without the Totem tag gets none", float(other_haste), 0.0)

	# Storm Totem frostbite: the chance of the totem's Blizzard application (one per 1 s, component scope)
	var st_model: Dictionary = FieldModels.find("StormTotemMutator.chanceToApplyFrostbitePerSecond")
	_check("Storm Totem frostbite: zone interval 1.0 s", float(st_model.get("zone", 0.0)), 1.0)
	_flag("Storm Totem frostbite: scope is the Blizzard component", str(st_model.get("scope", "")) == "component:Blizzard")
	Build.level = saved_level
	Build.set_class(1)  # Mage: the class of the sample build
	Build.set_skill(0, "ht16aw")


## Sets the class whose passive tree holds a node with this CharacterMutator target, unlocks its masteries and spends `points`
## on that node. Returns the class id, -1 if no class holds the node.
func _set_passive_points(target: String, points: int) -> int:
	for class_id: int in range(0, 6):
		var tree: Dictionary = GameData.get_passive_tree(class_id)
		if tree.is_empty():
			continue
		var effects: Dictionary = GameData.passive_effects(str(tree["treeID"]))
		for node_id: Variant in effects:
			for effect: Dictionary in effects[node_id].get("effects", []):
				if str(effect.get("target", "")) != target:
					continue
				Build.set_class(class_id)
				for node: Dictionary in tree["nodes"]:
					if int(node["mastery"]) == 0:
						while Build.add_point(int(node["id"])):
							pass
				_allocate_passive_path(tree, int(node_id), points)
				return class_id
	return -1
