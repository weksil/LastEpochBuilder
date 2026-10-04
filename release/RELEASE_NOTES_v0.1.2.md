# Last Epoch Builder 0.1.2

An update for **Last Epoch 1.5.0 (Season 5)**. Windows x64, no installation: unzip and run `LastEpochBuilder.exe`.

## New

- **Items tab reworked** (in the style of Path of Building): each slot is a dropdown of the character's items that fit it;
  unequipped items are listed below the slots, "+" adds one. Hovering an item shows what equipping it changes (DPS vs enemy
  and every numeric character stat). Unequipped items are saved in build files and build codes.
- **Item editor**: custom item names; one searchable item list sorted by required level; one tier + roll slider per affix
  with tier ticks; set bonuses of set items (active ones highlighted); searchable unique, item and affix lists with rich tooltips.
- **Unsaved changes with a live stat diff**: item edits stay a draft until "Save"; under the item the editor shows what saving
  would change (DPS vs enemy of the selected skill and character stats), "Discard changes" drops the edits.
- **More affixes**: uniques take legendary affixes (legendary potential, Weaver's Will); regular equipment has a sealed
  affix row; the "Corrupted" box adds a corrupted affix row with the corruption pool (items and idols); affix lists also
  offer set (Reforged), experimental, personal, weaver and enchantment affixes.
- **Idols**: the editor appears after a cell is picked and offers only idol bases and unique idols, named with their grid
  size (e.g. `[1x3]`); idols get the same roll sliders and stat diff as items.
- **Blessings**: effect tooltips in the dropdowns (including what a drop rate blessing applies to), the stat each blessing gives
  next to its slider, and a live stat diff of all chosen blessings.
- **Last Epoch Tools import**: retries up to 3 times on a request timeout and shows the request status.

## Fixes

- Imported blessings were not selected (the planner sends them as a timeline-keyed dictionary).
- Imported affixes landed in no editor row, so imported items showed empty prefix/suffix rows; sealed and corrupted affixes are
  now shown too.
- A new unique no longer inherits the affixes of the previous item.
- Node effect expressions that call game code the client lacks no longer print an error on every recalculation.
- Startup warnings and a parse error in the set bonus block.

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- Import from an offline save file is not implemented; the Weaver tree and set ids are not imported.
- Some base buffs defined only in prefab data (Flame Ward, Focus, Rebuke, …) are not modelled.

## Download

`LastEpochBuilder-0.1.2-windows-x64.zip`: `LastEpochBuilder.exe`, `LICENSE`, `README.txt`.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
