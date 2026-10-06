# UI scripts — contract

The visuals are defined in the scenes `client/scenes/**`. Scripts **do not create** UI nodes and do not set styles:
only `PackedScene.instantiate()` via `@export`, filling in texts/values, `visible`,
`theme_type_variation`, signals. Nodes are found by `%UniqueName`. Godot 4.7, tabs, static typing.
State is the `Build` autoload (the `changed` signal), data is `GameData`, calculations are in `docs/ENGINE.md`.
Subscribe to `Build.changed` in `_ready`. When filling controls from code, wrap it in
`set_block_signals(true/false)` so the signals do not loop.

**Instant updates.** All `SpinBox`es have `update_on_text_changed = true` (the value is applied while typing, without Enter), so
values from `Build` go back into controls only via `set_value_no_signal` / `set_pressed_no_signal` and only if they differ.
Recalculation on `Build.changed` is deferred (`call_deferred`, at most once per frame, a hidden tab is not calculated). Rows are not recreated while
the set of rows is the same: texts are updated in place, the value of a focused control is not touched, expanded breakdowns and scroll position are kept.
Changed values are highlighted for ~1.5 s by switching `theme_type_variation` (by a `SceneTreeTimer`, there are no styles in code).

**Theme (`theme/main_theme.tres`).** Checkboxes: the icons `theme/icons/check_*.svg` (checked — a gold plate with a tick, unchecked — an outlined
square), a `CheckBox` in the `pressed` state — a gold border and backing; variants `CheckBoxNoSource` (checked without a source in the build, red),
`CheckBoxPlain` (no border, inside cards). Cards: `SectionCard` / `SectionTitle`; tiles: `TilePanel`, `TilePanelMain`, `HeroCaption`,
`HeroValue(Main)`; rows: `CalcRow`/`CalcRowAlt` (zebra), `StatRowPlain`/`StatRowChanged`, `RowIdle`/`RowActive`/`RowNoSource`; values:
`ValueLabel`, `ValueLabelKey`, `*Changed`; breakdown — `BreakdownPanel` + `BreakdownLabel` (monospace `SystemFont`);
`SummaryActive`/`SummaryOff` — one-line group summaries; `FlatToggle` — a flat expander button; `DeltaUp`/`DeltaDown` — the change of a value.

**Searchable dropdowns.** `scenes/common/search_select.tscn` (`SearchSelect extends Button`, `scripts/common/search_select.gd`) is a drop-in for
`OptionButton` (`clear`, `add_item`, `select`, `get_item_id/index/text`, `get_selected_id`, `item_count`, signal `item_selected`; plus
`set_item_variation(index, theme type)` — the row colour from that type's `font_color`, e.g. `RarityUnique` / `RaritySet`): pressing it opens
`%Popup` with `%Search` (substring / all-words filter, Up/Down, Enter) and `%List`. Used for the unique, base, subtype and affix lists of `ItemEditor`.

## Localization
Source strings are English. Russian lives in `client/i18n/ru.po` (msgid = the English text). Scene texts are translated by Godot's
auto-translation; texts built in code use `tr()` in nodes and `LE.t()` in static engine code. Data labels from `client/data/*.json` are
English and are passed through `LE.t()` when shown. Code that compares a displayed label compares it with `LE.t("English label")`.
The language is chosen in the top bar (`%LanguageSelect`, items in `Settings.LOCALES` order, the `Settings` autoload, `user://settings.cfg`);
switching reloads the main scene while the `Build` autoload keeps the build (`main.gd` then syncs the top bar from `Build` and emits
`Build.changed` instead of selecting the first class). `LE.t()` records source strings without a translation in a non-English locale in
`LE.missing`; `tests/i18n_test` renders every tab in Russian for the saved builds and fails if anything is missing.

## Tree — `scripts/trees/tree_canvas.gd` (`class_name TreeCanvas extends ScrollContainer`)
Scene `scenes/trees/tree_canvas.tscn`: `%Canvas` > `%Content` > `%Decor`, `%Links`, `%Nodes`. `@export node_scene, link_scene, decor_scene,
margin := 60.0, min_zoom, max_zoom, zoom_step`.
- `signal add_requested(node_id: int)`, `signal remove_requested(node_id: int)`.
- The game's visuals are `TreeArt` (`scripts/trees/tree_art.gd`): the manifest `research/data/game/tree_art.json` and the sprites `res://assets/trees/`
  (built by `tools/extract/extract_tree_art.py`). Offsets and sizes are in game UI units, the y axis points up (`TreeArt.offset` flips it).
- `func show_tree(nodes: Array, tree_id: String)` — clear `%Decor`/`%Links`/`%Nodes`, lay out the nodes:
  position `Vector2(p[0], -p[1])`; panel decor `TreeArt.decor(tree_id, mastery of the first node)` (background, runes, ornaments — instances of
  `decor_scene`, `TextureRect`) extends the canvas bounds; shift so that the minimum = margin.
  A node is an instance of `node_scene` (`PassiveNode`): `setup(node, GameData.get_node_stats(tree_id, id), TreeArt.node_art(tree_id, id))`,
  position `pos − custom_minimum_size/2`, the node's signals → the canvas's signals. Links: for `requirements` inside the set — an instance of `link_scene`
  (`PassiveLink`), `connect_points(pos_req, pos_node, TreeArt.connection(tree_id))`. Nodes with `maxPoints == 0` (the root) are shown too.
- Zoom: `%Content.scale`, `%Canvas.custom_minimum_size = size × zoom`. A new tree is fitted to the window (no larger than 1:1)
  and refitted when the size changes, until the user has changed the zoom; Ctrl + wheel — zoom within `min_zoom…max_zoom`.
- `func refresh(get_points: Callable, can_add: Callable)` — `set_state(get_points.call(id), can_add.call(id))` for nodes,
  `set_active(both sides > 0)` for links.

Node `scenes/passives/passive_node.tscn` (`PassiveNode extends Button`): the game's layers in `%Art` — `%IconMask` (`clip_children`, the icon mask)
> `%Icon`, `%FadeAvailable`, `%FadeLocked` (icon dimming, colors in the scene); `%Border`, `%BorderBright` (the border of a taken node), `%Escape`
(the root's border), `%PointsPlate` (`NinePatchRect`, margins `TreeArt.apply_nine_slice`), `%PointsFrame`, `%PointsLabel` (variant `TreeNodePoints`).
The script takes the texture, size, offset and tint (`self_modulate` — the layer's color from the game data) of each layer from `TreeArt.layer(art, part)`;
the button gets the variant `TreeNodeArt` (no background). Without art (no icon) — the old circle with the `PassiveNode*` variants and the `%NameLabel` caption.
States with art: taken — `%BorderBright`; can be taken — `%FadeAvailable`; unavailable — `%FadeLocked`.
Node tooltip `scenes/trees/node_tooltip.tscn` (`NodeTooltip extends VBoxContainer`, `@export stat_scene` — one stat line, `node_tooltip_stat.tscn`).
`PassiveNode` (`@export tooltip_scene`) keeps a plain-text `tooltip_text` (`NodeTooltip.to_text`) and returns the scene from `_make_custom_tooltip`
(`NodeTooltip.model(stats, title, max_points, points)` → `show_model`). Sections: title, `Points: n/max`, description (`description`, else the older
`nodeDescription`; `{keyword}` braces are dropped), **Per point** (stats with `noScaling = 0`; from 2 points the line also shows the total), **Fixed**
(`noScaling = 1` in a node with `noScalingType = 0` SinglePoint: the value is given once from the first point), **Bonus at N points**
(`noScalingType = 1` PointThreshold, N = `noScalingPointThreshold`: `pointBonusDescription` and the `noScaling = 1` stats, with an Active / Inactive n/N
state; bonus lines are muted while inactive), and `altText` at the bottom. With `noScalingType = 0` the `pointBonusDescription` is not shown: in those nodes
it is stale text with no threshold in the game code (e.g. Skiasynthesis). Nodes with `maxPoints ≤ 1` merge per-point and fixed lines into **Effect**.
Downside stats use the `NodeTooltipDownside` variant, section headers `NodeTooltipHeader`.
Link `scenes/passives/passive_link.tscn` (`PassiveLink extends Node2D`): `%Art` rotated along the segment, `%Rail` (`NinePatchRect`, the game's rail) and
`%Fill` (glow, visible when both sides are taken); without art — `%Plain` (`Line2D`, colors in the scene).

`scripts/passives/passive_tab.gd` is to be rewritten onto `%TreeCanvas`: mastery tabs as now; `show_tree(mastery nodes, treeID)`;
signals → `Build.add_point/remove_point`; `refresh(Build.get_points, Build.can_add)`; `%PointsLabel`.

## Skills
`scripts/skills/skill_slot.gd` (`class_name SkillSlot extends PanelContainer`), scene `skill_slot.tscn`:
`@export var slot_index: int`; `%SlotLabel` "Slot N", `%SkillSelect` (item 0 "— empty —", then
`GameData.class_skills(Build.class_id, Build.mastery)` with the text `get_ability(id).abilityName`, metadata = id),
`%LevelSpin` → `Build.set_skill_level`, `%SelectButton` (toggle) → `signal selected(slot_index)`, `%PointsLabel`
"Tree points: spent / level". `func sync()` — update from `Build.skills[slot_index]`; `func set_selected(on)`.
`scripts/skills/skills_tab.gd` (`extends HBoxContainer`): the slots are children of `%Slots`. On `selected(i)` → `Build.selected_skill = i`
(the setter emits `Build.changed`, the tree is rebuilt on it; the slot buttons are synced with `Build.selected_skill` on every `changed`,
clicking again on the shown slot keeps it selected), the other slots `set_selected(false)`, show the tree: `tree = GameData.get_skill_tree(get_ability(id).skillTree)`,
`%TreeCanvas.show_tree(tree.nodes, tree.treeID)`, `%TreeTitle` = the skill name. The canvas signals →
`Build.add_skill_point(sel, id)` / `remove_skill_point`. `refresh` with the lambdas `func(id): return Build.get_skill_points(sel, id)` and
`Build.can_add_skill_point(sel, id)` (not `bind`: it appends the argument at the end). `%TreePoints` "spent / level". Rebuild the tree only when the skill/class changes.

## Items
`scripts/items/items_tab.gd` (`class_name ItemsTab extends HBoxContainer`), `@export stash_button_scene, choice_button_scene, select_group`.
The left column (`items_tab.tscn`): `%SlotList` holds 11 `slot_row.tscn` (`SlotRow`: `@export slot, slot_name, slot_icon`;
`%SlotIcon` — a plain picture (`mouse_filter` ignore); `%ItemButton` — the equipped item: pressing it shows the slot in the editor and opens the
choice list; the edited slot's button gets the variation `SlotItemSelected`; unique / set item names use `SlotItem(Selected)Unique` /
`…Set` and `ItemChoiceUnique` / `ItemChoiceSet` — `ItemCompare.rarity(item)`),
a separator, `%StashRows` (the unequipped items `Build.stash`, `stash_item_button.tscn`, grey variation `ItemButtonStashed`, no icon;
pressing one edits it), `%StashEmpty`, `%AddButton` "+" → a new stash item (the selected slot's type, its first base) opened in the editor,
where `%TypeRow` > `%TypeSelect` (stash mode only, types with icons) and the base are chosen.
Slot icons are `client/assets/items/*.png` (symbolic reward icons of the game, `tools/extract/extract_item_icons.py`).
- `%ChoicePopup` > `%ChoiceRows` (`item_choice_button.tscn`): "— none —" (`Build.unequip_to_stash`), every equipped item that fits the slot
  (variation `ItemChoice`, icon of the slot it is equipped in; another slot → `Build.move_item(from, to)`, the replaced item goes back if it
  fits or to the stash), every fitting stash item (variation `ItemChoiceStashed`, `Build.equip_from_stash(index, slot)`).
- `ItemButton` (`scripts/items/item_button.gd`) — the custom tooltip `item_diff_tooltip.tscn` (`ItemDiffTooltip.show_item(item, slot, changes)`):
  the item's mod lines (`ItemCompare.item_lines`) and "Equipping this item in <slot> will give you:" with the lines of
  `ItemCompare.diff(snapshot(Build), snapshot_with_items(Build, changes))` (`diff_line.tscn`, `DeltaUp`/`DeltaDown`). A snapshot is the
  "DPS vs enemy" of the selected skill plus every numeric `CharacterCalc` row; `snapshot_with_items` swaps `Build.items` without signals
  and restores it.
- Blessings tab (`blessings_tab.tscn`): `%Rows` (one `blessing_row.tscn` per timeline) and below them `%Summary` (hidden without blessings):
  "The chosen blessings give you:" — `%SummaryDps` and `%SummaryLines` (`ItemCompare.diff(snapshot_with_blessings(Build, {}), snapshot(Build))`,
  `diff_line.tscn`, `DeltaUp`/`DeltaDown`) or `%SummaryNone`; recomputed at most 20 times a second (`%DiffTimer`) while the tab is shown, also while a roll slider is dragged.
- `Build.stash` — an `Array` of item dicts of the same shape as `Build.items[slot]`; the signal `Build.stash_changed` does not trigger a
  recalculation. API: `stash_add`, `stash_set`, `stash_remove`, `equip_from_stash` (a swap), `equip_item`, `unequip_to_stash`, `move_item`.

`scripts/items/item_editor.gd` (`class_name ItemEditor extends PanelContainer`), `@export implicit_row_scene`:
- `edit_slot(slot, title)`; there is no base field: `%SubSelect` ("Item") lists every allowed subtype of every base that fits the slot
  (ENGINE.md §3; skip `isLegacySubType`), id = baseTypeID · 1000 + subTypeID, the base name in brackets when several bases fit; in slot mode
  item 0 is "— empty —". Choosing another base → `{base, sub, implicit_rolls: [255…], affixes: []}`, the same base keeps the affixes.
- Hover tooltips of the search lists (`SearchSelect.tooltip_builder`, id → Control): `item_info_tooltip.tscn` (`ItemInfoTooltip.show_unique /
  show_sub / show_affix`) — the name in the rarity colour (`RarityNormal/Unique/Set/Affix`), kind, level requirement, implicit and mod ranges,
  descriptions and lore for uniques, one line per tier for affixes. A set item adds `%SetBox` (`set_block.tscn`, `SetBlock.show_set(setID)`; also in `ItemDiffTooltip`, i.e. the stash and slot choice tooltips): "Set "name": n/m items equipped", the members
  (base in brackets; equipped ones `SetBonusActive`, the rest `SetBonusInactive`) and the bonuses "N items: …" in requirement order, active ones green. Uniques and items are sorted by required level, shown as " (level N)"
  (`ItemCompare.level_suffix`).
- `%Implicits`: one `implicit_row_scene` row per implicit: `%NameLabel` = propertyName (+ tags), `%RollSlider` 0..255
  (visible only if `maxValue > value`), `%ValueLabel` = `AffixMath.roll_value(...)` via `LE.fmt_num`/`fmt_pct`
  (INCREASED and values < 1 for resistances — in %).
- `%Affixes` holds 4 ready-made rows `Prefix1, Prefix2, Suffix1, Suffix2` (scene `affix_row.tscn`):
  `%KindLabel` "Prefix"/"Suffix"; `%AffixSelect` item 0 "— none —", then `GameData.affixes_for_type(base.type, class, kinds)` with the
  required `type` (PREFIX/SUFFIX), text `name` (special kinds get a marker: "(set)" in the set colour, "(experimental)", "(personal)",
  "(weaver)", "(enchantment)"), id = affixId; kinds `ItemEditor.AFFIX_KINDS` (Standard, Set, Experimental, Personal, IdolWeaver,
  IdolEnchantment; set and idol affixes filtered by class), the corrupted row offers only `Corrupted` affixes; `%TierSpin` 1..len(tiers); `%RollSlider` 0..255;
  `%ValueLabel` — the values of all the affix's `properties` for the tier and roll (via `AffixMath`, with the base's `effect_modifier`).
  `%RollSlider` covers every tier: value = (tier − 1) · 256 + roll, `tick_count = tiers + 1` marks the tier borders; `%TierSpin` follows it.
  Extra rows `Sealed` (index 4) and `Corrupted` (index 5) hold the sealed / corrupted affix ("Sealed prefix", "Corrupted suffix"…): the
  sealed row is shown on regular equipment (not idols, uniques or the altar), the corrupted row when the item is corrupted (`%CorruptedCheck`
  in `%AffixesHeader` next to the title sets `corrupted: true`, clearing it drops the corrupted affix; a corrupted subtype is always
  corrupted, the box is then disabled); either row is also shown whenever it holds an affix. Entries without a valid `index` (LE Tools imports, older saves) are placed by `ItemCompare.place_affixes` (by the affix
  type; imports flag `sealed` / `corrupted`); an affix the lists do not offer is appended to its row's list. A unique keeps the four
  regular rows for legendary affixes (title "Legendary affixes (legendary potential)" or "(Weaver's Will)" by `legendaryType`); a set item
  shows only its mods, the affix block only with the affixes it carries.
- Edits go to a draft (`_draft`; `_saved_item` is the stored item it was taken from); `Build` changes only on `%SaveButton`
  (`Build.set_item` / `Build.stash_set`, affixes — an array of `{id, tier, roll, kind:"prefix"|"suffix", index}`). An item put into an
  empty slot, the Type row, "— empty —" and the header buttons are stored at once (Equip / Move to stash save the draft first). While the
  draft differs, `%Pending` under the item shows `%PendingHeader`; `%PendingDps` — DPS vs enemy of the skill selected in Calculations
  "before → after (delta)", or "(no change)" muted, hidden when the skill has no DPS; then the other stat changes saving would give (`ItemCompare.diff`, lines
  `diff_line.tscn` `DeltaUp` / `DeltaDown`, else `%PendingNone`; recomputed after the edits at most 20 times a second (`DIFF_INTERVAL_MSEC`, `%DiffTimer`), also while a slider is dragged; the last
  edit is always shown): a slot against
  the build, an unequipped item as the stored version vs the draft equipped in its slot. `%RevertButton` drops the draft. Switching to
  another slot or item drops it too; a stored item changed elsewhere replaces it.
- `%EmptyHint` is visible when there is no item; then the implicits and the affixes are hidden. `%ClearButton` → `Build.clear_item(slot)`.
- `edit_stash(index)` edits an unequipped item (writes go to `Build.stash_set`, the base list is that of `ItemCompare.target_slot(item, "")`);
  `%EquipButton` (stash mode) → `Build.equip_from_stash`, `%StashCopyButton` → `Build.stash_add(item)`, `%StashMoveButton` (slot mode) →
  `Build.unequip_to_stash(slot)`; the signal `slot_requested(slot)` asks the tab to switch the editor to a slot.
- `%NameEdit` (header, when there is an item): a custom name stored as `item.name` (`ItemCompare.item_title` prefers it; the placeholder is
  `ItemCompare.default_title`); `%SlotTitle` is shown only for an empty slot.
- Set items: `%SetBonuses` — `%SetTitle` "Set "name": n/m items equipped" (`BuildMods.set_counts`) and one `set_bonus_line.tscn` per bonus,
  variation `SetBonusActive` when the requirement is met, otherwise `SetBonusInactive` (grey).

## Stats panel — `scripts/stats/stats_panel.gd`
`@export row_scene, group_scene`. On `Build.changed` (at most once per frame): `g = BuildMods.global_store(Build)`, `rows = CharacterCalc.compute(g.store, Build)`.
First the rows "Class/Mastery/Level/Passive points", then by groups: `group_scene` (Label) and `row_scene` (`StatRow`: `NameLabel`, `DeltaLabel`, `ValueLabel`,
`tooltip_text` = the breakdown). While the set of rows is the same, the rows are updated in place (`StatRow.update_row(text, tooltip, value)`): a changed row gets the variant
`StatRowChanged` for ~1.5 s, and if the row has a numeric `value`, the difference is shown next to it ("+12", "−3%", variants `DeltaUp`/`DeltaDown`).
`%SummaryCard` (visible if at least one skill on the bar has a positive "DPS vs enemy" row in its "Against enemy" section): `%SkillName` "Total DPS vs enemy",
`%SkillSummary` — the sum over the bar (`HeroValueMain`), `%SkillBreakdown` — one line "<skill> — <DPS>" per contributing skill, highest first (`HeroSkillList`),
`%SkillTarget` — "target: <Enemy.describe>", the card's tooltip is every skill's breakdown.

## Defense — `scripts/defense/defense_tab.gd` (`class_name DefenseTab extends VBoxContainer`)
Scene `scenes/defense/defense_tab.tscn`, `@export section_scene, row_scene` (the `calc_section` / `calc_row` scenes of Calculations).
`%GroupSelect` (`SearchSelect`): `DefenseCalc.groups()` — the average monster, every boss, the custom hit (id = index);
picking a group selects its first attack. `%AttackSelect`: the attacks of the current group (hidden for the custom hit),
refilled only when the group changes → `Build.set_defense("attack", key)`. The headline: `%AttackTitle`, `%ContextLabel` (area level and corruption), `%OneShotLabel`
(`NoSourceLabel`, visible when the worst hit kills from full health), tiles `%EhpTile` (main), `%MaxHitTile`, `%HitsTile`, `%TakenTile`
(`CalcTile`) from `result.summary`. "Fight parameters": `%AreaLevelSpin` → `set_defense("area_level")`, `%CorruptionSpin` →
`Build.set_enemy("corruption")` (the same value as on Conditions), `%WardSpin` → `Build.set_player_state("ward")`,
`%IntervalSpin` → `set_defense("interval")` (0 = the attack timing), `%RecoveryCheck` → `set_defense("recovery")`. `%CustomPanel`
(shown for the custom hit): `%Dmg0…%Dmg6`, `%CritChanceSpin` (percent), `%CritMultiSpin`. Sections of `DefenseCalc.compute` go into
`%Left` / `%Right` in their order and are updated in place like Calculations; `%Notes` is the "Not counted" block.

## Calculations headline — `scripts/calcs/calc_summary.gd`
`%ProjectileRow` above the tiles (visible only when `result.projectiles` is not empty, i.e. the skill fires projectiles,
docs/ENGINE.md §9.9): `%ProjectileOne` / `%ProjectileAverage` / `%ProjectileAll` — toggle buttons in one `ButtonGroup`
(`metadata/mode` = `one|average|all`) → `Build.set_skill_projectile_mode(Build.selected_skill, mode)`; disabled when the
projectiles cannot hit one target twice. `%ProjectileCount` — "<factor> of <count> per use", the tooltip is the row's breakdown.

## Idols — `scripts/idols/idols_tab.gd` (`extends HBoxContainer`)
Scene `scenes/idols/idols_tab.tscn`: `%Grid` holds 25 ready-made `IdolCell` buttons with `metadata/row`, `metadata/col`;
on the right `%EditorScroll` > `%ItemEditor` (the same `ItemEditor`, it understands idol keys itself; it offers only idol bases and
unique idols that fit the cell, each named with its grid size "[WxH]" from `IdolGrid.size_of`). Until a cell or "Edit altar" is picked `%EditorScroll` is hidden and `%EditorHint` asks to pick a cell;
it is hidden again when the edited altar or idol is removed by an altar change. The corrupted flag of an idol (altar properties) is the
editor's `%CorruptedCheck`. The helper is `IdolGrid` (`scripts/engine/idol_grid.gd`):
`key(row, col)`, `anchor(slot)`, `is_open(row, col)`, `occupancy(Build.items) -> {Vector2i(row, col): slot}`, `size_of(base_id)`.
The grids `GameData.idol_grid()` / `altar_grid(sub)` are already in `[row][col]` rows: the game's `unlockMatrix` is stored as `[x][y]` and transposed on load.
- Clicking a cell: if the cell is occupied by an idol → `slot = occupancy[cell]`; otherwise (an open cell) → `slot = IdolGrid.key(row, col)`.
  Then `%ItemEditor.edit_slot(slot, "Idol %d:%d" % [row + 1, col + 1])`, remember the selected slot.
- Updating the cells (in `_ready`, on `Build.changed` and after a click): blocked (`not is_open`) → `disabled = true`,
  variant `&"IdolCellBlocked"`, empty text. Occupied → `&"IdolCellOccupied"`; for the idol's top-left cell the text =
  `GameData.display_name(GameData.item_base(base))`, for the idol's other cells the text is empty. The cells of the selected slot
  (or the selected empty cell) → `&"IdolCellSelected"`. Free → `&"IdolCellOpen"`, empty text.
- The `tooltip_text` of an occupied cell: the subtype name and the affix lines (id → `GameData.affix(id).name`, tier).

## Unique items in `ItemEditor` (`scripts/items/item_editor.gd`)
The scene already contains `%UniqueRow` > `%UniqueSelect` (above the base), `%UniqueTitle`, `%UniqueMods` (a VBox for `implicit_row_scene` rows),
`%UniqueText` (Label). An item in `Build.items[slot]` may have `unique: int` (uniqueID) and `unique_rolls: Array[int]`
(index = the mod's `rollID`, 255 by default). API: `GameData.uniques` (an Array of the visible uniques: `uniqueID, displayName, name,
baseType, subTypes[], mods[{propertyName, tagNames, modType, rounding, rollID, canRoll, value, maxValue, hideInTooltip}],
tooltipDescriptions[{description}], isSetItem, setID, legendaryType}`), `GameData.unique(id)`, `GameData.set_data(setID)`
(`{setName, items[{uniqueID, name}], tooltipDescriptions[{description, setRequirement}]}`), `AffixMath.unique_value(mod, roll)`.
- `%UniqueSelect`: item 0 "— regular item —" (id `EMPTY_ID`), then the uniques whose base passes `_base_fits_slot(GameData.item_base(baseType))`
  (for idols — the same placement check), text = `GameData.display_name(u)`, id = uniqueID, sorted by name. Fill it in `_fill()`.
- Choosing a unique → `Build.set_item(slot, {unique, base: baseType, sub: subTypes[0], implicit_rolls: 255 for each implicit,
  unique_rolls: [255 × (max rollID + 1)], affixes: current})`, then `_fill()`. Choosing "regular" → remove the keys `unique`/`unique_rolls`.
  Manually changing the base to another one also removes `unique`.
- With a unique: `%SubSelect` `disabled = true`; `%UniqueTitle`, `%UniqueMods`, `%UniqueText` are visible (otherwise hidden).
  `%UniqueMods`: an `implicit_row_scene` row for every mod with `hideInTooltip == 0`: `%NameLabel` = `_prop_title(mod)`, `%RollSlider` is visible
  if `canRoll == 1 and maxValue > value`, the value = `unique_rolls[rollID]`; a change → write into `unique_rolls[rollID]` and `_commit`;
  `%ValueLabel` = `_format(mod, AffixMath.unique_value(mod, roll))` (update in `_update_values`, all rows of the same rollID in sync).
- `%UniqueText.text`: the lines `tooltipDescriptions[].description`; the set bonuses of a set item are in `%SetBonuses` (see "Items").
- `%AffixesTitle` for a unique: "Legendary affixes" (if `legendaryType == "LegendaryPotential"`), otherwise as now.
- `scripts/items/items_tab.gd` and `scripts/idols/idols_tab.gd`: if the item has `unique` — show the unique's name.

## Import from Last Epoch Tools — `scripts/import/letools_import_dialog.gd` (`class_name LEToolsImportDialog extends Window`)
The button `%ImportButton` ("Import…", the end of `TopBar/Row`) opens `%ImportDialog` (`popup_centered`); on the `imported` signal `main.gd` brings
`%ClassSelect` / `%MasterySelect` / `%LevelSpin` in line with `Build` without a repeated `Build.set_class`. The dialog: `%LinkEdit`, `%LoadButton`, `%StatusLabel`,
`%CloseButton`, `%Http` (HTTPRequest), `%OpenSiteButton` ("Open the LE Tools planner", `OS.shell_open` to
`https://www.lastepochtools.com/planner/`, where a character is imported by the account and character name) with a hint next to it.
- Flow: link → `GET /planner/<code>` → `LEToolsImport.extract_data_hash(html)` → `GET /api/internal/planner_data/<hash>` (the hash is issued by the
  page and tied to it, it cannot be cached) → JSON → `LEToolsImport.to_build` → `LEToolsImport.apply(Build, doc)`.
  Text starting with `{` is treated as ready-made response JSON (no network). The browser's User-Agent is **not** sent: Cloudflare answers 403
  to a Chrome UA with a non-Chrome TLS fingerprint, while the engine's UA gets through.
- Browser build (`OS.has_feature("web")`): the Last Epoch Tools tab is hidden — lastepochtools.com sends CORS only for its own origin.
- `to_build` accepts the full response `{data: {...}}` or just `data`; it returns `{class_id, mastery, level, passives, skills[5], items, blessings, warnings}`.
  Unknown ids/nodes are skipped with an English warning, no crashes.
- Skills come from the specialized trees `skillTrees` (`treeID`, `slotNumber`, `level`, `selected`), not from the skill bar `hud`:
  the bar may hold a skill without a tree while a specialized skill is off the bar. A specialized skill keeps its bar slot,
  the other specialized skills fill free slots in `slotNumber` order, bar skills without a tree take the slots that are still free
  (unspecialized, level 20); whatever does not fit is skipped with a warning.
- Id encoding (`LZString.decompress_from_encoded_uri` → a string of digits): `I` — `1` + base(3) + subtype(3) + rarity(1) + uniqueId (≥ 2 digits);
  `U` — subtype(3) + uniqueId; `A` — affixId. An idol `(x, y)` → `IdolGrid.key(y - 1, x - 1)`; sealed and corrupted affixes are appended
  to `affixes`, a corrupted idol gets `corrupted: true`. Slots: head→helmet, chest→body, waist→belt, feet→boots, hands→gloves,
  weapon1→weapon, weapon2→offhand, idol_altar→altar. Not supported: the Weaver tree and idols, set ids (`S`); blessings come as `{timelineID: {id, ir}}`
  (`I` base 34, subtype = the blessing id, roll = `ir[0]`), checked on `letools_ApbrXYvx.json`.

## Import by account through Maxroll — `scripts/import/maxroll_import_panel.gd` (`class_name MaxrollImportPanel extends VBoxContainer`), `scripts/engine/maxroll_import.gd` (`MaxrollImport`)
The import dialog (`scenes/import/letools_import_dialog.tscn`) holds `%SourceTabs`: tab 0 is `%MaxrollPanel` (instance of
`scenes/import/maxroll_import_panel.tscn`), tab 1 is the Last Epoch Tools panel above; tab titles are set in the dialog script.
The panel re-emits `imported` through the dialog. Nodes: `%AccountEdit`, `%FindButton`, `%CharacterList` (ItemList, metadata = the character
dictionary; double click imports), `%ImportButton`, `%StatusLabel`, `%Http`. The last account name is `Settings.maxroll_account`.
- Flow: account → `GET https://planners.maxroll.gg/lastepoch/characters/<account>` (a JSON array; an unknown or private account answers HTTP 500)
  → `MaxrollImport.parse_character_list` (`{name, level, class_id, mastery, cycle, hardcore, legacy}`; legacy = an older cycle than the newest
  one of the account; current cycle first, then by level) → pick → `GET …/<account>/<name>` → `MaxrollImport.to_build` → `LEToolsImport.apply`.
  A name can repeat within one account; the API returns one of them.
- The character JSON is the offline-save format (`research/07e_save_format.md`). `to_build` returns the doc of `LEToolsImport.to_build` and reuses its
  `passives_from` / `skills_from` (`savedCharacterTree`, `savedSkillTrees` with level = spent + unspent points capped at 20, `abilityBar` as the hud).
- Items come from `savedItems` by `containerID`: 2–12 equipment (10 → ring1, 9 → ring2), 123 with base 41 → the altar (other items of 123 are the
  idol inventory), 29 idols, 33–39 / 43–45 blessings (subtype = blessing id, roll = first implicit roll, slot = the blessing's first timeline),
  91–96 Weaver items (a warning only). The blob is upgraded to version 6 (`upgrade_item`, port of `save_parser.upgrade_to_v6`) and decoded by
  `decode_item`. Idol position: the game y axis goes up and the position is the bottom-left cell, so `row = 5 - y - height`, `col = x`
  (checked on real characters with altars). Affix ids are redirected by `convertOnIncompatibleItemType`; idol affixes get tier 1 except
  enchantments; regular-sealed and primordial affixes get `sealed`, corruption-sealed ones `corrupted`.

## Builds: saves and the build code — `scripts/builds/builds_dialog.gd` (`class_name BuildsDialog extends Window`), `scripts/engine/build_codec.gd` (`BuildCodec`)
The button `%BuildsButton` ("Builds…", top bar) opens `%BuildsDialog`; on its `loaded` signal `main.gd` syncs the top bar like after an import.
The dialog: `%NameEdit` + `%SaveButton` (save under a name, the same name overwrites), `%BuildList` (newest first; double click loads),
`%LoadButton`, `%DeleteButton` (asks `%DeleteConfirm` first), `%OpenFolderButton` (hidden in the browser build), `%CodeEdit`, `%CopyCodeButton` (encodes the current build,
puts the code into the field and the clipboard), `%LoadCodeButton` (decodes the field, or the clipboard when the field is empty), `%StatusLabel`, `%CloseButton`.
- `BuildCodec.to_dict(Build)` — a JSON-safe snapshot `{format: "le-builder", version: 1, class, mastery, level, quest_points, passives, skills[5]
  {ability, level, tree, inputs, hits}, selected_skill, items, stash, blessings, enemy, player}` (`stash` — the unequipped items; older saves have none); dictionary keys that are ids are written as strings.
- `from_dict(data)` validates and restores the types (JSON numbers are floats, keys are strings): unknown class → error; unknown passive / skill nodes,
  skills and item bases are skipped with English warnings; enemy and player state are merged over `Build.default_enemy()` / `default_player_state()`,
  so older saves get new keys with defaults. A newer `version` is refused. `apply(Build, doc)` replaces the build and emits `changed`.
- Build code (as in Path of Building): `JSON → zlib (FileAccess.COMPRESSION_DEFLATE) → base64` with the URL-safe alphabet (`-`, `_`) and no `=` padding.
  `decode` ignores whitespace and also accepts the plain JSON text.
- Save files: `user://builds/<name>.json` = `{name, saved (unix time), build: to_dict}`; characters not allowed in file names become `_`.
  In the exported build `user://` is `%APPDATA%/Godot/app_userdata/<project name>/`. `tests/build_codec_test` checks the round trip.
