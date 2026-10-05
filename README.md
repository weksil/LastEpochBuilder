# Last Epoch Builder

## [▶ Open Last Epoch Builder in the browser](https://weksil.github.io/LastEpochBuilder/)

Runs in any desktop browser with WebGL 2; saved builds stay in that browser. A Windows version is also available:

## [⬇ Download Last Epoch Builder 0.1.2 for Windows x64](https://github.com/weksil/LastEpochBuilder/releases/download/v0.1.2/LastEpochBuilder-0.1.2-windows-x64.zip)

All versions and release notes: [Releases](https://github.com/weksil/LastEpochBuilder/releases/latest).
No installation: unzip and run `LastEpochBuilder.exe`.

A build planner for Last Epoch in the spirit of Path of Building: exact numbers with a breakdown of every value, items,
idols, blessings, skill and passive trees, player and enemy conditions. Game version: **1.5.0 (Season 5)**.
Interface in English or Russian.

## Import a build from a link

The planner imports builds from [Last Epoch Tools](https://www.lastepochtools.com/planner/) links
(`https://www.lastepochtools.com/planner/XXXXXXXX`).
This import is available in the Windows version only: the browser cannot load Last Epoch Tools pages.

How to get a link to your character:

1. Open the [Last Epoch Tools planner](https://www.lastepochtools.com/planner/) and press the **import** button in the
   left toolbar.
2. Import the character:
   - **online character**: enter your account name and character name;
   - **offline character**: upload its save file from
     `C:\Users\<user>\AppData\LocalLow\Eleventh Hour Games\Last Epoch\Saves`
     (with Steam cloud saves: `<Steam>\userdata\<Steam user id>\899770\ac\WinAppDataLocalLow\Eleventh Hour Games\Last Epoch\Saves`).
3. Press **Save/Share** in the left menu and copy the link.

Build guides (Maxroll and others) usually link to a Last Epoch Tools planner too — copy that link.

Then in Last Epoch Builder press **Import…** in the top bar, paste the link and press **Load**. Class, mastery, level,
passives, skills with their trees, items, idols with the altar and blessings are loaded (the Weaver tree is not imported yet).

To share a build made in Last Epoch Builder, use **Builds… → Copy the code of the current build**; the other person pastes it in the same dialog and presses **Load from code**.

## What it shows

### Minion damage

![Minion damage components in the Calculations tab](docs/screenshots/minions.png)

Open **Calculations** and pick a skill that summons or uses minions (here the Falconer's Aerial Assault). Every minion attack
is its own damage component with damage per use, crit and damage against the enemy; the skill's DPS includes them.
Press **+** next to a number to see where it comes from: the minion's base damage, the player stats transferred to the
minion ("Player → minion"), the minion's innate modifiers and the skill tree nodes.

### Exact skill numbers

![Calculations tab with expanded breakdowns of Harvest](docs/screenshots/skill_calcs.png)

**Calculations** shows the selected skill: DPS against the enemy, average hit, uses per second, crit chance, then
sections for damage per use, conversions and tags, crit, speed and mana, ailments, skill parameters from the tree,
damage against the enemy (hit without and with a crit, as on the training dummy) and sustain. Each **+** expands the full
breakdown: base damage, every "added", "increased" and "more" modifier with its source (passive, item, idol, tree node,
buff), the enemy's resistances and penetration. What the planner does not model is listed in **Not counted** at the bottom.
The target and its state are set in **Conditions**.

### Stat diff while editing an item

![Item editor: the unsaved changes diff follows the affix roll slider](docs/screenshots/item_diff.gif)

Open **Items**, pick a slot and change the item: base, implicit rolls, affixes and their tier/roll sliders. Edits stay a
draft until **Save**; under the item the editor shows what saving would change — DPS of the selected skill against the
enemy and every character stat — live while a slider moves. **Discard changes** drops the edits. Hovering an item in a slot
dropdown shows the same diff for equipping it. Idols and blessings have the same diff.

## License

The code and documentation are distributed under the [MIT license](LICENSE).

Last Epoch is a trademark of Eleventh Hour Games. This project is not affiliated with or endorsed by Eleventh Hour Games.
The game data, texts and art extracted from the Last Epoch client (`research/data/game/`, `research/02_assets/`,
`client/assets/`) belong to Eleventh Hour Games and are included only so that the planner works; the MIT license does not
cover them. The `client/addons/godot_ai` plugin has its own MIT license.

Developer documentation (formula sources, architecture, tests, release build): [TECH_README.md](TECH_README.md).
