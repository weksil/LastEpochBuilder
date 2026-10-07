# Last Epoch Builder 0.2.0

An update for **Last Epoch 1.5.0 (Season 5)**. Runs in the browser: https://weksil.github.io/LastEpochBuilder/

## New

- **Defense tab**: effective health against the attacks of monolith end bosses and pinnacle bosses and against the
  average monster of a level 100 monolith, scaled by area level and corruption; dodge / block conversions, conditional
  defenses, damage taken as another type, delayed damage, recovery between hits. Enemy corruption is set on the
  Conditions tab.
- **Projectiles**: projectile count and shotgun hits count in skill DPS (also for minions that fire projectiles); the
  calculation shows the projectiles used for DPS, the shotgun and the maximum per use.
- **Skill bar DPS**: the stats panel shows the total DPS of the skill bar; skills cast by item affixes count in it.
- **Rogue shadows and Void Knight echoes** repeat skill uses; health and ward on shadow creation; nodes of another bar
  skill aimed at this skill count for it.
- **Automatic enemy ailments, shreds and curses** from the skill's own hits, minions, zones, other bar skills and skills
  used on cooldown, with average stacks and uptime; stacks spent by consuming hits; Shadow Daggers strikes.
- **Automatic buffs on you** (Dusk / Crimson Shroud, Silver Shroud, Smoke Blades, spell / element / crit / companion
  buffs, timed buffs) with their stacks; the Conditions tab takes the rates of events the calculation cannot derive
  (kills, stuns, arrow pickups, drops below high health).
- **Minions**: active minions per summoned type, summon limits with the increases of passives, skill nodes, items and
  uniques; skeleton and skeletal mage damage split by type; minion ability priorities with cooldowns and charges.
- **Weaver idols**: Weaver affixes only on Weaver idols, the altar's Weaver idol limit under the grid, Weaver affixes in
  refracted slots boosted like prefixes / suffixes.
- **Item pictures** from the game on the Items tab (slots, unequipped items, the choice list, the editor) and on the
  Idols tab (each idol covers its cells; the altar picture next to the altar list).
- **Undo / redo** of build edits (Ctrl+Z, Ctrl+Shift+Z / Ctrl+Y); Copy / Paste / Load for the build code; a Feedback
  button.
- Faster calculation (calculation cache, stat index, breakdowns built on demand).

## Fixes

- Corrupted affixes of idols in refracted altar slots are no longer boosted (the game does not boost them).
- The import warning names only the Weaver tree: Weaver idols in the grid were always imported.
- Fixes from a review of the calculation.

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- Import from an offline save file is not implemented; the Weaver tree and set ids are not imported.
- Some base buffs defined only in prefab data (Flame Ward, Focus, Rebuke, …) are not modelled.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
