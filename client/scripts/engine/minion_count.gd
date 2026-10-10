class_name MinionCount

## Active minions of the build (docs/ENGINE.md §9.4): one count per minion type summoned by the bar skills and the
## counts the models scale with (field_models `per: input:<key>` of COUNT_KEYS — «per minion», «per totem», «per wolf» …).
## A number set on the Conditions tab (Build.player_state.minions, keyed by actor name or count key) wins; otherwise:
## - a minion type: its summon limit (`limit_of`): the base (summonSettings `limit`, or `numberToSummon` when unlimited;
##   GROUPS for summons whose minions are chosen by the tree), the skill's «Max …» parameters (tree nodes and passives aimed
##   at the summon's mutator: added, increased, more, set), the AbilityProperties of passives, items and uniques
##   (LIMIT_PROPERTIES), «doubled» flags, «up to your maximum number of companions» (base 2 + SP MaximumCompanions);
## - a count key: the sum of the types it covers (all minions but totems / totems / one actor).

## Count keys of the models -> {label, kind: all | totems | actor, actors}. «storm_crows» is the same count as «crows».
const COUNT_KEYS: Dictionary = {
	"minions": {"label": "All minions (not totems)", "kind": "all"},
	"totems": {"label": "Active totems", "kind": "totems"},
	"wolves": {"label": "Wolves", "kind": "actor", "actors": ["Primal Wolf"]},
	"raptors": {"label": "Raptors", "kind": "actor", "actors": ["Primal Raptor"]},
	"crows": {"label": "Storm Crows", "kind": "actor", "actors": ["Storm Crow"]},
	"warriors_archers": {"label": "Skeleton warriors and archers", "kind": "actor", "actors": ["Skeleton Warrior", "Skeleton Archer"]},
}
const ALIASES: Dictionary = {"storm_crows": "crows"}
## Summons whose minion records are chosen by the tree (no `summonedBy` of their own): one type with the base limit of
## the code (SummonSkeletonMutator.getSkeletonLimit: 3 + additional; SummonMageMutator.getSkeletonMageLimit: 2 + …) and
## the members of its rotation, switched by tree flags (field_models texts): `if` — only with the flag, `unless` — not
## with any of these flags, `one` — at most one with the flag. The count is split evenly between the members (the
## summons alternate the types, D?).
const GROUPS: Dictionary = {
	"SummonSkeleton": {"actor": "Skeletons", "base": 3.0, "members": [
		{"actor": "Skeleton Warrior", "unless": ["Warriors not summoned"], "one": "Max one warrior"},
		{"actor": "Skeleton Archer", "unless": ["Archers not summoned"]},
		{"actor": "Skeleton Rogue", "if": "Adds rogues"},
	]},
	"SummonMage": {"actor": "Skeletal Mages", "base": 2.0, "members": [
		{"actor": "Skeleton Mage", "unless": ["Removes normal mages from rotation", "Replaces mages with Death Knights"]},
		{"actor": "Cryomancer", "if": "Adds cryomancers"},
		{"actor": "Pyromancer", "if": "Adds pyromancers", "unless": ["Removes pyromancers from rotation"]},
		{"actor": "Death Knight", "if": "Replaces mages with Death Knights"},
	]},
}
## «Max …» parameters of the summon skills (field_models labels, untranslated): tree nodes and passives such as
## SummonSkeletonMutator.additionalSkeletonsFromPassives.
const LIMIT_LABELS: Array[String] = ["Max skeleton count", "Max skeleton mages", "Max spectres", "Max forged weapons",
	"Max number of Thorn-totems", "Max crows", "Max wolves", "Max locusts", "Max locust count (multiplier)"]
## AbilityProperties that raise a summon limit (ability_property_fields*.json; AbilityStatsMutatorManager fields):
## ability name -> [{id, index, special, kind: add | double | no_summon | companions}].
const LIMIT_PROPERTIES: Dictionary = {
	"SummonSkeleton": [{"id": "summonSkeleton", "index": 120, "special": 4, "kind": "add"},
		{"id": "summonSkeleton", "index": 120, "special": 21, "kind": "double"},
		{"id": "summonSkeleton", "index": 120, "special": 9, "kind": "no_summon"}],
	"SummonMage": [{"id": "summonMage", "index": 291, "special": 6, "kind": "add"}],
	"SummonBoneGolem": [{"id": "summonBoneGolem", "index": 157, "special": 9, "kind": "add"}],
	"SummonWraith": [{"id": "summonWraith", "index": 146, "special": 2, "kind": "add"}],
	"SummonWeapon": [{"id": "summonWeapon", "index": 220, "special": 0, "kind": "add"}],
	"SummonThornTotem": [{"id": "summonThornTotem", "index": 58, "special": 6, "kind": "add"}],
	"SummonBallista": [{"id": "summonBallista", "index": 379, "special": 0, "kind": "add"}],
	"SummonStormTotem": [{"id": "summonStormTotem", "index": 195, "special": 13, "kind": "add"}],
	"SummonSpriggan": [{"id": "summonSpriggan", "index": 75, "special": 1, "kind": "add"}],
	"SummonLocust": [{"id": "summonLocust", "index": 582, "special": 4, "kind": "add"}],
	"SummonWolf": [{"id": "summonWolf", "index": 8, "special": 3, "kind": "companions"}],
	"SummonRaptor": [{"id": "summonRaptor", "index": 321, "special": 0, "kind": "companions"}],
}
## CharacterStats.getMaximumCompanions: Round(SP MaximumCompanions with added 2); 1 with PlayerProperty 85 (maxOneCompanion).
const BASE_COMPANIONS: float = 2.0
## PlayerProperty flags of the companion limit (both set by `0.1 < value`, CharacterMutator.applyModifiersBeforeExternalStatsCalculation):
## 85 maxOneCompanion (CharacterStats.getMaximumCompanions returns 1), 553 maxOneCompanionOfEachType (SummonTracker.maxOneOfAnyCompanion:
## one minion per actor type, the newest kept).
const PP_ONE_COMPANION: int = 85
const PP_ONE_OF_EACH_COMPANION: int = 553
const COMPANION_FLAGS: Array[int] = [85, 553]
## SummonTracker.unsummonExtraCompanions: every companion adds 60 to a budget of 60 x getMaximumCompanions, so one companion type
## holds at most getMaximumCompanions minions. Not capped here: Spriggan (extraNonCompanionCapSpriggans: spriggans outside the cap)
## and Falconry (its own getMaximum).
const COMPANION_UNCAPPED: Array[String] = ["SummonSpriggan", "Falconer 00 Falconry"]
## Contribution of one companion to the shared budget (Summoned.defaultContributionToCompanionLimit; SummonTracker.getCompanions_1).
const COMPANION_CONTRIBUTION: float = 60.0
## AbilityProperty summonWolf special 8 summonWolfCountAsTwoForLimit (mgr+0x1c5): SummonWolfMutator.contributionToCompanionLimitPerMinion x2.
## Special 2 convertWolvesTo2Squirrels (mgr+0x1c3) halves it, but SummonWolfMutator.getMaximum doubles the count, so a wolf slot keeps
## its share (the squirrel actor itself is not modelled).
const WOLF_COUNT_AS_TWO_SPECIAL: int = 8
## SummonSkeletonMutator.halfSkeletons (the model's flag text): the skeleton limit is halved unless it is also doubled.
const HALF_SKELETONS_FLAG: String = "Skeletons halved (damage, health, size increased)"

static var _cache: Dictionary = {}
static var _busy: bool = false


## A model input that is a global minion count (never a per-skill field).
static func is_count_key(key: String) -> bool:
	return COUNT_KEYS.has(ALIASES.get(key, key))


static func canonical(key: String) -> String:
	return str(ALIASES.get(key, key))


## Minion types summoned by the bar skills: [{actor, ability (name), skill (display name), totem, limit, limit_text}],
## one per actor. While a limit is being computed (the summon's store reads the counts) the bases are used.
static func types(build: Node) -> Array[Dictionary]:
	var key: PackedByteArray = PackedByteArray() if _busy else _signature(build)
	if not key.is_empty() and _cache.has(key):
		return _cache[key]
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot: int in range(build.skills.size()):
		var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
		if ab.is_empty():
			continue
		var ab_name: String = str(ab.get("name", ""))
		var entries: Array[Array] = []  # [actor, base]
		if GROUPS.has(ab_name):
			entries.append([str(GROUPS[ab_name]["actor"]), float(GROUPS[ab_name]["base"])])
		for minion: Dictionary in MinionCalc.minions_for(ab_name):
			entries.append([str(minion.get("actorName", "")), base_limit(minion, ab_name)])
		for e: Array in entries:
			var actor: String = str(e[0])
			if actor == "" or seen.has(actor):
				continue
			seen[actor] = true
			var lim: Dictionary = {"value": float(e[1]), "text": LE.fmt_num(float(e[1])), "flag_keys": []}
			if not _busy:
				lim = limit_of(build, slot, ab, float(e[1]))
			var t: Dictionary = {"actor": actor, "ability": ab_name, "skill": GameData.display_name(ab),
				"totem": (int(ab.get("tags", 0)) & LE.TOTEM) != 0, "limit": lim["value"], "limit_text": lim["text"],
				"slot": slot, "base": float(e[1])}
			if GROUPS.has(ab_name) and actor == str(GROUPS[ab_name]["actor"]):
				t["rotation"] = rotation(ab_name, lim["flag_keys"])
			out.append(t)
	if not _busy:
		_share_budget(build, out)
	if not key.is_empty():
		if _cache.size() >= 16:
			_cache.clear()
		_cache[key] = out
	return out


## Base summon limit of the minion for the ability that summons it (its own summonSettings entry, else the first).
static func base_limit(minion: Dictionary, ability_name: String) -> float:
	var chosen: Dictionary = {}
	for entry: Variant in minion.get("summonSettings", []):
		if entry is Dictionary and (chosen.is_empty() or str(entry.get("ability", "")) == ability_name):
			chosen = entry
			if str(entry.get("ability", "")) == ability_name:
				break
	if chosen.is_empty():
		return 1.0
	var lim: float = float(chosen.get("limit", 0.0))
	return lim if lim > 0.0 else maxf(float(chosen.get("numberToSummon", 1.0)), 1.0)


## Summon limit of the skill in `slot` from `base`: {value, text} — text lists the steps.
static func limit_of(build: Node, slot: int, ab: Dictionary, base: float) -> Dictionary:
	var was_busy: bool = _busy
	_busy = true
	var s: Dictionary = BuildMods.skill_store(build, slot, BuildMods.global_store(build)["store"])
	var companions: Dictionary = max_companions(build)
	_busy = was_busy
	var value: float = base
	var parts: PackedStringArray = [LE.t("base %s") % LE.fmt_num(base)]
	var labels: Array = LIMIT_LABELS.map(func(l: String) -> String: return LE.t(l))
	var params: Dictionary = s.get("params", {})
	for label: Variant in params:
		if not labels.has(str(label)):
			continue
		var p: Dictionary = params[label]
		var sources: Array = (p.get("sources", []) as Array).map(func(x: Variant) -> String: return str(x).replace("  (", " ("))
		var added: float = float(p.get("added", 0.0))
		var inc: float = float(p.get("increased", 0.0))
		var more: float = float(p.get("more", 1.0))
		if p.get("set") == null and inc == 0.0 and more == 1.0:
			value += added
			for src: String in sources:
				parts.append("+ " + src)
			continue
		if p.get("set") != null:
			value = float(p["set"])
			parts.append(LE.t("set to %s") % LE.fmt_num(value))
		if added != 0.0:
			value += added
			parts.append("%+d" % int(added))
		if inc != 0.0 or more != 1.0:
			value *= (1.0 + inc) * more
			parts.append("× %s" % LE.fmt_num((1.0 + inc) * more))
		parts.append("(%s)" % ", ".join(sources))
	var doubled: bool = false
	var no_summon: bool = false
	for prop: Dictionary in LIMIT_PROPERTIES.get(str(ab.get("name", "")), []):
		var pp: Dictionary = ShadowCalc.ability_property(build, str(prop["id"]), int(prop["index"]), int(prop["special"]))
		var v: float = float(pp["value"])
		if v == 0.0:
			continue
		match str(prop["kind"]):
			"add":
				value += v
				parts.append("+ %s (%s)" % [LE.fmt_num(v), ", ".join(pp["lines"])])
			"double":
				doubled = true
				parts.append(LE.t("× 2 (%s)") % ", ".join(pp["lines"]))
			"no_summon":
				no_summon = true
				parts.append(LE.t("none (%s)") % ", ".join(pp["lines"]))
			"companions":
				value = maxf(value, float(companions["value"]))
				parts.append(LE.t("up to the maximum number of companions %s (%s)") % [LE.fmt_num(float(companions["value"])), ", ".join(pp["lines"])])
	# SummonSkeletonMutator.getSkeletonLimit: doubled = 2 * (sum + 3); halved (and not doubled) = Round((sum + 3) * 0.5001);
	# both cancel; noSummonSkeletons = 0
	var half: bool = ab.get("name") == "SummonSkeleton" and (s.get("flag_keys", []) as Array).has(HALF_SKELETONS_FLAG)
	if doubled and not half:
		value *= 2.0
	elif half and not doubled:
		value *= 0.5001
		parts.append(LE.t("× 0.5 (skeletons halved)"))
	if no_summon:
		value = 0.0
	value = maxf(float(roundi(value)), 0.0)
	# SummonTracker.unsummonExtraCompanions / EnforceLimitOfOneOfEachCompanionType: a companion type holds at most the maximum number of companions
	if bool(ab.get("companion", false)) and not COMPANION_UNCAPPED.has(str(ab.get("name", ""))):
		var capped: float = companion_cap(value, float(companions["value"]), player_flag(build, PP_ONE_OF_EACH_COMPANION), contribution(build, ab))
		if capped < value:
			parts.append((LE.t("limited to %s: one companion of each type") if capped == 1.0 and float(companions["value"]) > 1.0 else LE.t("limited to %s by the maximum number of companions")) % LE.fmt_num(capped))
			value = capped
	return {"value": value, "flag_keys": s.get("flag_keys", []), "text": "%s = %s" % [" ".join(parts), LE.fmt_num(value)]}


## Budget share of one minion of a companion ability: 60, a wolf with summonWolfCountAsTwoForLimit 120.
static func contribution(build: Node, ab: Dictionary) -> float:
	if str(ab.get("name", "")) == "SummonWolf" and float(ShadowCalc.ability_property(build, "summonWolf", 8, WOLF_COUNT_AS_TWO_SPECIAL)["value"]) != 0.0:
		return COMPANION_CONTRIBUTION * 2.0
	return COMPANION_CONTRIBUTION


## Members of a GROUPS summon's rotation under the tree flags: [{actor, one}].
static func rotation(ability_name: String, flag_keys: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in GROUPS[ability_name]["members"]:
		if m.has("if") and not flag_keys.has(str(m["if"])):
			continue
		var blocked: bool = false
		for f: Variant in m.get("unless", []):
			blocked = blocked or flag_keys.has(str(f))
		if blocked:
			continue
		out.append({"actor": str(m["actor"]), "one": m.has("one") and flag_keys.has(str(m["one"]))})
	return out


## Counts of the members of a GROUPS summon on the bar: [{actor, count}] — the group count split evenly between the
## members of its rotation, a member limited to one gets at most 1.
static func members(build: Node, ability_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in types(build):
		if str(t["ability"]) != ability_name or not t.has("rotation"):
			continue
		var total: float = float(type_count(build, str(t["actor"]), float(t["limit"]))["value"])
		var rot: Array = t["rotation"]
		if rot.is_empty():
			return out
		var share: float = total / float(rot.size())
		var capped: float = 0.0
		var free: int = 0
		for m: Dictionary in rot:
			if bool(m["one"]) and share > 1.0:
				capped += 1.0
			else:
				free += 1
		for m: Dictionary in rot:
			var n: float = 1.0 if bool(m["one"]) and share > 1.0 else (total - capped) / float(free)
			out.append({"actor": str(m["actor"]), "count": n})
	return out


## Rounding of CharacterStats.getMaximumCompanions: Math.Round, half to even.
static func round_companions(x: float) -> float:
	return float(LE.round_half_even(x))


## Minions of one companion type the shared budget leaves: `value` limited to the maximum number of companions (60 per companion
## against a budget of 60 x maximum) and to 1 with PlayerProperty 553 ("one companion of each type").
static func companion_cap(value: float, maximum: float, one_of_each: bool, per_minion: float = COMPANION_CONTRIBUTION) -> float:
	var capped: float = minf(value, floorf(maximum * COMPANION_CONTRIBUTION / per_minion))
	return minf(capped, 1.0) if one_of_each else capped


## SummonTracker.unsummonExtraCompanions: every companion type draws on ONE budget of maximumCompanions x 60 and the oldest summoned are
## evicted first, so which minions stay depends on the order the player casts the skills. The calculator shows the maximum: the counts
## with the largest minion DPS that fit (D?). Counts set by hand on the Conditions tab are kept and use the budget first.
static func _share_budget(build: Node, out: Array[Dictionary]) -> void:
	# busy while the budget is computed: the global store reads minion counts (types()), which would re-enter this function
	var was_busy: bool = _busy
	var was_recording: bool = ConfigRelevance._recording
	ConfigRelevance._recording = false  # the budget is no condition source of the build
	_busy = true
	_share_budget_run(build, out)
	_busy = was_busy
	ConfigRelevance._recording = was_recording


static func _share_budget_run(build: Node, out: Array[Dictionary]) -> void:
	var budget: float = float(max_companions(build)["value"]) * COMPANION_CONTRIBUTION
	var given: Dictionary = explicit(build)
	var items: Array[Dictionary] = []
	var need: float = 0.0
	for i: int in range(out.size()):
		var ab: Dictionary = GameData.ability_by_name(str(out[i]["ability"]))
		if not bool(ab.get("companion", false)) or COMPANION_UNCAPPED.has(str(ab.get("name", ""))):
			continue
		var cost: float = contribution(build, ab)
		if given.has(str(out[i]["actor"])):
			budget -= maxf(float(given[str(out[i]["actor"])]), 0.0) * cost
			continue
		items.append({"index": i, "max": float(out[i]["limit"]), "cost": cost, "dps": 0.0})
		need += float(out[i]["limit"]) * cost
	budget = maxf(budget, 0.0)
	if items.size() < 1 or need <= budget:
		return
	# minion DPS of one minion of each type: the summon skill's DPS vs enemy with the base counts (types() is not re-entered while busy)
	for it: Dictionary in items:
		var t: Dictionary = out[int(it["index"])]
		var r: Dictionary = SkillCalc.compute(build, int(t["slot"]), false)
		for section: Dictionary in r.get("sections", []):
			for row: Dictionary in section.get("rows", []):
				if str(row.get("label", "")) == LE.t("DPS vs enemy") and str(section.get("title", "")) == LE.t("Against enemy"):
					it["dps"] = float(row.get("value", 0.0)) / maxf(float(t["base"]), 1.0)
	var counts: Array[float] = pick_counts(items, budget)
	for k: int in range(items.size()):
		var t2: Dictionary = out[int(items[k]["index"])]
		if counts[k] < float(t2["limit"]):
			t2["limit"] = counts[k]
			t2["limit_text"] = str(t2["limit_text"]) + LE.t("; limited to %s by the shared companion budget (D?: the combination with the most DPS is kept)") % LE.fmt_num(counts[k])


## Integer counts k_i in [0, max_i] with sum(k_i x cost_i) <= budget and the largest sum(k_i x dps_i). items: [{max, cost, dps}]. Ties go
## to the earlier item (bar order) and its larger count.
static func pick_counts(items: Array[Dictionary], budget: float) -> Array[float]:
	var state: Dictionary = {"best": [], "dps": -1.0}
	var cur: Array[float] = []
	cur.resize(items.size())
	_pick_rec(items, 0, budget, 0.0, cur, state)
	var out: Array[float] = []
	for v: Variant in state["best"]:
		out.append(float(v))
	return out


static func _pick_rec(items: Array[Dictionary], i: int, left: float, dps: float, cur: Array[float], state: Dictionary) -> void:
	if i == items.size():
		if dps > float(state["dps"]) + 1e-9:
			state["dps"] = dps
			state["best"] = cur.duplicate()
		return
	var cost: float = float(items[i]["cost"])
	var top: int = mini(int(items[i]["max"]), maxi(int(floorf(maxf(left, 0.0) / cost + 1e-9)), 0))
	for k: int in range(top, -1, -1):
		cur[i] = float(k)
		_pick_rec(items, i + 1, left - float(k) * cost, dps + float(k) * float(items[i]["dps"]), cur, state)


## PlayerProperty flag `index` (value > 0.1): passives and mastery bonus, item / idol affixes, unique effects (EnemyAilments.player_property)
## and set bonuses (BuildMods.set_counts; Boardman's gives 85 with 1 piece).
static func player_flag(build: Node, index: int) -> bool:
	if float(EnemyAilments.player_property(build, index)["value"]) > 0.1:
		return true
	var counts: Dictionary = BuildMods.set_counts(build)
	for set_id: Variant in counts:
		for bonus: Variant in GameData.set_data(int(set_id)).get("bonuses", []):
			if bonus is Dictionary and int(bonus.get("property", 0)) == LE.PLAYER_PROPERTY and int(bonus.get("tags", -1)) == index \
					and int(bonus.get("setRequirement", 99)) <= int(counts[set_id]) and float(bonus.get("value", 0.0)) > 0.1:
				return true
	return false


## Maximum number of companions: {value}.
static func max_companions(build: Node) -> Dictionary:
	if player_flag(build, PP_ONE_COMPANION):
		return {"value": 1.0}
	var store: StatStore = BuildMods.global_store(build)["store"]
	var sp: int = GameData.sp_id("MaximumCompanions")
	if sp < 0:
		return {"value": BASE_COMPANIONS}
	var q: StatQuery = store.query_untagged(sp)
	return {"value": round_companions((BASE_COMPANIONS + q.added) * (1.0 + q.increased) * q.more)}


## Explicit numbers of the Conditions tab: {actor or count key: count}.
static func explicit(build: Node) -> Dictionary:
	var d: Variant = build.player_state.get("minions", {})
	return d if d is Dictionary else {}


## Active minions of one type: {value, auto}.
static func type_count(build: Node, actor: String, limit_value: float) -> Dictionary:
	var given: Dictionary = explicit(build)
	if given.has(actor):
		return {"value": maxf(float(given[actor]), 0.0), "auto": false}
	return {"value": limit_value, "auto": true}


## Value of a count key: {value, auto, text} — text explains the automatic sum.
static func count(build: Node, key: String) -> Dictionary:
	key = canonical(key)
	var given: Dictionary = explicit(build)
	if given.has(key):
		return {"value": maxf(float(given[key]), 0.0), "auto": false, "text": ""}
	var spec: Dictionary = COUNT_KEYS.get(key, {})
	var total: float = 0.0
	var parts: PackedStringArray = []
	for t: Dictionary in types(build):
		var take: bool = false
		match str(spec.get("kind", "")):
			"all":
				take = not bool(t["totem"])
			"totems":
				take = bool(t["totem"])
			"actor":
				take = (spec.get("actors", []) as Array).has(t["actor"])
				if not take and t.has("rotation"):
					for m: Dictionary in members(build, str(t["ability"])):
						if (spec.get("actors", []) as Array).has(m["actor"]):
							total += float(m["count"])
							parts.append("%s %s" % [str(m["actor"]), LE.fmt_num(float(m["count"]))])
		if take:
			var n: float = float(type_count(build, str(t["actor"]), float(t["limit"]))["value"])
			total += n
			parts.append("%s %s" % [str(t["actor"]), LE.fmt_num(n)])
	var text: String = LE.t("sum of the summoned minions: %s") % ", ".join(parts) if not parts.is_empty() else LE.t("no such minion is summoned by the bar skills")
	return {"value": total, "auto": true, "text": text}


## Count of an actor summoned by `ability_name` (the minion components of the summon skill).
static func of_minion(build: Node, minion: Dictionary, ability_name: String) -> float:
	var actor: String = str(minion.get("actorName", ""))
	for t: Dictionary in types(build):
		if str(t["actor"]) == actor:
			return float(type_count(build, actor, float(t["limit"]))["value"])
	return float(type_count(build, actor, base_limit(minion, ability_name))["value"])


static func _signature(build: Node) -> PackedByteArray:
	return var_to_bytes([build.class_id, build.mastery, build.level, build.passives, build.skills, build.items, build.blessings,
		build.player_state, TranslationServer.get_locale()])
