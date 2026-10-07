# Backlog

Tasks deferred for later. We take them on by agreement.

## Client — visuals

- [x] **Tree visuals from the game client** (node icons and frames, backgrounds, ornaments, connections) — `tools/extract/extract_tree_art.py`,
  `client/assets/trees/`.
- [x] **Item pictures** (equipment, idol and altar subtypes, unique items) — `tools/extract/extract_item_pictures.py`,
  `client/assets/equipment/`, `client/assets/idols/`.
- [ ] **The remaining icons from the game client:** skill icons in slots and lists, blessings, classes,
  icons of tooltip rows (`tree_node_stats.json` → `tooltipStats[].icon`). The same method: UnityPy, `m_SpriteSoftRef`.
- [ ] Backgrounds, logos, class portraits — from the official site / lastepochtools, if the client does not have them.

## Calculation

- [ ] **Verify the conversion rules in the game.** `skill_conversions.json` was annotated from the text descriptions in the mutator code (D?).
  Check several skills (Fireball 50%/100% to lightning, Rive to void, Maelstrom to physical) against the in-game tooltip.
- [ ] Idol altars (`idols.json` `containerGrids.data`, refracted slots +100), unopened slot rewards 1..8,
  enchants and corrupted idol affixes (`IdolEnchantment`, `Corrupted`).
