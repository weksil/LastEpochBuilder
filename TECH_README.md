# Last Epoch Builder — technical README

Developer documentation: formula and data sources, architecture, checks, the release build. The user-facing page is
[README.md](README.md) (link to the web build, screenshots); GitHub Pages serves the browser build (see "Web build").

A build planner for Last Epoch in the spirit of Path of Building: exact numbers with a breakdown
of every value, items / idols / blessings / skill and passive trees,
checkboxes for player and enemy conditions, and character import in a few clicks.

Game version the data was checked against: **1.5.0 (Season 5)**.
Full plan, architecture and risks: [PLAN.md](PLAN.md).

## Status

| Part | State |
|---|---|
| Formula and data research | done (`research/`) |
| Extracted game data | ready (`research/data/game/`) |
| Calculation engine (GDScript, `client/scripts/engine/`) | the shared layer works: stat model, mod sources (class, passives, items, unique items and set bonuses, unique special effects from the model table (784 of 866, the rest are ordinary mods and the altar), special passive lists, idol altars, idols, attributes, blessings, skill tree), models for all 4890 skill tree mutator fields and special stat lists (stats, speed, mana, cooldown, parameters, triggers, sub-skills, minion stats), a skill as a set of damage components (main hit, sub-skills (one sub-skill from the prefab and a tree node is one component with a detonation count), damage from code, supported periodic damage of a single instance (Spirit Plague: damage over the whole action and per second, no crit), curse damage on hitting the target — frequency from two inputs, "your hits" (by default taken from the skill bar) and "minion and ally hits", triggers, minions, uses repeated by active Rogue shadows and Void Knight echoes (Warpath echoes once per second through its node), health and ward on shadow creation), enemy ailments, shreds and curses kept on the target (average stacks and uptime from the chance, hits per second and duration; the skill's hits, minions and zones that apply ailments every interval, the minions and zones of the other bar skills and the skills used on cooldown; stacks spent by consuming hits; Shadow Daggers strikes at 4 stacks as a damage component) unless a number is set on the Conditions tab, damage conversions and skill tag changes from tree nodes (a field written into the mutators of several parts of a combo skill counts once; nodes of another bar skill aimed at this skill count for it), character stats, skill damage, crit, speed, ailment damage (Ignite, Bleed, Poison, etc.: chance, stacks, damage per stack, limits), "in-game" DPS and DPS vs enemy, effective health against one enemy attack (the average monster of a level 100 monolith and the attacks of the monolith end bosses and pinnacle bosses, scaled by area level and corruption; dodge/block conversions, conditional defenses of the character mutator, damage taken as another type, delayed damage; maximum hit taken, hits to die with regeneration, ward, leech and on-hit recovery between hits). The test vectors from the research pass |
| Client (Godot 4.7) | working MVP: passives, 5 skills with trees (tree visuals from the game client: icons, frames, backgrounds, ornaments, connections), 11 item slots with affixes, idol grid, player and enemy conditions, a Calculations tab with a totals strip, skill buffs on the character and a breakdown of every number, a Defense tab with effective health against boss attacks, Conditions with a filter by source, a stats panel with highlighting of changes, saved builds and a shareable build code (as in Path of Building) |
| Not done | base buffs defined in prefab data rather than in code (Flame Ward 30%, Focus, Rebuke, etc. — their numbers were not found in the dump), import from a local offline save file (a character is imported by account name through Maxroll or by a Last Epoch Tools link; the Weaver tree is not imported, set ids of LE Tools are not imported). Damage is calculated against a single target: ailment spreading, chains and area damage to other enemies are not part of DPS. Special effects that reduce to behavior without numbers (immunities, AI, visuals) are listed under "Not counted". What is not counted in a specific build is shown in the "Not counted" section of the Calculations tab |

Deferred tasks are in [BACKLOG.md](BACKLOG.md).

## Where the formulas and data come from

Every engine formula relies on one of the sources below. The source label appears in the `research/` notes and in
[client/docs/ENGINE.md](client/docs/ENGINE.md). When sources disagree, the game code (D) wins, then the official guide (A).
Disagreements are marked ⚠ in `research/02_le_formulas.md`.

| Label | Source | How it was obtained | Where it is stored |
|---|---|---|---|
| **A** | The official in-game guide by Eleventh Hour Games (Game Guide) and patch notes | The guide text was taken from the localization file served by LE Tools (`/data/version150/i18n/full/en.json`, keys `GameGuide.*`). The formula images (armor, ward, dodge, block, stun, freeze) were transcribed into text | `research/02_le_formulas.md`, copies in `research/02_assets/` |
| **A** (data) | Assets of the installed 1.5.0 client: classes, attributes, properties, affixes, items, uniques, sets, ailments, idols and altars, blessings, trees, monsters | Unity bundles read with UnityPy and an AssetRipper export. Odin serialization (altar grids) parsed with a custom decoder. ActorScaler tables taken from `global-metadata.dat` | `research/data/game/*.json`, described in `research/07a`, `07b`, `07f` |
| **D** | Game client code (Unity 6000.4.8f1, IL2CPP) | Local decompilation: Cpp2IL (C# signatures and an ISIL disassembly of every method), Il2CppInspectorRedux (method addresses), Ghidra (pseudo-C). Float constants were read directly from `GameAssembly.dll`. The method was first checked on the armor formula: the recovered code matched the guide down to the last constant | Findings are in `research/07*` and ENGINE.md. The notes with disassembly fragments (`05`, `06*`, `07j`) and the dump itself are kept locally and are not published |
| **D?** | The same code, but the meaning of the spot is ambiguous | The reason is given next to the formula. Such spots were re-checked in separate waves (`research/07k`, `07m`) | same place |
| **B / X** | Community data and code: LE Tools bundles and planner, the Tunklab library, Maxroll articles, forum tests | Used for cross-checking and where there is no code or asset | `research/02_le_formulas.md`, `research/03_le_data_sources.md` |
| **C** | A guess or no source found | Not considered confirmed. What the engine does not implement is listed in the "Not counted" section of the Calculations tab | `research/02_le_formulas.md` |

Skill tree mechanics and unique special effects were assembled in stages:
- **Skill tree mutator fields** (4890 fields). For each field, we traced where the game code passes its value
  (`research/07c`, `07g`, `07h`; the tracer is `tools/extract/field_tracer.py`). The fields were then annotated with models following `tools/models/AUTHORING.md`
  and checked by `validate.py`. The label `D(w4*)` means: the use of the field is confirmed by a verbatim code quote, and the formula is partly derived by the annotation.
  The result is `client/data/field_models.json`.
- **Unique special effects** (`research/07d`, `07i`): the PlayerProperty and AbilityProperty handlers were read in the code.
  The result is `client/data/unique_effect_models.json`.
- **Damage and ailment conversions from trees** (`research/data/game/skill_conversions.json`) were annotated from the descriptions in the mutator code.
  This is D?; the in-game check is in [BACKLOG.md](BACKLOG.md).
- **Complex cases were worked out by hand** from the code: Holy Aura (`research/07l`), minions (`07d`, `07j`), the save format (`07e`).

In-game verification. Hit numbers were checked against the training dummy. For example, Harvest of the test build gives 995 without a crit and 2487 with a crit — the same as in the game.
That is why the default target is the dummy, and the calculation shows its "hit without crit" and "hit with crit". The layout of the idol altar grids was checked
against a screenshot from the game. The test vectors from the research are run by `client/tests/engine_test`.

The data and formula sources need to be re-checked after every game patch. The LE Tools bundle addresses change with the version,
the commands for repeating the extraction are described in the notes `research/03`–`07` (some of them local) and in the scripts under `tools/extract/`.

## Repository layout

```
README.md        user-facing README shown on GitHub (web build link, screenshots, license)
TECH_README.md   this file
LICENSE          MIT license (for the project code, see "License")
docs/            screenshots used by README.md (plain git, not LFS)
build_windows.ps1  builds the Windows x64 release (see "Release build")
build_web.ps1    builds the browser version (see "Web build")
.github/workflows/pages.yml  builds the browser version and publishes it to GitHub Pages
release/         README.txt shipped inside the release zip
PLAN.md          verdict, architecture, phases, risks
BACKLOG.md       deferred tasks
research/        research notes (01…07n) and data
  02_assets/     texts and images of the formulas from the in-game guide (PNGs are in Git LFS)
  data/          enums, tables and JSON with game data (data/game/*.json)
client/          Godot project
  assets/trees/  skill and passive tree sprites from the game client (PNGs in Git LFS; tools/extract/extract_tree_art.py)
  assets/items/  item type icons from the game client (PNGs in Git LFS; tools/extract/extract_item_icons.py)
  i18n/          ru.po — Russian translation (msgid = English source text)
  data/          the client's hand-written tables: unique_effect_models.json (unique special effects),
                 field_models.json (models of mutator fields and special stat lists, ENGINE.md §9)
  docs/          ENGINE.md — engine specification, UI.md — contract for UI scripts
  scenes/        UI scenes (.tscn): main, passives/, skills/, items/, config/, calcs/, defense/, stats/, trees/, builds/, common/
  scripts/       logic (.gd): autoload/ (Settings, GameData, Build, BuildHistory — undo / redo), engine/ (calculations), UI scripts in folders matching the scenes
  tests/         headless checks: engine_test (test vectors), ui_smoke (run through all tabs), trees_test, minion_test, letools_import_test, maxroll_import_test,
                 layout_test, relevance_test, i18n_test, build_codec_test, build_history_test, defense_test,
                 readme_screenshots (captures docs/screenshots, needs a window)
  export_presets.cfg  export preset "Windows Desktop"
  theme/         main_theme.tres — the shared theme and style variations
  addons/        the godot_ai plugin
```

Not part of the repository (kept locally, see `.gitignore`):
`dump/` and `tools/` (client decompilation, Ghidra, Cpp2IL, scripts), `build/` (release output), machine-specific files
(`.mcp.json`, `.serena/project.local.yml`, IDE folders, Godot `override.cfg` / `export_credentials.cfg`), notes
derived directly from disassembly (`05_*`, `06?_dump_*`, `07j_*`,
`abilities_code_damage.json`), agent briefs, `client/.godot/`, logs.

## Client (Godot)

- Engine: Godot 4.7, GL Compatibility renderer, Jolt physics.
- Interface language: English (default) or Russian — selector in the top bar; translations in client/i18n/ru.po (msgid = English source text).
- The project opens from `client/project.godot`, the main scene is `scenes/main.tscn`.
- Game data is read from `research/data/` through `LE.research_dir()` / `LE.game_data_dir()`: in the editor directly from the repository
  (`res://../research/data`), in the exported build from the packed copy `res://data/research` that `build_windows.ps1` puts there
  for the export (the copy is not committed). `client/data/` itself holds only the planner's hand-written tables.
- The **Godot AI** plugin (`client/addons/godot_ai`, v4.1.0, source
  <https://github.com/hi-godot/godot-ai>) is enabled in `[editor_plugins]`.
  When the project is opened in the editor, the plugin connects to the `godot-ai` MCP server,
  and Claude Code can drive the editor (scenes, nodes, scripts, running).
- [uv](https://docs.astral.sh/uv/) (`uvx`) is required — it launches the MCP server.

### Client code rules

- All visuals live only in scene files (`.tscn`) and the theme (`theme/main_theme.tres`).
  Scripts do not create UI nodes and do not set styles; they only instantiate ready-made scenes
  (`PackedScene` via `@export`), fill in values and switch `theme_type_variation`.
- Values apply immediately: every `SpinBox` has `update_on_text_changed` enabled, recalculation is deferred and runs at most once per frame,
  rows are updated in place (the set of rows does not change — nodes stay alive, so focus, expanded breakdowns and scroll position are preserved), and changed numbers are highlighted.
  Checkboxes and toggles are styled in the theme (icons in `client/theme/icons/`, an enabled row has a gold frame).
- Autoloads: `GameData` — loading the game JSON and searching it; `Build` — the build state
  (class, mastery, level, passives, skills, items, enemy, player state) with a `changed` signal.
- The engine is described in [client/docs/ENGINE.md](client/docs/ENGINE.md), the contracts of the UI scripts
  in [client/docs/UI.md](client/docs/UI.md). New files are written according to these documents.
- Every number on screen comes with a breakdown (the source of each mod).
  If a mechanic is not implemented, it goes into the "Not counted" list instead of being silently skipped.

### Tabs

- **Trees** (passives and skills) look like in the game: node icons under a mask, frames (a light one for taken nodes), a points badge, background,
  runes and ornaments, connection rails with a glow between taken nodes — all from the game's UI prefabs (`research/data/game/tree_art.json`,
  `client/assets/trees/`). The tree fits the window, Ctrl + mouse wheel zooms. 5 passive nodes without a UI node in the game prefabs are shown as a circle.
  The node tooltip is split into parts: description, "Per point" stats (with the total for the allocated points), "Fixed" stats (given once from
  the first point), "Bonus at N points" (the threshold bonus: its description and stats, active or not yet) and the extra explanation (`altText`).
- **Passives** — the class tree and three masteries; LMB adds a point, RMB removes one. A node's requirements
  (`requirements`) work as "OR": any neighbor with the required number of points is enough
  (`LocalTreeData.ArePassiveNodeRequirementsMet`); a point cannot be removed if the node would be cut off from the root. The
  `masteryRequirement` threshold is taken into account (points in nodes of the base tree and of this mastery with a lower
  threshold). Point limit: level − 2 + 15 from quests (07e §6); the restriction on other masteries is not implemented.
- **Skills** — 5 slots, skills of the class and the chosen mastery; tree points = skill level + the "+N to level" bonus from items.
- **Items** — 11 slots: base, subtype, implicits (roll 0–255), 2 prefixes and 2 suffixes (tier, roll).
  A unique item is chosen from a list: its mods with rolls by `rollID`, the base's implicits, legendary affixes.
  Set bonuses are counted by the number of distinct set items (Legends Entwined counts toward every set).
  Unique special effects that reduce to stats are computed from the `client/data/unique_effect_models.json` table
  (stats from attributes and resistances, conditional bonuses, properties of specific skills, multipliers of damage taken);
  conditional ones are enabled by flags in the Conditions tab, the rest are listed in "Not counted" with the reason.
  Values are quantized as in the game (`AffixMath`, 07a §6), taking the base's effect modifier into account.
  Items are switched as in Path of Building: each slot is a dropdown of the character's items that fit it (equipped ones carry
  the symbolic icon of their slot, unequipped ones are grey); below a separator the unequipped items are listed and "+" adds a new one (type, then base, in the editor). Items can be
  renamed; an affix slider runs through all its tiers, ticks mark the tier borders; the unique, base and affix lists have a search field.
  Edits stay unsaved until "Save": under the item the editor shows what saving would change (DPS, health, resistances…), "Discard
  changes" drops them. Uniques take prefixes and suffixes too (legendary potential, Weaver's Will). Affix lists also offer set
  ("Reforged"), experimental and personal affixes; regular items have a sealed affix row, and the "Corrupted" box adds a corrupted affix
  row with the corruption pool (items and idols).
  Hovering any item shows what equipping it changes (DPS vs enemy of the selected skill and every numeric character stat). The editor
  shows the bonuses of a set item's set: active ones in green, inactive ones grey. Slot icons are the item type icons of the game's
  prophecy / monolith rewards (`client/assets/items/`, `tools/extract/extract_item_icons.py`).
- **Blessings** — one per timeline (normal or grand) with a roll, implicits go into stats. Hovering a blessing in the dropdown shows its effect (roll range of every implicit). Under the rows a stat diff shows what all chosen blessings give (DPS and character stats, live while a roll slider moves).
- **Idols** — a 5×5 grid, an altar (13 subtypes) changes the grid and gives refracted cells and properties; clicking a cell places an idol,
  the base size is checked against free cells; 1 prefix and 1 suffix, affixes and large idols are by class. The idol editor (shown
  after picking a cell) offers only idol bases and unique idols (each with its size, e.g. "[1x3]"), with the same roll sliders, unsaved-changes stat diff, weaver /
  enchantment affixes and a corrupted affix row; the Items tab never offers idols.
- **Calculations** — at the top is a totals strip: DPS vs enemy (with the target name), average hit, uses per second, crit chance; below are the calculation parameters
  (hits on the target, stacks, number of minions, event frequency for triggers — change on the fly), the "Skill buffs on the character" panel
  (each skill on the bar with its mods on the character and an enable checkbox; the buffs apply to all skills and stats: "on the character" tree effects,
  Holy Aura, Symbols of Hope, Enchant Weapon, Firebrand, Aura of Decay, Dark Quiver) and sections in a fixed order: damage components (main hit, sub-skills,
  triggers, minions), conversions and final tags, crit and penetration, speed, mana and cooldown, ailments (a section for each), skill parameters from the tree,
  DPS vs enemy (hit without crit and with crit as on the dummy, average hit, per component and the total), sustain (leech, health/mana/ward per hit).
  "+" expands the breakdown (in a monospace font; expanded rows do not collapse on recalculation), "Not counted" is a collapsible block.
- **Defense** — effective health against one enemy attack, as "Maximum hit taken" / "Total EHP" in Path of Building. Two dropdowns:
  the group, then its attack. Groups: the average monster of a level 100 monolith (hit with every damage type, melee hit, ranged hit,
  spell hit, damage over time; `research/data/game/monster_damage.json`), the end bosses of the 10 monolith timelines and the pinnacle
  bosses (Aberroth, Herald of Oblivion, Morditas, Majasa, the Observer and its Vision, the Uber Aberroth Harbingers;
  `research/data/game/boss_attacks.json`), a custom hit. An attack is scaled to the area level (ActorScaler) and by the enemy
  corruption of the Conditions tab (also editable here). Dodge and block conversions, conditional defenses, damage taken as another
  type and delayed damage come from research/07n. Recovery between hits (regeneration, ward with decay, leech and on-hit gains of the
  skill selected on Calculations, recovery effects of the tree, uniques and passives) is simulated every "seconds between hits". The tiles show
  effective health (hits to die × raw hit), maximum hit taken, hits to die and the share of the raw damage taken; the sections show the
  attack, mitigation by damage type (resistance with the enemy's area penetration, damage taken, armor), avoidance (dodge, parry,
  glancing, block, enemy crit), the pool (health, ward, endurance, mana before health) and the maximum hit per damage type
  (client/docs/ENGINE.md §10). A warning appears when the worst hit (crit, +20% variance) kills from full health.
- **Conditions** — health and player state (hit recently / crit recently, movement, leech, mana below 50%, Haste, Frenzy,
  ward, curses and stacks on yourself, active shadows), "Buffs on me" with stacks (Dusk / Crimson / Silver Shroud, Void
  Essence, Divine Essence, Sharpshooter … — any positive ailment of `ailments.json`, its stats go to the character), enemy type/level/armor/resistances, flags (including "frozen") and stacks of ailments,
  shreds and curses (buffs are taken from `ailments.json`, the penalty against bosses is accounted for); an enemy ailment
  with "auto" on shows the average the selected skill keeps on the target (applications per second × duration, uptime), a
  number typed in replaces it, "Reset" returns all of them to auto. As in Path of Building, only the conditions
  that have a source in the build (skill, item, passive; `ConfigRelevance`) are shown, labeled with the source; the "Show all conditions" checkbox opens the full list,
  and enabled conditions without a source are highlighted in red. Each group has an "Active: …" line and a "Reset" button; ailments are shown with readable names.
- **Builds** (the "Builds…" button in the top bar) — save the current build under a name (`user://builds/<name>.json`), load or delete a saved one,
  copy the build code (the whole build as one line: JSON → zlib → URL-safe base64, as in Path of Building) and load a build from someone's code.
- **Import** (the "Import…" button in the top bar) — two tabs:
  - "Maxroll account": the account name → the character list (`GET planners.maxroll.gg/lastepoch/characters/<account>`) → pick a
    character → `GET …/<account>/<name>`. The answer is the game's offline-save JSON with binary item blobs (`research/07e`), the
    profile on Maxroll must be public. The last account name is kept in `user://settings.cfg`.
  - "Last Epoch Tools link": a build by a lastepochtools.com/planner/<code> link (or by pasted planner_data JSON). On a timeout
    (HTTPRequest.RESULT_TIMEOUT) the dialog waits 3 s and retries, up to 3 times.

  Both give class, mastery, level, passives, 5 skills with trees, items, idols with altar, blessings. The current build is replaced;
  unsupported things (Weaver; set items of LE Tools) and unrecognized ids are listed as warnings.
- **Stats** (on the right) — attributes, resources, defenses, resistances; a row's tooltip is its breakdown.

### Checks

```
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/engine_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/ui_smoke.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/trees_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/layout_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/relevance_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/i18n_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/letools_import_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/maxroll_import_test.tscn
Godot_v4.7-stable_win64_console.exe --headless --path client res://tests/defense_test.tscn
```
`engine_test` checks the test vectors from `research/06a–06c`, `07a`, checks uniques, sets and special effects
(including a run of all uniques with conditions enabled), Rogue shadows (with health / ward on creation), Void Knight
echoes (Warpath), nodes aimed at another bar skill, buffs on the player and combo parts (`letools_Q0V6XDLG.json`, `maxroll_char_palading.json`) and prints an example build with a breakdown;
`ui_smoke` runs through all tabs and prints script errors to the console (watchdog timer 180 s), checks typing into a `SpinBox` without Enter,
in-place updates of the Calculations rows, the totals strip and the "Reset" buttons;
`i18n_test` imports the saved builds, shows every tab in Russian and fails on every string that went through `LE.t()` without a
translation in `client/i18n/ru.po` (`LE.missing`);
`relevance_test` checks the Conditions filter (`ConfigRelevance`: which flags, numbers and ailments have a source in the build);
`defense_test` checks effective health (pool vectors of research/06c §2.7/§2.9, endurance modes, delayed damage, damage taken
as another type (07n §1), recovery between hits, ActorScaler and corruption scaling, the boss presets and the average monster,
an imported build against Uber Aberroth, a passive dodge conversion, the defense settings in the build code);
`minion_test` checks the transfer of player stats to a minion (07d §1.1);
`layout_test` imports an example build and checks that every tab fits a 1600 px wide window (long texts wrap);
`letools_import_test` checks import from Last Epoch Tools (LZString, ids, links, the saved response `tests/fixtures/letools_A83KxJq5.json`,
skills taken from the specialized trees rather than the skill bar (`letools_Q0V58LLX.json`), applying to `Build`, the button in the top bar); `letools_live` (not part of the suite, needs network) loads a live link through the dialog;
`maxroll_import_test` checks the Maxroll import (URLs, the character list `maxroll_list_jessrabbit.json`, item blob versions 1–6,
sealed / corrupted / primordial affixes, the characters `maxroll_char_palading.json` and `maxroll_char_chudlet.json` with altars, idols,
blessings and a set item, applying to `Build`); `maxroll_live` (not part of the suite, needs network) imports a live character through the dialog;
`trees_test` checks that tree nodes have icons from the game client and that every node of all 136 current skill trees and 5 passive trees can be taken
(obsolete version 0 trees — Fire Shield, Ice Ward, etc. — are skipped).

`readme_screenshots` (not part of the suite, run without `--headless`) imports the fixture builds and saves the English
screenshots of README.md and the landing page into `docs/screenshots/`: `minions.png`, `skill_calcs.png` and the frames of the
item editor GIF (`docs/screenshots/frames/`). Make the GIF and delete the frames:
```
ffmpeg -y -framerate 8 -i docs/screenshots/frames/%03d.png -vf "crop=1230:780:0:60,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" -loop 0 docs/screenshots/item_diff.gif
```

The tree visuals are built by the local script `tools/extract/extract_tree_art.py` (UnityPy over the game bundles: tree UI prefabs,
sprites by `m_Sprite` and soft references `m_SpriteSoftRef`) into `research/data/game/tree_art.json` and `client/assets/trees/`; after it
an asset import is needed (`Godot --headless --path client --import` or open the editor).

The models in `client/data/field_models.json` are built by the local pipeline `tools/models/` (packs by field semantics from
`research/data/game/mutator_field_semantics_*.json` → annotation by agents following `AUTHORING.md` → `validate.py` → `merge.py`).

The conversion rules in `research/data/game/skill_conversions.json` are built by the local scripts
`tools/extract/conversions/` (`prefilter.py` → annotation of batches → `merge.py` with checks and manual fixes).
The boss attacks in `research/data/game/boss_attacks.json` are built by `tools/extract/extract_boss_attacks.py` (UnityPy: boss
ActorData → actor prefab → abilities referenced in the prefab or named with the boss prefix → damage components; the monolith
timeline assets do not name their boss, so the timeline → boss mapping is given in the script); the average monster damage in
`research/data/game/monster_damage.json` by `tools/extract/extract_monster_damage.py` (ordinary monsters with `spawnsInMonolith`).
The recovery models of `client/data/field_models.json` and `unique_effect_models.json` carry an `amount` (how much a resource
effect restores, client/docs/ENGINE.md §10.3), annotated by hand from the field semantics.
The projectile counts and shotgun flags in `research/data/game/ability_projectiles.json` are built by
`tools/extract/extract_projectiles.py` from the AssetRipper export (client/docs/ENGINE.md §9.9).
An editor in which the autoloads were added without a restart shows false errors
`Identifier not found: Build/GameData` — they go away after the editor is restarted.

### Development tools

| Tool | What it does | How it is connected |
|---|---|---|
| godot-ai | controls the Godot editor from Claude Code | the plugin in `client/addons/godot_ai` + the user-scope MCP server `godot-ai` |
| Serena | semantic code navigation and editing | local `.mcp.json` (launched via `uvx` from `oraios/serena`), project settings in `.serena/project.yml` |

`.mcp.json` is machine-specific (it holds the absolute project path) and is not committed. To use Serena, create it in the repository root:
```json
{
  "mcpServers": {
    "serena": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena", "serena", "start-mcp-server",
               "--context", "claude-code", "--project", "<absolute path to the repository>"],
      "env": {}
    }
  }
}
```
On first launch, Claude Code will ask for permission to use the project MCP server `serena`.

### Release build

```
.uild_windows.ps1 -Version 0.1.4
```
Needs Godot 4.7 with the 4.7 export templates: the console exe is taken from `-Godot <path>`, else the `GODOT` environment variable,
else `godot` on `PATH`. The script copies
`research/data` into `client/data/research`, imports and exports the preset "Windows Desktop" (`client/export_presets.cfg`, x86_64,
data and assets embedded in the exe), deletes the copy and packs `build/LastEpochBuilder-<version>-windows-x64.zip`
(exe, LICENSE, `release/README.txt`). The version is also set in `client/project.godot` (`application/config/version`).

### Web build

```
.uild_web.ps1
```
Same Godot lookup as the release build; needs the 4.7 export template `web_nothreads_release.zip` and Python 3. The script copies
`research/data` into `client/data/research`, minifies the JSON of that copy, exports the preset "Web" into `build/web` and deletes
the copy. Test locally: `python -m http.server -d build/web 8060`, open `http://localhost:8060`.

- The preset is single-threaded (`variant/thread_support=false`): the threaded build needs COOP/COEP headers that GitHub Pages
  cannot send. The renderer is GL Compatibility (WebGL 2).
- Images of `client/assets/trees` and `client/assets/items` are imported as lossy WebP (`compress/mode=1`, quality 0.85) to keep
  the download small; new images there need the same import settings.
- `user://` (settings, saved builds) lives in the browser IndexedDB. The "open the saves folder" button is hidden there.
- Clipboard: Godot copies to the system clipboard; Ctrl+V in a text field pastes from it (Godot reads the browser paste event).
- Import: the Last Epoch Tools tab is hidden (lastepochtools.com sends CORS only for its own origin); the Maxroll import works
  (Maxroll sends CORS for any origin), as does a build code pasted in "Builds…".
- Publishing: `.github/workflows/pages.yml` runs on pushes to `main` that touch the client, the data or the build script, and by
  hand (Actions → "Web build to GitHub Pages"). Repository settings → Pages → Source must be "GitHub Actions".

### Localization

Source strings are English. Russian lives in `client/i18n/ru.po` (msgid = English text): scene texts are translated by Godot,
texts built in code go through `tr()` in nodes and `LE.t()` in static engine code, data labels from `client/data/*.json` are English
and are passed through `LE.t()` when shown. New user-visible strings need a Russian entry in `ru.po`; `i18n_test` lists the missing ones.
The language is chosen in the top bar and saved in `user://settings.cfg` (`Settings` autoload); switching reloads the main scene,
the build is kept in the `Build` autoload. Details: [client/docs/UI.md](client/docs/UI.md) "Localization".

## Git

- Branch `main`, all paths in the repository are relative.
- Git LFS is enabled for binary files (`.gitattributes`: images, audio, fonts,
  models, archives, `*.pck/*.res/*.scn`). JSON and Markdown use plain git.
- We commit only what is needed for further work: code, documentation, data.
  Temporary files, extraction scripts and disassembly materials are not committed.

## How to develop

1. Sources of truth for formulas: `research/02_le_formulas.md` (confidence labels)
   and the notes `06*`/`07*`; the label **D** means confirmed by the game code.
2. Take engine data from `research/data/game/*.json`, do not edit it by hand —
   it was obtained from the client dump.
3. Next steps: unique procs (`item_procs.json`), skill mutator field mechanics
   (07c/07g/07h), saving a build (see [PLAN.md](PLAN.md), section 5).

## Maintaining the README

TECH_README.md is updated in the same commit as the change that makes it stale:
a new folder or tool, a status change in the table above, a new build/run step,
a change to the git rules. We keep the "Status", "Repository layout" and "Development tools" sections up to date.
README.md is updated when a user-facing feature changes and when a feature worth a screenshot changes
(re-run `readme_screenshots`).

## License

The project's code and documentation are distributed under the MIT license, see [LICENSE](LICENSE).

The license does not cover Last Epoch materials. These are the data extracted from the client (`research/data/game/`),
the texts and images of the in-game guide (`research/02_assets/`) and the tree graphics (`client/assets/trees/`).
The rights to them belong to Eleventh Hour Games. They are kept in the repository only for the planner to work.
The `client/addons/godot_ai` plugin is distributed under its own MIT license (`client/addons/godot_ai/LICENSE`).
