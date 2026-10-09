# 10 - Audit of trigger and granted-skill models against the game code (2026-10-09)

Rule: only game data (decompiled code, ISIL, extracted assets) counts as evidence. Per-entry verdicts with quotes are in
`research/data/audit/` (`mutator_trigger_verdicts.json` 386 entries of client/data/field_models.json, `item_trigger_verdicts.json`
89 entries of client/data/unique_effect_models.json, `granted_abilities.json` inventories and facts). Navigation: `09_dump_navigation.md`.

## Flame Walker (CharacterMutator.fireAuraChanceWhileMovingOrMeleeDoubleUnder3, offset 0xEA8) - FACT
- Written only by passive node 38 (`MageTree__updateMutator.c`: points x 0.1). Read only in `CharacterMutator.OnUpdateTick`.
- A timer (0xEAC) fires once per second (`const ...Cooldown = 1`); each tick makes ONE `RngElement.Roll(field x mult)`; on success Fire Aura
  (ability 162) is cast once if the player is moving OR the ability in use is mid-animation with the Melee tag (AT bit 9).
  Attack count, hits and attack speed do not enter. Multiplier 2 when `FireAuraMutator.getNumberOfActiveAuras` < 3 (strict), else 1.
- `Roll`: false for p <= 0, true for p >= 1, one cast per roll. Fire Aura stack lasts 4 s (`DestroyAfterDuration`), a re-cast adds a
  separate instance; auras hit every enemy in radius on a shared 0.5 s timer, N auras = N hits per enemy per tick.
- Other Fire Aura sources have their own `ProcTimeTracker(3, 1.0)` (3 per 1 s) each: on kill, when hit, on crit, on first melee hit
  (`fireAuraChanceOnFirstMeleeHit`: once per melee use, on the first Melee hit). No limiter shared between sources.
- Planner mismatch (as of commit 50f441f): modelled as `use` x Melee per attack -> must be a 1/s tick (moving or melee ability in use).

## Systemic facts
- `ProcTimeTracker(limit, interval)`: at most `limit` procs per sliding `interval`; the roll happens before `TryProc`, so icd = interval / limit is right.
- `<x>Cooldown` / `<x>CooldownIndex` float pairs: the cooldown starts after a SUCCESS, so the real rate is 1 / (icd + 1 / (p x r)), the planner uses min(p x r, 1 / icd).
- Chance >= 100% is one guaranteed cast (the planner's cap is right) EXCEPT fields using `StochasticRound` (floor + roll on the fraction): several casts.
- Casts have no ability level (`constructAbilityObject` takes none): damage = the ability's base, `levelScaling` x character level, attribute scaling,
  the ability's own mutator and ability-property fields. Passive / unique / affix / idol casts use the PLAYER's stats (global store), not the owner skill's tree.
  (planner: components are computed in the owner skill's store -> likely overcount when the owner's tree has tag-matching stats.)
- Basic attack (ba1): Physical 2.0, isHit, ADE 1.0, AttackSpeed useDuration 0.75, tags Physical|Melee (bow variant Physical|Bow, swapped by `usingBow`);
  `basicAttackReplacer` is a one-time auto-equip into bar slot 4, not a combat mechanic. It triggers OnFirstMeleeHit casts like any melee ability.

## Field models (field_models.json): 48 wrong, 16 UNKNOWN, 44 verified in code, 278 consistent with semantics JSON
High impact: Flame Walker (above); AuraOfDecay.castsPeriodicNova period is max(1, 15 / (1 + ...)) not 1 s; FlameReave fireball/lightning on kill OR any hit
on a rare/boss; Harvest zombie on kill OR rare/boss hit (shared PTT 5 per 3 s). Missing/wrong limits: see `mutator_trigger_verdicts.json` (≈25 entries,
e.g. EnchantWeapon iceShard icd 0.5, Swipe claw totem icd 4 shared, DarkQuiver icd 3 + Bow, Transplant bone armor 10 s, CharacterMutator maelstrom 3 s,
retribution 0.2 s, revenant 10 s, healing totem 5 s, vine on kill 2 s, divine bolt PTT 2 per 1 s, arcaneLightning event hit + 5 s). 10 entries count every hit
where the code fires once per use / first hit (event granularity).

## Item / affix / idol / set triggers (unique_effect_models.json): 60 correct, 23 wrong, 6 UNKNOWN
Wrong: p42 Fire Trail (no roll, 100%, crit + 5 s), p81 Abyssal Echoes (any melee hit/kill, shared 3 s), p155 Lightning Blast (first melee hit per use),
Gaspar 517:1-3 (one shared cooldown 3 s x (1 - 517:4)), Aurelis 533:2 (first hit per use, boss/rare), Kuzon 489:2 (StochasticRound, Melee+Fire, PTT 4/s),
Vipertail 61:0, Eye of Storms 318:0, and ~12 entries whose tag filters exist only in `note` (Melee / Bow / Physical / Cold ...), see the JSON.
Unmodelled casts: idol/gear pp 1, 5, 9, 10, 29, 52, 158, 338, 539; set bonuses pp 68 (Halvar 3), 634 (Apiarist 3), 71:13 (Caretaker 2), 517:4; unique flags
p329, 415, 479, 594, 591, 616, 578; hard-coded CharacterMutator casts (31 of 90 ability ids) and 79 tree cast-like fields kept only as flags.

## Granted abilities
`category: nodeGranted` (189) = tooltip hint only (`SkillTreeNode.abilityGrantedByNode` is read only by tooltip/UI code); real grants are mutator writes,
CharacterMutator code and item/affix properties. 58 of the 189 are not referenced by the planner. UNKNOWN: form bars composition, prefab castChance values.

## Status of the fixes (2026-10-09)
Applied: Flame Walker as a 1 s tick (moving or Melee ability in use); `cooldown` / `stochastic` / `skill_any` keys in the trigger rate; character casts in the
global store; 49 entries of field_models.json and 27 of unique_effect_models.json corrected (limits, event, tags, cooldown kind). Not expressible yet
(engine support needed) and unmodelled casts: `research/audit_followups_field.md`, `research/audit_followups_unique.md`.
