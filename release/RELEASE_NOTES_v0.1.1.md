# Last Epoch Builder 0.1.1

A maintenance release for **Last Epoch 1.5.0 (Season 5)**. Windows x64, no installation: unzip and run `LastEpochBuilder.exe`.

## New

- **Builds dialog** ("Builds…" in the top bar): save the current build under a name, load or delete saved builds, open the saves folder.
- **Build code** (as in Path of Building): copy the build as a short text code and load a build from a code or the clipboard.
- **Tree node tooltips** split into parts: description, per-point stats with the total for the allocated points, fixed stats,
  the bonus at a point threshold with its active state.

## Fixes

- **Last Epoch Tools import**: specialized skills are taken from the planner's specialized trees, not from the skill bar. Before,
  a skill specialized but not on the bar (for example Ballista) was lost, and a bar skill without a tree took its slot.
- The Falconry node that makes the falcon screech at you at low health now follows the "Low" choice of the Health condition.

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- Import from an offline save file is not implemented; the Weaver tree and set ids are not imported.
- Some base buffs defined only in prefab data (Flame Ward, Focus, Rebuke, …) are not modelled.

## Download

`LastEpochBuilder-0.1.1-windows-x64.zip`: `LastEpochBuilder.exe`, `LICENSE`, `README.txt`.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
