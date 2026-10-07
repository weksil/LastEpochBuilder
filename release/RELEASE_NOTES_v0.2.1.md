# Last Epoch Builder 0.2.1

An update for **Last Epoch 1.5.0 (Season 5)**. Runs in the browser: https://weksil.github.io/LastEpochBuilder/

Includes everything listed in [0.2.0](RELEASE_NOTES_v0.2.0.md).

## New

- **Loot filter for the build** ("Loot filter…" in the top bar): makes a Last Epoch loot filter from the build's items and
  idols — the build's bases with the affixes you want to craft, exalted items of the build's item types with a wanted
  affix at tier 6+ (also the legendary affixes of uniques, for legendary crafting), the build's uniques with enough
  legendary potential and set items, idols with their affixes, and a rule that hides other normal, magic and rare items.
  Rules, affixes and uniques can be unchecked; the filter is downloaded as an .xml file for the game's Filters folder
  or copied as XML.
- **Trigger chains**: a trigger of another bar skill is computed through that slot with its own tree and triggers, up to
  3 levels (Flay → Chaos Bolts → Harvest); trigger chances that scale with a stat (Chaos Rip per max mana and others).
- **Transformed** flag on the Conditions tab: "while transformed" stats apply to every skill.
- Executioner's Tithe adds half of the weapons' added melee damage to Chaos Bolts; Great Harvest gets its cooldown on
  direct use only.

## Fixes

- Hollow Lich leech, Flay's alternate strike and on-kill Blood Eruption, the Chronostasis ward cap, trigger events of
  Triboelectra, Lightning in a Bottle and other Evade / movement uniques.

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- Import from an offline save file is not implemented; the Weaver tree and set ids are not imported.
- Loot filter rules keep the game's default colours, sounds and beams.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
