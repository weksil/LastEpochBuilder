extends HBoxContainer

var _current_slot: String = ""


func _ready() -> void:
	Build.changed.connect(_on_build_changed)

	# Get all slot buttons from SlotList
	var slot_list: VBoxContainer = %SlotList
	for button: Node in slot_list.get_children():
		if button is Button:
			var btn: Button = button
			if btn.has_meta("slot"):
				btn.pressed.connect(_on_slot_pressed.bind(btn))

	# Select first slot at startup
	if slot_list.get_child_count() > 0:
		var first_btn: Button = slot_list.get_child(0) as Button
		if first_btn:
			first_btn.button_pressed = true
			_on_slot_pressed(first_btn)


func _on_slot_pressed(button: Button) -> void:
	var slot: String = str(button.get_meta("slot", ""))
	var slot_name: String = str(button.get_meta("slot_name", ""))

	if slot != "":
		_current_slot = slot
		%ItemEditor.edit_slot(slot, slot_name)


func _on_build_changed() -> void:
	# Update all slot button texts
	var slot_list: VBoxContainer = %SlotList
	for button: Node in slot_list.get_children():
		if button is Button:
			var btn: Button = button
			if btn.has_meta("slot"):
				var slot: String = str(btn.get_meta("slot", ""))
				var slot_name: String = str(btn.get_meta("slot_name", ""))

				# Get item from Build
				var item_text: String = "—"
				if slot in Build.items:
					var item_data: Dictionary = Build.items[slot]
					if "unique" in item_data:
						var unique_id: int = item_data["unique"]
						var unique_item: Dictionary = GameData.unique(unique_id)
						item_text = GameData.display_name(unique_item)
					elif "base" in item_data:
						var base_id: int = item_data["base"]
						var sub_id: int = item_data.get("sub", 0)
						var base_item: Dictionary = GameData.item_base(base_id)
						var sub_item: Dictionary = GameData.item_sub(base_id, sub_id)

						# Use display name or name from subtype
						if not sub_item.is_empty():
							item_text = GameData.display_name(sub_item)
						elif not base_item.is_empty():
							item_text = base_item.get("typeName", "")

				btn.text = "%s: %s" % [slot_name, item_text]
