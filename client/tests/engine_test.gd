extends Node

## Headless engine check: test vectors from research/06a–06c, 07a and a sample build.
## Run: Godot_console.exe --headless --path client res://tests/engine_test.tscn

var _failed: int = 0


func _ready() -> void:
	_vectors()
	_sample_build()
	_idol_altar()
	_passive_field_models()
	print("ENGINE TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: float, want: float, eps: float = 0.0005) -> void:
	if absf(got - want) > eps:
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


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


func _vectors() -> void:
	_triggers_cooldown()
	_check("round_half_even(2.5)", LE.round_half_even(2.5), 2)
	_check("round_half_even(3.5)", LE.round_half_even(3.5), 4)
	_check("round_half_even(1028.5)", LE.round_half_even(1028.5), 1028)
	_check("affix Integer [5,10] roll 128", AffixMath.roll_value(5, 10, "Integer", "ADDED", 128, 0.0), 8)
	_check("affix Integer [5,10] roll 255", AffixMath.roll_value(5, 10, "Integer", "ADDED", 255, 0.0), 10)
	_check("affix inc [0.10,0.20] roll 200", AffixMath.roll_value(0.10, 0.20, "Hundredth", "INCREASED", 200, 0.0), 0.18)
	_check("affix inc [0.10,0.20] m 0.5 roll 255", AffixMath.roll_value(0.10, 0.20, "Hundredth", "INCREASED", 255, 0.5), 0.30)
	_check("affix [61,90] m 0.5 roll 0", AffixMath.roll_value(61, 90, "Integer", "ADDED", 0, 0.5), 92)
	_check("affix [61,90] m 0.5 roll 255", AffixMath.roll_value(61, 90, "Integer", "ADDED", 255, 0.5), 135)
	_check("effect_modifier 2H axe", AffixMath.effect_modifier(2.2, 0.75), 0.8286)
	_check("armour 1000 L50 phys", Enemy.armour_mitigation(1000, 50, false), 0.32390)
	_check("armour 1000 L50 non-phys", Enemy.armour_mitigation(1000, 50, true), 0.22673)
	_check("armour 3000 L75", Enemy.armour_mitigation(3000, 75, false), 0.53613)
	_check("armour -500 L75", Enemy.armour_mitigation(-500, 75, false), -0.19396)
	_check("tags Elemental vs Fire", 1.0 if LE.tags_match(LE.ELEMENTAL, LE.FIRE) else 0.0, 1.0)
	_check("tags Elemental|Spell vs Fire|Melee", 1.0 if LE.tags_match(LE.ELEMENTAL | LE.SPELL, LE.FIRE | LE.MELEE) else 0.0, 0.0)
	_check("level DR boss 75", Enemy.level_dr({"kind": "boss", "level": 75}), 0.7625)
	_check("level DR normal 50", Enemy.level_dr({"kind": "normal", "level": 50}), 0.54)

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

	# 06a T4 quotient
	_check("quotient 0.25", StatMod.make(LE.DAMAGE, "quotient", 0.25).more[0], -0.2)


func _sample_build() -> void:
	Build.set_class(1)  # Mage
	Build.set_level(100)
	print("--- Mage L100, no gear")
	var g: Dictionary = BuildMods.global_store(Build)
	for row: Dictionary in CharacterCalc.compute(g["store"], Build):
		if row["label"] in ["Здоровье", "Мана", "Интеллект", "Регенерация здоровья", "Избежание оглушения"]:
			print("  %s = %s" % [row["label"], row["text"]])
	_check("Mage L100 health 100+10·100", _row(g, "Здоровье"), 1100)
	_check("Mage L100 mana round(50+0.50506·100)", _row(g, "Мана"), 101)
	_check("Mage intelligence", _row(g, "Интеллект"), 3)

	# Unique: Snowblind (cold res 0.2–0.4, rollID 0) at roll 255 and roll 0
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	g = BuildMods.global_store(Build)
	_check("Snowblind cold res roll 255", Enemy.resistance(g["store"], 2).added, 0.40)
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [0, 255, 255]})
	g = BuildMods.global_store(Build)
	_check("Snowblind cold res roll 0 (fixed value)", Enemy.resistance(g["store"], 2).added, 0.20)
	_check("Snowblind special effects listed", 1.0 if str(g["notes"]).contains("Snowblind") else 0.0, 1.0)
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
	_check("Fireball fire hit 25 × 1.12", _section_value(r, "Урон за применение (до врага)", "Огонь"), 28.0)
	# Ignite (06d): 40% chance from the Fireball prefab, base 40 fire / 2.5 s, +12% generic damage from Int
	_check("Ignite chance", _section_value(r, "Айлмент: Ignite", "Шанс наложения"), 40.0)
	_check("Ignite stack damage 40 × 1.12", _section_value(r, "Айлмент: Ignite", "Полный урон одного стака"), 44.8)
	_check("Ignite DPS = uses × 0.4 × 44.8", _section_value(r, "Айлмент: Ignite", "DPS (без врага)"), 1.1 / 0.75 * 0.4 * 44.8, 0.01)
	_check("Ignite stacks = rate × 2.5", _section_value(r, "Айлмент: Ignite", "Стаков на цели в среднем"), 1.1 / 0.75 * 0.4 * 2.5, 0.01)
	# Carrion of Creation: SP 100 converts the Ignite chance into Bleed
	Build.set_item("gloves", {"unique": 431, "base": 4, "sub": 12, "implicit_rolls": [0, 0], "unique_rolls": [0, 0, 0, 0]})
	var conv_r: Dictionary = SkillCalc.compute(Build, 0)
	_check("Carrion: no Ignite left", 1.0 if _section_value(conv_r, "Айлмент: Ignite", "Шанс наложения") <= 0.0 else 0.0, 1.0)
	_check("Carrion: Bleed = 100% item + 40% converted", _section_value(conv_r, "Айлмент: Bleed", "Шанс наложения"), 140.0)
	Build.clear_item("gloves")
	# Oceareon SP 115: more damage per Shock stack on the target
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 10)
	var no_ring: float = _section_value(SkillCalc.compute(Build, 0), "Против врага", "DPS удара по врагу")
	Build.set_item("ring1", {"unique": 125, "base": 21, "sub": 2, "implicit_rolls": [0, 0], "unique_rolls": [0, 0, 0, 0, 0, 0]})
	var per_stack: float = 0.0
	for umod: Dictionary in GameData.unique(125)["mods"]:
		if int(umod["property"]) == LE.DAMAGE_PER_AILMENT_STACK:
			per_stack = AffixMath.unique_value(umod, 0)
	_check("Oceareon: ×(1 + per stack × 10 shocks)", _section_value(SkillCalc.compute(Build, 0), "Против врага", "DPS удара по врагу") / no_ring, 1.0 + per_stack * 10.0, 0.002)
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
		if section["title"] == "Урон за применение (до врага)":
			for row: Dictionary in section["rows"]:
				if row["label"] == "Огонь":
					aoe_breakdown = str(row["breakdown"])
	_check("Meteor: MeteorAoe base fire 240", 1.0 if aoe_breakdown.contains("База: 240") else 0.0, 1.0)
	_check("Meteor: fire damage >= 240", 1.0 if _section_value(r, "Урон за применение (до врага)", "Огонь") >= 240.0 else 0.0, 1.0)
	_check("Meteor: DPS in tooltip section > 0", 1.0 if _section_value(r, "DPS как в подсказке игры", "DPS") > 0.0 else 0.0, 1.0)
	_check("Meteor: DPS vs enemy > 0", 1.0 if _section_value(r, "Против врага", "DPS по врагу") > 0.0 else 0.0, 1.0)

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
					if mod.source.begins_with("Благословение"):
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
			if str(row["label"]).begins_with("DPS по врагу: Primal Wolf") or (str(row["label"]) == "DPS по врагу" and wolf_dps < 0.0):
				wolf_dps = float(str(row["text"]))
	print("--- Summon Wolf: %s" % str(r["sections"].map(func(x: Dictionary) -> String: return x["title"])))
	_check("Summon Wolf deals minion DPS", 1.0 if wolf_dps > 0.0 else 0.0, 1.0)
	_check("Summon Wolf declares the minions input", 1.0 if str(r.get("inputs", [])).contains("minions") else 0.0, 1.0)
	Build.set_skill(3, "")


## Special effects of uniques (unique_effect_models.json, docs/ENGINE.md §5.4.3).
func _unique_special_effects() -> void:
	var chill: int = GameData.enum_value("AilmentID", "Chill")
	# Snowblind PP 454: 24% more armour against chilled attackers (rollID 2 at 255), only while the enemy is chilled
	Build.set_item("helmet", {"unique": 2, "base": 0, "sub": 6, "implicit_rolls": [255, 255], "unique_rolls": [255, 255, 255]})
	var g: Dictionary = BuildMods.global_store(Build)
	_check("Snowblind armour more without chill", g["store"].query_untagged(LE.ARMOUR).more, 1.0)
	_check("Snowblind condition listed", 1.0 if str(g["notes"]).contains("учитывается при условии") else 0.0, 1.0)
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
	_check("Apostate's health = 2 × Vitality", per_vit, 2.0 * _row(g, "Живучесть"))
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
	_unique_skill_level_models()
	_all_uniques_smoke()


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
	var s: Dictionary = BuildMods.skill_store(Build, 0, g["store"])
	_check("global trigger reaches the skill result", float(s["triggers"].size()), 1.0)
	_check("global trigger is not a global stat", BuildMods.global_store(Build)["store"].query_untagged(LE.HEALTH).added, g["store"].query_untagged(LE.HEALTH).added - 2.0 * _row(g, "Живучесть"))
	_check("skill with a global trigger computes", 1.0 if not SkillCalc.compute(Build, 0)["sections"].is_empty() else 0.0, 1.0)
	player_models["285"] = {"kind": "param", "param": "projectiles", "label": "Тест-параметр", "mod": "added"}
	s = BuildMods.skill_store(Build, 0, g["store"])
	_check("global param row appears", 1.0 if s["params"].has("Тест-параметр") else 0.0, 1.0)
	player_models["285"] = {"kind": "flag", "text": "тестовый флаг"}
	g = BuildMods.global_store(Build)
	_check("flag effect is listed", 1.0 if str(g["notes"]).contains("тестовый флаг") else 0.0, 1.0)
	if had:
		player_models["285"] = old
	else:
		player_models.erase("285")
	Build.clear_item("amulet")
	Build.set_skill(0, "")


## Every unique, one at a time, with all player flags on: no script errors, count modelled effects.
func _all_uniques_smoke() -> void:
	const SLOT_BY_TYPE: Dictionary = {0: "helmet", 1: "body", 2: "belt", 3: "boots", 4: "gloves", 17: "offhand", 18: "offhand",
		19: "offhand", 20: "amulet", 21: "ring1", 22: "relic"}
	for key: String in EffectModels.PLAYER_FLAGS_RU:
		Build.set_player_state(key, true)
	for key: String in EffectModels.PLAYER_VALUES_RU:
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
	for key: String in EffectModels.PLAYER_FLAGS_RU:
		Build.set_player_state(key, false)
	for key: String in EffectModels.PLAYER_VALUES_RU:
		Build.set_player_state(key, 0)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Chill"), 0)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Bleed"), 0)
	Build.set_skill(0, "")


## Passive nodes into special lists (statsWhileDualWielding, statsWithWeaponRequirements, §5.2): conditions and sources.
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
	var wr_note: String = "Пассивка «%s» — учитывается при условии" % title
	_check("statsWithWeaponRequirements without a catalyst: condition note", 1.0 if str(g["notes"]).contains(wr_note) else 0.0, 1.0)
	Build.set_item("offhand", {"base": 19, "sub": 0, "implicit_rolls": [255, 255]})
	g = BuildMods.global_store(Build)
	var found: bool = false
	for mod: StatMod in g["store"].all_mods():
		if mod.source.begins_with("Пассивка «%s»" % title):
			found = true
	_check("statsWithWeaponRequirements with a catalyst: mod with the node title in the global store", 1.0 if found else 0.0, 1.0)
	Build.clear_item("offhand")
	g = BuildMods.global_store(Build)
	var dual_title: String = GameData.display_name(effects[dual_id])
	var dual_note: String = "Пассивка «%s» — учитывается при условии" % dual_title
	_check("statsWhileDualWielding without weapons: condition note", 1.0 if str(g["notes"]).contains(dual_note) else 0.0, 1.0)
	Build.set_item("weapon", {"base": 10, "sub": 1, "implicit_rolls": [255, 255]})
	Build.set_item("offhand", {"base": 10, "sub": 1, "implicit_rolls": [255, 255]})
	g = BuildMods.global_store(Build)
	var dual_found: bool = false
	for mod: StatMod in g["store"].all_mods():
		if mod.source.begins_with("Пассивка «%s»" % dual_title):
			dual_found = true
	_check("statsWhileDualWielding with two weapons: mod in the global store", 1.0 if dual_found else 0.0, 1.0)
	_check("statsWhileDualWielding with two weapons: no condition note", 0.0 if str(g["notes"]).contains(dual_note) else 1.0, 1.0)
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


## Idol altar (docs/ENGINE.md §5.4.1): altar grid, refracted slots, effect scaling and per-refracted-idol stats.
func _idol_altar() -> void:
	var saved: Dictionary = Build.items.duplicate(true)
	for slot: String in Build.items.keys():
		if IdolGrid.is_idol_key(slot) or slot == IdolGrid.ALTAR_SLOT:
			Build.items.erase(slot)
	_check("no altar: cell (1,0) not refracted", 1.0 if IdolGrid.is_refracted(1, 0, Build.items) else 0.0, 0.0)
	# Twisted Altar (sub 0): (1,0) is refracted (108), (1,1) open (4), (0,0) blocked (99)
	var affixes: Array = [{"id": 1089, "tier": 1, "roll": 255, "index": 0}, {"id": 1100, "tier": 1, "roll": 255, "index": 2}]
	Build.set_item(IdolGrid.ALTAR_SLOT, {"base": 41, "sub": 0, "implicit_rolls": [], "affixes": affixes})
	_check("altar grid: (1,0) refracted", 1.0 if IdolGrid.is_refracted(1, 0, Build.items) else 0.0, 1.0)
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
	Build.set_item(IdolGrid.key(1, 0), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": [entry]})
	var rolls: Array = idol_aff["tiers"][-1]["rolls"][0]
	var prop_id: int = int(idol_aff["properties"][0]["property"])
	var rounding: String = str(idol_aff["properties"][0].get("rounding", "Integer"))
	var aem: float = AffixMath.effect_modifier(float(GameData.item_base(25).get("affixEffectModifier", 0.0)), float(idol_aff.get("standardAffixEffectModifier", 0.0)))
	var plain: float = AffixMath.roll_value(float(rolls[0]), float(rolls[1]), rounding, "ADDED", 255, aem)
	var scaled: float = AffixMath.roll_value(float(rolls[0]), float(rolls[1]), rounding, "ADDED", 255, (1.0 + aem) * 1.08 - 1.0)
	var g: Dictionary = BuildMods.global_store(Build)
	var idol_total: float = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == prop_id and mod.source.contains(idol_aff["name"]):
			idol_total += mod.added
	_check("refracted idol affix scaled by 1+8%% (%s: %s -> %s)" % [idol_aff["name"], plain, scaled], idol_total, scaled)
	# Health per idol in a refracted slot: one idol in (1,0), another at (1,1) does not count
	Build.set_item(IdolGrid.key(1, 1), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": []})
	g = BuildMods.global_store(Build)
	var per_refracted: float = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == LE.HEALTH and mod.source.contains("Алтарь") and mod.source.contains("refracted-слоте") and not mod.source.contains("—"):
			per_refracted += mod.added
	_check("altar: +2 health per idol in a refracted slot (1 idol)", per_refracted, 2.0)
	# the same idol outside the altar's refracted slot is not scaled
	Build.clear_item(IdolGrid.key(1, 0))
	Build.set_item(IdolGrid.key(1, 1), {"base": 25, "sub": 0, "implicit_rolls": [], "affixes": [entry]})
	g = BuildMods.global_store(Build)
	idol_total = 0.0
	for mod: StatMod in g["store"].all_mods():
		if mod.property == prop_id and mod.source.contains(idol_aff["name"]):
			idol_total += mod.added
	_check("non-refracted idol affix unscaled", idol_total, plain)
	Build.items = saved
