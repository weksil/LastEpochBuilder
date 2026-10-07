class_name MinionCount

## Active minions of the build (docs/ENGINE.md §9.4): one count per minion type summoned by the bar skills and the
## counts the models scale with (field_models `per: input:<key>` of COUNT_KEYS — «per minion», «per totem», «per wolf» …).
## A number set on the Conditions tab (Build.player_state.minions, keyed by actor name or count key) wins; otherwise:
## - a minion type: its summon limit (summonSettings `limit`, or `numberToSummon` when unlimited) — limit increases of
##   passives and nodes are not read (D?), so type the real number when the build raises it;
## - a count key: the sum of the types it covers (all minions but totems / totems / one actor).

## Count keys of the models -> {label, kind: all | totems | actor, actors}. «storm_crows» is the same count as «crows».
const COUNT_KEYS: Dictionary = {
	"minions": {"label": "All minions (not totems)", "kind": "all"},
	"totems": {"label": "Active totems", "kind": "totems"},
	"wolves": {"label": "Wolves", "kind": "actor", "actors": ["Primal Wolf"]},
	"raptors": {"label": "Raptors", "kind": "actor", "actors": ["Primal Raptor"]},
	"crows": {"label": "Storm Crows", "kind": "actor", "actors": ["Storm Crow"]},
}
const ALIASES: Dictionary = {"storm_crows": "crows"}


## A model input that is a global minion count (never a per-skill field).
static func is_count_key(key: String) -> bool:
	return COUNT_KEYS.has(ALIASES.get(key, key))


static func canonical(key: String) -> String:
	return str(ALIASES.get(key, key))


## Minion types summoned by the bar skills: [{actor, ability (name), skill (display name), totem, limit}], one per actor.
static func types(build: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for slot: int in range(build.skills.size()):
		var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
		if ab.is_empty():
			continue
		var ab_name: String = str(ab.get("name", ""))
		for minion: Dictionary in MinionCalc.minions_for(ab_name):
			var actor: String = str(minion.get("actorName", ""))
			if actor == "" or seen.has(actor):
				continue
			seen[actor] = true
			out.append({"actor": actor, "ability": ab_name, "skill": GameData.display_name(ab),
				"totem": (int(ab.get("tags", 0)) & LE.TOTEM) != 0, "limit": limit(minion, ab_name)})
	return out


## Summon limit of the minion for the ability that summons it (its own summonSettings entry, else the first).
static func limit(minion: Dictionary, ability_name: String) -> float:
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
		if take:
			var n: float = float(type_count(build, str(t["actor"]), float(t["limit"]))["value"])
			total += n
			parts.append("%s %s" % [str(t["actor"]), LE.fmt_num(n)])
	var text: String = LE.t("sum of the summoned minions: %s") % ", ".join(parts) if not parts.is_empty() else LE.t("no such minion is summoned by the bar skills")
	return {"value": total, "auto": true, "text": text}


## Count of an actor summoned by `ability_name` (the minion components of the summon skill).
static func of_minion(build: Node, minion: Dictionary, ability_name: String) -> float:
	return float(type_count(build, str(minion.get("actorName", "")), limit(minion, ability_name))["value"])
