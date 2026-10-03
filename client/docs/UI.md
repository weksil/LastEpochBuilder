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
- CheckBox-ы с `metadata/flag` → копия `flags`, `Build.set_enemy("flags", d)`.
- `%AilmentList`: строка `ailment_row_scene` на каждый `GameData.enemy_ailments()`: `%NameLabel` = name,
  `tooltip_text` = список `buffs` («propertyName: значение»), `maxInstances`, «против боссов ×(1+moreBuffEffectAgainstBosses)»;
  `%StacksSpin.max_value` = maxInstances (или 200, если 0) → `Build.set_enemy_ailment(id, int(v))`.
  `%Filter.text_changed` скрывает строки, чьё имя не содержит текста (без учёта регистра).

## Расчёты — `scripts/calcs/calcs_tab.gd` (`extends VBoxContainer`), `@export section_scene, row_scene`
- `%SkillSelect`: 5 слотов «N. имя умения» (пустые — «N. —», disabled); выбор → `Build.selected_skill = i` и пересчёт.
- На `Build.changed` (и при показе вкладки, `visibility_changed`): если вкладка невидима — ничего не делать (лениво);
  иначе `r = SkillCalc.compute(Build, Build.selected_skill)`, очистить `%Sections`, для каждой секции инстанс `section_scene`
  (`%Title`, `%Rows`), для строки — `row_scene`: `%NameLabel`, `%ValueLabel` = text, `%Details` = breakdown,
  `%ExpandButton.toggled` → `%Details.visible`, кнопка скрыта, если breakdown пуст. Секция «Не учтено» из `r.notes`
  (строки без значения). Если у слота нет умения — одна секция с подсказкой выбрать умение во вкладке «Скиллы».

## Панель характеристик — `scripts/stats/stats_panel.gd`
`@export row_scene, group_scene`. На `Build.changed`: `g = BuildMods.global_store(Build)`,
`rows = CharacterCalc.compute(g.store, Build)`. Сначала строки «Класс/Мастерство/Уровень» (как сейчас), затем по группам:
`group_scene` (Label, text = group) и `row_scene` (`NameLabel`, `ValueLabel`, `tooltip_text` строки = breakdown).
`%SkillSummary`: если выбранный слот с умением — `SkillCalc.compute` → «Умение: DPS по врагу X (подсказка игры Y)»
(значения из секций «Против врага»/«DPS»; при отсутствии — пусто). Пересчёт откладывать `call_deferred`, не чаще раза за кадр.
