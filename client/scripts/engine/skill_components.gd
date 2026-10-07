class_name SkillComponents

## Damage components of a skill: the primary hit, sub-abilities spawned by the prefab, damage computed in code,
## tree/unique components and triggers (docs/ENGINE.md §9.3).
## component = {name, kind: primary|sub|trigger|minion|curse_hit|dot, ab, base, per_use, rate, note}.
## `curse_hit` (Bone Curse): damage dealt to the cursed enemy whenever it is hit, not per cast. `rate` is the weighted
## hit rate (own hits × (1 + moreDamageWhenHitByCreator) + other hits), `hit_rate` the plain hits per second.
## `dot` (Spirit Plague): a single maintained DoT instance (maxInstances 1) whose `base` damage is the TOTAL over the base
## `duration`; `rate` = 1 / duration damage events per second, `duration_inc` the increased duration of the skill.
## Several sources of the same sub-ability (prefab + tree node «explodes at end») are merged into one component with the
## summed `per_use` (the game counts detonations = 1 + extras, research/07h TransplantMutator.explodesAtEnd).

const SUB_REASONS: Array[String] = [
	"prefab:CreateAbilityObjectOnDeath", "prefab:CreateAbilityObjectOnStart", "prefab:CastAfterDuration",
]
const TYPE_ORDER: Array[String] = ["Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison"]
## Skill inputs of the curse-hit component: your hits on the cursed target per second (default: estimate from the bar),
## hits of minions and allies per second.
const CURSE_OWN_KEY: String = "curse_own_hits"
const CURSE_OTHER_KEY: String = "curse_other_hits"


static func collect(build: Node, slot: int, ab: Dictionary, s: Dictionary, out_notes: Array[String] = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ab_name: String = str(ab.get("name", ""))
	var primary: Dictionary = ab.get("primaryDamage", {}) if ab.get("primaryDamage") is Dictionary else {}
	if not primary.is_empty():
		result.append(_component(str(ab.get("abilityName", ab_name)), "primary", ab, primary, 1.0, 0.0, ""))

	for sub: Dictionary in GameData.sub_abilities(ab_name):
		if not _is_spawned(str(sub.get("spawn_reason", ""))) or _not_per_use(sub, ab_name):
			continue
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			continue
		_add_sub(result, str(sub.get("name", "")), sub, entry, 1.0, str(sub.get("spawn_reason", "")).trim_prefix("prefab:"))

	if primary.is_empty():
		_add_code_damage(result, build, slot, s, ab_name, ab, out_notes)

	for extra: Variant in s.get("components", []):
		if not extra is Dictionary:
			continue
		var sub: Dictionary = GameData.ability_by_name(str(extra.get("ability", "")))
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			_skip_note(out_notes, LE.t("Node \"%s\": sub-skill \"%s\" has no damage — not counted.") % [extra.get("node", "?"), extra.get("ability", "?")])
			continue
		_add_sub(result, str(sub.get("name", "")), sub, entry, float(extra.get("count", 1.0)), LE.t("node \"%s\"") % extra.get("node", ""))

	for trig: Variant in s.get("triggers", []):
		if not trig is Dictionary:
			continue
		# a triggered skill that is specialized on the bar is computed through its own slot (tree, triggers, ailments)
		var t_slot: int = bar_slot_of(build, slot, str(trig.get("ability", "")))
		if t_slot >= 0:
			if float(trig.get("rate", 0.0)) > 0.0:
				var t_ab: Dictionary = GameData.get_ability(str(build.skills[t_slot]["ability"]))
				var t_comp: Dictionary = _component(str(trig.get("label", GameData.display_name(t_ab))), "skill", t_ab, {}, 1.0,
					float(trig["rate"]), str(trig.get("note", "")))
				t_comp["slot"] = t_slot
				t_comp["single_projectile"] = bool(trig.get("single_projectile", false))
				result.append(t_comp)
			continue
		var sub: Dictionary = GameData.ability_by_name(str(trig.get("ability", "")))
		var entry: Dictionary = _first_damage(sub)
		if entry.is_empty():
			_skip_note(out_notes, LE.t("Trigger \"%s\": skill \"%s\" has no damage — not counted.") % [trig.get("label", "?"), trig.get("ability", "?")])
			continue
		var rate: float = float(trig.get("rate", 0.0))
		if rate <= 0.0:
			continue
		var label: String = str(trig.get("label", ""))
		result.append(_component(label if label != "" else str(sub.get("name", "")), "trigger", sub, entry, 1.0, rate, str(trig.get("note", label))))

	# minions summoned by the skill (§9.4): own stores built from the player's snapshot
	if (not MinionCalc.minions_for(ab_name).is_empty() or MinionCount.GROUPS.has(ab_name)) and s.get("store") is StatStore:
		# the number of each minion is set on the Conditions tab (MinionCount), the summon limit by default
		result.append_array(MinionCalc.components(s["store"], ab, s.get("minion_mods", []), build, s.get("minion_actor_mods", {})))
	return result


## Bar slot (other than `slot`) whose skill is the ability named `ability_name` (record `name`), -1 if none.
static func bar_slot_of(build: Node, slot: int, ability_name: String) -> int:
	if ability_name == "":
		return -1
	for i in range(build.skills.size()):
		if i != slot and str(GameData.get_ability(str(build.skills[i].get("ability", ""))).get("name", "")) == ability_name:
			return i
	return -1


static func _component(comp_name: String, kind: String, ab: Dictionary, base: Dictionary, per_use: float, rate: float, note: String) -> Dictionary:
	return {"name": comp_name, "kind": kind, "ab": ab, "base": base, "per_use": per_use, "rate": rate, "note": note}


## Sub-ability component per cast. A second source of the same ability (prefab, tree node) adds to the existing component's
## `per_use` instead of creating a duplicate one: the damage is dealt `per_use` times per cast, shown once.
static func _add_sub(result: Array[Dictionary], comp_name: String, sub: Dictionary, entry: Dictionary, per_use: float, note: String) -> void:
	for existing: Dictionary in result:
		var same: bool = existing["kind"] == "sub" and float(existing["rate"]) <= 0.0 and str(existing["name"]) == comp_name
		if same and str(existing["ab"].get("name", "")) == str(sub.get("name", "")):
			existing["per_use"] = float(existing["per_use"]) + per_use
			if note != "" and not str(existing["note"]).contains(note):
				existing["note"] = note if str(existing["note"]) == "" else "%s; %s" % [existing["note"], note]
			return
	result.append(_component(comp_name, "sub", sub, entry, per_use, 0.0, note))


static func _is_spawned(reason: String) -> bool:
	for r: String in SUB_REASONS:
		if reason.begins_with(r):
			return true
	return false


## A linked sub-ability that is not dealt on every use: the alternate ability of CastAfterDuration (Flay 2 Damage replaces
## Flay 1 Damage on the combo's second use, one of them per use), or one spawned through another linked record that the
## prefab casts only on kill (Flay Blood Explosion via the ChanceToCastOnKill delayer).
static func _not_per_use(sub: Dictionary, ab_name: String) -> bool:
	if str(sub.get("spawn_reason", "")) == "prefab:CastAfterDuration.alternateAbility":
		return true
	for parent: Variant in sub.get("parents", []):
		if str(parent) == ab_name:
			continue
		for reason: Variant in GameData.ability_by_name(str(parent)).get("reasons", []):
			if str(reason).begins_with("prefab:ChanceToCastOnKill"):
				return true
	return false


## First entry of a record's `damage` list (same shape as primaryDamage), {} if none.
static func _first_damage(rec: Dictionary) -> Dictionary:
	var list: Array = rec.get("damage", [])
	if list.is_empty() or not list[0] is Dictionary:
		return {}
	return list[0]


static func _skip_note(out_notes: Array[String], text: String) -> void:
	if not out_notes.has(text):
		out_notes.append(text)


## Components of abilities_code_damage.json with plain numbers; the rest are only reported in the notes.
static func _add_code_damage(result: Array[Dictionary], build: Node, slot: int, s: Dictionary, ab_name: String, ab: Dictionary,
		out_notes: Array[String]) -> void:
	var code: Dictionary = GameData.code_damage(ab_name)
	for comp: Dictionary in code.get("components", []):
		var id: String = str(comp.get("id", "")) if comp.get("id") != null else ""
		var label: String = id if id != "" else ab_name
		if not comp.get("damage") is Dictionary or (comp["damage"] as Dictionary).is_empty():
			continue
		# a zone that applies ailments every interval (Aura of Decay's poison): counted from the prefab by SkillCalc
		if str(comp.get("source", "")).begins_with("RepeatedlyApplyAilmentsInRadius"):
			continue
		var damage: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var numeric: bool = true
		for type_name: String in comp["damage"]:
			var v: Variant = comp["damage"][type_name]
			var idx: int = TYPE_ORDER.find(type_name)
			if (v is float or v is int) and idx >= 0:
				damage[idx] = float(v)
			else:
				numeric = false
		if not numeric:
			_skip_note(out_notes, LE.t("Damage \"%s\" of skill \"%s\" is computed by code from node values, not a plain number — not counted.") % [label, ab_name])
			continue
		var ade_v: Variant = comp.get("ADE")
		var crit_v: Variant = comp.get("crit")
		var hit_v: Variant = comp.get("isHit")
		var is_hit: bool = bool(hit_v) if hit_v != null else crit_v is Dictionary
		var base: Dictionary = {
			"damage": damage, "critChance": 0.0, "critMultiplier": 1.0, "critType": 1,
			"addedDamageScaling": float(ade_v) if (ade_v is float or ade_v is int) else 0.0,
			"isHit": 1 if is_hit else 0, "go": "",
		}
		if crit_v is Dictionary:
			base["critChance"] = float(crit_v.get("chance", 0.0))
			base["critMultiplier"] = float(crit_v.get("multiplier", 1.0))
			base["critType"] = 0
		var creator_more: Variant = comp.get("moreDamageWhenHitByCreator")
		if creator_more is float or creator_more is int:
			result.append(_curse_hit_component(build, slot, s, label, ab, base, 1.0 + float(creator_more), out_notes))
			continue
		var dur_v: Variant = comp.get("duration")
		var max_v: Variant = comp.get("maxInstances")
		if not is_hit and (dur_v is float or dur_v is int) and float(dur_v) > 0.0 and (max_v is float or max_v is int) and int(max_v) == 1:
			result.append(_dot_component(s, label, ab, base, float(dur_v)))
			continue
		result.append(_component(label, "sub", ab, base, 1.0, 0.0, LE.t("damage by code (abilities_code_damage.json)")))


## Maintained DoT (one instance per target, maxInstances 1): `base` damage is the total over the base duration, the instance is
## kept up by recasting, so there is one damage event per base duration (100% uptime assumed). An increased duration lengthens
## the instance and raises its total by the same factor (damage over time scales with duration in LE), so the damage per second does
## not change; `duration_inc` (param «duration» of the skill tree) is only shown (docs/ENGINE.md §9.3).
static func _dot_component(s: Dictionary, label: String, ab: Dictionary, base: Dictionary, duration: float) -> Dictionary:
	var inc: float = 0.0
	var params: Variant = s.get("params", {})
	if params is Dictionary:
		for key: Variant in params:
			var p: Dictionary = params[key]
			if str(p.get("param", "")) == "duration":
				inc += float(p.get("increased", 0.0))
	var comp: Dictionary = _component(label, "dot", ab, base, 1.0, 1.0 / duration, LE.t("periodic damage of one instance (abilities_code_damage.json)"))
	comp["duration"] = duration
	comp["duration_inc"] = inc
	return comp


## True if the skill deals hit damage by itself: a primary hit, a sub-ability spawned by the prefab or a code hit that is not
## a curse hit. Used for the estimate of your hits on a cursed target (SkillCalc.curse_own_hits_estimate).
static func deals_hit_damage(ab: Dictionary) -> bool:
	var primary: Variant = ab.get("primaryDamage")
	if primary is Dictionary and not (primary as Dictionary).is_empty():
		return int(primary.get("isHit", 1)) == 1
	for sub: Dictionary in GameData.sub_abilities(str(ab.get("name", ""))):
		if not _is_spawned(str(sub.get("spawn_reason", ""))):
			continue
		var entry: Dictionary = _first_damage(sub)
		if not entry.is_empty() and int(entry.get("isHit", 1)) == 1:
			return true
	for comp: Dictionary in GameData.code_damage(str(ab.get("name", ""))).get("components", []):
		if comp.get("moreDamageWhenHitByCreator") == null and comp.get("damage") is Dictionary and bool(comp.get("isHit", false)):
			return true
	return false


## Curse component: damage dealt to the cursed enemy on every hit it takes (ailment dealsDamageWhenHit). Declares the inputs
## «your hits» and «hits of minions and allies»; the rate is own × (1 + moreDamageWhenHitByCreator) + other (docs/ENGINE.md §9.3).
static func _curse_hit_component(build: Node, slot: int, s: Dictionary, label: String, ab: Dictionary, base: Dictionary,
		own_mult: float, out_notes: Array[String]) -> Dictionary:
	var inputs: Dictionary = {}
	if slot >= 0 and slot < build.skills.size():
		inputs = build.skills[slot].get("inputs", {})
	var global: StatStore = (s["store"] as StatStore).parent if s.get("store") is StatStore else null
	# the estimate is only the default of the input and its note: skipped while the user's value overrides it and nothing declares the input
	var estimate: Dictionary = {}
	if not inputs.has(CURSE_OWN_KEY) or s.get("inputs") is Array:
		estimate = SkillCalc.curse_own_hits_estimate(build, slot, global)
	var own: float = float(inputs.get(CURSE_OWN_KEY, estimate.get("rate", 0.0)))
	var other: float = float(inputs.get(CURSE_OTHER_KEY, 0.0))
	if s.get("inputs") is Array:
		_declare_input(s["inputs"], {"key": CURSE_OWN_KEY, "label": LE.t("Your hits on the cursed target per second (by other skills)"), "default": float(estimate["rate"])})
		_declare_input(s["inputs"], {"key": CURSE_OTHER_KEY, "label": LE.t("Hits of minions and allies on the cursed target per second"), "default": 0.0})
	var weighted: float = own * own_mult + other
	var hits: float = own + other
	var b: PackedStringArray = []
	b.append(LE.t("The curse hits the target every time it is hit (by any source); casting it deals no damage itself, recasting only refreshes the curse."))
	if inputs.has(CURSE_OWN_KEY):
		b.append(LE.t("Your hits on the cursed target: %s/s (set on the Calculations tab).") % LE.fmt_num(own))
	else:
		b.append(LE.t("Your hits on the cursed target: %s/s (estimate from the skill bar: %s).") % [LE.fmt_num(own), "; ".join(estimate["lines"]) if not estimate["lines"].is_empty() else LE.t("no other skills with hit damage")])
	b.append(LE.t("Hits of minions and allies: %s/s.") % LE.fmt_num(other))
	b.append(LE.t("Your hits deal ×%s more (moreDamageWhenHitByCreator %s + 1): damage events = %s × %s + %s = %s per second.") % [
		LE.fmt_num(own_mult), LE.fmt_num(own_mult - 1.0), LE.fmt_num(own), LE.fmt_num(own_mult), LE.fmt_num(other), LE.fmt_num(weighted)])
	b.append(LE.t("Hits on the target per second (for ailment chances): %s + %s = %s.") % [LE.fmt_num(own), LE.fmt_num(other), LE.fmt_num(hits)])
	b.append(LE.t("The number of hits per use is not used."))
	if weighted <= 0.0:
		_skip_note(out_notes, LE.t("Curse \"%s\": 0 hits on the target per second — set the hit rate on the Calculations tab.") % label)
	var comp: Dictionary = _component(label, "curse_hit", ab, base, 1.0, weighted, LE.t("curse damage when the target is hit (abilities_code_damage.json)"))
	comp["hit_rate"] = hits
	comp["event_text"] = "\n".join(b)
	return comp


static func _declare_input(inputs: Array, inp: Dictionary) -> void:
	for existing: Variant in inputs:
		if existing is Dictionary and existing.get("key") == inp["key"]:
			return
	inputs.append(inp)
