## Idol altar (item base 41): SP 130 IdolAltarProperty values and their effect on idols, docs/ENGINE.md §5.4.1.
class_name AltarMods

const ALTAR_PROPERTY: int = 130

## Idol kind groups counted for the per-idol properties.
const ORNATE_BASE: int = 31
const HUGE_BASE: int = 32
const ADORNED_BASE: int = 33

## IdolAltarPropertyID -> {label, who, sp, kind, special?, tags?}; `who` is the idol kind counted.
const PER_IDOL: Dictionary = {
	9: {"label": "Dodge rating per corrupted idol", "who": "corrupted", "sp": LE.DODGE_RATING, "kind": "added"},
	10: {"label": "Mana per corrupted idol", "who": "corrupted", "sp": LE.MANA, "kind": "added"},
	11: {"label": "Armor per corrupted idol", "who": "corrupted", "sp": LE.ARMOUR, "kind": "added"},
	12: {"label": "Ward decay threshold per corrupted idol", "who": "corrupted", "sp": LE.WARD_DECAY_THRESHOLD, "kind": "added"},
	13: {"label": "Health per heretical idol", "who": "heretical", "sp": LE.HEALTH, "kind": "added"},
	14: {"label": "Ward per second per heretical idol", "who": "heretical", "sp": LE.WARD_REGEN, "kind": "added"},
	15: {"label": "Less bonus damage from crits taken per heretical idol", "who": "heretical", "sp": LE.REDUCED_CRIT_BONUS_TAKEN, "kind": "added"},
	16: {"label": "Mana regen per Ornate idol", "who": "ornate", "sp": LE.MANA_REGEN, "kind": "increased"},
	17: {"label": "Health per Huge idol", "who": "huge", "sp": LE.HEALTH, "kind": "increased"},
	18: {"label": "Haste effect on you per omen idol", "who": "omen", "sp": LE.EFFECT_OF_AILMENT_ON_YOU, "kind": "increased", "haste": true},
	19: {"label": "Health per omen idol", "who": "omen", "sp": LE.HEALTH, "kind": "added"},
	22: {"label": "Health per idol in a refracted slot", "who": "refracted", "sp": LE.HEALTH, "kind": "added"},
	23: {"label": "Mana per idol in a refracted slot", "who": "refracted", "sp": LE.MANA, "kind": "added"},
	24: {"label": "Armor per idol in a refracted slot", "who": "refracted", "sp": LE.ARMOUR, "kind": "added"},
	25: {"label": "Ward decay threshold per idol in a refracted slot", "who": "refracted", "sp": LE.WARD_DECAY_THRESHOLD, "kind": "added"},
	26: {"label": "Strength per heretical idol", "who": "heretical", "sp": LE.STRENGTH, "kind": "added"},
	27: {"label": "Dexterity per heretical idol", "who": "heretical", "sp": LE.DEXTERITY, "kind": "added"},
	28: {"label": "Vitality per heretical idol", "who": "heretical", "sp": LE.VITALITY, "kind": "added"},
	29: {"label": "Healing effectiveness per heretical idol", "who": "heretical", "sp": 44, "kind": "increased"},
	30: {"label": "Elemental resistance per heretical idol", "who": "heretical", "sp": LE.ELEMENTAL_RES, "kind": "added"},
}

## Idol limit properties (notes only): id -> [label, idol kind].
const LIMITS: Dictionary = {
	0: ["Omen idol limit", "omen"],
	5: ["Weaver idol limit", "weaver"],
	6: ["Heretical idol limit", "heretical"],
	7: ["Adorned idol limit", "adorned"],
	8: ["Corrupted idol limit", "corrupted"],
}

## IdolAltarPropertyID.WeaverIdolLimit.
const WEAVER_LIMIT: int = 5

const KIND_LABELS: Dictionary = {
	"corrupted": "corrupted", "heretical": "heretical", "omen": "omen", "weaver": "Weaver",
	"adorned": "Adorned", "ornate": "Ornate", "huge": "Huge", "unique": "unique/legendary",
	"refracted": "in refracted slots",
}


## Idol kinds of one stored idol: corrupted (item flag `corrupted: true` or a corrupted subtype), heretical / omen /
## weaver (by subtype name), ornate / huge / adorned (by base), unique (any unique or legendary item).
static func idol_kinds(item: Dictionary) -> Dictionary:
	var base_id: int = int(item.get("base", -1))
	var sub: Dictionary = GameData.item_sub(base_id, int(item.get("sub", -1)))
	var sub_name: String = str(sub.get("name", ""))
	return {
		"corrupted": bool(item.get("corrupted", false)) or int(sub.get("isCorruptedSubtype", 0)) != 0,
		"heretical": sub_name.contains("Heretical"),
		"omen": sub_name.contains("Omen") or str(sub.get("affixEffectiveness", "")) == "OmenIdol",
		"weaver": sub_name.contains("Weaver"),
		"ornate": base_id == ORNATE_BASE,
		"huge": base_id == HUGE_BASE,
		"adorned": base_id == ADORNED_BASE,
		"unique": item.has("unique"),
	}


## True if the idol covers at least one refracted cell of the current altar.
static func in_refracted_slot(slot: String, item: Dictionary, items: Dictionary) -> bool:
	var a: Vector2i = IdolGrid.anchor(slot)
	for cell: Vector2i in IdolGrid.cells(a.x, a.y, int(item.get("base", -1))):
		if IdolGrid.is_refracted(cell.x, cell.y, items):
			return true
	return false


## IdolAltarPropertyID -> summed value of the altar's implicits and affixes.
static func altar_values(items: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var altar: Dictionary = IdolGrid.altar(items)
	if altar.is_empty():
		return values
	for mod: StatMod in ItemMods.item_mods(IdolGrid.ALTAR_SLOT, altar):
		if mod.property != ALTAR_PROPERTY:
			continue
		var v: float = mod.added + mod.increased
		for m: float in mod.more:
			v += m
		values[mod.tags] = float(values.get(mod.tags, 0.0)) + v
	return values


## Effect multipliers of idols in refracted slots {"prefix", "suffix", "enchant"} from altar properties 1–4.
static func refracted_scale(values: Dictionary) -> Dictionary:
	var both: float = float(values.get(1, 0.0))
	return {
		"prefix": 1.0 + both + float(values.get(2, 0.0)),
		"suffix": 1.0 + both + float(values.get(3, 0.0)),
		"enchant": 1.0 + float(values.get(4, 0.0)),
	}


## Number of idols of each kind in the build (plus "refracted": idols in a refracted slot).
static func idol_counts(items: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for kind: String in KIND_LABELS:
		counts[kind] = 0
	for slot: String in items:
		if not IdolGrid.is_idol_key(slot) or not items[slot].has("base"):
			continue
		var item: Dictionary = items[slot]
		var kinds: Dictionary = idol_kinds(item)
		for kind: String in kinds:
			if kinds[kind]:
				counts[kind] += 1
		if in_refracted_slot(slot, item, items):
			counts["refracted"] += 1
	return counts


## Weaver idol limit of the altar (property 5); 0 = no limit: IdolsItemContainer.CanPlaceNewWeaverIdol lets any number
## of Weaver idols in while the rounded limit is below 1 (altars without the property).
static func weaver_limit(items: Dictionary) -> int:
	return roundi(float(altar_values(items).get(WEAVER_LIMIT, 0.0)))


## Number of Weaver idols in the grid above the altar limit (0 when within the limit or without one).
static func weaver_excess(items: Dictionary) -> int:
	var limit: int = weaver_limit(items)
	return maxi(0, int(idol_counts(items)["weaver"]) - limit) if limit > 0 else 0


## True if some larger idol sits above a smaller one (same column, larger area, higher row) — breaks property 21.
static func larger_above_smaller(items: Dictionary) -> bool:
	var rects: Array[Rect2i] = []
	for slot: String in items:
		if IdolGrid.is_idol_key(slot) and items[slot].has("base"):
			var a: Vector2i = IdolGrid.anchor(slot)
			var size: Vector2i = IdolGrid.size_of(int(items[slot]["base"]))
			rects.append(Rect2i(a.y, a.x, size.x, size.y))  # x = column, y = row
	for upper: Rect2i in rects:
		for lower: Rect2i in rects:
			if upper.end.y > lower.position.y:
				continue  # not strictly above
			var overlap: bool = upper.position.x < lower.end.x and lower.position.x < upper.end.x
			if overlap and upper.get_area() > lower.get_area():
				return true
	return false


## Idol-affix delta caused by the refracted-slot effect: scaled mods minus unscaled mods (the same list shape).
static func _scale_deltas(slot: String, item: Dictionary, scale: Dictionary, source_prefix: String) -> Array[StatMod]:
	var out: Array[StatMod] = []
	var base_mods: Array[StatMod] = ItemMods.item_mods(slot, item)
	var scaled_mods: Array[StatMod] = ItemMods.item_mods(slot, item, scale)
	if base_mods.size() != scaled_mods.size():
		return out
	for i in range(base_mods.size()):
		var b: StatMod = base_mods[i]
		var s: StatMod = scaled_mods[i]
		var d := StatMod.new()
		d.property = b.property
		d.special = b.special
		d.tags = b.tags
		d.extra = b.extra
		d.added = s.added - b.added
		d.increased = s.increased - b.increased
		var changed: bool = d.added != 0.0 or d.increased != 0.0
		for j in range(mini(b.more.size(), s.more.size())):
			var factor: float = (1.0 + s.more[j]) / (1.0 + b.more[j]) - 1.0
			d.more.append(factor)
			changed = changed or factor != 0.0
		if changed:
			d.source = "%s — %s" % [source_prefix, b.source]
			out.append(d)
	return out


## Adds the altar's own effects to the global store (call after the idols' own mods are added, before attributes).
static func apply(build: Node, store: StatStore, notes: Array[String]) -> void:
	var altar: Dictionary = IdolGrid.altar(build.items)
	if altar.is_empty():
		return
	var altar_name: String = GameData.display_name(GameData.item_sub(IdolGrid.ALTAR_BASE, int(altar.get("sub", 0))))
	var prefix: String = LE.t("Altar \"%s\"") % altar_name
	var values: Dictionary = altar_values(build.items)
	var counts: Dictionary = idol_counts(build.items)

	# 1–4: effect of idol affixes / enchants in refracted slots
	var scale: Dictionary = refracted_scale(values)
	if not (is_equal_approx(scale["prefix"], 1.0) and is_equal_approx(scale["suffix"], 1.0) and is_equal_approx(scale["enchant"], 1.0)):
		var label: String = LE.t("%s: effect of idols in refracted slots (prefixes ×%s, suffixes ×%s, enchants ×%s)") % [
			prefix, LE.fmt_num(scale["prefix"]), LE.fmt_num(scale["suffix"]), LE.fmt_num(scale["enchant"])]
		for slot: String in build.items:
			if not IdolGrid.is_idol_key(slot) or not build.items[slot].has("base"):
				continue
			if in_refracted_slot(slot, build.items[slot], build.items):
				store.add_all(_scale_deltas(slot, build.items[slot], scale, label))
		if int(counts["refracted"]) == 0:
			notes.append(LE.t("%s: refracted-slot idol boost has no effect — no idols in such slots") % prefix)

	# 0, 5–8: idol limits (the planner does not cap idols; shown for reference)
	for id: int in LIMITS:
		if not values.has(id):
			continue
		var limit: Array = LIMITS[id]
		notes.append(LE.t("%s: %s +%s (in build: %d)") % [prefix, LE.t(limit[0]), LE.fmt_num(float(values[id])), int(counts[limit[1]])])
	if weaver_excess(build.items) > 0:
		notes.append(LE.t("%s: %d Weaver idols, above the limit of %d — the game does not let them into the grid") % [
			prefix, int(counts["weaver"]), weaver_limit(build.items)])

	# 9–19, 22–30: stat per idol of a kind
	for id: int in PER_IDOL:
		if not values.has(id):
			continue
		var model: Dictionary = PER_IDOL[id]
		var count: int = int(counts[model["who"]])
		if count <= 0:
			continue
		var special: int = int(BuildMods.PLAYER_AILMENTS["haste"]) if model.get("haste", false) else 0
		store.add(StatMod.make(int(model["sp"]), str(model["kind"]), float(values[id]) * count, 0,
			"%s: %s ×%d" % [prefix, LE.t(model["label"]), count], special))

	# 20: more damage to bosses per unique / legendary idol
	if values.has(20) and int(counts["unique"]) > 0:
		var boss: int = GameData.enum_value("ConditionalDamageProperty", "ToBossesButNotRares")
		store.add(StatMod.make(LE.CONDITIONAL_DAMAGE, "more", float(values[20]) * int(counts["unique"]), 0,
			LE.t("%s: damage to bosses per unique/legendary idol ×%d") % [prefix, int(counts["unique"])], boss))

	# 21: cooldown recovery if no larger idols are above smaller ones
	if values.has(21):
		if larger_above_smaller(build.items):
			notes.append(LE.t("%s: cooldown recovery speed has no effect — a larger idol is above a smaller one") % prefix)
		else:
			store.add(StatMod.make(LE.CDR, "increased", float(values[21]), 0,
				LE.t("%s: cooldown recovery speed (larger idols not above smaller ones)") % prefix))
