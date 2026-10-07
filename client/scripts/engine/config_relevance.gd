class_name ConfigRelevance

## Which controls of the "Conditions" tab matter for the current build (Path of Building style): a control is shown only
## when something in the build reads it. compute(build) -> {
##   "player_flags": {key: reason}, "player_values": {key: reason}, "ailments": {ailment_id: reason}, "enemy": {flag: reason},
##   "minions": {actor name or MinionCount count key: reason}}
## A key present = relevant; reason = short translated text naming the source (shown as a tooltip).
## Sources:
## - conditions and "per" sources of effect models (uniques, passive and skill trees): EffectModels.blocked calls note_model
##   while compute() rebuilds the stores with recording on;
## - conditional damage (SP 117, ConditionalDamageProperty) and damage per ailment stack (SP 115): the keys a condition
##   reads are found by probing Enemy.has_condition with an enemy that has only that key set;
## - ailments the build applies: prefab chances of the equipped skills, "chance to apply" stats (SP 1), ailment conversions;
## - Haste / Frenzy on the player: stats that grant them or raise their effect on you.

const PROBE_LIMIT: int = 8  # a condition matched by more keys counts any ailment («per negative ailment»): not shown per key
const HASTE_ON_HIT: String = "HasteOnHitChance"

static var _recording: bool = false
static var _rec: Dictionary = {}
static var _regexes: Dictionary = {}  # pattern -> compiled RegEx of _scan_buff_sources


static func compute(build: Node) -> Dictionary:
	# re-entrant: the recording state of an outer compute is restored when this one ends
	var prev_rec: Dictionary = _rec
	var prev_recording: bool = _recording
	_rec = {"player_flags": {}, "player_values": {}, "player_buffs": {}, "ailments": {}, "enemy": {}, "minions": {}}
	_recording = true
	# the global store records too: passives and uniques that scale with a minion count («per minion», «per totem»)
	var global: StatStore = BuildMods.global_store(build)["store"]
	var stores: Array[Dictionary] = []
	for slot: int in range(build.skills.size()):
		var ability: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
		if not ability.is_empty():
			stores.append({"ability": ability, "result": BuildMods.skill_store(build, slot, global)})
	_recording = prev_recording
	var out: Dictionary = _rec
	_rec = prev_rec
	_scan_mods(out, global.mods, LE.t("Character"))
	for s: Dictionary in stores:
		var name: String = LE.t("Skill \"%s\"") % GameData.display_name(s["ability"])
		_scan_mods(out, s["result"]["store"].mods, name)
		_scan_skill_ailments(out, s["ability"], s["result"], name)
	_scan_buff_sources(out, build)
	var params: Dictionary = {}
	for s: Dictionary in stores:
		for label: Variant in s["result"].get("params", {}):
			params[str(s["result"]["params"][label].get("param", ""))] = LE.t("Skill \"%s\": %s") % [GameData.display_name(s["ability"]), str(label)]
	# every minion type summoned by a bar skill can be counted by hand
	for t: Dictionary in MinionCount.types(build):
		_add(out, "minions", str(t["actor"]), LE.t("Skill \"%s\"") % str(t["skill"]))
	var inputs: Dictionary = EnemyAilments.input_reasons(build, params)
	for group: String in inputs:
		for key: String in inputs[group]:
			_add(out, group, key, str(inputs[group][key]))
	return out


## Active shadows and the buffs of the "Buffs on me" list: shown when the build creates or uses them (texts of the taken
## passive and skill nodes, the bar skills and the equipped uniques name them) or a bar skill is imitated by shadows (ShadowCalc).
const SHADOW_TEXT: String = "(?i)\\{shadows?\\}|\\bshadows\\b"
const SHROUD_TEXT: String = "(?i)\\{shroud\\}|any shroud"
const SHROUDS: Array[String] = ["DuskShroud", "CrimsonShroud", "SilverShroud"]


static func _scan_buff_sources(out: Dictionary, build: Node) -> void:
	var texts: Array[Array] = []  # [text, reason]
	var ptree: Dictionary = GameData.get_passive_tree(build.class_id)
	for node: Dictionary in ptree.get("nodes", []):
		if int(build.passives.get(int(node.get("id", -1)), 0)) > 0:
			texts.append([str(node.get("description", "")), LE.t("Passive \"%s\"") % str(node.get("displayName", ""))])
	for slot: int in range(build.skills.size()):
		var ab: Dictionary = GameData.get_ability(str(build.skills[slot].get("ability", "")))
		if ab.is_empty():
			continue
		var name: String = LE.t("Skill \"%s\"") % GameData.display_name(ab)
		if ShadowCalc.imitates(ab):
			_add(out, "player_values", "shadows", LE.t("%s: repeated by active shadows") % name)
		texts.append([str(ab.get("description", "")), name])
		var tree: Dictionary = GameData.get_skill_tree(str(ab.get("skillTree", "")))
		var taken: Dictionary = build.skills[slot].get("tree", {})
		for node: Dictionary in tree.get("nodes", []):
			if int(taken.get(int(node.get("id", -1)), taken.get(str(node.get("id", -1)), 0))) > 0:
				texts.append([str(node.get("description", "")), LE.t("%s: node \"%s\"") % [name, str(node.get("displayName", ""))]])
	for item_slot: String in build.items:
		var item: Dictionary = build.items[item_slot]
		if item.has("unique"):
			var u: Dictionary = GameData.unique(int(item["unique"]))
			texts.append([JSON.stringify(u.get("tooltip", [])) + JSON.stringify(GameData.unique_effects(int(item["unique"]))),
				LE.t("Item \"%s\"") % GameData.display_name(u)])
	var patterns: Array[Array] = [[SHADOW_TEXT, "player_values", "shadows"]]
	for ail: Dictionary in GameData.player_buffs():
		var shown_name: String = str(ail.get("displayName", ""))
		if shown_name != "":
			patterns.append(["(?i)\\b%s\\b" % _regex_escape(shown_name), "player_buffs", int(ail["id"])])
	for shroud: String in SHROUDS:
		patterns.append([SHROUD_TEXT, "player_buffs", GameData.enum_value("AilmentID", shroud)])
	for pattern: Array in patterns:
		var re: RegEx = _regexes.get(str(pattern[0]))
		if re == null:
			re = RegEx.create_from_string(str(pattern[0]))
			_regexes[str(pattern[0])] = re
		for t: Array in texts:
			if re.search(str(t[0])) != null:
				_add(out, str(pattern[1]), pattern[2], str(t[1]))


static func _regex_escape(text: String) -> String:
	var out: String = ""
	for ch: String in text:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out


## Called by EffectModels.blocked: records every condition and "per" source of the model while compute() runs.
static func note_model(model: Dictionary, ctx: Dictionary) -> void:
	if not _recording:
		return
	var reason: String = _ctx_source(ctx)
	for cond: String in model.get("when", []):
		_note_condition(cond, reason)
	for key: String in ["at_least", "below"]:
		if model.has(key):
			_note_source(str(model[key].get("per", "")), reason)
	if model.has("per"):
		_note_source(str(model["per"]), reason)


static func _note_condition(cond: String, reason: String) -> void:
	var kind: String = cond.get_slice(":", 0)
	var arg: String = cond.get_slice(":", 1)
	match kind:
		"enemy":
			if arg != "boss_or_rare":
				_add_ailment(_rec, GameData.enum_value("AilmentID", arg), reason)
		"enemy_any":
			for a: String in arg.split("|"):
				_add_ailment(_rec, GameData.enum_value("AilmentID", a), reason)
		"enemy_flag":
			_add(_rec, "enemy", arg, reason)
		"player":
			_add(_rec, "player_flags", arg.trim_prefix("!"), reason)


static func _note_source(per: String, reason: String) -> void:
	var arg: String = per.get_slice(":", 1)
	match per.get_slice(":", 0):
		"enemy_stacks":
			_add_ailment(_rec, GameData.enum_value("AilmentID", arg), reason)
		"player":
			_add(_rec, "player_values", arg, reason)
		"buff":
			_add(_rec, "player_buffs", GameData.enum_value("AilmentID", arg), reason)
		"input":
			if MinionCount.is_count_key(arg):
				_add(_rec, "minions", MinionCount.canonical(arg), reason)


static func _ctx_source(ctx: Dictionary) -> String:
	var build: Node = ctx["build"]
	var item_slot: String = str(ctx.get("item_slot", ""))
	if item_slot != "":
		var item: Dictionary = build.items.get(item_slot, {})
		if item.has("unique"):
			return LE.t("Item \"%s\"") % GameData.display_name(GameData.unique(int(item["unique"])))
		return LE.t("Item \"%s\"") % GameData.display_name(GameData.item_base(int(item.get("base", -1))))
	var slot: int = int(ctx.get("slot", -1))
	if slot >= 0 and slot < build.skills.size():
		return LE.t("Skill \"%s\"") % GameData.display_name(GameData.get_ability(str(build.skills[slot].get("ability", ""))))
	return LE.t("Passives and special effects")


## Stats of one store: conditional damage, damage per stack, "chance to apply", Haste / Frenzy sources.
static func _scan_mods(out: Dictionary, mods: Array[StatMod], fallback: String) -> void:
	var haste_sp: int = GameData.sp_id(HASTE_ON_HIT)
	for mod: StatMod in mods:
		var reason: String = mod.source if mod.source != "" else fallback
		match mod.property:
			LE.CONDITIONAL_DAMAGE:
				_probe_condition(out, mod.special, reason)
			LE.DAMAGE_PER_AILMENT_STACK:
				_add_ailment(out, mod.special, reason)
			LE.AILMENT_CHANCE:
				if mod.special > 0 and mod.added > 0.0:
					_add_ailment(out, mod.special, reason)
			LE.AILMENT_CONVERSION:
				if mod.added > 0.1:
					_add_ailment(out, mod.tags, reason)
		if mod.property == haste_sp and mod.added > 0.0:
			_add(out, "player_flags", "haste", reason)
		if mod.tags & LE.TRANSFORM:
			_add(out, "player_flags", "transformed", reason)
		if mod.property == LE.EFFECT_OF_AILMENT_ON_YOU:
			for key: String in BuildMods.PLAYER_AILMENTS:
				if int(BuildMods.PLAYER_AILMENTS[key]) == mod.special:
					_add(out, "player_flags", key, reason)


## Prefab chances of the skill and ailment conversions of its tree.
static func _scan_skill_ailments(out: Dictionary, ability: Dictionary, result: Dictionary, name: String) -> void:
	if int(ability.get("isTransform", 0)) == 1:
		_add(out, "player_flags", "transformed", name)
	for entry: Dictionary in ability.get("ailmentsOnHit", []):
		for a: Dictionary in entry.get("ailments", []):
			if float(a.get("chance", 0.0)) > 0.0:
				_add_ailment(out, GameData.ailment_id_by_name(str(a.get("ailment", ""))), name + LE.t(": chance to apply"))
	for c: Dictionary in result.get("conversions", []):
		for ac: Dictionary in c["rule"].get("ailment_convert", []):
			_add_ailment(out, GameData.ailment_id_by_name(str(ac.get("to", ""))), LE.t("%s: node \"%s\"") % [name, c["node"]])


## Keys (enemy flags, ailments) that make Enemy.has_condition(cdp) non-zero on their own.
static func _probe_condition(out: Dictionary, cdp: int, reason: String) -> void:
	var hits: Array[Array] = []
	var base: Dictionary = {"kind": "normal", "flags": {}, "ailments": {}}
	for flag: String in ["moving", "stunned", "low_health", "high_health", "full_health", "frozen"]:
		var probe: Dictionary = base.duplicate(true)
		probe["flags"][flag] = true
		if Enemy.has_condition(probe, cdp) > 0.0:
			hits.append(["enemy", flag])
	for ail: Dictionary in GameData.enemy_ailments():
		var probe: Dictionary = base.duplicate(true)
		probe["ailments"][int(ail["id"])] = 1
		if Enemy.has_condition(probe, cdp) > 0.0:
			hits.append(["ailment", int(ail["id"])])
	if hits.size() > PROBE_LIMIT:
		return
	for h: Array in hits:
		if h[0] == "enemy":
			_add(out, "enemy", h[1], reason)
		else:
			_add_ailment(out, h[1], reason)


## A positive ailment (a buff the build gives you: Void Essence, Dusk Shroud …) goes to the "Buffs on me" list.
static func _add_ailment(out: Dictionary, id: int, reason: String) -> void:
	if id < 0:
		return
	for key: String in BuildMods.PLAYER_AILMENTS:
		if int(BuildMods.PLAYER_AILMENTS[key]) == id:
			_add(out, "player_flags", key, reason)  # Haste / Frenzy are checkboxes
			return
	_add(out, "player_buffs" if int(GameData.ailment(id).get("positive", 0)) != 0 else "ailments", id, reason)


## First reason wins; later sources are appended up to three.
static func _add(out: Dictionary, group: String, key: Variant, reason: String) -> void:
	var d: Dictionary = out[group]
	if not d.has(key):
		d[key] = reason
	elif not str(d[key]).contains(reason) and str(d[key]).count("\n") < 2:
		d[key] = str(d[key]) + "\n" + reason
