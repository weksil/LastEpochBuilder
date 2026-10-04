# Last Epoch Builder 0.1.0

First public build of a Path of Building style planner for **Last Epoch 1.5.0 (Season 5)**: exact numbers with a breakdown of
every value. Windows x64, no installation: unzip and run `LastEpochBuilder.exe`.

## What it does

- **Passive and skill trees** with the game's own visuals (icons, frames, backgrounds, connections), point limits and requirements;
  5 skill slots with their trees, "+N to level" from items.
- **Items, uniques and sets**: 11 slots, bases, implicits, prefixes and suffixes with tier and roll, unique items with their rolls and
  special effects, set bonuses; **idols** on the 5×5 grid with all 13 idol altars and refracted slots; **blessings**.
- **Calculations**: damage of every component of a skill (hits, sub-skills, triggers, minions), conversions, crit, speed and mana,
  ailments (Ignite, Bleed, Poison and others), DPS against the enemy, sustain, skill buffs on the character. Every number expands into
  its breakdown with the source of each modifier; what is not modelled is listed under "Not counted".
- **Conditions**: player and enemy state, enemy type, level, armor, resistances, ailment / shred / curse stacks. Only the conditions
  that something in your build uses are shown (Path of Building style).
- **Import** from a Last Epoch Tools planner link (lastepochtools.com/planner/…).
- **Interface language**: English or Russian, selector in the top bar.

Hit numbers are checked against the in-game training dummy; formulas come from the official in-game guide, the game client's code and
data (see "Where the formulas and data come from" in the README).

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- No saving / loading of builds yet; import from an offline save file is not implemented; Weaver tree and set ids are not imported.
- Some base buffs defined only in prefab data (Flame Ward, Focus, Rebuke, …) are not modelled.

## Download

`LastEpochBuilder-0.1.0-windows-x64.zip`: `LastEpochBuilder.exe`, `LICENSE`, `README.txt`.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
