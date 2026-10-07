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
## ability name -> [{id, index, special, kind: add | double | companions}].
const LIMIT_PROPERTIES: Dictionary = {
	"SummonSkeleton": [{"id": "summonSkeleton", "index": 120, "special": 4, "kind": "add"},
		{"id": "summonSkeleton", "index": 120, "special": 21, "kind": "double"}],
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
## CharacterStats.getMaximumCompanions: Round(SP MaximumCompanions with added 2); 1 with «Limited to one companion».
const BASE_COMPANIONS: float = 2.0

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
				"totem": (int(ab.get("tags", 0)) & LE.TOTEM) != 0, "limit": lim["value"], "limit_text": lim["text"]}
			if GROUPS.has(ab_name) and actor == str(GROUPS[ab_name]["actor"]):
				t["rotation"] = rotation(ab_name, lim["flag_keys"])
			out.append(t)
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
				value *= 2.0
				parts.append(LE.t("× 2 (%s)") % ", ".join(pp["lines"]))
			"companions":
				value = maxf(value, float(companions["value"]))
				parts.append(LE.t("up to the maximum number of companions %s (%s)") % [LE.fmt_num(float(companions["value"])), ", ".join(pp["lines"])])
	value = maxf(float(roundi(value)), 0.0)
	return {"value": value, "flag_keys": s.get("flag_keys", []), "text": "%s = %s" % [" ".join(parts), LE.fmt_num(value)]}


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


## Maximum number of companions: {value}.
static func max_companions(build: Node) -> Dictionary:
	var store: StatStore = BuildMods.global_store(build)["store"]
	var sp: int = GameData.sp_id("MaximumCompanions")
	if sp < 0:
		return {"value": BASE_COMPANIONS}
	var q: StatQuery = store.query_untagged(sp)
	return {"value": float(roundi((BASE_COMPANIONS + q.added) * (1.0 + q.increased) * q.more))}


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
