# Last Epoch Builder 0.1.4

An update for **Last Epoch 1.5.0 (Season 5)**. Windows x64, no installation: unzip and run `LastEpochBuilder.exe`.
The same version runs in the browser: https://weksil.github.io/LastEpochBuilder/

## New

- **Browser version** on GitHub Pages. The Last Epoch Tools import and the "open the saves folder" button are not
  available there; use the Maxroll account import.
- **Import by account name through Maxroll**: enter the account name, pick a character from the list and the build is
  loaded: equipment, idols, blessings, passives and skills. The last account name is remembered.
- **Corrupted attributes**: an attribute converted by a corrupted affix (e.g. "Vitality converted to Rampancy") gives its
  corrupted per-point stats instead of the regular ones and is shown under the new name. Exulis "per 10 Rampancy/
  Brutality/..." effects read the converted attribute value; Rampancy's "more damage taken without Frenzy" is modelled.

## Fixes

- Base mastery bonuses (Falconer +12 Dexterity etc.) were never applied.
- The attribute breakdown header showed the value as a percent ("11100%"); Endurance was multiplied by 100 twice.

## Known limitations

- Damage is calculated against a single target (no spreading, chains or area damage to other enemies).
- Import from an offline save file is not implemented; the Weaver tree and set ids are not imported.
- Some base buffs defined only in prefab data (Flame Ward, Focus, Rebuke, …) are not modelled.

## Download

`LastEpochBuilder-0.1.4-windows-x64.zip`: `LastEpochBuilder.exe`, `LICENSE`, `README.txt`.

The code is MIT licensed. Game data and art extracted from Last Epoch belong to Eleventh Hour Games and are included only so that the
planner works.
