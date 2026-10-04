extends Node

## User settings that survive restarts (user://settings.cfg). Loaded before the UI: the interface language is set here.
## Source strings are English; Russian comes from res://i18n/ru.po (project setting internationalization/locale/translations).

const PATH: String = "user://settings.cfg"
const LOCALES: Array[String] = ["en", "ru"]

var locale: String = "en"


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		locale = str(cfg.get_value("ui", "locale", "en"))
	if not LOCALES.has(locale):
		locale = "en"
	TranslationServer.set_locale(locale)


## Switches the interface language and reloads the main scene (the build lives in the Build autoload and is kept).
func set_locale(value: String) -> void:
	if not LOCALES.has(value) or value == locale:
		return
	locale = value
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("ui", "locale", locale)
	cfg.save(PATH)
	TranslationServer.set_locale(locale)
	get_tree().reload_current_scene()
