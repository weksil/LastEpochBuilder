class_name ShadowCalc

## Rogue shadows (docs/ENGINE.md §9.10). A shadow (ability CreateShadow, AbilityID 469) imitates your next direct use of
## Shadow Cascade, Shurikens, Umbral Blades, Dreamslash or Acid Flask (and indirect uses of Shadow Cascade); up to 3 are
## active (ability description). The number of active shadows is the player value «shadows» of the Conditions tab: every
## active shadow repeats a use of an imitated skill, so the skill gets a «Shadows: …» damage component with
## per_use × shadows. Properties of CreateShadow (AbilityProperty 469) from passives, items and idols:
## 0 max shadows, 1 health on shadow creation, 2 increased damage of skills used by shadows, 3 ward on shadow creation,
## 4 crit chance of skills used by shadows, 5 chance to recreate a used shadow (RogueShadow.RollResummonChance).
## Shadows are consumed by the use they imitate and last up to 5 s, so keeping N shadows takes N × max(uses/s, 1/5)
## creations per second; health / ward on creation (CreateShadowMutator.Mutate) become sustain rows of the skill.

const ABILITY_ID: String = "createShadow"
const ABILITY_INDEX: int = 469
const BASE_MAX: float = 3.0
## Ability names (abilities.json `name`) that shadows imitate.
const IMITATED: Array[String] = ["ShadowCascade", "Shurikens", "Umbral Blades 1", "Dreamslash", "AcidFlask"]
## AbilityProperty indices of CreateShadow counted here (their «not counted» notes are dropped).
const HANDLED: Array[int] = [0, 1, 2, 3, 4, 5]
const LIFETIME: float = 5.0
## More damage of a shadow's use by ability name: Umbral Blades shadows throw one blade with 300% more damage (altText;
## BaseUmbralBladesMutator.getTempStats adds a MoreStat when usedByShadow).
const SHADOW_MORE: Dictionary = {"Umbral Blades 1": 3.0}
## Skills whose shadow use throws a single projectile: the projectile factor of the skill does not apply to the copy.
const SINGLE_PROJECTILE: Array[String] = ["Umbral Blades 1"]
## Tree flags that stop shadows imitating the skill.
const BLOCKING_FLAGS: Array[String] = ["Shadows do not execute Dreamslash"]


static func imitates(ab: Dictionary) -> bool:
	return IMITATED.has(str(ab.get("name", "")))


## Sum of a CreateShadow property: passives plus item / idol mods (AbilityProperty, tags 469, specialTag = index).
## {value, lines}
static func property(build: Node, index: int) -> Dictionary:
	return ability_property(build, ABILITY_ID, ABILITY_INDEX, index)


## Sum of an AbilityProperty of any ability (`ability_id` = abilityIDName, `ability_index` = AbilityID value): passives and
## the mastery bonus, item / idol affixes, unique effects. {value, lines}
static func ability_property(build: Node, ability_id: String, ability_index: int, index: int) -> Dictionary:
	var lines: PackedStringArray = []
	var total: float = 0.0
	var tree: Dictionary = GameData.get_passive_tree(build.class_id)
	var tree_id: String = str(tree.get("treeID", ""))
	var effects: Dictionary = GameData.passive_effects(tree_id)
	var nodes: Array[Array] = []  # [node, points]
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
			var stat: Variant = effect.get("stat")
			if not stat is Dictionary or str(stat.get("abilityID", "")) != ability_id:
				continue
			if int(str(stat.get("abilityPropertyIndex", "-1"))) != index or points < int(effect.get("minPoints", 0)):
				continue
			var v: float = BuildMods.eval_value(stat.get("value", stat.get("added")), points)
			if v != 0.0:
				total += v
				lines.append(LE.t("Passive \"%s\" ×%d: %s") % [str(node.get("displayName", "")), points, LE.fmt_num(v)])
	for slot: String in build.items:
		if not (BuildMods.SLOTS.has(slot) or IdolGrid.is_idol_key(slot)):
			continue
		for mod: StatMod in ItemMods.item_mods(slot, build.items[slot]):
			if mod.property == LE.ABILITY_PROPERTY and mod.tags == ability_index and mod.special == index:
				total += mod.added
				lines.append("%s: %s" % [mod.source, LE.fmt_num(mod.added)])
	# special effects of the equipped uniques (unique mods are not affixes: UniqueEffects reads their rolls)
	for e: Dictionary in UniqueEffects.entries(build):
		if int(e["ability_index"]) == ability_index and int(e["effect"].get("propertyIndex", -1)) == index:
			total += float(e["pp"])
			lines.append("%s: %s" % [e["label"], LE.fmt_num(float(e["pp"]))])
	return {"value": total, "lines": lines}


static func max_shadows(build: Node) -> float:
	return BASE_MAX + float(property(build, 0)["value"])


## Active shadows: the Conditions value, at most the shadow limit.
static func count(build: Node) -> float:
	return clampf(float(build.player_state.get("shadows", 0)), 0.0, max_shadows(build))


## Mods of skills used by shadows: increased damage (property 2) and added crit chance (property 4).
static func shadow_mods(build: Node) -> Array[StatMod]:
	var out: Array[StatMod] = []
	var dmg: Dictionary = property(build, 2)
	if float(dmg["value"]) != 0.0:
		out.append(StatMod.make(LE.DAMAGE, "increased", float(dmg["value"]), 0,
			LE.t("Increased damage of skills used by shadows (%s)") % "; ".join(dmg["lines"])))
	var crit: Dictionary = property(build, 4)
	if float(crit["value"]) != 0.0:
		out.append(StatMod.make(LE.CRIT_CHANCE, "added", float(crit["value"]), 0,
			LE.t("Crit chance of skills used by shadows (%s)") % "; ".join(crit["lines"])))
	return out


## True if a passive effect is an ability property counted by the engine (CreateShadow here, the Shadow Daggers finisher
## by EnemyAilments).
static func handles_effect(effect: Dictionary) -> bool:
	var stat: Variant = effect.get("stat")
	if not stat is Dictionary:
		return false
	var index: int = int(str(stat.get("abilityPropertyIndex", "-1")))
	match str(stat.get("abilityID", "")):
		ABILITY_ID:
			return HANDLED.has(index)
		EnemyAilments.FINISHER_ID:
			return index == 0
	return false


## Shadow components of a skill: a copy of every hit component (primary / sub) with per_use × shadows, computed on the
## skill store built for a shadow use (models with «use:shadow» on, «use:direct» off) plus `shadow_mods`.
## Returns [] when the skill is not imitated, there are no shadows or a tree node stops the imitation.
static func components(build: Node, slot: int, ab: Dictionary, global: StatStore, base_components: Array[Dictionary],
		s: Dictionary, out_notes: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not imitates(ab):
		return out
	for flag: String in s.get("flag_keys", []):
		if BLOCKING_FLAGS.has(flag):
			return out
	var n: float = count(build)
	if n <= 0.0:
		var note: String = LE.t("Shadows imitate \"%s\": set the number of active shadows on the Conditions tab (now 0).") % GameData.display_name(ab)
		if not out_notes.has(note):
			out_notes.append(note)
		return out
	var extra: Array[StatMod] = shadow_mods(build)
	if SHADOW_MORE.has(str(ab.get("name", ""))):
		extra.append(StatMod.make(LE.DAMAGE, "more", float(SHADOW_MORE[str(ab.get("name", ""))]), 0,
			LE.t("Shadows using %s: one blade with more damage (game code)") % GameData.display_name(ab)))
	var limit_text: String = LE.t("Active shadows %s (Conditions tab, limit %s); each repeats the use.") % [LE.fmt_num(n), LE.fmt_num(max_shadows(build))]
	var recreate: Dictionary = property(build, 5)
	if float(recreate["value"]) > 0.0:
		limit_text += " " + LE.t("A used shadow comes back with chance %s (%s): it helps keep the number of shadows set on the Conditions tab and does not add uses.") % [
			LE.fmt_pct(float(recreate["value"])), "; ".join(recreate["lines"])]
	out = repeat_components(build, slot, global, base_components, "shadow", n, LE.t("Shadows: %s"), limit_text, extra)
	if SINGLE_PROJECTILE.has(str(ab.get("name", ""))):
		for comp: Dictionary in out:
			comp["single_projectile"] = true
			comp["note"] = str(comp["note"]) + " " + LE.t("A shadow throws one blade: the projectiles of your throw do not apply.")
	return out


## Health and ward gained on shadow creation per second, as sustain rows (the Defense tab reads them): the skill keeps
## its shadows by creating shadows × max(uses/s, 1 / lifetime) per second. [] when the skill is not repeated by shadows.
static func sustain_rows(build: Node, ab: Dictionary, s: Dictionary, uses: float) -> Array:
	var rows: Array = []
	if not imitates(ab):
		return rows
	for flag: String in s.get("flag_keys", []):
		if BLOCKING_FLAGS.has(flag):
			return rows
	var n: float = count(build)
	if n <= 0.0:
		return rows
	var created: float = n * maxf(uses, 1.0 / LIFETIME)
	for entry: Array in [[1, "health_gain", LE.t("Health on shadow creation per second")], [3, "ward_gain", LE.t("Ward on shadow creation per second")]]:
		var p: Dictionary = property(build, int(entry[0]))
		var per: float = float(p["value"])
		if per <= 0.0:
			continue
		var b: PackedStringArray = [LE.t("Shadows created per second = active shadows %s × max(uses/s %s, 1 / %s s) = %s") % [
			LE.fmt_num(n), LE.fmt_num(uses), LE.fmt_num(LIFETIME), LE.fmt_num(created)]]
		b.append(LE.t("%s per shadow × %s/s = %s/s") % [LE.fmt_num(per), LE.fmt_num(created), LE.fmt_num(per * created)])
		b.append_array(p["lines"])
		rows.append({"label": entry[2], "text": LE.fmt_num(per * created), "breakdown": "\n".join(b), "sustain": entry[1], "value": per * created})
	return rows


## Copies of the hit components (primary / sub) of a skill repeated by something else (shadows, Void Knight echoes):
## per_use × `per_use`, computed on the skill store built for that use (`BuildMods.skill_store(…, use)`: models with
## «use:<use>» on, «use:direct» off) plus `extra` mods. `name_fmt` names a copy from the component name.
static func repeat_components(build: Node, slot: int, global: StatStore, base_components: Array[Dictionary], use: String,
		per_use: float, name_fmt: String, note: String, extra: Array[StatMod]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rs: Dictionary = BuildMods.skill_store(build, slot, global, use)
	for comp: Dictionary in base_components:
		if not (comp["kind"] == "primary" or comp["kind"] == "sub"):
			continue
		var store := StatStore.new()
		store.parent = rs["store"]
		var by_name: Dictionary = rs.get("component_mods", {})
		for key: String in [str(comp["ab"].get("name", "")), str(comp["ab"].get("abilityName", "")), str(comp["name"])]:
			if key != "" and by_name.has(key):
				for mod: Variant in by_name[key]:
					if mod is StatMod and not store.mods.has(mod):
						store.add(mod)
		store.add_all(extra)
		var copy: Dictionary = comp.duplicate()
		copy["name"] = name_fmt % comp["name"]
		copy["kind"] = use
		copy["per_use"] = float(comp["per_use"]) * per_use
		copy["store"] = store
		copy["conversions"] = rs["conversions"]
		copy["note"] = note
		out.append(copy)
	return out
