# UI-скрипты — контракт

Визуал задан в сценах `client/scenes/**`. Скрипты **не создают** UI-узлы и не задают стили:
только `PackedScene.instantiate()` через `@export`, заполнение текста/значений, `visible`,
`theme_type_variation`, сигналы. Узлы ищутся по `%UniqueName`. Godot 4.7, табы, статическая типизация.
Состояние — автозагрузка `Build` (сигнал `changed`), данные — `GameData`, расчёты — `docs/ENGINE.md`.
Подписка на `Build.changed` — в `_ready`. При заполнении контролов кодом оборачивать в
`set_block_signals(true/false)`, чтобы не зациклить сигналы.

**Мгновенные обновления.** Все `SpinBox` имеют `update_on_text_changed = true` (значение применяется при наборе, без Enter), поэтому
значения из `Build` возвращаются в контролы только через `set_value_no_signal` / `set_pressed_no_signal` и только если они отличаются.
Пересчёт на `Build.changed` откладывается (`call_deferred`, не чаще раза за кадр, скрытая вкладка не считается). Строки не пересоздаются, пока
набор строк тот же: обновляются тексты на месте, у контрола с фокусом значение не трогается, раскрытые расшифровки и прокрутка сохраняются.
Изменившиеся значения подсвечиваются на ~1,5 с сменой `theme_type_variation` (по таймеру `SceneTreeTimer`, стилей в коде нет).

**Тема (`theme/main_theme.tres`).** Чекбоксы: иконки `theme/icons/check_*.svg` (включён — золотая плашка с галочкой, выключен — контурный
квадрат), `CheckBox` в состоянии `pressed` — золотая рамка и подложка; варианты `CheckBoxNoSource` (включён без источника в билде, красный),
`CheckBoxPlain` (без рамки, внутри карточек). Карточки: `SectionCard` / `SectionTitle`; плитки: `TilePanel`, `TilePanelMain`, `HeroCaption`,
`HeroValue(Main)`; строки: `CalcRow`/`CalcRowAlt` (зебра), `StatRowPlain`/`StatRowChanged`, `RowIdle`/`RowActive`/`RowNoSource`; значения:
`ValueLabel`, `ValueLabelKey`, `*Changed`; расшифровка — `BreakdownPanel` + `BreakdownLabel` (моноширинный `SystemFont`);
`SummaryActive`/`SummaryOff` — однострочные итоги групп; `FlatToggle` — плоская кнопка-раскрывашка; `DeltaUp`/`DeltaDown` — разница значения.

## Дерево — `scripts/trees/tree_canvas.gd` (`class_name TreeCanvas extends ScrollContainer`)
Сцена `scenes/trees/tree_canvas.tscn`: `%Canvas` > `%Content` > `%Decor`, `%Links`, `%Nodes`. `@export node_scene, link_scene, decor_scene,
margin := 60.0, min_zoom, max_zoom, zoom_step`.
- `signal add_requested(node_id: int)`, `signal remove_requested(node_id: int)`.
- Визуал игры — `TreeArt` (`scripts/trees/tree_art.gd`): манифест `research/data/game/tree_art.json` и спрайты `res://assets/trees/`
  (собираются `tools/extract/extract_tree_art.py`). Смещения и размеры — в единицах UI игры, ось y вверх (`TreeArt.offset` переворачивает).
- `func show_tree(nodes: Array, tree_id: String)` — очистить `%Decor`/`%Links`/`%Nodes`, разложить узлы:
  позиция `Vector2(p[0], -p[1])`; декор панели `TreeArt.decor(tree_id, mastery первого узла)` (фон, руны, орнаменты — инстансы
  `decor_scene`, `TextureRect`) расширяет границы канвы; сдвиг так, чтобы минимум = margin.
  Узел — инстанс `node_scene` (`PassiveNode`): `setup(node, GameData.get_node_stats(tree_id, id), TreeArt.node_art(tree_id, id))`,
  позиция `pos − custom_minimum_size/2`, сигналы узла → сигналы канвы. Связи: для `requirements` внутри набора — инстанс `link_scene`
  (`PassiveLink`), `connect_points(pos_req, pos_node, TreeArt.connection(tree_id))`. Узлы с `maxPoints == 0` (корень) тоже показываются.
- Масштаб: `%Content.scale`, `%Canvas.custom_minimum_size = размер × масштаб`. Новое дерево вписывается в окно (не крупнее 1:1)
  и перевписывается при изменении размера, пока пользователь не менял масштаб; Ctrl + колесо — масштаб в пределах `min_zoom…max_zoom`.
- `func refresh(get_points: Callable, can_add: Callable)` — `set_state(get_points.call(id), can_add.call(id))` для узлов,
  `set_active(обе стороны > 0)` для связей.

Узел `scenes/passives/passive_node.tscn` (`PassiveNode extends Button`): слои игры в `%Art` — `%IconMask` (`clip_children`, маска иконки)
> `%Icon`, `%FadeAvailable`, `%FadeLocked` (затемнение иконки, цвета в сцене); `%Border`, `%BorderBright` (рамка взятого узла), `%Escape`
(рамка корня), `%PointsPlate` (`NinePatchRect`, отступы `TreeArt.apply_nine_slice`), `%PointsFrame`, `%PointsLabel` (вариант `TreeNodePoints`).
Скрипт берёт текстуру, размер, смещение и оттенок (`self_modulate` — цвет слоя из данных игры) каждого слоя из `TreeArt.layer(art, часть)`;
кнопка получает вариант `TreeNodeArt` (без фона). Без арта (нет иконки) — прежний круг с вариантами `PassiveNode*` и подписью `%NameLabel`.
Состояния с артом: взят — `%BorderBright`; можно взять — `%FadeAvailable`; недоступен — `%FadeLocked`.
Связь `scenes/passives/passive_link.tscn` (`PassiveLink extends Node2D`): `%Art` повёрнут вдоль отрезка, `%Rail` (`NinePatchRect`, рельс игры) и
`%Fill` (свечение, видно, когда обе стороны взяты); без арта — `%Plain` (`Line2D`, цвета в сцене).

`scripts/passives/passive_tab.gd` переписать на `%TreeCanvas`: вкладки мастерств как сейчас; `show_tree(узлы мастерства, treeID)`;
сигналы → `Build.add_point/remove_point`; `refresh(Build.get_points, Build.can_add)`; `%PointsLabel`.

## Скиллы
`scripts/skills/skill_slot.gd` (`class_name SkillSlot extends PanelContainer`), сцена `skill_slot.tscn`:
`@export var slot_index: int`; `%SlotLabel` «Слот N», `%SkillSelect` (item 0 «— пусто —», далее
`GameData.class_skills(Build.class_id, Build.mastery)` с текстом `get_ability(id).abilityName`, metadata = id),
`%LevelSpin` → `Build.set_skill_level`, `%SelectButton` (toggle) → `signal selected(slot_index)`, `%PointsLabel`
«Очки дерева: spent / level». `func sync()` — обновить из `Build.skills[slot_index]`; `func set_selected(on)`.
`scripts/skills/skills_tab.gd` (`extends HBoxContainer`): слоты — дети `%Slots`. На `selected(i)` → `Build.selected_skill = i`
(сеттер шлёт `Build.changed`, дерево перестраивается на нём; кнопки слотов синхронизируются с `Build.selected_skill` на каждый `changed`,
повторный клик по показанному слоту оставляет его выбранным), остальные слоты `set_selected(false)`, показать дерево: `tree = GameData.get_skill_tree(get_ability(id).skillTree)`,
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
Три карточки (`SectionCard`): «Игрок» и «Противник» слева, «Айлменты, шреды и проклятия на противнике (стаки)» справа; сверху `%ShowAllCheck` («Показать все условия»,
по умолчанию выключен) и `%EmptyHint`. У каждой группы однострочный итог (`%PlayerSummary`, `%EnemySummary`, `%AilmentSummary`: «Активно: Haste, Двигаюсь» /
«Ничего не включено», вариант `SummaryActive`/`SummaryOff`) и допись «· скрыто N без источника» / «· без источника: N». Кнопки `%ResetPlayerButton` →
`Build.reset_player_conditions()` и `%ResetAilmentsButton` → `Build.clear_enemy_ailments()` (по одному `changed`).
- **Фильтр как в Path of Building**: `ConfigRelevance.compute(Build)` (`scripts/engine/config_relevance.gd`, вычисляется только при видимой вкладке, не чаще раза за кадр) возвращает
  `{player_flags, player_values, ailments, enemy}` — ключ присутствует, если у условия есть источник в билде, значение — текст источника (может быть несколько строк), он идёт в `tooltip_text`
  (у айлментов — ещё и вторая строка строки). Без «Показать все условия» скрыты флаги игрока, числа игрока, флаги противника и айлменты без источника, **кроме** тех, чьё значение
  отличается от значения по умолчанию (флаги противника `high_health` и `full_health` по умолчанию включены): такие остаются видимыми и помечаются «нет источника»
  (`CheckBoxNoSource`, `RowNoSource`). Строка с фокусом ввода не скрывается. Тип, уровень, броня и сопротивления противника видны всегда. Если нечего показывать — `%EmptyHint`
  «Нет условий, от которых зависит билд». Нет файла `config_relevance.gd` — всё считается имеющим источник.
- `%HealthSelect` → `Build.set_player_state("health", ["full","high","normal","low"][i])`.
- `%KindSelect` → `Build.set_enemy("kind", ["dummy","normal","magic","rare","miniboss","boss"][i])`; `%LevelSpin` → "level"; `%ArmourSpin` → "armour".
- SpinBox-ы с `metadata/res_index` (дети `%EnemyGrid`) → `res[i]` (копия массива, затем `Build.set_enemy("res", arr)`).
- CheckBox-ы `%EnemyFlags` с `metadata/flag` → копия `flags`, `Build.set_enemy("flags", d)` (в т. ч. `frozen`).
- CheckBox-ы `%PlayerFlags` с `metadata/player_flag` (`hit_recently, crit_recently, moving, leeching, low_mana, haste, frenzy`) → `Build.set_player_state(flag, pressed)`;
  SpinBox-ы в строках `%PlayerValues` (`PanelContainer` > `HBoxContainer` > `Label`, `SpinBox`) с `metadata/player_value` (`ward, curses, ignite_stacks, damned_stacks`) →
  `Build.set_player_state(key, int(v))`. Строка с ненулевым значением — `RowActive`.
- `%AilmentList`: по `AilmentRow` (`scenes/config/ailment_row.tscn`, `class_name AilmentRow`) на каждый `GameData.enemy_ailments()`: `%NameLabel` = `displayName` (иначе `name`),
  `%KindLabel` («проклятие» / «шред»), `%ReasonLabel` = источник, `tooltip_text` = описание, `buffs`, `maxInstances`, «против боссов ×(1+moreBuffEffectAgainstBosses)»;
  `%StacksSpin.max_value` = maxInstances (или 200) → `signal stacks_changed(id, stacks)` → `Build.set_enemy_ailment`. Строка со стаками — `RowActive`, без источника — `RowNoSource`.
  Строки с источником идут первыми. `%Filter.text_changed` скрывает строки, чьё имя (оба названия и вид) не содержит текста (без учёта регистра).

## Расчёты — `scripts/calcs/calcs_tab.gd` (`class_name CalcsTab extends VBoxContainer`), `@export section_scene, row_scene, input_row_scene`
Сверху вниз: `%SkillSelect` (5 слотов «N. имя умения», пустые «N. —»; выбор → `Build.selected_skill`), `%Summary` (`CalcSummary`), прокручиваемый `%Scroll`
с `ParamsPanel` («Параметры расчёта»: `%HitsSpin` и сетка `%Inputs` в 2 колонки), `%Buffs` (`BuffsPanel`), колонками `%Left` / `%Right` и `%Wide` (`%Notes`).
- `r = SkillCalc.compute(Build, Build.selected_skill)` один раз за кадр на `Build.changed` и при показе вкладки (невидимая вкладка ничего не считает).
- **Полоса итогов** `scenes/calcs/calc_summary.tscn` (`class_name CalcSummary`, `show_result(result)`): имя умения, «Цель: …» и четыре плитки `CalcTile`
  (`show_value(text, sub, tooltip)`): «DPS по врагу» (главная), «Средний удар» (строка «Средний удар по врагу»), «Применений в секунду», «Шанс крита».
  Значения берутся из строк результата по метке внутри своего раздела (`CalcSummary.find_row(result, метка, раздел)`): DPS, средний удар и цель —
  из раздела ровно «Против врага» (у каждого раздела «Айлмент: …» есть своя строка «DPS по врагу»), применения — из «Скорость и мана», крит — из «Крит»
  (для применений и крита, если раздела нет, — первая строка с меткой); нет строки — «—». Подсказка плитки — расшифровка строки.
- **Параметры**: `SkillInputRow` (`setup(slot, inp)`, `fits(inp)`, `update_input(slot, inp)`): число — `SpinBox`, флаг — `CheckBox` с текстом метки. Набор строк
  пересоздаётся только при смене слота или набора ключей/типов; иначе значения обновляются без сигналов (`max` — только если изменился).
- **Секции** в фиксированном порядке (`CalcsTab.ordered_sections`): сначала основной компонент (урон → конверсии → пробивание/крит → скорость и мана → айлменты →
  параметры умения → против врага → восполнение), затем остальные компоненты (подумения, срабатывания) в том же порядке. Колонки заполняются подряд:
  первая половина строк — `%Left`, остальное — `%Right`. Секция — `section_scene` (`%Title`, `%Rows`), строка — `row_scene` (`CalcRow`: `setup(key, row, alt, expanded, key_row)`,
  `update_row(row)`; «+»/«−» раскрывает `%DetailsPanel`/`%Details`, кнопка скрыта без расшифровки; строка «DPS по врагу» разделов «… Против врага» — `ValueLabelKey`).
  Идентичность строки — «заголовок секции|метка» (повторы с `#n`). Если набор секций и строк тот же — строки обновляются на месте (изменившееся значение мигает);
  иначе дерево пересоздаётся, раскрытые строки восстанавливаются по ключу (`_expanded`), `scroll_vertical` сохраняется.
- «Не учтено» из `r.notes` — сворачиваемый блок `CalcNotes` (`show_notes(notes)`, по умолчанию свёрнут, «▸ Не учтено (N)»), скрыт без заметок.
- Нет умения в слоте — одна секция с подсказкой выбрать умение во вкладке «Скиллы».
- **Баффы умений на персонажа** — `scenes/calcs/buffs_panel.tscn` (`BuffsPanel.refresh()`, `@export row_scene` = `BuffSkillRow`): `BuildMods.skill_buffs(Build)` даёт по
  каждому умению на панели (одно на умение) `{slot, ability_name, active, toggle, mods}`. Строка: `%ActiveCheck` («Слот N · умение», привязан к входу `buff_active` через
  `Build.set_skill_input(slot, "buff_active", on)`), статус («действует · модов: N» / «выключен — не действует» / «нет баффов на персонажа» — тогда вместо галочки метка),
  раскрывашка «моды (N)» со строками `BuildMods.describe_mod(mod)` («+60% inc Damage — источник»). Выключенное умение показывает моды, которые дало бы включённое.

## Панель характеристик — `scripts/stats/stats_panel.gd`
`@export row_scene, group_scene`. На `Build.changed` (не чаще раза за кадр): `g = BuildMods.global_store(Build)`, `rows = CharacterCalc.compute(g.store, Build)`.
Сначала строки «Класс/Мастерство/Уровень/Пассивных очков», затем по группам: `group_scene` (Label) и `row_scene` (`StatRow`: `NameLabel`, `DeltaLabel`, `ValueLabel`,
`tooltip_text` = расшифровка). Пока набор строк тот же, строки обновляются на месте (`StatRow.update_row(text, tooltip, value)`): изменившаяся строка на ~1,5 с получает вариант
`StatRowChanged`, а если у строки есть числовое `value` — рядом показывается разница («+12», «−3%», варианты `DeltaUp`/`DeltaDown`).
`%SummaryCard` (виден, если в выбранном слоте умение и есть строка «DPS по врагу» раздела «Против врага»): `%SkillName` «<умение> · DPS по врагу», `%SkillSummary` — число (`HeroValueMain`),
`%SkillTarget` — «цель: <Enemy.describe>», подсказка карточки — расшифровка строки.

## Идолы — `scripts/idols/idols_tab.gd` (`extends HBoxContainer`)
Сцена `scenes/idols/idols_tab.tscn`: `%Grid` содержит 25 готовых кнопок `IdolCell` с `metadata/row`, `metadata/col`;
справа `%ItemEditor` (тот же `ItemEditor`, он сам понимает ключи идолов). Помощник — `IdolGrid` (`scripts/engine/idol_grid.gd`):
`key(row, col)`, `anchor(slot)`, `is_open(row, col)`, `occupancy(Build.items) -> {Vector2i(row, col): slot}`, `size_of(base_id)`.
Сетки `GameData.idol_grid()` / `altar_grid(sub)` уже в строках `[row][col]`: `unlockMatrix` игры хранится как `[x][y]` и транспонируется при загрузке.
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
