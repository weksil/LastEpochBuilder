extends Node

## Russian locale check: imports the sample LE Tools builds, shows every tab in Russian and lists the source strings that
## went through LE.t() without a translation in client/i18n/ru.po. Headless: prints «I18N TEST: OK» or the missing strings.

const LEToolsImportScript: GDScript = preload("res://scripts/engine/letools_import.gd")
const FIXTURES: Array[String] = ["res://tests/fixtures/letools_A83KxJq5.json", "res://tests/fixtures/letools_ApbrXYvx.json", "res://tests/fixtures/letools_Q0V58LLX.json"]


func _ready() -> void:
	get_tree().create_timer(170.0).timeout.connect(func() -> void:
		print("I18N TEST TIMEOUT")
		get_tree().quit(1))
	TranslationServer.set_locale("ru")
	var main: Control = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(3)
	for fixture: String in FIXTURES:
		var doc: Dictionary = LEToolsImportScript.to_build(JSON.parse_string(FileAccess.get_file_as_string(fixture)))
		LEToolsImportScript.apply(Build, doc)
		main.get_node("%ImportDialog").imported.emit()
		await _frames(2)
		var tabs: TabContainer = main.get_node("%Tabs")
		for slot: int in range(5):
			Build.selected_skill = slot
			for i in range(tabs.get_tab_count()):
				tabs.current_tab = i
				await _frames(2)
		var cfg: Node = tabs.get_child(tabs.get_tab_count() - 1)
		if cfg.has_node("%ShowAllCheck"):
			cfg.get_node("%ShowAllCheck").button_pressed = true
			await _frames(2)
	var keys: Array = LE.missing.keys()
	keys.sort()
	for k: Variant in keys:
		print("MISSING: %s" % str(k).replace("\n", "\n"))
	TranslationServer.set_locale("en")
	print("I18N TEST: %s (%d strings without translation)" % ["OK" if keys.is_empty() else "FAIL", keys.size()])
	get_tree().quit(0 if keys.is_empty() else 1)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
