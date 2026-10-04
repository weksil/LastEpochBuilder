extends Node

## Captures the English screenshots of README.md and docs/index.html into ../docs/screenshots/ (see TECH_README.md "Checks"). Needs a window (not --headless):
## Godot_console.exe --path client res://tests/readme_screenshots.tscn

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")
const WINDOW_SIZE: Vector2i = Vector2i(1600, 1200)
const ITEMS_TAB: int = 2
const CALCS_TAB: int = 5
## Frames of each half of the item slider sweep.
const FRAMES: int = 24

var _main: Control
var _tabs: TabContainer
var _out: String


func _ready() -> void:
	Settings.locale = "en"
	TranslationServer.set_locale("en")
	get_window().size = WINDOW_SIZE
	get_window().move_to_center()
	_out = ProjectSettings.globalize_path("res://").path_join("../docs/screenshots").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_tabs = _main.get_node("%Tabs")
	await _frames(5)

	# 1. minions: Rogue Falconer, Aerial Assault with the falcon's attack as a damage component
	_import("letools_Q0V58LLX")
	await _calcs(0)
	await _expand_and_scroll(["Falco: Rogue Falcon Melee: Damage per use"], "Falco", ["Physical"])
	await _shot("minions.png")

	# 2. exact skill numbers: Acolyte, Harvest with breakdowns
	_import("letools_A83KxJq5")
	await _calcs(4)
	await _expand_and_scroll(["Against enemy", "Damage per use"], "", ["Hit without crit", "Physical"])
	await _shot("skill_calcs.png")

	# 3. item editor: sweep the roll of a damage affix of the amulet; the unsaved diff follows it live (frames -> GIF)
	_tabs.current_tab = ITEMS_TAB
	await _frames(5)
	_tabs.get_child(ITEMS_TAB).call("_edit_slot", "amulet")
	await _frames(5)
	var affixes: Node = _main.find_child("ItemEditor", true, false).get_node("%Affixes")
	var slider: HSlider = null
	for row: Node in affixes.get_children():
		if row.visible and (row.get_node("Top/AffixSelect") as Button).text.contains("Physical"):
			slider = row.get_node("Bottom/RollSlider")
			break
	var start: float = slider.value
	var low: float = maxf(0.0, start - 3.0 * 256.0)
	var frames_dir: String = _out.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var steps: Array[float] = []
	for i in range(FRAMES):
		steps.append(lerpf(start, low, float(i) / (FRAMES - 1)))
	for i in range(FRAMES):
		steps.append(lerpf(low, slider.max_value, float(i) / (FRAMES - 1)))
	for i in range(steps.size()):
		slider.value = steps[i]
		await get_tree().create_timer(0.08).timeout
		await _shot("frames/%03d.png" % i)
	await _shot("item_diff.png")
	get_tree().quit()


func _import(fixture: String) -> void:
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/%s.json" % fixture)
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	_main.get_node("%ImportDialog").imported.emit()


func _calcs(skill: int) -> void:
	_tabs.current_tab = CALCS_TAB
	Build.selected_skill = skill
	Build.changed.emit()
	await _frames(6)


## Expands the first rows whose label starts with one of `labels` inside sections whose title contains one of `sections`,
## then scrolls to the first section whose title contains `scroll_to` (top when empty).
func _expand_and_scroll(sections: Array, scroll_to: String, labels: Array) -> void:
	var calcs: CalcsTab = _tabs.get_child(CALCS_TAB) as CalcsTab
	var target: Control = null
	for column: VBoxContainer in [calcs.left_column, calcs.right_column]:
		for section: Node in column.get_children():
			var title: String = (section.get_node("%Title") as Label).text
			if scroll_to != "" and target == null and title.contains(scroll_to):
				target = section as Control
			if not sections.any(func(s: String) -> bool: return title.contains(s)):
				continue
			for label: String in labels:
				for row: Node in section.get_node("%Rows").get_children():
					if (row.get_node("%NameLabel") as Label).text.begins_with(label):
						var button: Button = row.get_node("%ExpandButton")
						if button.visible:
							button.button_pressed = true
						break
	await _frames(4)
	if target != null:
		calcs.scroll.ensure_control_visible(target)
		calcs.scroll.scroll_vertical = int(target.global_position.y - calcs.scroll.global_position.y) + calcs.scroll.scroll_vertical - 8
	await _frames(4)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(file))
	print("saved ", _out.path_join(file))


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
