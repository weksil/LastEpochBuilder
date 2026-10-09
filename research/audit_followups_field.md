# Follow-ups of the field_models.json trigger audit (what the planner cannot express yet)

Source: `research/data/audit/mutator_trigger_verdicts.json`, re-checked against the decompiled code (`dump/decomp/LE.dll/<Class>.c`, `dump/isil`,
`research/data/game/character_mutator_init.json` for CharacterMutator constructor values). Entries below were NOT changed (or only partly) in
`client/data/field_models.json`. "cooldown" = the limit is a cooldown field that starts after a successful roll (`cooldown: true`).

## A. Needs engine support (entry left unchanged unless noted)

### AbyssalEchoesMutator.chanceToDetonateDevouringOrbs
- Code: `AbyssalEchoesMutator.Mutate` loops over the Void Rift list (`devourMut+0x238`) and rolls the chance once per Void Rift.
- Model: one roll per use (`on: use`, count 1). Correct count = number of Void Rifts alive/created per cast.
- Needs: `count` that follows a skill quantity (number of Void Rifts), not a constant.

### AuraOfDecayMutator.castsPeriodicNova
- Code: `AuraOfDecayMutator.OnMutatorUpdate` (decomp AuraOfDecayMutator.c) resets `periodicNovaTimer` (0x148) to
  `max(1.0, 15.0 / (1 + PoisonResFraction * 10 * novaICDRPer10PoisonRes))` after each cast. Base period 15 s (0 poison resistance).
- Model: `on: second`, chance 1 (1 cast/s). Wrong by 15x at 0 resistance.
- `second` + `icd` cannot express it: the interval depends on the poison resistance (stat) and the field `novaICDRPer10PoisonRes`.
- Needs: an interval formula (icd from a stat source, e.g. `icd_per`/`icd_min`).

### CharacterMutator.chanceToCastLightningEverySecondWhileChannelling (unchanged)
- Code: `CharacterMutator.OnUpdateTick`: `if (timer 0x2C0 > cooldown 0x2BC (1.0)) { if Roll(0x2C8) and isUsingChannelledAbility { timer = 0; CastStormBolt } }`.
  There is NO 1 s roll timer: once the shared 1 s cooldown has elapsed the roll is repeated on every tick until it succeeds. The cooldown
  timer 0x2C0 is the same field as for `chanceToCastLightningOnCast` (OnAbilityUse: Roll(0x2B8), timer >= cooldown, Spell tag bit 8, timer = 0).
- The model (`on: second`, chance v) would need the tick rate of OnUpdateTick (not in the game data) or "rolls until success" semantics.
  Adding `icd 1` with either limit kind would give a wrong rate (real rate is about 1 per (1 s + a few ticks) whenever the chance per tick is not tiny).
- Needs: event `tick` / "re-rolled each frame after the cooldown" model, and a limiter shared between the two fields.

### FlameReaveMutator.fireballOnKillOrEliteHit and lightningBlastOnKillOrEliteHit (unchanged)
- Code: `FlameReaveMutator.OnHitDetailed`: `if (Actor_isRareOrBoss(target) || DetailedAbilityEvent.get_kill())` then
  `TryProc(0x1d8 fireballPTT)` / `TryProc(0x1e8 lightningBlastPTT)`; both PTT are (3, 2.0) = icd 0.667; mana cost x0.5.
- Model has only `kill` (+ icd 0.67), so a single-target boss fight gets 0 triggers. The field fires on kill OR on every hit against a rare/boss.
- Needs: two events for one field (`on: ["kill", "hit"]` with the `when` applying only to the hit event), one shared limiter.

### HarvestMutator.zombieChanceOnKillOrRareBossHit (unchanged)
- Code: `HarvestMutator.OnKill`: Roll -> TryProc(0x1e0 zombiePTT); `HarvestMutator.OnHit`: Actor_isRareOrBoss -> Roll -> TryProc(0x1e0); ctor PTT (5, 3.0) = icd 0.6.
- Same as Flame Reave: kill OR rare/boss hit, one shared PTT. Model counts only kills.

### SpiritThornsMutator.castEntanglingOnMaxSpirits (unchanged)
- Semantics: `SpiritThornsMutator.Mutate`: when living Vale Spirits reach the maximum, `ConsumeAllValeSpirits` and cast Entangling Roots.
- Model: `on: use`, chance 1 (every use). Correct rate = (spirits gained per second) / max spirits.
- Needs: an event "resource reached its maximum" with the gain rate, or a count of uses per trigger (every N-th use).

### SummonBoneGolemMutator.boneShatterRepeatChance (unchanged)
- Code (semantics + ctor): the field is copied into the golem controller; Roll(chance) on a HIT of Bone Shatter (the golem's ability), PTT (2, 1.0) = icd 0.5.
- Model: `on: cast` (casts of the owner skill) with icd 0.5. The event is a hit of ANOTHER ability (Bone Shatter) used by the golem.
- Needs: event "hit of a given ability / minion ability hit" with its own rate.

### Limits shared between different fields
Each field is modelled alone with the correct own limit; the sum of fields is overcounted when the build has several of them.
- SwipeMutator.clawTotemOnHitChance (rare/boss hit) and clawTotemOnKillChance: one `summonClawTotemPTT` (1, 4.0) in `SwipeMutator.SummonClawTotem`
  (called from OnHit and OnKill). Both got icd 4.
- MaelstromMutator.chanceToAutoCastOnHit / chanceToAutoCastOnKill: one `autoCastTimer` (0x1CC) / `autoCastCooldown` (2.0): both are checked and reset by OnHitMaelstrom and OnKillMaelstrom.
- CharacterMutator.chanceToCastLightningOnCast and ...EverySecondWhileChannelling share timer 0x2C0 (see above).
- ChaosBoltsMutator.harvestChanceOnHitPerDex: counter `harvestsTriggered` (max 3, reset every 1.0 s by a timer): a fixed window, modelled as icd 0.333 (rate <= 3/s).
- Character-level limiters are global (one ProcTimeTracker / cooldown field for the whole character) but `use`/`hit` triggers of CharacterMutator
  are counted once in every skill slot: divine bolt (PTT 2/1 s), fire aura on first melee hit (PTT 3/1 s), arcane lightning (5 s cooldown), lightning on cast (1 s cooldown). With several qualifying skills on the bar the totals add up above the real limit.
- Needs: a limiter key (`limit_group`) shared by fields/slots.

## B. Modelled only partly (the rest cannot be expressed)

- CharacterMutator.chanceToCastDivineBoltOnMeleeHit: applied `skill_any: Melee`, icd 0.5. The real chance is `field(0x378) * (1 + increasedChanceToCastDivineBoltOnMeleeHit (0x37C))`; the second field has no model, so the multiplier is missing.
- CharacterMutator.arcaneLightningTargets: applied `on: hit`, `skill_any: Lightning` (hit tags bit 1 = Lightning), icd 5, cooldown, count = targets. The cooldown is shared by the whole character (see above). `skill_any` tests the tags of the skill being calculated.
- IceThornsMutator.sunderingThornsOnHitChance: icd 4 (base `sunderingThornsBaseCooldown`, ctor 4.0); the code sets the index to `base / (1 + increasedSunderingThornsCooldownRecovery)`; the recovery field is not applied.
- EnchantWeaponMutator.chanceToZapOnMelee: icd 1 (PTT (1, 1.0)); while the enchant is active `ChangeInterval(1 - zapActiveReducedCooldown)` is applied (`Mutate`), restored to 1.0 in `OnActiveEnded`. Not modelled. The same OnHitDetailed block (equipped flag 0x1D4, then `(tags & 0x200) == 0 -> return`) gates the zap, the fire burst and the ice shard to Melee hits.
  `skill_any: Melee` was NOT added: the owner skill (Enchant Weapon, tags 131200 = Buff) has no Melee tag, so the filter would zero the trigger. The same holds for DarkQuiverMutator.arrowChanceOnBowAttack: code requires a Bow-tagged ability use (tag bit 11) and a 3 s cooldown (0x160 ctor 3.0, cooldown applied); `skill_any: Bow` was NOT added because Dark Quiver itself has tag Buff (131072). The planner counts uses of the owner skill here, not of the player's Bow skills.
  Needs: events of OTHER skills on the bar (`on` with a source of "uses of skills with tag X").
- BoneCurseMutator.boneCurseOnHitForDurationOnCast: icd 1 + cooldown applied; the trigger exists only for `(1 - reappliers) * f` seconds after a direct cast (`autoCastEndTime`, 0x1C4) - not modelled.
- RipBloodMutator.splatterChance: applied `on: use` (one new enemy per cast vs one target). Code (`numberOfSplatters`): chance <= 1: Roll(f) -> 1; chance > 1: 1 + Roll(f - 1) (expected min(f, 2)). The skill node gives at most 4 x 0.25 = 1.0, so the cap at 1 matters only with extra sources.
- IceShard (EnchantWeaponMutator.iceShardOnMeleeHitChance): note text "chance x3 while active" was kept from the old model and not re-verified.

## C. Verdict claims that did NOT hold (code checked)

- CinderStrikeMutator.firstStrikeFlaskChance (verdict: stochastic count): `ChanceToCreateAbilityObjectOnNewEnemyHit.createAbilityObject` caps the chance at 1.0 unless `overCapChanceAddedCasts` (0x44) is set; `CinderStrikeExplosionMutator.Mutate` does not set it (it sets `canOnlyTriggerOnce` 0x38 = 1). So the default 100% cap is right, and the event is once per explosion (applied `on: use`).
- MaelstromMutator.chanceToAutoCastOnHit: no `Actor_isRareOrBoss` anywhere in `MaelstromMutator.c`; `OnHitMaelstrom` is subscribed to the generic `AbilityEventListener.onHitEvent`. The `enemy:boss_or_rare` condition was removed (verdict confirmed).

## D. Limit kind not established (cooldown flag left at the default = ProcTimeTracker window)

The cooldown comes from an `ExtraAbility` struct / adapter / component that is not decoded, so "cooldown field after success" vs "cadence" is UNKNOWN:
- FalconryMutator.throwsAcidFlask (6 s), FalconryMutator.throwsFeatherKnives (10 s), NetMutator.dropsCaltropsAtTarget (2 s), SummonStormCrowMutator.crowCastsWisdom (10 s),
  SummonWolfMutator.iceBite (6 s), SwarmbladeSpinMutator.locustsPer3SecondsFromSwarm (3 s), SummonMageMutator.dksCastHungeringSouls (6 s, ExtraAbility range struct not decoded).
- SummonSabertoothMutator.ancestralSabertoothSummonChance (10 per 5 s) and SummonScorpionMutator.scorpionAvalancheBoulderOnMeleeChance (3 per 2 s): the PTT sits in the minion adapter (not in the mutator class); semantics JSON only.
- RipBloodMutator.bloodTetherOnRareOrBoss: icd 1 stands in for the per-use flag (0x282, once per direct use), not for a time limit.

Verified as ProcTimeTracker windows (default kept): AuraOfDecay explode (2/3 s), ChaosBolts ripblood (counter 2 per 1 s), CharacterMutator.chanceToCastLightningOnMeleeHit (3/1 s), EnchantWeapon fireBurst (2/2 s; the limit becomes 4 while active, not modelled),
Firebrand fireAuraChancePerStack (4/1 s), ManaStrike staticOrb (3/2 s), SmeltersWrath javelin (1/6 s).

## E. Other

- CharacterMutator.fireAuraChanceWhileMovingOrMeleeDoubleUnder3 (Flame Walker): already corrected in the working tree before this pass (`on: second`, `moving_or_melee`); not touched.
- `engine_test.tscn` fails one check ("Volatile Reversal DPS: got 28006.7, want 28079") with and without these data changes (reproduced with all audit edits reverted), so it comes from other uncommitted edits.
