extends Node

## Headless UI smoke run: drives main.tscn through every tab; script errors show up in the console.
## Run: Godot_console.exe --headless --path client res://tests/ui_smoke.tscn


func _ready() -> void:
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

	# items tab: pick a wand through the editor
	tabs.current_tab = 2
	await _frames(1)
	var items_tab: Node = tabs.get_child(2)
	var weapon_button: Button = items_tab.get_node("%SlotList/Slot_weapon")
	weapon_button.pressed.emit()
	await _frames(1)
	var editor: Node = items_tab.get_node("%ItemEditor")
	var base_select: OptionButton = editor.get_node("%BaseSelect")
	for i in range(base_select.item_count):
		if base_select.get_item_text(i).to_lower().contains("wand"):
			base_select.select(i)
			base_select.item_selected.emit(i)
			break
	await _frames(2)
	var prefix: Node = editor.get_node("%Affixes/Prefix1")
	var affix_select: OptionButton = prefix.get_node("Top/AffixSelect")
	if affix_select.item_count > 1:
		affix_select.select(1)
		affix_select.item_selected.emit(1)
	await _frames(2)
	print("weapon: %s" % weapon_button.text)
	print("item: %s" % str(Build.items.get("weapon", {})))

	# unique helmet through the editor
	var helmet_button: Button = items_tab.get_node("%SlotList/Slot_helmet")
	helmet_button.pressed.emit()
	await _frames(1)
	var unique_select: OptionButton = editor.get_node("%UniqueSelect")
	for i in range(unique_select.item_count):
		if unique_select.get_item_text(i) == "Snowblind":
			unique_select.select(i)
			unique_select.item_selected.emit(i)
	await _frames(2)
	print("unique helmet: %s / %s" % [helmet_button.text, str(Build.items.get("helmet", {}))])
	print("unique rows: %d, text: %s" % [editor.get_node("%UniqueMods").get_child_count(), editor.get_node("%UniqueText").text.replace("
", " | ")])

	# idols tab: place an idol at the first open cell and give it an affix
	tabs.current_tab = 3
	await _frames(1)
	var idols_tab: Node = tabs.get_child(3)
	for cell: Node in idols_tab.get_node("%Grid").get_children():
		if not cell.disabled:
			cell.pressed.emit()
			break
	await _frames(1)
	var idol_editor: Node = idols_tab.get_node("%ItemEditor")
	var idol_base: OptionButton = idol_editor.get_node("%BaseSelect")
	if idol_base.item_count > 1:
		idol_base.select(1)
		idol_base.item_selected.emit(1)
	await _frames(2)
	var idol_affix: OptionButton = idol_editor.get_node("%Affixes/Suffix1").get_node("Top/AffixSelect")
	if idol_affix.item_count > 1:
		idol_affix.select(1)
		idol_affix.item_selected.emit(1)
	await _frames(2)
	for item_slot: String in Build.items:
		if IdolGrid.is_idol_key(item_slot):
			print("idol %s: %s" % [item_slot, str(Build.items[item_slot])])

	# config tab: shock stacks and boss
	tabs.current_tab = 6
	await _frames(1)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "Shock"), 10)
	Build.set_enemy_ailment(GameData.enum_value("AilmentID", "ArmourShred"), 20)
	await _frames(2)

	# calcs tab
	tabs.current_tab = 5
	await _frames(3)
	var sections: Node = tabs.get_child(5).get_node("%Sections")
	print("calc sections: %d" % sections.get_child_count())
	var summary: Label = main.get_node("Margin/Layout/Split/StatsPanel/VBox/SkillSummary")
	print("summary: %s" % summary.text)
	print("UI SMOKE DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
