class_name EchoCalc

## Void Knight echoes (docs/ENGINE.md §9.10): a use of a melee attack, throwing attack or void spell is repeated 1 second
## later with a chance (CharacterMutator.TryToEchoAbility, research: game code). The skill gets an «Echo: …» damage
## component with per_use × chance, computed on the skill store of an echoed use («use:echo» models) plus the echo mods.
## Chance: CharacterMutator.chanceToRepeatMeleeThrowingAttacksAndVoidSpells (Void Knight mastery 10%, passives);
## Rive × (1 + echoChanceModifierWithRive); Vengeance + additionalEchoChanceWithVengeance and Abyssal Echoes
## + abyssalEchoesAdditionalEchoChance (only when the chance is already above 0); the skill tree param «echo_chance».
## Eligible: tags Melee, Throwing or Void + Spell; not a movement skill (Void Cleave is), not Anomaly, not channelled
## (Warpath only with its node «Warpath can echo»). Echo mods: increased damage (PlayerProperty 57 «increased Echo
## Damage»), Rive more (moreEchoDamageWithRive), Time Rot chance (echoTimeRotChance).

const CHANCE_FIELD: String = "CharacterMutator.chanceToRepeatMeleeThrowingAttacksAndVoidSpells"
const RIVE_FIELD: String = "CharacterMutator.echoChanceModifierWithRive"
const ADDED_BY_ABILITY: Dictionary = {
	"Vengeance": "CharacterMutator.additionalEchoChanceWithVengeance",
	"AbyssalEchoes": "CharacterMutator.abyssalEchoesAdditionalEchoChance",
}
const RIVE_MORE_FIELD: String = "CharacterMutator.moreEchoDamageWithRive"
const TIME_ROT_FIELD: String = "CharacterMutator.echoTimeRotChance"
const ECHO_DAMAGE_PP: int = 57
const MOVEMENT_ALLOWED: Array[String] = ["VoidCleave"]
const NEVER: Array[String] = ["Anomaly"]
const CHANNEL_FLAG: String = "Warpath can echo repeat"


## Sum of a CharacterMutator field over the taken passives and the mastery bonus: {value, lines}.
static func passive_field(build: Node, target: String) -> Dictionary:
	var lines: PackedStringArray = []
	var total: float = 0.0
	var tree_id: String = str(GameData.get_passive_tree(build.class_id).get("treeID", ""))
	var effects: Dictionary = GameData.passive_effects(tree_id)
	var nodes: Array[Array] = []
	for node_id: Variant in build.passives:
		var points: int = int(build.passives[node_id])
		if points > 0 and effects.has(int(node_id)):
			nodes.append([effects[int(node_id)], points])
	var bonus: Dictionary = GameData.mastery_bonus(tree_id, int(build.mastery))
	if not bonus.is_empty():
		nodes.append([bonus, 1])
	for entry: Array in nodes:
		var node: Dictionary = entry[0]
		var points: int = entry[1]
		for effect: Dictionary in node.get("effects", []):
			if str(effect.get("target", "")) != target or not effect.has("value") or points < int(effect.get("minPoints", 0)):
				continue
			var v: float = BuildMods.eval_value(effect["value"], points)
			if v != 0.0:
				total += v
				lines.append(LE.t("Passive \"%s\" ×%d: %s") % [str(node.get("displayName", "")), points, LE.fmt_num(v)])
	return {"value": total, "lines": lines}


static func eligible(ab: Dictionary, s: Dictionary) -> bool:
	var name: String = str(ab.get("name", ""))
	if NEVER.has(name):
		return false
	var tags: int = int(ab.get("tags", 0))
	if not ((tags & LE.MELEE) != 0 or (tags & LE.THROWING) != 0 or ((tags & LE.VOID) != 0 and (tags & LE.SPELL) != 0)):
		return false
	if bool(ab.get("countsAsMovementAbility", 0)) and not MOVEMENT_ALLOWED.has(name):
		return false
	if bool(ab.get("channelled", 0)) and not (s.get("flags", []) as Array).has(CHANNEL_FLAG):
		return false
	return true


## Echo chance of a skill: {value, lines}.
static func chance(build: Node, ab: Dictionary, s: Dictionary) -> Dictionary:
	var base: Dictionary = passive_field(build, CHANCE_FIELD)
	var v: float = float(base["value"])
	var lines: PackedStringArray = base["lines"]
	var name: String = str(ab.get("name", ""))
	if name.begins_with("Rive"):
		var rive: Dictionary = passive_field(build, RIVE_FIELD)
		if float(rive["value"]) != 0.0:
			v *= 1.0 + float(rive["value"])
			lines.append(LE.t("Rive: × (1 + %s)") % LE.fmt_num(float(rive["value"])))
	if ADDED_BY_ABILITY.has(name) and v > 0.0:
		var add: Dictionary = passive_field(build, ADDED_BY_ABILITY[name])
		v += float(add["value"])
		lines.append_array(add["lines"])
	var params: Variant = s.get("params", {})
	if params is Dictionary:
		for label: Variant in params:
			var p: Dictionary = params[label]
			if str(p.get("param", "")) != "echo_chance":
				continue
			var added: float = float(p["set"]) if p.get("set") != null else float(p.get("added", 0.0))
			var factor: float = (1.0 + float(p.get("increased", 0.0))) * float(p.get("more", 1.0))
			v = (v + added) * factor
			lines.append("%s: +%s, ×%s" % [label, LE.fmt_num(added), LE.fmt_num(factor)])
	return {"value": clampf(v, 0.0, 1.0), "lines": lines}


## Mods of an echoed use.
static func echo_mods(build: Node, ab: Dictionary) -> Array[StatMod]:
	var out: Array[StatMod] = []
	var inc: float = 0.0
	var inc_lines: PackedStringArray = []
	for slot: String in build.items:
		if not (BuildMods.SLOTS.has(slot) or IdolGrid.is_idol_key(slot)):
			continue
		for mod: StatMod in ItemMods.item_mods(slot, build.items[slot]):
			if mod.property == LE.PLAYER_PROPERTY and mod.tags == ECHO_DAMAGE_PP:
				inc += mod.added
				inc_lines.append("%s: %s" % [mod.source, LE.fmt_pct(mod.added)])
	for e: Dictionary in UniqueEffects.entries(build):
		if int(e["effect"].get("ppIndex", -1)) == ECHO_DAMAGE_PP and str(e["effect"].get("source", "")) == "PlayerProperty":
			inc += float(e["pp"])
			inc_lines.append("%s: %s" % [e["label"], LE.fmt_pct(float(e["pp"]))])
	if inc != 0.0:
		out.append(StatMod.make(LE.DAMAGE, "increased", inc, 0, LE.t("Increased echo damage (%s)") % "; ".join(inc_lines)))
	if str(ab.get("name", "")).begins_with("Rive"):
		var rive: Dictionary = passive_field(build, RIVE_MORE_FIELD)
		if float(rive["value"]) != 0.0:
			out.append(StatMod.make(LE.DAMAGE, "more", float(rive["value"]), 0, LE.t("Echo of Rive (%s)") % "; ".join(rive["lines"])))
	var rot: Dictionary = passive_field(build, TIME_ROT_FIELD)
	if float(rot["value"]) != 0.0:
		out.append(StatMod.make(LE.AILMENT_CHANCE, "added", float(rot["value"]), 0, LE.t("Time Rot chance of echoes (%s)") % "; ".join(rot["lines"]),
			GameData.enum_value("AilmentID", "TimeRot")))
	return out


## Echo components of a skill ([] when it cannot echo or the chance is 0).
static func components(build: Node, slot: int, ab: Dictionary, global: StatStore, base_components: Array[Dictionary],
		s: Dictionary) -> Array[Dictionary]:
	if not eligible(ab, s):
		return []
	var c: Dictionary = chance(build, ab, s)
	if float(c["value"]) <= 0.0:
		return []
	var note: String = LE.t("Echo chance %s (%s): the use is repeated 1 s later.") % [LE.fmt_pct(float(c["value"])), "; ".join(c["lines"])]
	return ShadowCalc.repeat_components(build, slot, global, base_components, "echo", float(c["value"]), LE.t("Echo: %s"), note,
		echo_mods(build, ab))
