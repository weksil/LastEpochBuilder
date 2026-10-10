# 12 - Prefab / serialized-component extraction: scout notes (Last Epoch 1.5.0, Unity 6000.4.8f1 IL2CPP)

Scope: which audit unblockers ("needs prefab ...", research/11_calc_audit.md) can be answered from serialized prefab data, and
how. Everything below was tested read-only against `StreamingAssets/LEAssetBundles` with `tools/venv/Scripts/python` (UnityPy 1.25.4).
No data files were written. Labels: FACT = observed in this scout (command/result named), UNKNOWN = not established.

## 1. Where the prefabs live (FACT)

| Prefab kind | Bundle(s) | How to find the root GameObject |
|---|---|---|
| Ability prefabs (1044 player / minion / sub abilities in `abilities.json`) | `PermaLoad.bundle` (989) and 55 `assets_*.bundle` | `abilities.json[].abilityPrefab.{key,bundle,root}`; key = `Ability.abilityPrefabSoftRef.guid` as `"%016x%016x" % (_0,_1)`; `BundleIndex.key_to_bundle[key]` -> `(bundle, GameObject pathID, 'GameObject', name)`. All 1044 resolve (tested: 1044 ok, 0 missing). |
| Monster ability prefabs (the other 3305 `Ability` assets in PermaLoad) | same | same field on the `Ability` asset (read all PermaLoad `Ability` MonoBehaviours, not only `abilities.json`) |
| Minion / boss / monster ACTOR prefabs | `assets_<hash>.bundle`, one bundle per actor (1029 of 1035 `ActorData` resolve into 1027 bundles) | `ActorData.ActorSoftRef.guid` (PermaLoad `ActorData`) -> `BundleIndex.key_to_bundle`. Example: StormTotem -> `assets_5e22454fccdde44f.bundle`, GO pathID 1379579832290830979. |
| Player prefab (mutators, PlayerMana, UsingAbilityPlayer, CastSpeedManager) | `assets_d7321f5c187fdc63.bundle` (only bundle with `UsingAbilityPlayer`) | container name search / script index |
| Zone / spawner / scene copies of monsters | `scene_*.bundle` (1204 bundles carry a `UnitHealth`) | not the source of truth for per-actor data; use the ActorData soft reference instead |

Child objects: components sit on the root and on child GameObjects; walk `Transform.m_Children` (helper `walk()` in
`tools/extract/extract_minion_stats.py`, yields `(goPath, className, obj)`). Prefab variants are flattened in bundles; nested
prefabs are reached through soft refs (`GameObject` guids) or `AbilityRef` keys and need a second lookup.

Component census over the ability prefabs (tested, 1044 prefabs, 6.2 s): DestroyAfterDuration 1019, CastAfterDuration 141,
CreateAbilityObjectOnDeath 112, RepeatedlyDamageEnemiesWithinRadius 52, RepeatedlyApplyAilmentsInRadius 33,
DamageEnemiesWithBeam 21, CastAtRandomPointAfterDuration 11, RepeatedlyHitsTargets 6. (Whole PermaLoad: 3891 / 946 / 538 / 165 /
81 / 184 / 59 / 5 objects; all read without error in 3.7 s.)

## 2. Can UnityPy read them? (FACT: yes, no dummydll / Cpp2IL needed)

The bundles ship embedded TypeTrees. `obj.read_typetree()` returns every serialized field of every MonoBehaviour tested; zero
failures over 6000+ objects of the classes above, plus UsingMultipleAbilitiesAI, ChargeManager, AbilityRangeList, PlayerMana, mutators.
The script class name is not in the typetree; it comes from `SerializedFile.script_types` -> `monoscripts.bundle` MonoScript
(`common.load_scripts()` + `common.script_class()`). `dump/dummydll` and the Cpp2IL output are only needed for field OFFSETS and
non-serialized fields (see the caveat in section 5), not for reading values.

Caveats:
- `read_typetree()` returns fields in serialized order with defaults filled as stored; a field that is `[NonSerialized]` or private
  without `[SerializeField]` is simply absent (see ChargeManager, NetMutator.netTrap below). Absent is not "0".
- `PPtr` fields are `{m_FileID, m_PathID}`. `m_FileID 0` = same bundle; otherwise `sf.externals[m_FileID-1]` names the CAB
  (tested: Ailment refs in `assets_08628f6535ef4210` are FileID 4 -> `CAB-PermaLoad`, pathID -> `Ailment` asset name).
- `AbilityRef` is `{key:int}` (the AbilityManager key), `SoftRef` is `{guid:{_0,_1}}`.
- `references: {version, RefIds}` (managed refs) is empty on the objects seen.
- Performance: PermaLoad opens in ~3 s; an actor bundle in ~0.05 s; all 1027 actor bundles take roughly 1 min.

## 3. Working minimal reader + test (FACT, run and verified)

```python
import sys, json
sys.path.insert(0, r"D:/LastEpochBuilder/tools/extract")
from common import load_scripts, open_bundle, script_class, BundleIndex, UI_NOISE
S = load_scripts(); idx = BundleIndex()
def components(sf, go_pid):                       # components of ONE GameObject (walk() in extract_minion_stats recurses)
    go = sf.objects[go_pid].read_typetree()
    for c in go["m_Component"]:
        p = c["component"]
        if p["m_FileID"] == 0 and p["m_PathID"] in sf.objects:
            o = sf.objects[p["m_PathID"]]
            yield (script_class(sf, o, S) or o.type.name), o
_, sf = open_bundle("PermaLoad.bundle")
loc = idx.key_to_bundle["40668731ebf9a5b4c9d81d2a1bfa3910"]    # LightningStorm abilityPrefab.key -> (bundle, pathID, 'GameObject', name)
for cls, o in components(sf, loc[1]):
    if cls in ("CastAtRandomPointAfterDuration", "DestroyAfterDuration"):
        tt = o.read_typetree(); print(cls, {k: v for k, v in tt.items() if k not in UI_NOISE})
```

Test result on `LightningStorm.prefab` (GameObject pathID 6759853834484851510, PermaLoad, 14 components):
- `DestroyAfterDuration {duration: 2.0, age: 0.0, ageResets: 0, expireNextUpdate: 0}`
- `CastAtRandomPointAfterDuration {ability: PPtr(0,0), abilityRef: {key: 348150271}, duration: 0.35 (0.3499999940395355), initialDelay: 0.0, limitCasts: 0, remainingCasts: 0, castsAtStart: 1, additionalCastsAtStart: 0, castAllAtStart: 0, radius: 2.5, raycastHeight: 10.0, raycastDistance: 20.0, ...}`
  matches the audit's duration 0.35 / castsAtStart 1 / DestroyAfterDuration 2.
- Other components seen: AbilityMover, HitDetector, SelfDestroyer, StartsAtTarget, AbilityMutatorManager, `StormLightningMutator`, Stats.

## 4. Resolving references to abilities (FACT)

1. `AbilityRef.key` (CastAtRandomPointAfterDuration.abilityRef, CastAfterDuration.abilityRef, CreateAbilityObjectOnDeath.abilityToInstantiateRef,
   CastSpeedManager.overrides[].abilityRef, AbilityList.abilityRefs[], RepeatedlyApplyAilmentsInRadius.minionAbilityToApplyTo)
   -> `abilities.json[].key` (same int; 348150271 = StormLightning, `playerAbilityID` ""; 1342156288 = LightningStorm `ls25`).
   Authoritative table: PermaLoad `AbilityManager.keyedArray[{ability: PPtr, key}]` (4345 keys) -> `Ability` asset `m_Name`.
2. Direct `Ability` PPtrs (`ability`, `abilityToInstantiate`, `Ability.comboAbilities[]`, `AbilityList.abilities[]`): FileID 0 in
   PermaLoad prefabs -> `abilities.json[].pathID`; otherwise via `externals`.
3. Coverage: of ~250 CreateAbilityObjectOnDeath / CastAfterDuration refs in the 1044 player-ability prefabs, 54 distinct keys are
   missing in `abilities.json` (it holds the 1044 player-reachable abilities); all 54 are in `keyedArray` as PermaLoad `Ability` assets
   (verified) (e.g. ExplosiveArrowExplosion, FirePatch,
   SmallDelayedFireCircle, boss sub-abilities). So rows must be keyed from `keyedArray`/all PermaLoad `Ability` assets, and
   `playerAbilityID` is filled from `abilities.json` when present, else null (monster/sub abilities have no playerAbilityID).
4. Row key: `(owner ability name = abilities.json name / Ability.m_Name, abilityKey, goPath, class)`; `playerAbilityID` joined via
   `abilities.json` by `key`.
5. Ailment PPtrs resolve to PermaLoad `Ailment` asset names (Haste, Frenzy, Frailty, Ignite, ...) as shown in section 2.
6. Fallback "owner" mapping for sub-abilities: the ability whose prefab contains the ref (`parents` in `abilities.json`).

## 5. Audit unblockers

### Extractable with this method (prefab / actor-prefab / Ability-asset serialized data)

| Audit # | Needed | Source (class.field) |
|---|---|---|
| 85 (hit counts of sub-abilities) | CastAtRandomPointAfterDuration (duration, initialDelay, castsAtStart, additionalCastsAtStart, limitCasts, castAllAtStart, radius), CastAfterDuration (interval, castsPerInterval, limitCasts, castOnStartAsWell, castChance, randomExtraCasts, minInterval, ...), CreateAbilityObjectOnDeath (chanceToCast, additionalCasts, randomExtraCasts, delay, abilityToInstantiateRef), DestroyAfterDuration.duration, ExtraProjectiles | ability prefabs |
| 102 (per-tick ailment zones) | RepeatedlyApplyAilmentsInRadius {radius, minRadius, applicationInterval, ailments[{ailment, chance, rolledSeparately, damageModifier, increasedDuration, increasedEffect}], delay, limitDuration, maxDuration, applyOnStart, targetType, increasedAilmentApplicationFrequencyPerSecond, moreDamage}; RepeatedlyDamageEnemiesWithinRadius (damage interval/radius), DamageEnemiesWithBeam.damageInterval / damageAtStart / baseDamageStats, RepeatedlyHitsTargets.interval / maxTargets (DrainLife interval 0.1833, maxTargets 3; Disintegrate damageInterval 0.25 confirm the audit text) | ability prefabs |
| 102 (Black Hole, Devouring Orb, Focus, Hail of Arrows, Infernal Shade) | These have NO RepeatedlyApplyAilmentsInRadius (tested). The zone comes from RepeatedlyDamageEnemiesWithinRadius / RepeatedlyPullEnemiesWithinRadius / RepeatedlyGiveParentResources (Focus) / `DestroyAfterDuration`; the ailment-per-second fields are mutator fields (code). The extractor can report the presence and intervals of those components; it cannot supply an ailment tick that is not serialized. |
| 81, 86/#146 (boss and minion use speed) | `UsingAbility.baseUseSpeedMultiplier` (serialized on `UsingMultipleAbilitiesAI` / `UsingAbilityAI` of actor prefabs; sampled 20 actors, all 1.0; player prefab `UsingAbilityPlayer` 1.1), `CastSpeedManager.overrides[{abilityRef,useDelay,useDuration}]` (StormTotem: LightningStorm useDuration 0.95), `AbilityList.abilityRefs[]`; plus Ability asset fields already in PermaLoad: speedScaler, speedMultiplier, speedScalerEffectiveness, maximumUseSpeed (Ability+0x64), minimumUseDuration for MONSTER abilities (not in `boss_attacks.json`) | actor prefabs + all PermaLoad `Ability` assets |
| 93 (AbilityRangeList) | `ranges[{minRange, engageRange, maxRange, persuitRange}]`, comboReplacementRanges, healthThresholds, pursuitRangeCap (StormTotem: engage 14 / max 15 / pursuit 16) | actor prefabs |
| 63 (Rive consume rate) | `Ability.comboAbility / comboAbilities[] / comboTimeLimit / comboBehaviour / bypassCooldownOnComboReset / isPartOfComboAbility` (Rive1: comboAbility 1, comboTimeLimit 3.0, 2 combo abilities) | `Ability` assets, not prefabs (same UnityPy read; `abilities.json` does not carry these columns) |
| 31 (Lunge distance) | `Ability.stopRange` (Lunge 1.15, Rive 1.6), `stopRangeAffectedByWeaponRange`, `subtractStopRangeForManaCostPerDistance` (Lunge 0) | `Ability` assets (the 0xC8 / 0x174 offsets) |
| 18 (prefab divider) | `BaseMana.addedManaCostDivider` (+0x98) IS serialized on `PlayerMana`; value 0 (not listed among non-zero fields of either PlayerMana object in the player prefab). Minion actors: read `BaseMana`/`ManaStrike...` the same way if they carry one. | actor prefabs |
| 90 (Explosive Trap component presence), 25 (what the prefab spawns) | component class list per ability prefab / child (e.g. ShieldRush prefab holds DamageEnemyOnHit + CreateAbilityObjectOnDeath + BuffParent) | ability prefabs |
| 86 (minion mutator -> ability mapping) | `*Mutator.abilityRef` and `AbilityList.abilityRefs` of minion actor prefabs (non-zero serialized fields) | actor prefabs |

### NOT extractable by this method

| Audit # | Why |
|---|---|
| 88 `ChargeManager.increasedRecoverySpeed` (+0xD8) | NOT serialized: the ChargeManager typetree holds only abilitiesStartOffCooldown, abilitiesStartWithRandomCharges, abilitiesCanPreventChargeRegenDuringUse, preventRegenForOutOfPhaseAbilities (tested on StormTotem). The audit's "prefab-serialised field not exported" is not correct; value is set at runtime by code. |
| 25 `NetMutator.netTrap` (+0x1B0), `JudgementMutator.shieldRush` (+0x1F8), `HealingHandsMutator.shieldRush` (+0x1C0) | Private Ability fields absent from the mutator typetrees in the player prefab (tested keys of NetMutator / JudgementMutator / HealingHandsMutator). They are assigned in code (UNKNOWN where). |
| 101, 18 (mutator overrides of getManaCost / getMinimumManaCost / GetMoreManaCost), 57 (UseAbility event order), 64, 76, 91, 106 | code behaviour, not serialized data |
| 96 (Haste / Frenzy durations per source, ~45 timed-gain fields) | mutator fields are in the player prefab (existing `abilities.json` `mutator` block holds non-zero defaults) but durations/gain are applied in code |
| 74c (spawn share of magic / rare monsters) | lives in MonsterRarityManager asset and per-zone spawner components in `scene_*.bundle` (SpawnerPlacementManager etc.); a different extraction, not attempted here (UNKNOWN whether complete) |
| 135, 124, 125 | event rates / code paths |

## 6. Plan (proposed scripts, one output file each)

1. `tools/extract/extract_prefab_components.py` -> `research/data/game/prefab_ability_components.json`: for every `Ability` in
   PermaLoad with a prefab (4349), walk the prefab (depth-limited nested soft refs), emit per component of the whitelist
   {CastAtRandomPointAfterDuration, CastAfterDuration, CreateAbilityObjectOnDeath, DestroyAfterDuration, RepeatedlyApplyAilmentsInRadius,
   RepeatedlyDamageEnemiesWithinRadius, RepeatedlyHitsTargets, DamageEnemiesWithBeam, ExtraProjectiles, RepeatedlyPullEnemiesWithinRadius,
   RepeatedlyGiveParentResources, BuffParent, ExistsWhileChannelling} all non-UI serialized fields (raw), refs resolved to
   `{key, abilityName, playerAbilityID|null}`; plus the full component class list per GameObject path.
2. `tools/extract/extract_actor_prefab_components.py` -> `prefab_actor_components.json`: for each of 1035 ActorData: UsingAbility* (baseUseSpeedMultiplier),
   CastSpeedManager.overrides, AbilityList.abilityRefs, AbilityRangeList, ChargeManager, ComboAbilityList, BaseMana/PlayerMana; player prefab separately.
3. `tools/extract/extract_ability_asset_extras.py` -> `ability_asset_extras.json`: all 4349 `Ability` assets: combo*, stopRange*, subtractStopRange*,
   speedScaler, speedMultiplier, speedScalerEffectiveness, maximumUseSpeed, minimumUseDuration, hasMinimumUseDuration, cooldown, charges.
Run with `tools/venv/Scripts/python`; reuse `common.py` (`load_scripts`, `open_bundle`, `BundleIndex`) and `walk()` from `extract_minion_stats.py`;
keep a small bundle cache (see `Bundles` in `extract_abilities.py`); expected total runtime a few minutes.
