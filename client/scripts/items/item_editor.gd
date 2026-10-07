class_name ItemEditor extends PanelContainer

## Edits one equipment slot of Build.items or one unequipped item of Build.stash (docs/UI.md "Items").
## Edits change a draft of the item; %Pending under the item shows the stat changes Save would give. Controls live in
## item_editor.tscn.

## The edited item is gone or moved: the parent should show the slot instead.
signal slot_requested(slot: String)

const EMPTY_ID: int = 99999
const UNIQUE_EMPTY_ID: int = 99998
## Rows 0-1 prefixes, 2-3 suffixes, 4 the sealed and 5 the corrupted affix (ItemCompare.SEALED/CORRUPTED_AFFIX_INDEX).
const AFFIX_ROWS: Array[String] = ["Prefix1", "Prefix2", "Suffix1", "Suffix2", "Sealed", "Corrupted"]
## Slot kind of every %TypeSelect entry, indexed by the entry id.
const TYPE_SLOTS: Array[String] = ["helmet", "body", "belt", "boots", "gloves", "weapon", "offhand", "amulet", "ring1", "relic"]
## specialAffixType kinds offered in the prefix / suffix / sealed rows; the corrupted row offers CORRUPTED_KINDS.
const AFFIX_KINDS: Array[String] = ["Standard", "Set", "Experimental", "Personal", "IdolWeaver", "IdolEnchantment"]
const CORRUPTED_KINDS: Array[String] = ["Corrupted"]
## Marker after the name of a special affix in the affix lists (translated).
const KIND_TAGS: Dictionary = {"Set": "set", "Experimental": "experimental", "Personal": "personal", "IdolWeaver": "weaver",
	"IdolEnchantment": "enchantment", "Corrupted": "corrupted"}
## Values of an affix roll slider per tier: the slider covers every tier, value = (tier - 1) * TIER_SPAN + roll.
const TIER_SPAN: int = 256
## %SubSelect entry id = baseTypeID * SUB_ID_STRIDE + subTypeID.
const SUB_ID_STRIDE: int = 1000
## The unsaved-changes diff is recomputed at most this often (20 times a second).
const DIFF_INTERVAL_MSEC: int = 50

@export var implicit_row_scene: PackedScene
@export var set_line_scene: PackedScene
@export var info_tooltip_scene: PackedScene
@export var diff_line_scene: PackedScene

## The slot being edited; in stash mode the slot kind of the stashed item (it filters bases and uniques).
var _slot: String = ""
## Index of the edited Build.stash entry, -1 when an equipment slot is edited.
var _stash_index: int = -1
var _filling: bool = false
## The item as shown and edited; Save stores it.
var _draft: Dictionary = {}
## The stored item when the draft was taken: a different stored item (changed elsewhere) replaces the draft.
var _saved_item: Dictionary = {}
## The stats the unsaved-changes diff compares against; cleared whenever the build changes.
var _base_snapshot: Dictionary = {}
## An unsaved-changes diff update is queued (end of the frame or %DiffTimer).
var _diff_queued: bool = false
var _last_diff_msec: int = -DIFF_INTERVAL_MSEC


func _ready() -> void:
	%UniqueSelect.item_selected.connect(_on_unique_selected)
	%SubSelect.item_selected.connect(_on_sub_selected)
	%TypeSelect.item_selected.connect(_on_type_selected)
	%UniqueSelect.tooltip_builder = _unique_tooltip
	%SubSelect.tooltip_builder = _sub_tooltip
	%NameEdit.text_changed.connect(_on_name_changed)
	%ClearButton.pressed.connect(_on_clear)
	%StashCopyButton.pressed.connect(func() -> void: Build.stash_add(_item()))
	%StashMoveButton.pressed.connect(_on_stash_move)
	%EquipButton.pressed.connect(_on_equip)
	%SaveButton.pressed.connect(_save)
	%RevertButton.pressed.connect(_revert)
	%CorruptedCheck.toggled.connect(_on_corrupted_toggled)
	%DiffTimer.timeout.connect(_update_diff)
	for row_name: String in AFFIX_ROWS:
		var row: Node = %Affixes.get_node(row_name)
		if row_name.begins_with("Prefix") or row_name.begins_with("Suffix"):
			row.get_node("Top/KindLabel").text = tr("Prefix") if row_name.begins_with("Prefix") else tr("Suffix")
		row.get_node("Top/AffixSelect").item_selected.connect(func(_i: int) -> void: _store_affixes(true))
		row.get_node("Top/AffixSelect").tooltip_builder = _affix_tooltip
		row.get_node("Top/TierSpin").value_changed.connect(_on_tier_spin.bind(row))
		row.get_node("Bottom/RollSlider").value_changed.connect(func(_v: float) -> void: _store_affixes(false))
	Build.changed.connect(_on_build_changed)
	Build.stash_changed.connect(_on_build_changed)


func edit_slot(slot: String, title: String) -> void:
	_stash_index = -1
	_slot = slot
	%NameEdit.release_focus()
	%SlotTitle.text = title
	_load()
	_fill()


## Edits Build.stash[index], an unequipped item.
func edit_stash(index: int) -> void:
	_stash_index = index
	%NameEdit.release_focus()
	_slot = ItemCompare.target_slot(Build.stash[index], "") if index >= 0 and index < Build.stash.size() else ""
	%SlotTitle.text = tr("Unequipped item")
	_load()
	_fill()


## Makes sure the Type row is shown (it is only used for unequipped items).
func focus_type() -> void:
	%TypeRow.visible = _stash_index >= 0
	if %TypeSelect.focus_mode != Control.FOCUS_NONE:
		%TypeSelect.grab_focus()


## True when the shown item differs from the stored one (Save would change the build).
func is_dirty() -> bool:
	return _draft != _saved_item


## The item as shown and edited (the draft).
func _item() -> Dictionary:
	return _draft


## The item as stored in the slot or the stash entry.
func _stored() -> Dictionary:
	if _stash_index >= 0:
		return Build.stash[_stash_index] if _stash_index < Build.stash.size() else {}
	return Build.items.get(_slot, {})


## Takes the stored item as the draft; unsaved edits are dropped.
func _load() -> void:
	_saved_item = _stored().duplicate(true)
	_draft = _saved_item.duplicate(true)
	_base_snapshot = {}


## Stores an item in the slot or the stash entry; it becomes the draft too.
func _put(item: Dictionary) -> void:
	_saved_item = item.duplicate(true)
	_draft = item.duplicate(true)
	if _stash_index >= 0:
		Build.stash_set(_stash_index, item)
	else:
		Build.set_item(_slot, item)


## Removes the item: deletes the stash entry (and hands over to the slot), or empties the slot.
func _remove() -> void:
	if _stash_index >= 0:
		Build.stash_remove(_stash_index)
		slot_requested.emit(_slot)
	else:
		_saved_item = {}
		_draft = {}
		Build.clear_item(_slot)


func _on_build_changed() -> void:
	_base_snapshot = {}
	if _stash_index >= 0 and _stash_index >= Build.stash.size():
		slot_requested.emit.call_deferred(_slot)
	elif (_slot != "" or _stash_index >= 0) and not _filling and _stored() != _saved_item:
		# the item was changed elsewhere (the slot list, another tab, an import): it replaces the draft
		_load()
		_fill.call_deferred()
	else:
		_queue_diff()
	if _slot != "":
		_update_set_bonuses.call_deferred()


# --- filling controls from Build ---------------------------------------------------

func _fill() -> void:
	_filling = true
	var item: Dictionary = _item()
	var unique_id: int = int(item.get("unique", UNIQUE_EMPTY_ID))
	var base_id: int = int(item.get("base", EMPTY_ID))
	var base: Dictionary = GameData.item_base(base_id) if item.has("base") else {}

	# Fill unique select
	%UniqueSelect.clear()
	%UniqueSelect.add_item(tr("— regular item —"), UNIQUE_EMPTY_ID)
	var uniques: Array = GameData.uniques
	var unique_items: Array = []
	for u: Dictionary in uniques:
		var u_base: Dictionary = GameData.item_base(int(u.get("baseType", -1)))
		if _base_fits_slot(u_base):
			unique_items.append(u)
	unique_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var level_a: int = ItemCompare.unique_level(a)
		var level_b: int = ItemCompare.unique_level(b)
		if level_a != level_b:
			return level_a < level_b
		return GameData.display_name(a) < GameData.display_name(b))
	for u: Dictionary in unique_items:
		%UniqueSelect.add_item(GameData.display_name(u) + _idol_size_tag(GameData.item_base(int(u.get("baseType", -1))))
			+ ItemCompare.level_suffix(ItemCompare.unique_level(u)), int(u["uniqueID"]))
		%UniqueSelect.set_item_variation(%UniqueSelect.item_count - 1,
			&"RaritySet" if int(u.get("isSetItem", 0)) != 0 else &"RarityUnique")
	%UniqueSelect.select(maxi(0, %UniqueSelect.get_item_index(unique_id)))

	_fill_sub_select(item)

	var has_unique: bool = unique_id != UNIQUE_EMPTY_ID
	_fill_implicits(item)
	if has_unique:
		_fill_unique(item, unique_id)
	_fill_affixes(item, base)

	var has_item: bool = not base.is_empty() or has_unique
	var is_idol: bool = IdolGrid.is_idol_key(_slot)
	%AffixesTitle.text = tr("Affixes (1 prefix, 1 suffix)") if is_idol else tr("Affixes (2 prefixes, 2 suffixes)")
	var is_set: bool = has_unique and int(GameData.unique(unique_id).get("isSetItem", 0)) != 0
	if has_unique and not is_set:
		var weaver: bool = str(GameData.unique(unique_id).get("legendaryType", "")) == "WeaversWill"
		%AffixesTitle.text = tr("Legendary affixes (Weaver's Will)") if weaver else tr("Legendary affixes (legendary potential)")

	%SubSelect.disabled = has_unique
	%EmptyHint.visible = not has_item
	%SlotTitle.visible = not has_item
	%NameEdit.visible = has_item
	%NameEdit.placeholder_text = ItemCompare.default_title(item)
	var custom_name: String = str(item.get("name", ""))
	if not %NameEdit.has_focus() and %NameEdit.text != custom_name:
		%NameEdit.text = custom_name
	var in_stash: bool = _stash_index >= 0
	%TypeRow.visible = in_stash
	%TypeSelect.select(TYPE_SLOTS.find("ring1" if _slot == "ring2" else _slot))
	%EquipButton.visible = in_stash and has_item
	%StashCopyButton.visible = has_item and BuildMods.SLOTS.has(_slot)
	%StashMoveButton.visible = has_item and not in_stash and BuildMods.SLOTS.has(_slot)
	%ClearButton.visible = has_item
	# a unique takes affixes as a legendary (legendary potential, Weaver's Will); a set item shows only its mods (and
	# the corrupted affix); _fill_affixes hides the rows that do not apply
	var any_row: bool = %Affixes.get_children().any(func(row: Node) -> bool: return row.visible)
	%CorruptedCheck.visible = has_item and _slot != IdolGrid.ALTAR_SLOT
	%AffixesHeader.visible = has_item and (any_row or %CorruptedCheck.visible)
	%AffixesTitle.visible = any_row
	%Affixes.visible = has_item and any_row
	%CorruptedCheck.set_pressed_no_signal(_is_corrupted(item))
	%CorruptedCheck.disabled = _corrupted_subtype(item)
	%ImplicitsTitle.visible = has_item and %Implicits.get_child_count() > 0
	%Implicits.visible = has_item
	%UniqueTitle.visible = has_unique
	%UniqueMods.visible = has_unique
	%UniqueText.visible = has_unique
	_filling = false
	_update_values()
	_update_set_bonuses()
	_queue_diff()


## %SubSelect: every usable subtype of every base that fits the slot; id = baseTypeID * 1000 + subTypeID.
func _fill_sub_select(item: Dictionary) -> void:
	var bases: Array = []
	for b: Dictionary in GameData.item_bases:
		if _base_fits_slot(b):
			bases.append(b)
	var show_base: bool = bases.size() > 1
	%SubSelect.clear()
	if _stash_index < 0:
		%SubSelect.add_item(tr("— empty —"), EMPTY_ID)
	var entries: Array[Dictionary] = []
	for b: Dictionary in bases:
		for sub: Dictionary in b.get("subItems", []):
			if _sub_allowed(sub):
				entries.append({"id": int(b["baseTypeID"]) * SUB_ID_STRIDE + int(sub["subTypeID"]), "name": GameData.display_name(sub),
					"base": GameData.display_name(b), "level": int(sub.get("levelRequirement", 0)), "size": _idol_size_tag(b)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["level"] != b["level"]:
			return a["level"] < b["level"]
		return a["name"] < b["name"])
	for entry: Dictionary in entries:
		var label: String = entry["name"]
		if show_base:
			label += " (%s)" % entry["base"]
		label += entry["size"]
		%SubSelect.add_item(label + ItemCompare.level_suffix(entry["level"]), entry["id"])
	if item.has("base"):
		var current_id: int = int(item["base"]) * SUB_ID_STRIDE + int(item.get("sub", 0))
		if %SubSelect.get_item_index(current_id) < 0:
			# e.g. the subtype of a unique that is legacy or restricted to another class
			var current: Dictionary = GameData.item_sub(int(item["base"]), int(item.get("sub", 0)))
			%SubSelect.add_item(GameData.display_name(current) + ItemCompare.level_suffix(int(current.get("levelRequirement", 0))), current_id)
		%SubSelect.select(%SubSelect.get_item_index(current_id))
	else:
		%SubSelect.select(0)


## " [WxH]" (grid width x height, e.g. " [1x3]") after the name of an idol base, "" for other bases.
func _idol_size_tag(base: Dictionary) -> String:
	if not GameData.is_idol_type(int(base.get("type", -1))):
		return ""
	var size: Vector2i = IdolGrid.size_of(int(base["baseTypeID"]))
	return " [%dx%d]" % [size.x, size.y]


func _unique_tooltip(unique_id: int) -> Control:
	if unique_id == UNIQUE_EMPTY_ID or GameData.unique(unique_id).is_empty():
		return null
	var tip: ItemInfoTooltip = info_tooltip_scene.instantiate()
	tip.show_unique(unique_id)
	return tip


func _sub_tooltip(entry_id: int) -> Control:
	if entry_id == EMPTY_ID:
		return null
	var tip: ItemInfoTooltip = info_tooltip_scene.instantiate()
	@warning_ignore("integer_division")
	tip.show_sub(entry_id / SUB_ID_STRIDE, entry_id % SUB_ID_STRIDE)
	return tip


func _affix_tooltip(affix_id: int) -> Control:
	if affix_id == EMPTY_ID or GameData.affix(affix_id).is_empty():
		return null
	var tip: ItemInfoTooltip = info_tooltip_scene.instantiate()
	tip.show_affix(affix_id)
	return tip


func _base_fits_slot(base: Dictionary) -> bool:
	var type_name: String = str(base.get("typeName", ""))
	if IdolGrid.is_idol_key(_slot):
		var a: Vector2i = IdolGrid.anchor(_slot)
		return GameData.is_idol_type(int(base.get("type", -1))) 			and IdolGrid.fits(Build.items, a.x, a.y, int(base["baseTypeID"]), _slot)
	if _slot == "altar":
		return type_name in ItemCompare.SLOT_TYPES.get(_slot, [])
	return ItemCompare.fits_slot(_slot, base)


## Non-legacy subtypes usable by the current class.
func _sub_allowed(sub: Dictionary) -> bool:
	if int(sub.get("isLegacySubType", 0)) != 0:
		return false
	var classes: Array = sub.get("classRequirement", [])
	return classes.is_empty() or classes.has(_class_name())


func _class_name() -> String:
	return str(GameData.get_class_data(Build.class_id).get("className", ""))


func _fill_implicits(item: Dictionary) -> void:
	for child: Node in %Implicits.get_children():
		%Implicits.remove_child(child)
		child.queue_free()
	var sub: Dictionary = GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1)))
	var rolls: Array = item.get("implicit_rolls", [])
	var implicits: Array = sub.get("implicits", [])
	for j in range(implicits.size()):
		var imp: Dictionary = implicits[j]
		var row: Node = implicit_row_scene.instantiate()
		%Implicits.add_child(row)
		row.get_node("%NameLabel").text = ItemCompare.prop_title(imp)
		var slider: HSlider = row.get_node("%RollSlider")
		slider.visible = _implicit_rolls(imp)
		slider.set_value_no_signal(float(rolls[j]) if j < rolls.size() else 255.0)
		slider.value_changed.connect(_on_implicit_roll.bind(j))


## True when the implicit's value depends on the roll (a fixed value, also after rounding, gets no slider).
func _implicit_rolls(imp: Dictionary) -> bool:
	var rounding: String = str(imp.get("rounding", "Integer"))
	var mod_type: String = str(imp.get("modType", "ADDED"))
	var lo: float = float(imp.get("value", 0.0))
	var hi: float = float(imp.get("maxValue", lo))
	return not is_equal_approx(AffixMath.roll_value(lo, hi, rounding, mod_type, 0, 0.0), AffixMath.roll_value(lo, hi, rounding, mod_type, 255, 0.0))


func _fill_unique(item: Dictionary, unique_id: int) -> void:
	for child: Node in %UniqueMods.get_children():
		%UniqueMods.remove_child(child)
		child.queue_free()

	var unique: Dictionary = GameData.unique(unique_id)
	var mods: Array = unique.get("mods", [])
	var unique_rolls: Array = item.get("unique_rolls", [])

	for mod: Dictionary in mods:
		if int(mod.get("hideInTooltip", 0)) != 0:
			continue
		var roll_id: int = int(mod.get("rollID", 0))
		var row: Node = implicit_row_scene.instantiate()
		%UniqueMods.add_child(row)
		row.get_node("%NameLabel").text = ItemCompare.prop_title(mod)
		var slider: HSlider = row.get_node("%RollSlider")
		var can_roll: int = int(mod.get("canRoll", 0))
		slider.visible = can_roll == 1 and not is_equal_approx(AffixMath.unique_value(mod, 0), AffixMath.unique_value(mod, 255))
		slider.set_value_no_signal(float(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255.0)
		slider.value_changed.connect(_on_unique_roll.bind(roll_id))

	# Unique text (the set bonuses have their own block, _update_set_bonuses)
	var text_lines: PackedStringArray = []
	var descriptions: Array = unique.get("tooltipDescriptions", [])
	for desc_obj: Dictionary in descriptions:
		text_lines.append(str(desc_obj.get("description", "")))

	%UniqueText.text = ItemCompare.expand_template("\n".join(text_lines))


## Set bonuses of the edited set unique: pieces equipped and the bonus list, active ones highlighted.
func _update_set_bonuses() -> void:
	var item: Dictionary = _item()
	var unique: Dictionary = GameData.unique(int(item["unique"])) if item.has("unique") else {}
	var is_set: bool = int(unique.get("isSetItem", 0)) != 0
	%SetBonuses.visible = is_set
	for child: Node in %SetLines.get_children():
		%SetLines.remove_child(child)
		child.queue_free()
	if not is_set:
		return
	var set_id: int = int(unique.get("setID", -1))
	var set_data: Dictionary = GameData.set_data(set_id)
	var count: int = int(BuildMods.set_counts(Build).get(set_id, 0))
	var total: int = (set_data.get("items", []) as Array).size()
	%SetTitle.text = tr("Set \"%s\": %d/%d items equipped") % [str(set_data.get("setName", "")), count, total]
	var bonuses: Array = (set_data.get("tooltipDescriptions", []) as Array).duplicate()
	bonuses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("setRequirement", 0)) < int(b.get("setRequirement", 0)))
	for desc_obj: Dictionary in bonuses:
		var requirement: int = int(desc_obj.get("setRequirement", 0))
		var line: Label = set_line_scene.instantiate()
		%SetLines.add_child(line)
		line.text = ItemCompare.expand_template("(%d) %s" % [requirement, str(desc_obj.get("description", ""))])
		line.theme_type_variation = &"SetBonusActive" if requirement <= count else &"SetBonusInactive"


## The item's affixes with their editor rows (imported items have none, ItemCompare.place_affixes).
func _placed_affixes(item: Dictionary) -> Array:
	return ItemCompare.place_affixes(item.get("affixes", []), IdolGrid.is_idol_key(_slot))


## True when the item counts as corrupted: the user's flag or a corrupted subtype.
func _is_corrupted(item: Dictionary) -> bool:
	return bool(item.get("corrupted", false)) or _corrupted_subtype(item)


func _corrupted_subtype(item: Dictionary) -> bool:
	return int(GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1))).get("isCorruptedSubtype", 0)) != 0


## Affixes of the given kinds that roll on the base, split by type: {"PREFIX": [...], "SUFFIX": [...]}.
func _affix_options(base: Dictionary, kinds: Array) -> Dictionary:
	var options: Dictionary = {"PREFIX": [], "SUFFIX": []}
	if not base.is_empty():
		for aff: Dictionary in GameData.affixes_for_type(int(base.get("type", -1)), _class_name(), kinds):
			if options.has(str(aff.get("type", ""))):
				options[str(aff["type"])].append(aff)
	return options


## AFFIX_KINDS offered for the item: Weaver affixes roll only on Weaver idols (GenerateItems.IsValidAffix isWeaverIdol).
func _affix_kinds(item: Dictionary) -> Array:
	if IdolGrid.is_idol_key(_slot) and AltarMods.idol_kinds(item)["weaver"]:
		return AFFIX_KINDS
	return AFFIX_KINDS.filter(func(k: String) -> bool: return k != "IdolWeaver")


func _fill_affixes(item: Dictionary, base: Dictionary) -> void:
	var stored: Array = _placed_affixes(item)
	var is_set: bool = item.has("unique") and int(GameData.unique(int(item["unique"])).get("isSetItem", 0)) != 0
	var is_idol: bool = IdolGrid.is_idol_key(_slot)
	var options: Dictionary = _affix_options(base, _affix_kinds(item))
	var corrupted_options: Dictionary = _affix_options(base, CORRUPTED_KINDS)
	for r in range(AFFIX_ROWS.size()):
		var row: Node = %Affixes.get_node(AFFIX_ROWS[r])
		var select: SearchSelect = row.get_node("Top/AffixSelect")
		var extra: bool = r >= ItemCompare.SEALED_AFFIX_INDEX
		var kinds: Array = ["PREFIX", "SUFFIX"] if extra else (["PREFIX"] if r < 2 else ["SUFFIX"])
		var pool: Dictionary = corrupted_options if r == ItemCompare.CORRUPTED_AFFIX_INDEX else options
		var entry: Dictionary = {}
		for e: Dictionary in stored:
			if int(e.get("index", -1)) == r:
				entry = e
		var affix_id: int = int(entry.get("id", EMPTY_ID))
		select.clear()
		select.add_item(tr("— none —"), EMPTY_ID)
		for kind: String in kinds:
			for aff: Dictionary in pool[kind]:
				var special: String = str(aff.get("specialAffixType", "Standard"))
				var label: String = str(aff.get("name", ""))
				if KIND_TAGS.has(special):
					label += " (%s)" % tr(KIND_TAGS[special])
				select.add_item(label, int(aff["affixId"]))
				if special == "Set":
					select.set_item_variation(select.item_count - 1, &"RaritySet")
		# an affix the lists do not offer (another class, imported data) is still shown in its row
		if affix_id != EMPTY_ID and select.get_item_index(affix_id) < 0 and not GameData.affix(affix_id).is_empty():
			select.add_item(str(GameData.affix(affix_id).get("name", "")), affix_id)
		if extra:
			var prefix: bool = str(GameData.affix(affix_id).get("type", "PREFIX")) == "PREFIX"
			var label: String = ("Sealed prefix" if prefix else "Sealed suffix") if r == ItemCompare.SEALED_AFFIX_INDEX \
				else ("Corrupted prefix" if prefix else "Corrupted suffix")
			row.get_node("Top/KindLabel").text = tr(label)
		select.select(maxi(0, select.get_item_index(affix_id)))
		var tiers: int = GameData.affix(affix_id).get("tiers", []).size()
		var spin: SpinBox = row.get_node("Top/TierSpin")
		spin.max_value = maxi(1, tiers)
		var tier: int = clampi(int(entry.get("tier", mini(5, maxi(1, tiers)))), 1, maxi(1, tiers))
		spin.set_value_no_signal(float(tier))
		var slider: HSlider = row.get_node("Bottom/RollSlider")
		slider.max_value = maxi(1, tiers) * TIER_SPAN
		slider.tick_count = maxi(1, tiers) + 1
		slider.set_value_no_signal(float((tier - 1) * TIER_SPAN + clampi(int(entry.get("roll", 255)), 0, TIER_SPAN - 1)))
		for path: String in ["Top/TierLabel", "Top/TierSpin", "Bottom"]:
			row.get_node(path).visible = affix_id != EMPTY_ID
		# idols have one prefix and one suffix; the sealed row on regular equipment, the corrupted row on corrupted
		# items; set items show only the affixes they carry; a stored affix is always shown
		var has_affix: bool = affix_id != EMPTY_ID
		if r == ItemCompare.SEALED_AFFIX_INDEX:
			row.visible = has_affix or not (is_idol or item.has("unique") or _slot == IdolGrid.ALTAR_SLOT)
		elif r == ItemCompare.CORRUPTED_AFFIX_INDEX:
			row.visible = has_affix or (_is_corrupted(item) and _slot != IdolGrid.ALTAR_SLOT)
		else:
			row.visible = not (is_idol and (r == 1 or r == 3)) and (has_affix or not is_set)


# --- storing user edits ---------------------------------------------------------------

func _on_unique_selected(index: int) -> void:
	if _filling:
		return
	var unique_id: int = %UniqueSelect.get_item_id(index)
	if unique_id == UNIQUE_EMPTY_ID:
		var item: Dictionary = _item().duplicate(true)
		item.erase("unique")
		item.erase("unique_rolls")
		_commit(item)
	else:
		var item: Dictionary = _item().duplicate(true)
		var new_item: Dictionary = ItemCompare.unique_item(unique_id)
		_keep_name(new_item, item)
		_commit(new_item)
	_fill()


## Copies the user's custom name of `old_item` into a rebuilt item.
func _keep_name(new_item: Dictionary, old_item: Dictionary) -> void:
	if old_item.has("name"):
		new_item["name"] = old_item["name"]


## The Corrupted box: sets the item flag (it opens the corrupted affix row); clearing it drops the corrupted affix.
func _on_corrupted_toggled(on: bool) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	if item.is_empty():
		return
	if on:
		item["corrupted"] = true
	else:
		item.erase("corrupted")
		item["affixes"] = _placed_affixes(item).filter(func(entry: Dictionary) -> bool:
			return int(entry.get("index", -1)) != ItemCompare.CORRUPTED_AFFIX_INDEX)
	_commit(item)
	_fill()


func _on_name_changed(text: String) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	if item.is_empty():
		return
	var custom_name: String = text.strip_edges()
	if custom_name.is_empty():
		item.erase("name")
	else:
		item["name"] = custom_name
	_commit(item)


func _on_unique_roll(value: float, roll_id: int) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var unique_rolls: Array = item.get("unique_rolls", [])
	while unique_rolls.size() <= roll_id:
		unique_rolls.append(255)
	unique_rolls[roll_id] = int(value)
	item["unique_rolls"] = unique_rolls
	_commit(item)


func _on_sub_selected(index: int) -> void:
	if _filling:
		return
	var entry_id: int = %SubSelect.get_item_id(index)
	if entry_id == EMPTY_ID:
		_remove()
	else:
		var item: Dictionary = _item()
		@warning_ignore("integer_division")
		var base_id: int = entry_id / SUB_ID_STRIDE
		# another base starts without affixes; the same base keeps them
		var kept_affixes: Array = item.get("affixes", []) if int(item.get("base", -1)) == base_id else []
		var new_item: Dictionary = ItemCompare.new_item(base_id, entry_id % SUB_ID_STRIDE, kept_affixes)
		# Weaver affixes leave with the Weaver subtype
		if not AltarMods.idol_kinds(new_item)["weaver"]:
			new_item["affixes"] = new_item.get("affixes", []).filter(func(a: Dictionary) -> bool:
				return str(GameData.affix(int(a.get("id", -1))).get("specialAffixType", "")) != "IdolWeaver")
		_keep_name(new_item, item)
		_commit(new_item)
	_fill()


## Stash mode: turns the item into a fresh one of the first base of the chosen kind; the custom name stays.
func _on_type_selected(index: int) -> void:
	if _filling:
		return
	var kind: String = TYPE_SLOTS[%TypeSelect.get_item_id(index)]
	var base_id: int = ItemCompare.first_base(kind)
	if kind == ("ring1" if _slot == "ring2" else _slot) or base_id < 0:
		_fill()
		return
	var old_item: Dictionary = _item()
	_slot = kind
	var new_item: Dictionary = ItemCompare.new_item(base_id, ItemCompare.default_sub(GameData.item_base(base_id), _class_name()), [])
	_keep_name(new_item, old_item)
	_put(new_item)
	_fill()


func _on_implicit_roll(value: float, index: int) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var rolls: Array = item.get("implicit_rolls", [])
	while rolls.size() <= index:
		rolls.append(255)
	rolls[index] = int(value)
	item["implicit_rolls"] = rolls
	_commit(item)


func _on_clear() -> void:
	_remove()
	_fill()


## Moves the item as shown (unsaved edits included) to the stash.
func _on_stash_move() -> void:
	_save()
	Build.unequip_to_stash(_slot)
	_load()
	_fill()


## Stash mode: equips the item as shown into its slot; the item that was there takes its place in the stash.
func _on_equip() -> void:
	_save()
	var slot: String = _slot
	Build.equip_from_stash(_stash_index, slot)
	slot_requested.emit(slot)


## Reads the four affix rows into Build. refill = true when the affix choice changed (tier range may differ).
func _store_affixes(refill: bool) -> void:
	if _filling:
		return
	var item: Dictionary = _item().duplicate(true)
	var affixes: Array = []
	for r in range(AFFIX_ROWS.size()):
		var row: Node = %Affixes.get_node(AFFIX_ROWS[r])
		var affix_id: int = row.get_node("Top/AffixSelect").get_selected_id()
		if affix_id == EMPTY_ID or not row.visible:
			continue
		var tiers: int = GameData.affix(affix_id).get("tiers", []).size()
		var tier_roll: Vector2i = _slider_position(row.get_node("Bottom/RollSlider"), tiers)
		# keep the tier box in step with the slider
		(row.get_node("Top/TierSpin") as SpinBox).set_value_no_signal(float(tier_roll.x))
		var stored: Dictionary = {
			"id": affix_id, "index": r, "kind": "prefix" if r < 2 else "suffix",
			"tier": tier_roll.x, "roll": tier_roll.y,
		}
		if r >= ItemCompare.SEALED_AFFIX_INDEX:
			stored["kind"] = "prefix" if str(GameData.affix(affix_id).get("type", "")) == "PREFIX" else "suffix"
			stored["sealed" if r == ItemCompare.SEALED_AFFIX_INDEX else "corrupted"] = true
		affixes.append(stored)
	item["affixes"] = affixes
	_commit(item)
	if refill:
		_fill()


## (tier, roll) of an affix roll slider: value = (tier - 1) * TIER_SPAN + roll; the very end of the range is the
## top roll of the last tier.
func _slider_position(slider: HSlider, tiers: int) -> Vector2i:
	var tier_count: int = maxi(1, tiers)
	var value: int = int(slider.value)
	var tier: int = mini(floori(float(value) / TIER_SPAN) + 1, tier_count)
	return Vector2i(tier, clampi(value - (tier - 1) * TIER_SPAN, 0, TIER_SPAN - 1))


## The tier box was edited: move the slider to the same roll within the new tier, then store.
func _on_tier_spin(value: float, row: Node) -> void:
	if _filling:
		return
	var slider: HSlider = row.get_node("Bottom/RollSlider")
	var tiers: int = GameData.affix(row.get_node("Top/AffixSelect").get_selected_id()).get("tiers", []).size()
	var roll: int = _slider_position(slider, tiers).y
	var tier: int = clampi(int(value), 1, maxi(1, tiers))
	slider.set_value_no_signal(float((tier - 1) * TIER_SPAN + roll))
	_store_affixes(false)


## An edit of the shown item: it stays an unsaved draft; an item put into an empty slot is stored at once.
func _commit(item: Dictionary) -> void:
	if _saved_item.is_empty():
		_put(item)
	else:
		_draft = item
	_update_values()
	_queue_diff()


## Save: stores the draft in the slot or the stash entry.
func _save() -> void:
	if is_dirty():
		_put(_draft.duplicate(true))
	_queue_diff()


## Discards the unsaved edits.
func _revert() -> void:
	_load()
	_fill()


# --- unsaved changes ---------------------------------------------------------------------

## Shows or hides %Pending; its stat lines follow the edits at most every DIFF_INTERVAL_MSEC (a dragged slider fires
## often); the queued update reads the latest draft, so the last edit is always shown.
func _queue_diff() -> void:
	%Pending.visible = is_dirty()
	if not is_dirty() or _diff_queued:
		return
	_diff_queued = true
	var wait_msec: int = _last_diff_msec + DIFF_INTERVAL_MSEC - Time.get_ticks_msec()
	if wait_msec <= 0 or not is_inside_tree():
		_update_diff.call_deferred()
	else:
		%DiffTimer.start(wait_msec / 1000.0)


## The stat changes saving the draft would give: an equipment slot against the build, an unequipped item against
## the stored version equipped in its slot.
func _update_diff() -> void:
	_diff_queued = false
	_last_diff_msec = Time.get_ticks_msec()
	for child: Node in %PendingLines.get_children():
		%PendingLines.remove_child(child)
		child.queue_free()
	%Pending.visible = is_dirty()
	if not is_dirty():
		return
	if _stash_index >= 0:
		%PendingHeader.text = tr("Saving the changes will give you (with the item equipped in %s):") % ItemCompare.slot_title(_slot)
	else:
		%PendingHeader.text = tr("Saving the changes will give you:")
	if _slot == "":
		%PendingDps.visible = false
		%PendingNone.visible = true
		return
	if _base_snapshot.is_empty():
		_base_snapshot = ItemCompare.snapshot(Build) if _stash_index < 0 else ItemCompare.snapshot_with_item(Build, _slot, _saved_item)
	var before: Dictionary = _base_snapshot.duplicate()
	var after: Dictionary = ItemCompare.snapshot_with_item(Build, _slot, _draft)
	_show_dps(before.get("dps", {}), after.get("dps", {}))
	before.erase("dps")
	after.erase("dps")
	var lines: Array[Dictionary] = ItemCompare.diff(before, after)
	for line: Dictionary in lines:
		var label: Label = diff_line_scene.instantiate()
		%PendingLines.add_child(label)
		label.text = str(line.get("text", ""))
		label.theme_type_variation = &"DeltaUp" if float(line.get("delta", 0.0)) > 0.0 else &"DeltaDown"
	%PendingLines.visible = not lines.is_empty()
	%PendingNone.visible = lines.is_empty() and not %PendingDps.visible


## %PendingDps: DPS vs enemy of the skill selected in Calculations before and after saving, also when it stays the same
## (snapshot entries "dps"; hidden when the skill has no DPS).
func _show_dps(before: Dictionary, after: Dictionary) -> void:
	var dps_label: Label = %PendingDps
	var source: Dictionary = after if not after.is_empty() else before
	dps_label.visible = not source.is_empty()
	if source.is_empty():
		return
	var old_value: float = float(before.get("value", 0.0))
	var new_value: float = float(after.get("value", 0.0))
	var delta: float = new_value - old_value
	var title: String = str(source.get("label", ""))
	if absf(delta) < ItemCompare.EPSILON:
		dps_label.text = tr("%s: %s (no change)") % [title, LE.fmt_num(new_value)]
		dps_label.theme_type_variation = &"MutedLabel"
	else:
		dps_label.text = "%s: %s → %s (%s)" % [title, LE.fmt_num(old_value), LE.fmt_num(new_value), ItemCompare.format_delta(delta, false)]
		dps_label.theme_type_variation = &"DeltaUp" if delta > 0.0 else &"DeltaDown"


# --- value labels ----------------------------------------------------------------------

func _update_values() -> void:
	var item: Dictionary = _item()
	var unique_id: int = int(item.get("unique", UNIQUE_EMPTY_ID))

	# Update unique mod values
	if unique_id != UNIQUE_EMPTY_ID:
		var unique: Dictionary = GameData.unique(unique_id)
		var mods: Array = unique.get("mods", [])
		var unique_rolls: Array = item.get("unique_rolls", [])
		var unique_mod_rows: Array = %UniqueMods.get_children()
		var mod_row_index: int = 0
		for mod: Dictionary in mods:
			if int(mod.get("hideInTooltip", 0)) != 0:
				continue
			if mod_row_index >= unique_mod_rows.size():
				break
			var roll_id: int = int(mod.get("rollID", 0))
			var roll: int = int(unique_rolls[roll_id]) if roll_id < unique_rolls.size() else 255
			var v: float = AffixMath.unique_value(mod, roll)
			unique_mod_rows[mod_row_index].get_node("%ValueLabel").text = ItemCompare.format_value(mod, v)
			unique_mod_rows[mod_row_index].get_node("%RollSlider").set_value_no_signal(float(roll))
			mod_row_index += 1

	# Implicits of the base apply to regular and unique items
	var base: Dictionary = GameData.item_base(int(item.get("base", -1)))
	var sub: Dictionary = GameData.item_sub(int(item.get("base", -1)), int(item.get("sub", -1)))
	var rolls: Array = item.get("implicit_rolls", [])
	var implicits: Array = sub.get("implicits", [])
	var rows: Array = %Implicits.get_children()
	for j in range(mini(rows.size(), implicits.size())):
		var imp: Dictionary = implicits[j]
		var roll: int = int(rolls[j]) if j < rolls.size() else 255
		var v: float = AffixMath.roll_value(float(imp["value"]), float(imp.get("maxValue", imp["value"])),
			str(imp.get("rounding", "Integer")), str(imp.get("modType", "ADDED")), roll, 0.0)
		rows[j].get_node("%ValueLabel").text = ItemCompare.format_value(imp, v)

	var used: Array[int] = []
	for entry: Dictionary in _placed_affixes(item):
		var index: int = int(entry.get("index", 0))
		var aff: Dictionary = GameData.affix(int(entry["id"]))
		var tiers: Array = aff.get("tiers", [])
		var tier: int = int(entry.get("tier", 1))
		if index < 0 or index >= AFFIX_ROWS.size() or tier < 1 or tier > tiers.size():
			continue
		used.append(index)
		var m: float = AffixMath.effect_modifier(float(base.get("affixEffectModifier", 0.0)), float(aff.get("standardAffixEffectModifier", 0.0)))
		var lines: PackedStringArray = []
		var props: Array = aff.get("properties", [])
		var ranges: Array = tiers[tier - 1].get("rolls", [])
		for j in range(mini(props.size(), ranges.size())):
			var prop: Dictionary = props[j]
			var v: float = AffixMath.roll_value(float(ranges[j][0]), float(ranges[j][1]), str(prop.get("rounding", "Integer")),
				str(prop.get("modType", "ADDED")), int(entry.get("roll", 255)), m)
			lines.append("%s %s" % [ItemCompare.format_value(prop, v), ItemCompare.prop_title(prop)])
		%Affixes.get_node(AFFIX_ROWS[index]).get_node("Bottom/ValueLabel").text = "\n".join(lines)
	for r in range(AFFIX_ROWS.size()):
		if not used.has(r):
			%Affixes.get_node(AFFIX_ROWS[r]).get_node("Bottom/ValueLabel").text = ""
