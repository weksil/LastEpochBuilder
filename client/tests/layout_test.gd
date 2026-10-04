extends Node

## Layout check: imports the sample LE Tools build (tests/fixtures) and verifies that every tab fits a 1600 px wide window
## (long texts must wrap instead of widening the whole interface). Wide controls are printed on failure.
## Headless: prints «LAYOUT TEST: OK» and quits. Run from the editor (project_run custom) it stays open on «Расчёты».

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")
const WINDOW_WIDTH: float = 1600.0
const CALCS_TAB: int = 5

var _failed: bool = false


func _ready() -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	if headless:
		get_tree().create_timer(120.0).timeout.connect(func() -> void:
			print("LAYOUT TEST TIMEOUT")
			get_tree().quit(1))
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	var tabs: TabContainer = main.get_node("%Tabs")
	var margin: Control = main.get_node("Margin")

	# 1. empty default build (empty-state texts differ from a filled build)
	await _check_tabs(tabs, margin, "empty")

	# 2. imported sample build
	var text: String = FileAccess.get_file_as_string("res://tests/fixtures/letools_A83KxJq5.json")
	LEToolsImportScript.apply(Build, LEToolsImportScript.to_build(JSON.parse_string(text)))
	main.get_node("%ImportDialog").imported.emit()
	await _frames(3)
	await _check_tabs(tabs, margin, "sample")

	if not headless:
		tabs.current_tab = CALCS_TAB
		return
	print("LAYOUT TEST: %s" % ("FAIL" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)


func _check_tabs(tabs: TabContainer, margin: Control, label: String) -> void:
	for i in range(tabs.get_tab_count()):
		tabs.current_tab = i
		await _frames(3)
		var width: float = margin.get_combined_minimum_size().x
		print("[%s] tab %s: min width %d" % [label, tabs.get_tab_title(i), int(width)])
		if width > WINDOW_WIDTH:
			_failed = true
			print("FAIL: [%s] tab %s needs %d px > %d" % [label, tabs.get_tab_title(i), int(width), int(WINDOW_WIDTH)])
			_report(margin, 1)


## Prints the chain of visible controls whose minimum width is large (the culprit is the deepest one).
func _report(node: Node, depth: int) -> void:
	for child: Node in node.get_children():
		if child is Control and (child as Control).is_visible_in_tree():
			var w: float = (child as Control).get_combined_minimum_size().x
			if w > WINDOW_WIDTH / 2.0:
				var txt: String = str(child.get("text")).substr(0, 60) if "text" in child else ""
				print("%s%s [%s] min_w=%d %s" % ["  ".repeat(depth), child.name, child.get_class(), int(w), txt])
				_report(child, depth + 1)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
