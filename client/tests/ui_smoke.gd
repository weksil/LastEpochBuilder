extends Node

## Headless UI smoke run: drives main.tscn through every tab; script errors show up in the console.
## Run: Godot_console.exe --headless --path client res://tests/ui_smoke.tscn


var tree_switch_failed: bool = false
## Idols offered in the Items tab, other items in the Idols tab, or broken sealed / corrupted affix rows.
var split_failed: bool = false


func _ready() -> void:
	# a script error stops this coroutine; never hang the headless run
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("UI SMOKE TIMEOUT")
		get_tree().quit(1))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)

	var class_select: OptionButton = main.get_node("%ClassSelect")
	class_select.select(1)
	class_select.item_selected.emit(1)
	await _frames(2)

	var mastery: OptionButton = main.get_node("%MasterySelect")
	mastery.select(1)
	mastery.item_selected.emit(1)
	await _frames(2)

	var tree: Dictionary = GameData.get_passive_tree(1)
	for node: Dictionary in tree["nodes"]:
		if int(node["mastery"]) == 0:
			Build.add_point(int(node["id"]))
	await _frames(2)

	var tabs: TabContainer = main.get_node("%Tabs")
	for i in range(tabs.get_tab_count()):
		tabs.current_tab = i
		await _frames(2)
		print("tab ok: %s" % tabs.get_tab_title(i))

	# skills tab: choose Fireball in slot 1 through the OptionButton
	tabs.current_tab = 1
	await _frames(1)
	var slot: Node = tabs.get_child(1).get_node("%Slots").get_child(0)
	var select: OptionButton = slot.get_node("%SkillSelect")
	for i in range(select.item_count):
		if select.get_item_metadata(i) == "fi9":
			select.select(i)
			select.item_selected.emit(i)
	slot.get_node("%SelectButton").toggled.emit(true)
	await _frames(2)
	var fb: Dictionary = GameData.get_skill_tree("fi9")
	for node: Dictionary in fb["nodes"]:
		Build.add_skill_point(0, int(node["id"]))
	await _frames(2)
	print("skill points: %d" % Build.skill_points_spent(0))
	# switching the shown tree: "Tree" of slot 2 (another skill) and back to slot 1
	var skills_tab: Node = tabs.get_child(1)
	var slot2: Node = skills_tab.get_node("%Slots").get_child(1)
	var select2: OptionButton = slot2.get_node("%SkillSelect")
	select2.select(select2.item_count - 1)
	select2.item_selected.emit(select2.item_count - 1)
	slot2.get_node("%SelectButton").toggled.emit(true)
	await _frames(2)
	var title2: String = skills_tab.get_node("%TreeTitle").text
	slot.get_node("%SelectButton").toggled.emit(true)
	await _frames(2)
	var title1: String = skills_tab.get_node("%TreeTitle").text
	print("tree titles: slot 2 \"%s\", slot 1 \"%s\"" % [title2, title1])
	if title2 == title1 or title1 != str(GameData.get_ability("fi9").get("abilityName", "")):
		tree_switch_failed = true
		print("FAIL: skill tree does not follow the selected slot")

	# items tab: pick a wand through the editor
	tabs.current_tab = 2
	await _frames(1)
	var items_tab: Node = tabs.get_child(2)
	var weapon_row: Node = items_tab.get_node("%SlotList/Slot_weapon")
	items_tab._edit_slot("weapon")
	await _frames(1)
	var editor: Node = items_tab.get_node("%ItemEditor")
	var sub_select: SearchSelect = editor.get_node("%SubSelect")
	for i in range(sub_select.item_count):
		if sub_select.get_item_text(i).to_lower().contains("wand"):
			sub_select.select(i)
			sub_select.item_selected.emit(i)
			break
	await _frames(2)
	var prefix: Node = editor.get_node("%Affixes/Prefix1")
	var affix_select: SearchSelect = prefix.get_node("Top/AffixSelect")
	if affix_select.item_count > 1:
		affix_select.select(1)
		affix_select.item_selected.emit(1)
	await _frames(2)
	# the affix is an unsaved edit: the build keeps the old item, the diff block shows up, Save stores it
	var pending_failed: bool = false
	if not editor.is_dirty() or not editor.get_node("%Pending").visible or Build.items.get("weapon", {}) == editor._item():
		pending_failed = true
		print("FAIL: an affix edit did not stay an unsaved draft with the diff block shown")
	editor._update_diff()
	print("pending lines: %d" % editor.get_node("%PendingLines").get_child_count())
	print("pending dps: %s" % editor.get_node("%PendingDps").text)
	if editor.get_node("%PendingLines").get_child_count() == 0 and not editor.get_node("%PendingNone").visible 			and not editor.get_node("%PendingDps").visible:
		pending_failed = true
		print("FAIL: the unsaved-changes block shows neither DPS, stat lines nor \"No stat changes\"")
	editor.get_node("%SaveButton").pressed.emit()
	await _frames(2)
	if editor.is_dirty() or editor.get_node("%Pending").visible or Build.items.get("weapon", {}) != editor._item():
		pending_failed = true
		print("FAIL: Save did not store the edited weapon")
	print("weapon: %s" % weapon_row.get_node("%ItemButton").text)
	print("item: %s" % str(Build.items.get("weapon", {})))
	# hover tooltips of the search lists
	var hover_failed: bool = false
	var hover_selects: Array[SearchSelect] = [editor.get_node("%UniqueSelect"), editor.get_node("%SubSelect"), affix_select]
	for hover_select: SearchSelect in hover_selects:
		var hover_id: int = -1
		for i in range(hover_select.item_count):
			var entry_id: int = hover_select.get_item_id(i)
			if entry_id != ItemEditor.EMPTY_ID and entry_id != ItemEditor.UNIQUE_EMPTY_ID:
				hover_id = entry_id
				break
		var hover_tip: Variant = hover_select.tooltip_builder.call(hover_id) if hover_id >= 0 else null
		if hover_tip is Control:
			(hover_tip as Control).free()
		else:
			hover_failed = true
			print("FAIL: no hover tooltip for the first entry of %s" % hover_select.name)

	# the Items tab offers no idols in any slot; a regular item has the sealed row
	for item_slot: String in BuildMods.SLOTS:
		items_tab._edit_slot(item_slot)
		await _frames(1)
		_check_editor_bases(editor, false, item_slot)
	items_tab._edit_slot("weapon")
	await _frames(1)
	if not editor.get_node("%Affixes/Sealed").visible:
		split_failed = true
		print("FAIL: no sealed affix row on a regular weapon")
	_check_corrupted_row(editor, "weapon")

	# unique helmet through the editor
	var helmet_row: Node = items_tab.get_node("%SlotList/Slot_helmet")
	items_tab._edit_slot("helmet")
	await _frames(1)
	var unique_select: SearchSelect = editor.get_node("%UniqueSelect")
	var snowblind_id: int = -1
	for i in range(unique_select.item_count):
		if unique_select.get_item_text(i).begins_with("Snowblind"):
			snowblind_id = unique_select.get_item_id(i)
	# open the popup, search by a name fragment and pick the single hit with Enter
	unique_select.pressed.emit()
	await _frames(2)
	var unique_search: LineEdit = unique_select.get_node("%Search")
	var unique_list: ItemList = unique_select.get_node("%List")
	var search_failed: bool = snowblind_id < 0 or unique_list.item_count != unique_select.item_count
	unique_search.text = "snowbl"
	unique_search.text_changed.emit("snowbl")
	if unique_list.item_count != 1:
		search_failed = true
		print("FAIL: searching \"snowbl\" gave %d rows instead of 1" % unique_list.item_count)
	unique_search.text_submitted.emit("snowbl")
	if search_failed:
		print("FAIL: the searchable unique select did not list every item or Snowblind")
	await _frames(2)
	editor.get_node("%SaveButton").pressed.emit()
	await _frames(2)
	print("unique helmet: %s / %s" % [helmet_row.get_node("%ItemButton").text, str(Build.items.get("helmet", {}))])
	if int(Build.items.get("helmet", {}).get("unique", -1)) != snowblind_id:
		search_failed = true
		print("FAIL: Enter in the search did not choose Snowblind")
	print("unique rows: %d, text: %s" % [editor.get_node("%UniqueMods").get_child_count(), editor.get_node("%UniqueText").text.replace("
", " | ")])

	# unequipped items: copy the helmet to the stash, open the choice list, add an item and equip it
	var failed_items: bool = false
	editor.get_node("%StashCopyButton").pressed.emit()
	await _frames(2)
	var stash_rows: Node = items_tab.get_node("%StashRows")
	print("stash: %d, stash buttons: %d" % [Build.stash.size(), stash_rows.get_child_count()])
	if Build.stash.size() != 1 or stash_rows.get_child_count() != 1:
		failed_items = true
		print("FAIL: Copy to stash did not add an item")
	items_tab._show_choices("helmet", helmet_row.get_node("%ItemButton"))
	await _frames(2)
	var choice_rows: Node = items_tab.get_node("%ChoiceRows")
	print("choices: %d" % choice_rows.get_child_count())
	if choice_rows.get_child_count() < 3:
		failed_items = true
		print("FAIL: the helmet choice list lacks entries (none, equipped, stash copy)")
	else:
		var tip: Node = choice_rows.get_child(choice_rows.get_child_count() - 1)._make_custom_tooltip("")
		print("choice tooltip lines: %d" % tip.get_node("%Lines").get_child_count())
		tip.free()
	items_tab.get_node("%ChoicePopup").hide()
	items_tab.get_node("%AddButton").pressed.emit()
	await _frames(2)
	var equip_button: Button = editor.get_node("%EquipButton")
	print("stash after add: %d, equip button visible: %s" % [Build.stash.size(), equip_button.visible])
	if Build.stash.size() != 2 or not equip_button.visible:
		failed_items = true
		print("FAIL: the + button did not add an editable stash item")
	if not editor.get_node("%TypeRow").visible:
		failed_items = true
		print("FAIL: the Type row is hidden for an unequipped item")
	# custom name
	var name_edit: LineEdit = editor.get_node("%NameEdit")
	name_edit.text = "My test helm"
	name_edit.text_changed.emit("My test helm")
	editor.get_node("%SaveButton").pressed.emit()
	await _frames(2)
	var stash_button: Button = items_tab.get_node("%StashRows").get_child(1)
	print("named item: %s / button \"%s\"" % [str(Build.stash[1].get("name", "")), stash_button.text])
	if str(Build.stash[1].get("name", "")) != "My test helm" or stash_button.text != "My test helm":
		failed_items = true
		print("FAIL: the custom item name was not stored or shown")
	# type -> relic (id 9)
	var type_select: OptionButton = editor.get_node("%TypeSelect")
	type_select.select(type_select.get_item_index(9))
	type_select.item_selected.emit(type_select.get_item_index(9))
	await _frames(2)
	var relic_base: Dictionary = GameData.item_base(int(Build.stash[1].get("base", -1)))
	if relic_base.is_empty() or not ItemCompare.fits_slot("relic", relic_base) or str(Build.stash[1].get("name", "")) != "My test helm":
		failed_items = true
		print("FAIL: the Type row did not turn the item into a relic with its name kept: %s" % str(Build.stash[1]))
	# one slider for tier and roll: put a 3rd tier affix on the first prefix of the weapon-type item
	type_select.select(type_select.get_item_index(5))
	type_select.item_selected.emit(type_select.get_item_index(5))
	await _frames(2)
	var tier_prefix: Node = editor.get_node("%Affixes/Prefix1")
	var tier_affix_select: SearchSelect = tier_prefix.get_node("Top/AffixSelect")
	var tier_picked: bool = false
	for i in range(1, tier_affix_select.item_count):
		if GameData.affix(tier_affix_select.get_item_id(i)).get("tiers", []).size() >= 3:
			tier_affix_select.select(i)
			tier_affix_select.item_selected.emit(i)
			tier_picked = true
			break
	await _frames(2)
	if tier_picked:
		var tier_slider: HSlider = tier_prefix.get_node("Bottom/RollSlider")
		tier_slider.value = 256 * 2 + 100
		tier_slider.value_changed.emit(256.0 * 2 + 100)
		editor.get_node("%SaveButton").pressed.emit()
		await _frames(2)
		var stored: Array = Build.stash[1].get("affixes", [])
		print("tier slider affix: %s" % str(stored))
		if stored.size() != 1 or int(stored[0]["tier"]) != 3 or int(stored[0]["roll"]) != 100 \
				or int((tier_prefix.get_node("Top/TierSpin") as SpinBox).value) != 3:
			failed_items = true
			print("FAIL: the tier+roll slider did not store tier 3, roll 100")
	else:
		print("tier slider: no weapon affix with 3 tiers, skipped")
	equip_button.pressed.emit()
	await _frames(2)
	print("stash after equip: %d" % Build.stash.size())
	if Build.stash.size() != 2 or not Build.items.has("helmet"):
		failed_items = true
		print("FAIL: equipping a stash item did not swap it with the equipped one")

	# blessings tab: select a blessing in the first timeline
	tabs.current_tab = 4
	await _frames(1)
	var blessings_tab: Node = tabs.get_child(4)
	var blessings_rows: Array = blessings_tab.get_node("%Rows").get_children()
	if blessings_rows.size() > 0:
		var first_row: Node = blessings_rows[0]
		var blessing_select: OptionButton = first_row.get_node("%BlessingSelect")
		if blessing_select.item_count > 1:
			blessing_select.select(1)
			blessing_select.item_selected.emit(1)
		await _frames(1)
		var roll_slider: HSlider = first_row.get_node("%RollSlider")
		roll_slider.value = 128
		roll_slider.value_changed.emit(128.0)
	await _frames(2)
	print("blessings: %s" % str(Build.blessings))

	# idols tab: place an idol at the first open cell and give it an affix
	tabs.current_tab = 3
	await _frames(1)
	var idols_tab: Node = tabs.get_child(3)
	if idols_tab.get_node("%EditorScroll").visible:
		split_failed = true
		print("FAIL: the idol editor is shown before a cell is picked")
	for cell: Node in idols_tab.get_node("%Grid").get_children():
		if not cell.disabled:
			cell.pressed.emit()
			break
	await _frames(1)
	var idol_editor: Node = idols_tab.get_node("%ItemEditor")
	if not idols_tab.get_node("%EditorScroll").visible:
		split_failed = true
		print("FAIL: the idol editor is hidden after a cell is picked")
	_check_editor_bases(idol_editor, true, "idol cell")
	var idol_sub: SearchSelect = idol_editor.get_node("%SubSelect")
	if idol_sub.item_count > 1:
		idol_sub.select(1)
		idol_sub.item_selected.emit(1)
	await _frames(2)
	var idol_affix: SearchSelect = idol_editor.get_node("%Affixes/Suffix1").get_node("Top/AffixSelect")
	if idol_affix.item_count > 1:
		idol_affix.select(1)
		idol_affix.item_selected.emit(1)
	idol_editor.get_node("%SaveButton").pressed.emit()
	await _frames(2)
	if idol_editor.get_node("%Affixes/Sealed").visible:
		split_failed = true
		print("FAIL: an idol shows the sealed affix row")
	_check_corrupted_row(idol_editor, "idol")
	for item_slot: String in Build.items:
		if IdolGrid.is_idol_key(item_slot):
			print("idol %s: %s" % [item_slot, str(Build.items[item_slot])])

	# config tab: shock stacks and boss
	tabs.current_tab = 7
	await _frames(1)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 10)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "ArmourShred"), 20)
	await _frames(2)

	# calcs tab
	tabs.current_tab = 5
	await _frames(3)
	var calcs: Node = tabs.get_child(5)
	var section_count: int = 0
	for column: String in ["%Left", "%Right"]:
		section_count += calcs.get_node(column).get_child_count()
	print("calc sections: %d" % section_count)
	var summary: Label = main.get_node("Margin/Layout/Split/StatsPanel/VBox/SummaryCard/SummaryBox/SkillSummary")
	print("summary: %s" % summary.text)

	# instant updates: typing in a SpinBox applies without Enter and the rows are updated in place
	var failed: bool = false
	var hits_spin: SpinBox = calcs.get_node("%HitsSpin")
	var edit: LineEdit = hits_spin.get_line_edit()
	edit.text = "2"
	edit.text_changed.emit("2")
	await _frames(3)
	var rows_before: Array = calcs._row_nodes.duplicate()
	edit.text = "3"
	edit.text_changed.emit("3")
	await _frames(3)
	var hits_now: float = float(Build.skills[Build.selected_skill]["hits"])
	print("typed hits: %s" % hits_now)
	if not is_equal_approx(hits_now, 3.0):
		failed = true
		print("FAIL: typed text was not applied")
	if calcs._row_nodes.size() != rows_before.size() or (not rows_before.is_empty() and calcs._row_nodes[0] != rows_before[0]):
		failed = true
		print("FAIL: calc rows were rebuilt on a value change")
	var summary_tile: Label = calcs.get_node("%Summary").get_node("%DpsTile").get_node("%Value")
	print("headline DPS: %s" % summary_tile.text)
	if summary_tile.text == "—":
		failed = true
		print("FAIL: headline DPS is empty")
	# buffs panel lists the equipped skills
	print("buff rows: %d" % calcs.get_node("%Buffs").get_node("%List").get_child_count())
	# defense tab: a boss preset through the dropdown, corruption typed in the tab goes to the enemy, tiles filled
	tabs.current_tab = 6
	await _frames(3)
	var defense: Node = tabs.get_child(6)
	var group_select: SearchSelect = defense.get_node("%GroupSelect")
	group_select.select(1)
	group_select.item_selected.emit(1)
	await _frames(2)
	var attack_select: SearchSelect = defense.get_node("%AttackSelect")
	attack_select.select(1)
	attack_select.item_selected.emit(1)
	await _frames(2)
	if DefenseCalc.group_of(str(Build.defense["attack"])) != str(DefenseCalc.groups()[1]["key"]) or attack_select.item_count < 2:
		failed = true
		print("FAIL: defense group / attack was not applied: %s" % str(Build.defense["attack"]))
	var corruption_edit: LineEdit = (defense.get_node("%CorruptionSpin") as SpinBox).get_line_edit()
	corruption_edit.text = "200"
	corruption_edit.text_changed.emit("200")
	await _frames(3)
	var ehp_text: String = defense.get_node("%EhpTile").get_node("%Value").text
	print("defense: %s, corruption %d, EHP %s" % [str(Build.defense["attack"]), int(Build.enemy["corruption"]), ehp_text])
	if int(Build.enemy["corruption"]) != 200 or ehp_text == "—":
		failed = true
		print("FAIL: defense tab corruption or EHP tile")
	Build.set_enemy("corruption", 0)
	# conditions: reset buttons and the show-all switch
	tabs.current_tab = 7
	await _frames(3)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 4)
	await _frames(2)
	Build.clear_enemy_ailments()
	await _frames(2)
	if not (Build.enemy["ailments"] as Dictionary).is_empty():
		failed = true
		print("FAIL: clear_enemy_ailments")
	Build.set_player_state("haste", true)
	Build.reset_player_conditions()
	if bool(Build.player_state["haste"]):
		failed = true
		print("FAIL: reset_player_conditions")
	failed = failed or split_failed or tree_switch_failed or failed_items or search_failed or hover_failed or pending_failed
	# interface language: the Russian catalogue (res://i18n/ru.po) is loaded and switching the locale works
	var saved_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	# the Russian text is spelled with escapes: no Cyrillic in the sources
	if LE.t("DPS vs enemy") != "DPS \u043f\u043e \u0432\u0440\u0430\u0433\u0443":
		failed = true
		print("FAIL: ru locale does not translate \"DPS vs enemy\" (is ru.po loaded?): %s" % LE.t("DPS vs enemy"))
	TranslationServer.set_locale("en")
	if LE.t("DPS vs enemy") != "DPS vs enemy":
		failed = true
		print("FAIL: en locale changes \"DPS vs enemy\"")
	TranslationServer.set_locale(saved_locale)
	print("UI SMOKE %s" % ("FAIL" if failed else "DONE"))
	get_tree().quit(1 if failed else 0)


## Every base and unique the editor offers is an idol (want_idol) or none is.
func _check_editor_bases(editor: Node, want_idol: bool, label: String) -> void:
	var sub_select: SearchSelect = editor.get_node("%SubSelect")
	var unique_select: SearchSelect = editor.get_node("%UniqueSelect")
	var base_ids: Array[int] = []
	for i in range(sub_select.item_count):
		if sub_select.get_item_id(i) != ItemEditor.EMPTY_ID:
			@warning_ignore("integer_division")
			base_ids.append(sub_select.get_item_id(i) / ItemEditor.SUB_ID_STRIDE)
	for i in range(unique_select.item_count):
		if unique_select.get_item_id(i) != ItemEditor.UNIQUE_EMPTY_ID:
			base_ids.append(int(GameData.unique(unique_select.get_item_id(i)).get("baseType", -1)))
	if want_idol and sub_select.item_count < 2:
		split_failed = true
		print("FAIL: %s offers no idol bases" % label)
	for base_id: int in base_ids:
		if GameData.is_idol_type(int(GameData.item_base(base_id).get("type", -1))) != want_idol:
			split_failed = true
			print("FAIL: %s offers %s" % [label, GameData.display_name(GameData.item_base(base_id))])
			return
	print("%s: %d bases and uniques, all %s" % [label, base_ids.size(), "idols" if want_idol else "non-idols"])


## The Corrupted box opens the corrupted row with corruption affixes only; clearing it closes the row again.
func _check_corrupted_row(editor: Node, label: String) -> void:
	var check: CheckBox = editor.get_node("%CorruptedCheck")
	var row: Node = editor.get_node("%Affixes/Corrupted")
	check.button_pressed = true
	var select: SearchSelect = row.get_node("Top/AffixSelect")
	var count: int = 0
	for i in range(select.item_count):
		var affix: Dictionary = GameData.affix(select.get_item_id(i))
		if select.get_item_id(i) != ItemEditor.EMPTY_ID:
			count += 1
			if str(affix.get("specialAffixType", "")) != "Corrupted":
				split_failed = true
				print("FAIL: %s corrupted row offers %s" % [label, affix.get("name", "?")])
				break
	if not row.visible or count == 0:
		split_failed = true
		print("FAIL: %s: the Corrupted box does not open a corrupted row with affixes" % label)
	check.button_pressed = false
	if row.visible:
		split_failed = true
		print("FAIL: %s: clearing Corrupted keeps the corrupted row" % label)
	editor._revert()
	print("%s corrupted affixes: %d" % [label, count])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
