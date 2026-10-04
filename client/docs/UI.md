# UI-скрипты — контракт

Визуал задан в сценах `client/scenes/**`. Скрипты **не создают** UI-узлы и не задают стили:
только `PackedScene.instantiate()` через `@export`, заполнение текста/значений, `visible`,
`theme_type_variation`, сигналы. Узлы ищутся по `%UniqueName`. Godot 4.7, табы, статическая типизация.
Состояние — автозагрузка `Build` (сигнал `changed`), данные — `GameData`, расчёты — `docs/ENGINE.md`.
Подписка на `Build.changed` — в `_ready`. При заполнении контролов кодом оборачивать в
`set_block_signals(true/false)`, чтобы не зациклить сигналы.

## Дерево — `scripts/trees/tree_canvas.gd` (`class_name TreeCanvas extends ScrollContainer`)
Сцена `scenes/trees/tree_canvas.tscn`: `%Canvas` > `%Links`, `%Nodes`. `@export node_scene, link_scene, margin := 60.0`.
- `signal add_requested(node_id: int)`, `signal remove_requested(node_id: int)`.
- `func show_tree(nodes: Array, tree_id: String)` — очистить `%Links`/`%Nodes` (queue_free детей), разложить узлы:
  позиция `Vector2(p[0], -p[1])`, сдвиг так, чтобы минимум = margin; `%Canvas.custom_minimum_size = max + margin`;
  инстанс `node_scene` (`PassiveNode`): `setup(node, GameData.get_node_stats(tree_id, id))`, позиция `pos − custom_minimum_size/2`,
  сигналы узла → сигналы канвы. Связи: для `requirements` внутри набора — инстанс `link_scene` (`PassiveLink`), `points = [pos_req, pos_node]`.
  Узлы с `maxPoints == 0` (корень) тоже показываются.
- `func refresh(get_points: Callable, can_add: Callable)` — `set_state(get_points.call(id), can_add.call(id))` для узлов,
  `set_active(обе стороны > 0)` для связей.

`scripts/passives/passive_tab.gd` переписать на `%TreeCanvas`: вкладки мастерств как сейчас; `show_tree(узлы мастерства, treeID)`;
сигналы → `Build.add_point/remove_point`; `refresh(Build.get_points, Build.can_add)`; `%PointsLabel`.

## Скиллы
`scripts/skills/skill_slot.gd` (`class_name SkillSlot extends PanelContainer`), сцена `skill_slot.tscn`:
`@export var slot_index: int`; `%SlotLabel` «Слот N», `%SkillSelect` (item 0 «— пусто —», далее
`GameData.class_skills(Build.class_id, Build.mastery)` с текстом `get_ability(id).abilityName`, metadata = id),
`%LevelSpin` → `Build.set_skill_level`, `%SelectButton` (toggle) → `signal selected(slot_index)`, `%PointsLabel`
«Очки дерева: spent / level». `func sync()` — обновить из `Build.skills[slot_index]`; `func set_selected(on)`.
`scripts/skills/skills_tab.gd` (`extends HBoxContainer`): слоты — дети `%Slots`. На `selected(i)` → `Build.selected_skill = i`,
остальные слоты `set_selected(false)`, показать дерево: `tree = GameData.get_skill_tree(get_ability(id).skillTree)`,
`%TreeCanvas.show_tree(tree.nodes, tree.treeID)`, `%TreeTitle` = имя умения. Сигналы канвы →
`Build.add_skill_point(sel, id)` / `remove_skill_point`. `refresh` с лямбдами `func(id): return Build.get_skill_points(sel, id)` и
`Build.can_add_skill_point(sel, id)` (не `bind`: он добавляет аргумент в конец). `%TreePoints` «spent / level». Перестраивать дерево только при смене умения/класса.

## Предметы
`scripts/items/items_tab.gd` (`extends HBoxContainer`): кнопки слотов — дети `%SlotList` с `metadata/slot`, `metadata/slot_name`.
Нажатие → `%ItemEditor.edit_slot(slot, slot_name)`. Текст кнопки: «slot_name: имя предмета» или «slot_name: —».
Первый слот выбран при старте.
`scripts/items/item_editor.gd` (`class_name ItemEditor extends PanelContainer`), `@export implicit_row_scene`:
- `edit_slot(slot, title)`; `%BaseSelect`: item 0 «— пусто —», затем базы `GameData` items, подходящие слоту (ENGINE.md §3),
  id = baseTypeID. `%SubSelect`: подтипы базы (`displayName` или `name`, id = subTypeID; пропускать `isLegacySubType`).
- Выбор базы/подтипа → `Build.set_item(slot, {base, sub, implicit_rolls: [255…], affixes: []})`.
- `%Implicits`: по строке `implicit_row_scene` на импликит: `%NameLabel` = propertyName (+ теги), `%RollSlider` 0..255
  (видим только если `maxValue > value`), `%ValueLabel` = `AffixMath.roll_value(...)` через `LE.fmt_num`/`fmt_pct`
  (INCREASED и значения < 1 у сопротивлений — в %).
- `%Affixes` содержит 4 готовые строки `Prefix1, Prefix2, Suffix1, Suffix2` (сцена `affix_row.tscn`):
  `%KindLabel` «Префикс»/«Суффикс»; `%AffixSelect` item 0 «— нет —», затем `GameData.affixes_for_type(base.type)` с нужным
  `type` (PREFIX/SUFFIX), текст `name`, id = affixId; `%TierSpin` 1..len(tiers); `%RollSlider` 0..255;
  `%ValueLabel` — значения всех `properties` аффикса для тира и ролла (через `AffixMath`, с `effect_modifier` базы).
  Любое изменение → `Build.set_item(slot, обновлённый dict)` (affixes — массив до 4 `{id, tier, roll, kind:"prefix"|"suffix", index}`).
- `%EmptyHint` видим, когда базы нет; тогда `%SubRow`, импликиты и аффиксы скрыты. `%ClearButton` → `Build.clear_item(slot)`.

## Условия — `scripts/config/config_tab.gd` (`extends ScrollContainer`), `@export ailment_row_scene`
- `%HealthSelect` → `Build.set_player_state("health", ["full","high","normal","low"][i])`.
- `%KindSelect` → `Build.set_enemy("kind", ["dummy","normal","magic","rare","miniboss","boss"][i])`;
  `%LevelSpin` → "level"; `%ArmourSpin` → "armour".
- SpinBox-ы с `metadata/res_index` (дети `EnemyGrid`) → `res[i]` (копия массива, затем `Build.set_enemy("res", arr)`).
- CheckBox-ы с `metadata/flag` → копия `flags`, `Build.set_enemy("flags", d)` (в т. ч. `frozen` — «Заморожен»).
- Состояние игрока (для особых эффектов уникальных, ENGINE §5.4.3): CheckBox-ы с `metadata/player_flag`
  (`hit_recently, crit_recently, moving, leeching, low_mana, haste, frenzy`) → `Build.set_player_state(flag, pressed)`;
  SpinBox-ы в `%PlayerValues` с `metadata/player_value` (`ward, curses, ignite_stacks, damned_stacks`) →
  `Build.set_player_state(key, int(v))`. Синхронизация из `Build.player_state` в `_sync_from_build`.
- `%AilmentList`: строка `ailment_row_scene` на каждый `GameData.enemy_ailments()`: `%NameLabel` = name,
  `tooltip_text` = список `buffs` («propertyName: значение»), `maxInstances`, «против боссов ×(1+moreBuffEffectAgainstBosses)»;
  `%StacksSpin.max_value` = maxInstances (или 200, если 0) → `Build.set_enemy_ailment(id, int(v))`.
  `%Filter.text_changed` скрывает строки, чьё имя не содержит текста (без учёта регистра).

## Расчёты — `scripts/calcs/calcs_tab.gd` (`extends VBoxContainer`), `@export section_scene, row_scene`
- `%SkillSelect`: 5 слотов «N. имя умения» (пустые — «N. —», disabled); выбор → `Build.selected_skill = i` и пересчёт.
- На `Build.changed` (и при показе вкладки, `visibility_changed`): если вкладка невидима — ничего не делать (лениво);
  иначе `r = SkillCalc.compute(Build, Build.selected_skill)`, очистить колонки `%Left` / `%Right` / `%Wide` (внутри `%Sections`), каждую секцию — инстанс `section_scene` — в более
  короткую по числу строк из двух колонок
  (`%Title`, `%Rows`), для строки — `row_scene`: `%NameLabel`, `%ValueLabel` = text, `%Details` = breakdown,
  `%ExpandButton.toggled` → `%Details.visible`, кнопка скрыта, если breakdown пуст. Секция «Не учтено» из `r.notes`
  (строки без значения) — на всю ширину в `%Wide`. `%NameLabel` переносит текст (autowrap), чтобы длинные строки не расширяли окно
  (проверяет `tests/layout_test`). Если у слота нет умения — одна секция с подсказкой выбрать умение во вкладке «Скиллы».

## Панель характеристик — `scripts/stats/stats_panel.gd`
`@export row_scene, group_scene`. На `Build.changed`: `g = BuildMods.global_store(Build)`,
`rows = CharacterCalc.compute(g.store, Build)`. Сначала строки «Класс/Мастерство/Уровень» (как сейчас), затем по группам:
`group_scene` (Label, text = group) и `row_scene` (`NameLabel`, `ValueLabel`, `tooltip_text` строки = breakdown).
`%SkillSummary`: если выбранный слот с умением — `SkillCalc.compute` → «Умение: DPS по врагу (<цель>) X»
(значение строки «DPS по врагу» секции «Против врага»; при отсутствии — пусто). Пересчёт откладывать `call_deferred`, не чаще раза за кадр.

## Идолы — `scripts/idols/idols_tab.gd` (`extends HBoxContainer`)
Сцена `scenes/idols/idols_tab.tscn`: `%Grid` содержит 25 готовых кнопок `IdolCell` с `metadata/row`, `metadata/col`;
справа `%ItemEditor` (тот же `ItemEditor`, он сам понимает ключи идолов). Помощник — `IdolGrid` (`scripts/engine/idol_grid.gd`):
`key(row, col)`, `anchor(slot)`, `is_open(row, col)`, `occupancy(Build.items) -> {Vector2i(row, col): slot}`, `size_of(base_id)`.
- Клик по клетке: если клетка занята идолом → `slot = occupancy[cell]`; иначе (открытая клетка) → `slot = IdolGrid.key(row, col)`.
  Затем `%ItemEditor.edit_slot(slot, "Идол %d:%d" % [row + 1, col + 1])`, запомнить выбранный slot.
- Обновление клеток (в `_ready`, на `Build.changed` и после клика): заблокированная (`not is_open`) → `disabled = true`,
  вариант `&"IdolCellBlocked"`, текст пустой. Занятая → `&"IdolCellOccupied"`; у левой верхней клетки идола текст =
  `GameData.display_name(GameData.item_base(base))`, у остальных клеток идола текст пустой. Клетки выбранного slot
  (или выбранная пустая клетка) → `&"IdolCellSelected"`. Свободная → `&"IdolCellOpen"`, текст пустой.
- `tooltip_text` занятой клетки: имя подтипа и строки аффиксов (id → `GameData.affix(id).name`, тир).

## Уникальные предметы в `ItemEditor` (`scripts/items/item_editor.gd`)
Сцена уже содержит `%UniqueRow` > `%UniqueSelect` (над базой), `%UniqueTitle`, `%UniqueMods` (VBox для строк `implicit_row_scene`),
`%UniqueText` (Label). Предмет в `Build.items[slot]` может иметь `unique: int` (uniqueID) и `unique_rolls: Array[int]`
(индекс = `rollID` мода, по умолчанию 255). API: `GameData.uniques` (Array видимых уникальных: `uniqueID, displayName, name,
baseType, subTypes[], mods[{propertyName, tagNames, modType, rounding, rollID, canRoll, value, maxValue, hideInTooltip}],
tooltipDescriptions[{description}], isSetItem, setID, legendaryType}`), `GameData.unique(id)`, `GameData.set_data(setID)`
(`{setName, items[{uniqueID, name}], tooltipDescriptions[{description, setRequirement}]}`), `AffixMath.unique_value(mod, roll)`.
- `%UniqueSelect`: item 0 «— обычный предмет —» (id `EMPTY_ID`), затем уникальные, чья база проходит `_base_fits_slot(GameData.item_base(baseType))`
  (для идолов — та же проверка места), текст = `GameData.display_name(u)`, id = uniqueID, сортировка по имени. Заполнять в `_fill()`.
- Выбор уникального → `Build.set_item(slot, {unique, base: baseType, sub: subTypes[0], implicit_rolls: 255 на каждый импликит,
  unique_rolls: [255 × (max rollID + 1)], affixes: текущие})`, затем `_fill()`. Выбор «обычный» → убрать ключи `unique`/`unique_rolls`.
  Ручная смена базы на другую тоже убирает `unique`.
- При уникальном: `%BaseSelect` и `%SubSelect` `disabled = true`; `%UniqueTitle`, `%UniqueMods`, `%UniqueText` видимы (иначе скрыты).
  `%UniqueMods`: строка `implicit_row_scene` на каждый мод с `hideInTooltip == 0`: `%NameLabel` = `_prop_title(mod)`, `%RollSlider` виден,
  если `canRoll == 1 and maxValue > value`, значение = `unique_rolls[rollID]`; изменение → записать в `unique_rolls[rollID]` и `_commit`;
  `%ValueLabel` = `_format(mod, AffixMath.unique_value(mod, roll))` (обновлять в `_update_values`, все строки одного rollID синхронно).
- `%UniqueText.text`: строки `tooltipDescriptions[].description`; если `isSetItem` — пустая строка, «Сет «setName»:» и строки
  `set_data.tooltipDescriptions` вида «(N) description».
- `%AffixesTitle` для уникального: «Легендарные аффиксы» (если `legendaryType == "LegendaryPotential"`), иначе как сейчас.
- `scripts/items/items_tab.gd` и `scripts/idols/idols_tab.gd`: если у предмета есть `unique` — показывать имя уникального.

## Импорт из Last Epoch Tools — `scripts/import/letools_import_dialog.gd` (`class_name LEToolsImportDialog extends Window`)
Кнопка `%ImportButton` («Импорт…», конец `TopBar/Row`) открывает `%ImportDialog` (`popup_centered`); по сигналу `imported` `main.gd` приводит
`%ClassSelect` / `%MasterySelect` / `%LevelSpin` к `Build` без повторного `Build.set_class`. Диалог: `%LinkEdit`, `%LoadButton`, `%StatusLabel`,
`%CloseButton`, `%Http` (HTTPRequest), `%OpenSiteButton` («Открыть планировщик LE Tools», `OS.shell_open` на
`https://www.lastepochtools.com/planner/`, где персонаж импортируется по имени аккаунта и персонажа) с подсказкой рядом.
- Поток: ссылка → `GET /planner/<код>` → `LEToolsImport.extract_data_hash(html)` → `GET /api/internal/planner_data/<hash>` (хеш выдаётся
  страницей и привязан к ней, закешировать нельзя) → JSON → `LEToolsImport.to_build` → `LEToolsImport.apply(Build, doc)`.
  Текст, начинающийся с `{`, считается готовым JSON ответа (без сети). User-Agent браузера **не** отправляется: Cloudflare отвечает 403
  на Chrome UA с нехромовым TLS-отпечатком, а UA движка пропускает.
- `to_build` принимает полный ответ `{data: {...}}` или только `data`; возвращает `{class_id, mastery, level, passives, skills[5], items, blessings, warnings}`.
  Непонятные id/узлы пропускаются с русским предупреждением, падений нет.
- Кодировка id (`LZString.decompress_from_encoded_uri` → строка цифр): `I` — `1` + база(3) + подтип(3) + редкость(1) + uniqueId (≥ 2 цифр);
  `U` — подтип(3) + uniqueId; `A` — affixId. Идол `(x, y)` → `IdolGrid.key(y - 1, x - 1)`; запечатанный и осквернённый аффиксы дописываются
  в `affixes`, осквернённый идол получает `corrupted: true`. Слоты: head→helmet, chest→body, waist→belt, feet→boots, hands→gloves,
  weapon1→weapon, weapon2→offhand, idol_altar→altar. Не поддерживается: дерево и идолы Weaver, сетовые id (`S`); блоки благословений
  (`I` база 34, подтип = id благословения, ролл = `ir[0]`) реализованы по догадке и не проверены на живом примере.
