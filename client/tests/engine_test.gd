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
	_passive_field_models()
	_buff_skills()
	_buff_skill_base_models()
	_sustain()
	_curse_hits()
	_high_health_vs_dummy()
	_detonations_and_maintained_dot()
	_item_compare()
	_projectiles()
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
	_check("block 1000 L50", CharacterCalc.block_mitigation(1000, 50), 0.45132)
	_check("block 2000 L75", CharacterCalc.block_mitigation(2000, 75), 0.54069)
	_check("block 500 L100", CharacterCalc.block_mitigation(500, 100), 0.26428)
	_check("fmt_pct 9.8298%", 1.0 if LE.fmt_pct(0.098298) == "9.83%" else 0.0, 1.0)
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
	_check("Summon Wolf declares the minions input", 1.0 if str(r.get("inputs", [])).contains("minions") else 0.0, 1.0)
	Build.set_skill(3, "")


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
	_check("global trigger is not a global stat", BuildMods.global_store(Build)["store"].query_untagged(LE.HEALTH).added, g["store"].query_untagged(LE.HEALTH).added - 2.0 * _row(g, "Vitality"))
	_check("skill with a global trigger computes", 1.0 if not SkillCalc.compute(Build, 0)["sections"].is_empty() else 0.0, 1.0)
	player_models["285"] = {"kind": "param", "param": "projectiles", "label": "Test parameter", "mod": "added"}
	s = BuildMods.skill_store(Build, 0, g["store"])
	_check("global param row appears", 1.0 if s["params"].has("Test parameter") else 0.0, 1.0)
	player_models["285"] = {"kind": "flag", "text": "test flag"}
	g = BuildMods.global_store(Build)
	_check("flag effect is listed", 1.0 if "\n".join(PackedStringArray(g["notes"])).contains("test flag") else 0.0, 1.0)
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
	var scaled: float = AffixMath.roll_value(float(rolls[0]), float(rolls[1]), rounding, "ADDED", 255, (1.0 + aem) * 1.08 - 1.0)
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
	Build.items = saved


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
	_check("Transplant: no duplicate per-component DPS rows", _count_rows(r, "Against enemy", "DPS vs enemy: DetonateBody"), 0.0)
	var avg: float = _section_value(r, "Against enemy", "Average hit vs enemy")
	var ail: float = _section_value(r, "Against enemy", "Ailment DPS vs enemy")
	# the sample build has «Reign of Blood» (explodes at arrival): the prefab detonation + 1 extra per cast
	_check("Transplant: 2 detonations per cast with the node", _section_value(r, HEAD, "Damage events per second"), uses * 2.0, 0.005)
	_check("Transplant: hit DPS = average hit × casts/s × 2", _section_value(r, "Against enemy", "Hit DPS vs enemy"), avg * uses * 2.0, 0.05)
	_check("Transplant: DPS = hit DPS + ailments once", _section_value(r, "Against enemy", "DPS vs enemy"), avg * uses * 2.0 + ail, 0.05)
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
