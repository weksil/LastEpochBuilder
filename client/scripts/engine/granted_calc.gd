class_name GrantedCalc

## Granted skills (docs/ENGINE.md §9.6): skills the build casts through triggers (passives of the character mutator, uniques and
## affixes, skill tree nodes) that are not on the skill bar. Each is a "virtual slot" on the Calculations tab: a view of the
## component that the owning bar skill already counts (SkillCalc), so nothing is counted twice.

## Id of the basic attack entry (always listed; a real calculation on a temporary bar slot, not a view).
const BASIC_ID: String = "BasicPlayerAttack"
## `owner` of a granted skill that the basic attack triggers.
const BASIC_OWNER: int = -1
const BOW_ABILITY_KEY: String = "ba1_bow"


## Ability id of the basic attack for the equipped weapon: the bow attack with a bow in the main hand, else the melee one.
static func basic_ability_id(build: Node) -> String:
	var weapon: Dictionary = build.items.get("weapon", {})
	var bow: bool = not weapon.is_empty() and str(GameData.item_base(int(weapon.get("base", -1))).get("typeName", "")) == "BOW"
	if not bow:
		return "ba1"
	if GameData.get_ability(BOW_ABILITY_KEY).is_empty():
		GameData._abilities[BOW_ABILITY_KEY] = GameData.ability_by_name("BasicPlayerBowAttack")
	return BOW_ABILITY_KEY if not GameData.get_ability(BOW_ABILITY_KEY).is_empty() else "ba1"


## Runs `fn(slot)` with the basic attack on a temporary slot after the bar slots (removed afterwards), so SkillCalc computes it
## like a bar skill: the calculation caches are keyed by the bar contents, the slot is never seen by other calculations.
static func with_basic_slot(build: Node, fn: Callable) -> Variant:
	var skill: Dictionary = build.default_skill()
	skill["ability"] = basic_ability_id(build)
	skill["level"] = 1
	build.skills.append(skill)
	var out: Variant = fn.call(build.skills.size() - 1)
	build.skills.pop_back()
	return out


## Result of the owner of a granted skill: a bar slot, or the basic attack.
static func _owner_result(build: Node, owner: int, details: bool) -> Dictionary:
	if owner == BASIC_OWNER:
		return with_basic_slot(build, func(slot: int) -> Dictionary: return SkillCalc.compute(build, slot, details))
	return SkillCalc.compute(build, owner, details)


static func _owner_name(build: Node, owner: int) -> String:
	if owner == BASIC_OWNER:
		return LE.t("Basic attack")
	return GameData.display_name(GameData.get_ability(str(build.skills[owner].get("ability", ""))))


## Text of the selector entry and the title: «<name> (granted)», the basic attack without the suffix.
static func label(entry: Dictionary) -> String:
	return str(entry["name"]) if bool(entry.get("basic", false)) else LE.t("%s (granted)") % str(entry["name"])


## Virtual slots of the build: [{id (ability name), name, owner (first bar slot whose triggers cast it), owners (all of them)}].
## Taken from the lean results of the bar skills, so they match what the calculation sees.
static func skills(build: Node) -> Array[Dictionary]:
	var key: PackedByteArray = CalcCache.build_key(build)
	var hit: Variant = CalcCache.lookup("granted_skills", key)
	if hit == null:
		hit = _skills(build)
		CalcCache.put("granted_skills", key, hit)
	return (hit as Array[Dictionary]).duplicate(true)


static func _skills(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if build.class_id < 0 or GameData.get_ability("ba1").is_empty():
		return out
	out.append({"id": BASIC_ID, "name": LE.t("Basic attack"), "basic": true, "owner": BASIC_OWNER, "owners": []})
	var by_id: Dictionary = {}
	# bar slots first: the first of them is the owner shown, the basic attack comes last
	var owners: Array[int] = []
	for slot in range(build.skills.size()):
		if str((build.skills[slot] as Dictionary).get("ability", "")) != "":
			owners.append(slot)
	owners.append(BASIC_OWNER)
	for owner in owners:
		var result: Dictionary = _owner_result(build, owner, false)
		for ability_name: Variant in result.get("granted_names", []):
			var id: String = str(ability_name)
			if by_id.has(id):
				(by_id[id]["owners"] as Array).append(owner)
				continue
			var ab: Dictionary = GameData.ability_by_name(id)
			var entry: Dictionary = {"id": id, "name": GameData.display_name(ab), "owner": owner, "owners": [owner]}
			by_id[id] = entry
			out.append(entry)
	return out


## Slot-like calculation of a granted skill by its id: SkillCalc.compute-shaped result ({title, sections, notes, inputs, hits,
## virtual_id, input_slot}). Empty (no sections) if the build no longer casts it. The rate and the numbers are those of its
## component inside the owning bar skill; `inputs` are the event rates of the owner (events_*), edited on the owner's slot.
static func compute(build: Node, id: String, details: bool = true) -> Dictionary:
	var key: Array = [CalcCache.build_key(build), id, EnemyAilments.enabled, EnemyAilments._busy, MinionCount._busy, details]
	var hit: Variant = CalcCache.lookup("granted_calc", key)
	if hit == null:
		hit = _compute(build, id, details)
		CalcCache.put("granted_calc", key, hit)
	return (hit as Dictionary).duplicate(true)


static func _compute(build: Node, id: String, details: bool) -> Dictionary:
	var result: Dictionary = {"title": "", "sections": [], "notes": [], "inputs": [], "hits": 1.0, "virtual_id": id}
	var entry: Dictionary = {}
	for candidate: Dictionary in skills(build):
		if str(candidate["id"]) == id:
			entry = candidate
			break
	if entry.is_empty():
		return result
	if bool(entry.get("basic", false)):
		return _compute_basic(build, details)
	var owner: int = int(entry["owner"])
	var owner_result: Dictionary = _owner_result(build, owner, details)
	var name: String = str(entry["name"])
	var owner_name: String = _owner_name(build, owner)
	result["title"] = label(entry)

	var parts: Array[Dictionary] = []
	var rate: float = 0.0
	var hit_dps: float = 0.0
	var ail_dps: float = 0.0
	var notes_of_rate: PackedStringArray = []
	for part: Dictionary in owner_result.get("granted", []):
		if str(part["ability"]) != id:
			continue
		parts.append(part)
		rate += float(part["rate"])
		hit_dps += float(part["hit_enemy"])
		ail_dps += float(part["ail_dps"])
		if str(part["note"]) != "":
			notes_of_rate.append(str(part["note"]))

	var sections: Array = [_header(build, entry, owner_name, rate, notes_of_rate, parts.is_empty())]
	var base: Dictionary = {}
	for section: Dictionary in owner_result.get("sections", []):
		if str(section.get("granted", "")) != id:
			continue
		var copy: Dictionary = {"title": str(section["title"]).trim_prefix(str(section.get("strip", ""))), "rows": section["rows"]}
		if base.is_empty() and copy["title"] == LE.t("Against enemy"):
			base = copy
		sections.append(copy)
	var target_row: Dictionary = CalcSummary.find_row(owner_result, "Target", "Against enemy")
	if base.is_empty():
		var first_main: bool = false
		for section: Dictionary in owner_result.get("sections", []):
			if str(section.get("granted_main", "")) == id:
				# the component is the first one of the owner (it deals no damage itself): its rows follow the target row
				var main_rows: Array = section["rows"]
				var count: int = 1 + int(parts[0]["enemy_rows"]) if not parts.is_empty() else 1
				base = {"title": LE.t("Against enemy"), "rows": main_rows.slice(0, count)}
				first_main = true
				break
		if not first_main:
			base = {"title": LE.t("Against enemy"), "rows": [target_row] if not target_row.is_empty() else []}
		sections.append(base)
	elif not target_row.is_empty():
		(base["rows"] as Array).push_front(target_row)
	var rows: Array = base["rows"]
	if ail_dps > 0.0:
		rows.append({"label": LE.t("Ailment DPS vs enemy"), "text": LE.fmt_num(ail_dps), "breakdown": LE.t("Sum of the DPS of all ailments vs enemy (the \"Ailment: …\" sections).")})
	rows.append({"label": LE.t("DPS vs enemy"), "text": LE.fmt_num(hit_dps + ail_dps), "value": hit_dps + ail_dps, "breakdown":
		LE.t("Hit %s + ailments %s = %s") % [LE.fmt_num(hit_dps), LE.fmt_num(ail_dps), LE.fmt_num(hit_dps + ail_dps)]})
	result["sections"] = sections

	# notes of the owner that name this skill
	for n: Variant in owner_result.get("notes", []):
		if str(n).contains(name) and not (result["notes"] as Array).has(n):
			(result["notes"] as Array).append(n)
	# the event rates the owner reads for its triggers are edited on the owner's slot
	var inputs: Array = []
	for inp: Dictionary in owner_result.get("inputs", []) if owner != BASIC_OWNER else []:
		if str(inp.get("key", "")).begins_with("events_"):
			inputs.append(inp)
	result["inputs"] = inputs
	result["input_slot"] = owner if owner != BASIC_OWNER else -1
	if not details:
		SkillCalc._make_lean(result)
	return result


## The basic attack: a full calculation on a temporary slot. It is not on the bar and adds nothing to the bar skills' totals; its
## own event inputs and hits are not editable (nothing stores them), the defaults are used.
static func _compute_basic(build: Node, details: bool) -> Dictionary:
	var result: Dictionary = with_basic_slot(build, func(slot: int) -> Dictionary: return SkillCalc.compute(build, slot, details))
	result["title"] = LE.t("Basic attack")
	result["virtual_id"] = BASIC_ID
	result["inputs"] = []
	var info: Dictionary = {"title": LE.t("Basic attack"), "rows": [
		{"label": LE.t("Skill"), "text": LE.t("Basic attack"), "breakdown": LE.t("The attack every character has: weapon damage, attack speed of the equipped weapon (a bow attack with a bow). It is not on the skill bar and is not part of any bar skill's DPS. Skill level 1; hits and event rates use defaults.")},
	]}
	(result["sections"] as Array).push_front(info)
	if not details:
		SkillCalc._make_lean(result)
	return result


## First section: where the number is counted, the trigger rate, and the skill level.
static func _header(build: Node, entry: Dictionary, owner_name: String, rate: float, rate_notes: PackedStringArray, no_component: bool) -> Dictionary:
	var owner: int = int(entry["owner"])
	var owners: PackedStringArray = []
	for slot: Variant in entry["owners"]:
		owners.append(LE.t("basic attack") if int(slot) == BASIC_OWNER else str(int(slot) + 1))
	var counted: String = LE.t("This skill is not on the skill bar. Its damage is already counted inside the calculation of %s (\"%s\") as a triggered component; this entry is a view of that component with its own breakdown and does not add anything to the totals (nothing is counted twice).") % [LE.t("bar slot %d") % (owner + 1) if owner != BASIC_OWNER else LE.t("the basic attack"), owner_name]
	if owner == BASIC_OWNER:
		counted = LE.t("This skill is not on the skill bar and no bar skill casts it: only the basic attack does, and the basic attack is not part of any bar skill's DPS. The numbers below are not included in the totals of the bar skills.")
	if owners.size() > 1:
		counted += LE.t("\nThe same skill is also triggered by bar slots: %s (shown for the first one only).") % ", ".join(owners.slice(1))
	var uses_text: String = "\n".join(rate_notes) if not rate_notes.is_empty() else LE.t("No trigger events per second: set the event rate in the parameters below (the rate is read by the owning skill).")
	var rows: Array = [
		{"label": LE.t("Counted in"), "text": ("%d. %s" % [owner + 1, owner_name]) if owner != BASIC_OWNER else owner_name, "breakdown": counted},
		{"label": LE.t("Uses per second"), "text": LE.fmt_num(rate), "breakdown": uses_text},
		{"label": LE.t("Skill level"), "text": "1", "breakdown":
			LE.t("A granted skill has no skill tree and no level of its own in the build: the ability's base damage (level 1) is used, as in the owning skill's calculation. The game data gives no other level for granted casts.")},
	]
	if no_component:
		rows.append({"label": LE.t("Damage"), "text": "0", "breakdown": LE.t("The trigger fires 0 times per second now, so the owning skill has no component for it.")})
	return {"title": LE.t("Granted skill"), "rows": rows}
