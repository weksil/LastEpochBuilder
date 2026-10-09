# 08 — Build damage optimization: methodology

How a build is pushed to maximum damage with the planner engine, worked out on the Lich build
`lastepochtools.com/planner/A6PRJ4De` (2026-10-07…09): 95 k DPS → 149.5 M (sustainable variant), 175.8 M (formula
maximum), 69.7 M (all resistances capped, rare gear). The tooling is local (`tools/optimizer/`, not published); this note is
the method, the tool reference and the lessons.

The engine is the judge: the objective is the "DPS vs enemy" row of the main skill slot (`SkillCalc`), against the
target of the Conditions tab (training dummy by default). Whatever the engine does not model does not exist for the
optimizer, so the method spends as much effort on checking the engine as on searching.

## 1. Principles

1. **Mechanics first, search second.** Blind enumeration of skills × passives × gear × idols is slow (≈100 evaluations/s,
   §8) and gets stuck in the archetype it starts from. First find the mechanic that scales best, then optimize around it.
2. **Look for multiplicative structure, not for big numbers.** Inside one bucket (added, increased, a single more, crit,
   speed) LE adds values, so each stat alone grows damage linearly. Super-linear growth comes only from:
   - one resource feeding several independent multipliers — damage grows like resourceᵏ, k = the number of factors it feeds;
   - counts multiplied by counts — projectiles × shadows / copies × hits × ailments per hit;
   - trigger chains — every level multiplies the rate of the next one;
   - trigger chances above 100% that scale with a stat (several casts per hit).
   True exponential growth does not exist in the LE formula: «more per stack» is linear in stacks (`1 + N·m`, research/06a),
   and the engine computes a steady state without feedback loops. The realistic best is a polynomial.
3. **Every ×2 jump is a suspect.** A large gain from one change is either a real scaling mechanic or an engine model bug.
   Read the breakdown before optimizing on it (§4). In this case seven bugs were found that way.
4. **Respect the user's limits as hard constraints**, encoded in the validator (§7), not as afterthoughts.

## 2. Pipeline overview

| Phase | What | Output |
|---|---|---|
| 0 | Import, set the level and the limits, baseline breakdown | baseline DPS, first audit |
| 1 | Mechanic discovery: probes, community builds, engine coverage | the archetype to build around |
| 2 | Engine audit and fixes (with tests) | an engine that values the archetype correctly |
| 3 | Seed: a strong build of the archetype made legal for the limits | starting point |
| 4 | Optimization rounds: trees → passives → supports → gear (two phases) → idols | optimized build |
| 5 | Variants (defense, sustain), validation, saving | builds in `user://builds` |

## 3. Phase 1 — finding the mechanic

### 3.1 Elasticity probe (`probe.py`)
Adds growing amounts of one stat (class base mods injected for one evaluation) and prints DPS at ×1, ×2, ×4, ×8 steps with
the marginal gain per step. A growing marginal gain (CONVEX) marks a stat that feeds several multipliers.
On the Harvest build everything was linear except «all attributes» (Dexterity → Harvest added damage × Intelligence →
increased damage). On the mana Flay build max mana was strongly convex: +200 mana ×1.52, +1600 mana ×8.5 (≈ quadratic).
Also useful: capped stats show as «concave» (crit chance above 100% gives nothing).

### 3.2 Community builds (subagent research + import)
A research subagent (sonnet, web only) lists the current season's top builds of the class with planner links and the
mechanic each one scales with. The planner JSON of a lastepochtools link is fetched with the Godot User-Agent (Cloudflare
answers 403 to curl's default one):
```
UA="GodotEngine/4.7.stable.official (Windows)"
curl -A "$UA" https://www.lastepochtools.com/planner/<code>          # page → 32-hex data hash
curl -A "$UA" -H "Referer: …/planner/<code>" https://www.lastepochtools.com/api/internal/planner_data/<hash>
```
Every imported build is computed by the engine and compared with the author's claims. A strong claimed build that the
engine values low points to an unmodelled mechanic (here: Allie's mana Flay Lich, 34 k in the engine before the fixes).

### 3.3 Engine coverage of the mechanic
Read the notes of the main slot's result: «… has no damage — not counted», «counted when: …», «not counted». Each of them on
a component of the candidate mechanic is a gap to close before optimizing (§4).

### 3.4 What was found for Acolyte / Lich
- Flay «Chaos Rip»: chance per 1 max mana to cast a Chaos Bolt on hit (>100% = several bolts); «Deadly Plot»: more damage per
  100 max mana for Flay and the skills its tree triggers → DPS ∝ mana².
- Chaos Bolts tree: Harvest (per Dexterity, ≤ 1/s) and Rip Blood (per Intelligence / 2, ≤ 2/s) triggers; Flay «Marrow Gnawer»
  triggers Marrow Shards on crit. Specialized skills of other masteries are allowed once their tree has enough points
  (Chaos Bolts needs 5 Warlock points); mastery start skills (Chthonic Fissure, Summon Wraith) are not.
- Executioner's Tithe: half of the weapons' added melee damage as Chaos Bolts spell damage; direct Harvest → Great Harvest
  (5 s cooldown) restoring 20–30% max mana on boss hits (the mana sustain of the build).

## 4. Phase 2 — engine audit

Procedure: build a breakdown of the main slot (`SkillCalc.compute(Build, slot, true)`), print every section, and check
the largest contributors against the item / node text. Fix the model or the engine, add the translation if a string is
new, run the full test suite, re-run the audit.

Bug patterns found (all fixed, commit `7a2245b`):

| Pattern | Example | Symptom |
|---|---|---|
| Wrong scale of a «per» source | Hollow Lich: factor 100 instead of 10 (leech tooltip % = stat × 10) | +1137% increased damage |
| Effect value used as a multiplier instead of a cap | Chronostasis: up to v ward consumed ×1/10 | +100 000 melee damage |
| Trigger on the wrong event | Triboelectra / Lightning in a Bottle fired on every skill use instead of Evade / dodge | ×2–3.5 from a boot/belt |
| Alternate sub-ability counted as additional | Flay 2 Damage (`CastAfterDuration.alternateAbility`) | Flay ×2 |
| On-kill sub counted per use | Flay Blood Explosion through its `ChanceToCastOnKill` delayer | extra component vs a dummy |
| Cooldown of an effect ignored | Great Harvest (+150% more, 5 s cooldown) at full attack speed | ×18 Harvest |
| Missing state | «while transformed» stats need the Transform tag on the skill | helmet affix ignored |
| Missing mechanic | triggered bar skills not computed through their own tree; stat-scaled trigger chances | the archetype valued ×13 too low |

Rules kept from the audit: a triggered use of a bar skill counts only its hits (curse damage, maintained DoTs and minions
stay in the skill's own slot); item triggers on use / cast do not fire from triggered uses; a trigger marked
`single_projectile` is one projectile (Chaos Rip: one bolt).

## 5. Phase 3 — seed

Take the strongest engine-valued community build of the archetype and make it legal for the limits (`run3.py`, `legalize`):
remove sealed affixes, tiers ≤ 6 with at most one T6 per item, uniques reduced to the allowed legendary affixes, the level and
passive point cap of the request, the user's blessings if they are not part of the request, `player.transformed` for forms.
Starting from a seed instead of the user's build reached 2.8 M before any gear search (the user's build topped at 0.25 M
after its own trees and passives).

## 6. Phase 4 — optimization rounds

Two rounds of the sequence below were enough; the second one mostly re-balances gear against the new passives.

### 6.1 Skill trees and passives (`trees.py`)
- Validity mirrors `Build`: requirements («any of»), connectivity to a root, `masteryRequirement` thresholds (points in the
  base tree and the node's mastery below the threshold).
- Extra rules the engine does not check (kept in the optimizer): ≥ 20 points in the base tree (every community build has
  them), non-chosen masteries only up to the halfway threshold (`masteryRequirement` ≤ 20), minimum points in a mastery whose
  skill is on the bar, required nodes (Executioner for a dagger / axe off-hand).
- Search: greedy fill by gain per point where each candidate is «unlock path + 1 point» or «unlock path + max points» (crosses
  zero-value connector nodes and threshold bonuses); then swaps — score every single removal and every single addition,
  then only the top 8 × top 8 pairs exactly (≈120 evaluations per step instead of ≈3000); then «kicks» — strip a whole node and
  refill. An allocation that breaks only the extra rules is repaired (`enforce_mins`), never reset.

### 6.2 Support skills (`skills.py`)
For each free bar slot try every allowed skill with a quickly filled tree; a skill of another mastery is accepted only after
the passives are re-optimized with its mastery points, and only for the two best such candidates clearly above (5%) the best
own-mastery skill.

### 6.3 Gear in two phases (`unique_screen.py`, `gear2.py`)
1. **Unique / set screening.** Every unique of every slot on the reference build without legendary affixes: DPS vs the empty
   slot, vs the current item, and the «+400 mana» ratio with and without the item. A changed ratio marks an item that
   changes the scaling itself (Devoured Knowledge). Items with a ×2+ jump are audited (§4) before anything else.
2. **Mod pool and crafting.** For each base type of the slot: rank every affix alone on a blank item (the gain is relative
   to the build, so it already knows what the build lacks); keep the top 10 prefixes / suffixes and the top 6 corrupted;
   craft by coordinate descent over the positions (2 prefixes, 2 suffixes, 1 corrupted, 2 passes), then choose the one T6;
   re-pick the subtype with the final affixes. The best uniques of the screen get their legendary affixes from the same pool.
   The slot keeps the best of crafted rares and filled uniques.
- Weapons: compare two-handed, one-handed + shield / catalyst and dual wield (the dual-wield variant first re-optimizes the
  passives with the required node).

### 6.4 Idols (`idols.py`)
Altars: the 4 with the most open cells plus the current one. Per altar: a template per idol base (best prefix / suffix /
corrupted alone), greedy placement by gain per cell, altar affixes as a crafted item, then affix descent of every placed
idol in context.

## 7. Phase 5 — objectives, validation, delivery

- **Constraints as penalties.** Resistance cap: the worker returns `dps × exp(−16 × Σ max(0, 75% − resistance))` (10% missing
  ≈ ×0.2), so every optimizer first closes the cap and then maximizes damage; over-cap is worth nothing unless the build
  scales with it (Torment of the Red Tundra: damage per uncapped cold resistance). Rare preference: the slot takes the best
  crafted rare unless the unique is more than 15% stronger.
- **Sustain check by hand.** The engine does not charge trigger mana costs. For the mana Flay build: ≈2 mana per bolt × bolts/s
  against regeneration plus Great Harvest refunds; the build that loses the sustain item is kept only as a «formula
  maximum» variant.
- **Validator** (`validate.py`): no sealed affix, tiers ≤ 6 and ≤ 1 T6 per item, ≤ 1 corrupted affix, legendary affixes ≤ the
  allowed LP, droppable bases, passive validity with the extra rules, mastery points for the bar skills, the required form
  on the bar.
- **Delivery:** `final.tscn` prints the build, the DPS of every slot and the character stats, and saves it with
  `BuildCodec.save_build` to `user://builds` (`%APPDATA%/Godot/app_userdata/LastEpochBuilder/builds/`), where the planner's
  «Builds…» dialog lists it.

## 8. Tooling (`tools/optimizer/`, local)

- `godot/worker.gd` + `worker.tscn`: a persistent headless worker. Copy `godot/*` to `client/tests/_opt/` before a run and
  delete the folder afterwards (it must not be committed). Jobs are JSON files `job_<id>.json` → `res_<id>.json` in a job
  folder; a job carries the base build once (`BuildCodec.to_dict` snapshot) and then only patches
  (`passives`, `skills`, `items`, `probe`, …).
- `pool.py`: starts N workers, sends small chunks to whichever worker is idle (efficiency cores are ~3× slower, equal chunks
  wait for the slowest), `evaluate(base, patches)`. `import_letools(res_path)` converts a planner JSON.
- Throughput on the i7-14700HX laptop: one evaluation ≈ 30–40 ms; total ≈ 100–110 evaluations/s, saturated at ~8 workers
  (more workers slow each other down). Two independent runs of 5 workers each use the machine as well as one of 10.
- Scripts: `common.py` (logging, scorers, class rules: `SKILL_MASTERY`, `DUAL_WIELD_NODE`, `BASE_TREE_MIN`,
  `OTHER_MASTERY_MAX` — Acolyte values, change them for another class), `trees.py`, `skills.py` (`LICH_SKILLS`), `gear.py`
  (bases, affix pools, `MAX_TIER`, `NORMAL_TIER`, `LP_AFFIXES`), `gear2.py`, `idols.py`, `probe.py`, `unique_screen.py`,
  `run3.py` (seed + rounds), `run4.py` (two-phase gear rounds), `run6.py` (resistance-capped rare variant), `fixpass.py`
  (re-optimize passives and trees), `validate.py`. Usage: `python run4.py <build json> <tag> <workers> <rounds>`; logs go to
  `run_<tag>.log`. `builds/` holds the snapshots of this case.
- Headless Godot gotcha: a new `class_name` is unknown to `--headless` runs until the project is imported; use `preload`
  or plain scripts in temporary folders.

## 9. Adapting to another build

1. Set the class constants in `common.py` / `skills.py` (bar skill list, mastery skills and their point requirements,
   required nodes such as dual wield), the limits in `gear.py`, and the main skill slot (`pool.main`).
2. Run the baseline and the probe; read the breakdown and the notes of the main slot.
3. Survey the season's builds of the class, import them, compare engine values with the claims; pick the archetype.
4. Audit and fix the engine for that archetype first (tests, translations, ENGINE.md), only then search.
5. Seed → rounds (§6) → variants → validator → save.

## 10. Known engine limitations relevant to optimization

- Mana (and other resource) costs of triggered casts are not charged; sustain must be checked by hand.
- Ailments applied by triggered uses are part of their DPS but do not feed the automatic enemy ailments (stack-count and
  «per ailment» effects of other components see only direct sources).
- Not enforced by `Build`: 20 points in the base tree before mastery trees; the halfway limit of non-chosen masteries.
- The single-target model (memory `decision-single-target`): kills, pack size and on-kill triggers do not add damage against
  the dummy; «boss or rare» conditions are off for the dummy.
