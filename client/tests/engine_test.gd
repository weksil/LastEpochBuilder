extends Node

## Headless engine check: test vectors from research/06a–06c, 07a and a sample build.
## Run: Godot_console.exe --headless --path client res://tests/engine_test.tscn

var _failed: int = 0


func _ready() -> void:
	_vectors()
	_sample_build()
	print("ENGINE TEST: %s" % ("OK" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, got: float, want: float, eps: float = 0.0005) -> void:
	if absf(got - want) > eps:
		_failed += 1
		print("FAIL %s: got %s, want %s" % [label, got, want])
	else:
		print("ok   %s = %s" % [label, got])


func _vectors() -> void:
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
