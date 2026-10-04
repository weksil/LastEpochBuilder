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
`scripts/items/items_tab.gd` (`extends HBoxContainer`): the slot buttons are children of `%SlotList` with `metadata/slot`, `metadata/slot_name`.
Pressing → `%ItemEditor.edit_slot(slot, slot_name)`. The button text: "slot_name: item name" or "slot_name: —".
The first slot is selected at start.
`scripts/items/item_editor.gd` (`class_name ItemEditor extends PanelContainer`), `@export implicit_row_scene`:
- `edit_slot(slot, title)`; `%BaseSelect`: item 0 "— empty —", then the `GameData` item bases that fit the slot (ENGINE.md §3),
  id = baseTypeID. `%SubSelect`: the base's subtypes (`displayName` or `name`, id = subTypeID; skip `isLegacySubType`).
- Choosing a base/subtype → `Build.set_item(slot, {base, sub, implicit_rolls: [255…], affixes: []})`.
- `%Implicits`: one `implicit_row_scene` row per implicit: `%NameLabel` = propertyName (+ tags), `%RollSlider` 0..255
  (visible only if `maxValue > value`), `%ValueLabel` = `AffixMath.roll_value(...)` via `LE.fmt_num`/`fmt_pct`
  (INCREASED and values < 1 for resistances — in %).
- `%Affixes` holds 4 ready-made rows `Prefix1, Prefix2, Suffix1, Suffix2` (scene `affix_row.tscn`):
  `%KindLabel` "Prefix"/"Suffix"; `%AffixSelect` item 0 "— none —", then `GameData.affixes_for_type(base.type)` with the required
  `type` (PREFIX/SUFFIX), text `name`, id = affixId; `%TierSpin` 1..len(tiers); `%RollSlider` 0..255;
  `%ValueLabel` — the values of all the affix's `properties` for the tier and roll (via `AffixMath`, with the base's `effect_modifier`).
  Any change → `Build.set_item(slot, updated dict)` (affixes — an array of up to 4 `{id, tier, roll, kind:"prefix"|"suffix", index}`).
- `%EmptyHint` is visible when there is no base; then `%SubRow`, the implicits and the affixes are hidden. `%ClearButton` → `Build.clear_item(slot)`.

## Conditions — `scripts/config/config_tab.gd` (`extends ScrollContainer`), `@export ailment_row_scene`
Three cards (`SectionCard`): "Player" and "Enemy" on the left, "Ailments, shreds and curses on the enemy (stacks)" on the right; at the top `%ShowAllCheck` ("Show all conditions",
off by default) and `%EmptyHint`. Each group has a one-line summary (`%PlayerSummary`, `%EnemySummary`, `%AilmentSummary`: "Active: Haste, Moving" /
"Nothing enabled", variant `SummaryActive`/`SummaryOff`) and a suffix "· N hidden without a source" / "· without a source: N". The buttons `%ResetPlayerButton` →
`Build.reset_player_conditions()` and `%ResetAilmentsButton` → `Build.clear_enemy_ailments()` (one `changed` each).
- **A filter like Path of Building**: `ConfigRelevance.compute(Build)` (`scripts/engine/config_relevance.gd`, computed only while the tab is visible, at most once per frame) returns
  `{player_flags, player_values, ailments, enemy}` — a key is present if the condition has a source in the build, the value is the source text (may be several lines), it goes into `tooltip_text`
  (for ailments — also the second line of the row). Without "Show all conditions", player flags, player numbers, enemy flags and ailments without a source are hidden, **except** those whose value
  differs from the default (the enemy flags `high_health` and `full_health` are on by default): those stay visible and are marked "no source"
  (`CheckBoxNoSource`, `RowNoSource`). A row with input focus is not hidden. The enemy's type, level, armor and resistances are always visible. If there is nothing to show — `%EmptyHint`
  "No conditions the build depends on". If the file `config_relevance.gd` is missing — everything is considered to have a source.
- `%HealthSelect` → `Build.set_player_state("health", ["full","high","normal","low"][i])`.
- `%KindSelect` → `Build.set_enemy("kind", ["dummy","normal","magic","rare","miniboss","boss"][i])`; `%LevelSpin` → "level"; `%ArmourSpin` → "armour".
- The SpinBoxes with `metadata/res_index` (children of `%EnemyGrid`) → `res[i]` (a copy of the array, then `Build.set_enemy("res", arr)`).
- The CheckBoxes `%EnemyFlags` with `metadata/flag` → a copy of `flags`, `Build.set_enemy("flags", d)` (including `frozen`).
- The CheckBoxes `%PlayerFlags` with `metadata/player_flag` (`hit_recently, crit_recently, moving, leeching, low_mana, haste, frenzy`) → `Build.set_player_state(flag, pressed)`;
  the SpinBoxes in the `%PlayerValues` rows (`PanelContainer` > `HBoxContainer` > `Label`, `SpinBox`) with `metadata/player_value` (`ward, curses, ignite_stacks, damned_stacks`) →
  `Build.set_player_state(key, int(v))`. A row with a non-zero value is `RowActive`.
- `%AilmentList`: one `AilmentRow` (`scenes/config/ailment_row.tscn`, `class_name AilmentRow`) per `GameData.enemy_ailments()`: `%NameLabel` = `displayName` (otherwise `name`),
  `%KindLabel` ("curse" / "shred"), `%ReasonLabel` = the source, `tooltip_text` = the description, `buffs`, `maxInstances`, "against bosses ×(1+moreBuffEffectAgainstBosses)";
  `%StacksSpin.max_value` = maxInstances (or 200) → `signal stacks_changed(id, stacks)` → `Build.set_enemy_ailment`. A row with stacks is `RowActive`, without a source — `RowNoSource`.
  Rows with a source go first. `%Filter.text_changed` hides rows whose name (both names and the kind) does not contain the text (case-insensitive).

## Calculations — `scripts/calcs/calcs_tab.gd` (`class_name CalcsTab extends VBoxContainer`), `@export section_scene, row_scene, input_row_scene`
Top to bottom: `%SkillSelect` (5 slots "N. skill name", empty ones "N. —"; the choice → `Build.selected_skill`), `%Summary` (`CalcSummary`), a scrollable `%Scroll`
with `ParamsPanel` ("Calculation parameters": `%HitsSpin` and the `%Inputs` grid in 2 columns), `%Buffs` (`BuffsPanel`), the columns `%Left` / `%Right` and `%Wide` (`%Notes`).
- `r = SkillCalc.compute(Build, Build.selected_skill)` once per frame on `Build.changed` and when the tab is shown (an invisible tab calculates nothing).
- **The summary strip** `scenes/calcs/calc_summary.tscn` (`class_name CalcSummary`, `show_result(result)`): the skill name, "Target: …" and four `CalcTile`
  tiles (`show_value(text, sub, tooltip)`): "DPS vs enemy" (the main one), "Average hit" (the row "Average hit vs enemy"), "Uses per second", "Crit chance".
  The values are taken from the result rows by the label inside their section (`CalcSummary.find_row(result, label, section)`): DPS, average hit and target —
  from exactly the section "Against enemy" (each "Ailment: …" section has its own "DPS vs enemy" row), uses — from "Speed and mana", crit — from "Crit"
  (for uses and crit, if there is no section — the first row with the label); no row — "—". The tile's tooltip is the row's breakdown.
- **Parameters**: `SkillInputRow` (`setup(slot, inp)`, `fits(inp)`, `update_input(slot, inp)`): a number — `SpinBox`, a flag — `CheckBox` with the label text. The set of rows
  is recreated only when the slot or the set of keys/types changes; otherwise values are updated without signals (`max` — only if it changed).
- **Sections** in a fixed order (`CalcsTab.ordered_sections`): first the main component (damage → conversions → penetration/crit → speed and mana → ailments →
  skill parameters → against enemy → sustain), then the other components (sub-skills, triggers) in the same order. The columns are filled consecutively:
  the first half of the rows is `%Left`, the rest is `%Right`. A section is `section_scene` (`%Title`, `%Rows`), a row is `row_scene` (`CalcRow`: `setup(key, row, alt, expanded, key_row)`,
  `update_row(row)`; "+"/"−" expands `%DetailsPanel`/`%Details`, the button is hidden without a breakdown; the "DPS vs enemy" row of the "… Against enemy" sections — `ValueLabelKey`).
  A row's identity is "section title|label" (repeats with `#n`). If the set of sections and rows is the same — the rows are updated in place (a changed value flashes);
  otherwise the tree is recreated, expanded rows are restored by key (`_expanded`), `scroll_vertical` is kept.
- "Not counted" from `r.notes` is a collapsible block `CalcNotes` (`show_notes(notes)`, collapsed by default, "▸ Not counted (N)"), hidden without notes.
- No skill in the slot — one section with a hint to pick a skill in the "Skills" tab.
- **Skill buffs on the character** — `scenes/calcs/buffs_panel.tscn` (`BuffsPanel.refresh()`, `@export row_scene` = `BuffSkillRow`): `BuildMods.skill_buffs(Build)` gives for
  each skill on the bar (one per skill) `{slot, ability_name, active, toggle, mods}`. The row: `%ActiveCheck` ("Slot N · skill", bound to the `buff_active` input via
  `Build.set_skill_input(slot, "buff_active", on)`), the status ("active · mods: N" / "off — not active" / "no buffs on the character" — then a label instead of the checkbox),
  an expander "mods (N)" with the rows `BuildMods.describe_mod(mod)` ("+60% inc Damage — source"). A disabled skill shows the mods that it would give if enabled.

## Stats panel — `scripts/stats/stats_panel.gd`
`@export row_scene, group_scene`. On `Build.changed` (at most once per frame): `g = BuildMods.global_store(Build)`, `rows = CharacterCalc.compute(g.store, Build)`.
First the rows "Class/Mastery/Level/Passive points", then by groups: `group_scene` (Label) and `row_scene` (`StatRow`: `NameLabel`, `DeltaLabel`, `ValueLabel`,
`tooltip_text` = the breakdown). While the set of rows is the same, the rows are updated in place (`StatRow.update_row(text, tooltip, value)`): a changed row gets the variant
`StatRowChanged` for ~1.5 s, and if the row has a numeric `value`, the difference is shown next to it ("+12", "−3%", variants `DeltaUp`/`DeltaDown`).
`%SummaryCard` (visible if the selected slot has a skill and there is a "DPS vs enemy" row in the "Against enemy" section): `%SkillName` "<skill> · DPS vs enemy", `%SkillSummary` — the number (`HeroValueMain`),
`%SkillTarget` — "target: <Enemy.describe>", the card's tooltip is the row's breakdown.

## Idols — `scripts/idols/idols_tab.gd` (`extends HBoxContainer`)
Scene `scenes/idols/idols_tab.tscn`: `%Grid` holds 25 ready-made `IdolCell` buttons with `metadata/row`, `metadata/col`;
on the right `%ItemEditor` (the same `ItemEditor`, it understands idol keys itself). The helper is `IdolGrid` (`scripts/engine/idol_grid.gd`):
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
- With a unique: `%BaseSelect` and `%SubSelect` `disabled = true`; `%UniqueTitle`, `%UniqueMods`, `%UniqueText` are visible (otherwise hidden).
  `%UniqueMods`: an `implicit_row_scene` row for every mod with `hideInTooltip == 0`: `%NameLabel` = `_prop_title(mod)`, `%RollSlider` is visible
  if `canRoll == 1 and maxValue > value`, the value = `unique_rolls[rollID]`; a change → write into `unique_rolls[rollID]` and `_commit`;
  `%ValueLabel` = `_format(mod, AffixMath.unique_value(mod, roll))` (update in `_update_values`, all rows of the same rollID in sync).
- `%UniqueText.text`: the lines `tooltipDescriptions[].description`; if `isSetItem` — an empty line, "Set "setName":" and the lines
  `set_data.tooltipDescriptions` of the form "(N) description".
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
- `to_build` accepts the full response `{data: {...}}` or just `data`; it returns `{class_id, mastery, level, passives, skills[5], items, blessings, warnings}`.
  Unknown ids/nodes are skipped with an English warning, no crashes.
- Id encoding (`LZString.decompress_from_encoded_uri` → a string of digits): `I` — `1` + base(3) + subtype(3) + rarity(1) + uniqueId (≥ 2 digits);
  `U` — subtype(3) + uniqueId; `A` — affixId. An idol `(x, y)` → `IdolGrid.key(y - 1, x - 1)`; sealed and corrupted affixes are appended
  to `affixes`, a corrupted idol gets `corrupted: true`. Slots: head→helmet, chest→body, waist→belt, feet→boots, hands→gloves,
  weapon1→weapon, weapon2→offhand, idol_altar→altar. Not supported: the Weaver tree and idols, set ids (`S`); blessing blocks
  (`I` base 34, subtype = the blessing id, roll = `ir[0]`) are implemented by guesswork and not verified on a live example.

## Builds: saves and the build code — `scripts/builds/builds_dialog.gd` (`class_name BuildsDialog extends Window`), `scripts/engine/build_codec.gd` (`BuildCodec`)
The button `%BuildsButton` ("Builds…", top bar) opens `%BuildsDialog`; on its `loaded` signal `main.gd` syncs the top bar like after an import.
The dialog: `%NameEdit` + `%SaveButton` (save under a name, the same name overwrites), `%BuildList` (newest first; double click loads),
`%LoadButton`, `%DeleteButton` (asks `%DeleteConfirm` first), `%OpenFolderButton`, `%CodeEdit`, `%CopyCodeButton` (encodes the current build,
puts the code into the field and the clipboard), `%LoadCodeButton` (decodes the field, or the clipboard when the field is empty), `%StatusLabel`, `%CloseButton`.
- `BuildCodec.to_dict(Build)` — a JSON-safe snapshot `{format: "le-builder", version: 1, class, mastery, level, quest_points, passives, skills[5]
  {ability, level, tree, inputs, hits}, selected_skill, items, blessings, enemy, player}`; dictionary keys that are ids are written as strings.
- `from_dict(data)` validates and restores the types (JSON numbers are floats, keys are strings): unknown class → error; unknown passive / skill nodes,
  skills and item bases are skipped with English warnings; enemy and player state are merged over `Build.default_enemy()` / `default_player_state()`,
  so older saves get new keys with defaults. A newer `version` is refused. `apply(Build, doc)` replaces the build and emits `changed`.
- Build code (as in Path of Building): `JSON → zlib (FileAccess.COMPRESSION_DEFLATE) → base64` with the URL-safe alphabet (`-`, `_`) and no `=` padding.
  `decode` ignores whitespace and also accepts the plain JSON text.
- Save files: `user://builds/<name>.json` = `{name, saved (unix time), build: to_dict}`; characters not allowed in file names become `_`.
  In the exported build `user://` is `%APPDATA%/Godot/app_userdata/<project name>/`. `tests/build_codec_test` checks the round trip.
