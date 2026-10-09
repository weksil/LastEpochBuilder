# Follow-ups of the item / affix / set trigger audit (client/data/unique_effect_models.json)

Source: `research/data/audit/item_trigger_verdicts.json`, `research/10_trigger_audit.md`. Rule: only game data counts. Every fact below
was re-read in the dump (`dump/decomp/LE.dll/<Class>.c`, `dump/work_wave3/pp/pp_<n>.txt`, `dump/work_wave4/traces_uniq/`, `dump/cs/DiffableCs/LE/`).

Engine semantics to keep in mind when reading "engine support needed":
- `skill_any` / `skill_mask` are ANY-of masks (`tags & mask != 0`) and are checked against the tags of the skill being computed.
  The game often needs ALL tags (Melee AND Fire, Spell AND element) or an ability identity (Javelin, Meteor): not expressible.
- Ability-bound entries (`ability` section, key `index:property`) are applied only while the skill with that ability id is computed,
  so events that the game takes from OTHER skills' uses or hits (Gaspar, Volcanic Orb, Avalanche on melee hits, Burning Dagger on
  melee fire hits) are counted in the wrong skill context. Adding `skill_any` there would test the owner skill's tags, so it was NOT added.
- Ability-bound `second` / `hit_taken` ... entries are counted only in the first damaging skill slot (`UniqueEffects.CHARACTER_EVENTS`,
  `first_skill_slot`), which is wrong for an entry bound to a specific skill such as Maelstrom 318:0.

## A. Entries changed only partly (the rest needs engine support)

| Key | Done in the JSON | Still missing (facts and evidence) | Engine support needed |
|---|---|---|---|
| player 42 Fire Trail | chance 1, cooldown 5 s after the cast | Event is "crit received" (`HitDamageTaken`: `(hitEvents & Crit(2))`, `fireTrailIndex >= fireTrailCooldown(5.0)`, index = 0 on cast, no `RngElement.Roll` with the field; pp_42.txt). The planner has only `hit_taken`; the user must enter crits taken per second. | event `crit_taken` |
| player 81 Abyssal Echoes | skill_any Melee, no boss condition, cooldown 3 s | `OnHit` (tags bit 9, `CharacterMutator.c` ~27440) and `OnKill` (same bit, `~31990`) share `...Cooldown`/`...Index` (+0xDAC/+0xDB0); Roll then cast of ability 118, index = 0. There is no `isRareOrBoss` in this block. Kills use up the same cooldown. | one cooldown shared by two events (hit + kill) |
| player 480 Doom Pulse | skill_any Fire/Cold/Lightning/Necrotic/Void, icd 1 cooldown | `OnAbilityUse` (`CharacterMutator.c` 18032): five separate `...SpellUseLastTime` timestamps (+0x1B58..), the cast happens if for SOME element in the tags the last cast of that element is older than 1.0 s, then only that element's stamp is updated, ability 0x31d, no roll. A skill with two elements casts about twice per second. There is no Spell-tag test in the block (the property name says "Spell"). | per-element timers (count = number of matching elements of the skill) |
| component 32:1 Frozen Ire | skill_any Cold | `Frozen_Ire.onHitEventDetailed`: Roll(0.15) else, against Undead (type list contains 2), Roll(0.176471), i.e. 30% in total against Undead; tag test uses the ability's tags including fake tags (`vtable +0x2E8`, arg 4 = Cold); not Tundra Nova itself (ability 0x13b). | chance depending on enemy type; fake tags in `skill_any` |
| ability 517:1 / 517:2 / 517:3 Gaspar's set | cooldown flag, note | AUDIT CORRECTION: the audit says one cooldown shared by the three pieces. The code has THREE timers: `remainingFireProcCooldown` +0x190, `remainingColdProcCooldown` +0x194, `remainingLightningProcCooldown` +0x198 (`GasparSetSwipeMutator.cs`), each set to `getProcCooldown()` = 3.0 x (1 - stat +0x2250) right after its own successful Roll (`GasparSetSwipeMutator.c` 792-1076). Spell tag (bit 8) AND the element tag are needed (`(tags >> 8 & 1) == 0 -> return`). The events come from the player's other skill uses, not from GasparSetSwipe (abilityIdOnly, no skill of that id is computed). The 2pc bonus 517:4 = 0.5 gives 1.5 s. | cooldown that scales with another property (517:4); Spell AND element mask; events of the owner's bar skills |
| ability 489:2 Burning Dagger | stochastic: true | `BurningDaggerMutator.OnDetailedHit`: n = StochasticRound(stat +0x1c98), requires `(tags & 0x208) == 0x208` (Melee AND Fire), ONE ProcTimeTracker (4 per 1 s, +0x120) on the proc, then n daggers (the planner's cap counts daggers, not procs). Events come from other skills' melee fire hits; the entry is computed in Burning Dagger's own context (Fire, Throwing). | AND-mask; owner-bar event routing; PTT on procs, not casts |
| ability 318:0 Maelstrom | rewritten as `second`, chance 1, count v, icd 3 (v casts per 3 s on average) | Each cast first checks `BaseMana.hasEnoughManaToUse` and spends the mana (`MaelstromMutator.OnMutatorUpdate`, `idolAutoCastIndex` +0x1F8 vs cooldown +0x1F4 = 3.0, the timer restarts at every expiry). Only counted while Maelstrom is the first damaging slot (see above). | mana cost per trigger cast; per-skill `second` events |

## B. FACT-wrong entries left unchanged (not expressible)

| Key | Issue and facts | Engine support needed |
|---|---|---|
| player 247 Meteor on crit | `CharacterMutator.OnCrit` (23629): Roll(+0x132C), `mana > 0`, `hasMeteorMutator` (+0x2227, the character has the Meteor skill) and `ability != Ability(7)` (crits of Meteor itself excluded), cast at the nearest enemy, no cooldown. | `when` "skill on bar" and "cast skill is not X" |
| player 444 Voidwinter Bolt | `OnHit`: Roll(+0x1A2C), then (tags bit 9 Melee) OR ability is `javelin` / `fallingJavelin` / `javelinLightningSpear`; PTT 8 per 2.0 s plus `minVoidwinterBoltInterval` 0.2 s; ability 0x319. Javelin has tags Physical|Throwing (1025) so no tag mask separates it from other Throwing skills. | ability-name filter (`skill_names`) |
| ability 61:0 Serpent Strike | `SerpentStrikeMutator.OnKill`: Roll(`snakeOnKillChance` +0x130 of the TREE (base 0.12) + item stat +0x5FC), after `AbilityAcceptableForEvents`; summons field `summonSerpent` (+0x240, ability 59). `SummonSerpent` and `SummonPrimalSerpent` both summon actor PrimalSerpent in abilities.json. `TryToSummonPrimalSnake` (+0x248) is only used by `OnMinionHit`. The model uses only the item value as chance. | chance = tree base + item |
| ability 78:9 / 78:10 Volcanic Orb | `VolcanicOrbMutator.OnStartedUsingAbility` (direct use of ANY ability): needs Melee tag (bit 9) or the traversal flag, Roll(fire +0xA54 / cold +0xA58) and the element tag (Fire 8 / Cold 4) of the used ability, one PTT per element (1 per 3.0 s). Events come from other skills' uses; the entry is computed in Volcanic Orb's context (Fire, Spell). | AND-mask / movement-or-melee condition; owner-bar event routing |
| ability 209:15 Avalanche | `AvalancheSnowballMutator.OnHitAvalanche`: hits of other skills need the Melee tag (0x200); hits by Avalanche itself take the crit branch; PTT 5 per 1.0 s (+0x128); no Roll. Events come from the melee skills' hits. | owner-bar event routing |
| set 517:4 Gaspar's 2pc | `getProcCooldown` = 3.0 x (1 - stat +0x2250), 517:4 = 0.5 -> 1.5 s; not read by the planner at all | cooldown modifier read by the 517:1-3 models |

## C. Cooldown-type decision (step 2 of the task)

Cooldown that starts after a successful roll (`cooldown: true` set): player 156, 37, 40, 166, 28, 30, 133, 138, 42, 81, 76, 480, ability 137:1, 517:1-3,
component 22:0, 65:0. Evidence: the field pair `<x>Cooldown` / `<x>Index` (index reset to 0 on the cast) or `remaining<x>Cooldown` set to the constant on the
cast: pp_156/37/40/28/166/30/138, `HitDamageTaken` 15380-15470 (+0xC94/+0xC98 for 37), `RipBloodMutator.OnHit` 1701-1712, `Keepers_Gloves.onHitEvent`,
`Arboreal_Circuit` (0xA8 reset at 81).
ProcTimeTracker window / sliding list (default, `icd` = interval / limit): 661, 32, 83, 153, 212, 264, 398, 444, 448, 508, 577, 579, 581, 11, 12, 26, 44, 54,
ability 339:0, 708:0, 61:1, 550:2, 78:9, 78:10, 209:15, 489:2. Fixed timers (the cast fires when the timer expires, no roll gating it): player 4, 75, ability 318:0, component 74:1.
138 Aurora Amulet (UNKNOWN entry): cooldown flag set; the threshold is a literal 0.3 (`afStack / maxHealth < 0.3`, pp_138.txt), remaining cooldown 20.0 s.

## D. UNKNOWN entries left unchanged (no new evidence)

player 661 (count 4 per proc: pp is only tested > 0 in `OnAbilityUse`, PTT 2 per 6 s, any Totem-tag ability), 570 (ignited enemy conditions), ability 694:2, 722:0, 253:1
(Roll sites of the reading stats not decoded).

## E. Casts the planner does not model at all (audit `unmodelled`)

| Key | What | Facts and evidence |
|---|---|---|
| p1 idol 214 | Lightning Strike when you spend >= 10 mana on a skill | `CharacterMutator.OnManaSpent`, field `chanceToCastLightningAtRandomNearbyOnTenManaSpent` |
| p5 idol 218 | Thorn Totem on hit | OnHit Roll `chanceOnHitToSummonThornTotem`, actor not dying, PTT 1 per 1.0 s (`chanceOnHitToSummonThormTotemPTT`), getAbility(58) |
| p9 idol 222 | Healing Nova when hit | HitDamageTaken Roll `chanceToCastHealingNovaWhenHit`, getAbility(76) |
| p10 idol 223 | Earthquake Aftershock on melee attack | OnAbilityUse Roll `chanceToCastAftershockAtNearbyOnMeleeAttack`, needs `hasEarthquakeMutator`, PTT `aftershockOnMeleePTT` 10 per 2.0 s |
| p29 idol 243 / equipment 395 | Lightning Aegis when hit | HitDamageTaken Roll `chanceToCastLightningAegisWhenHit`, getAbility(68) |
| p52 idol 275 | Divine Bolt on a 0 mana skill | OnManaSpent `chanceToCastDivineBoltOn0ManaSkillUse`; OnHit also has `chanceToCastDivineBoltOnMeleeHit` (getAbility 213, PTT) with no PP index found |
| p158 belt affix 67 | Freezing Concoction on potion use | onPotionUse Roll `freezingConcoctionOnPotionUseChance`, getAbility(549) |
| p338 belt affix 714 | Bees on potion use | onPotionUse, `remainingDelayForCastingBeesAfterPotionUse` 0.5 s |
| p539 idol 937 | Acid Flask on bow hit | OnHit Roll `acidFlaskChanceOnBowHit`, Bow tag (bit 11), PTT 1 per 3.0 s, getAbility(50) |
| p51, p66, p68, p386, p428, p695, p702 | Manifest Strike on melee hit, Divine Bolt while channelling, Avalanche on spell crit, Caltrops on dodge, Frost Claw on first melee hit, Bloodice shard on cast, Ice Nova on boss/rare hit | CharacterMutator Roll sites exist; no unique or affix carries them (p68 only through the Halvar set) |
| Halvar's 3pc (p68) | 100% Avalanche Boulder on spell crit | OnCrit Roll `chanceToCastAvalancheSnowballOnSpellCrit`, `avalancheSnowballOnSpellCritIndex >= Cooldown(1.0)` (cooldown type), tags & 0x100 |
| Apiarist's 3pc (p634) | a Queen Bee summon | OnUpdateTick `summonQueenBee` |
| Caretaker's 2pc (71:13) | Entangling Roots every 3 s while moving | ability property 71:13 exists, no reader decoded |
| Gaspar's 2pc (517:4) | -50% proc cooldown | `getProcCooldown` (see section A) |
| p329 Box of Hydrae | Hydrahedron on kill with fire skills, 9 s cooldown | OnKill Roll `chanceToInvokeHydrahedronOnKillWithFireSkills`, `timeLastCastHydrahedronOnKill` |
| p415 Orian's Sun Seal | autocast Sigils of Hope every 6 s above half mana | CharacterMutator `sigilsOfHopeAutocastManaConsumptionAndCooldownPercentage` |
| p479, p594, p591, p616, p578 | Flames of Midnight (Wandering Spirit on fire/necrotic/void use), Evolution's End (Rift Beast on a boss below 40%, 40 s), Hydra Arc (repeat bow attack after evade), Tyrant's Skull, Chorus of the Anurok (summons) | CharacterMutator flag fields only |
| 468:6, 114:0, 216:6, 146:7, 405:2, 17:12, 782:11, 689:30 | Penumbra (Shadow Dagger on Lethal Mirage hit), Shadow Beacon (Devouring Orbs), Palarus (Smite at 2 extra targets), Wraithlord's Harbour, Phase Point (Black Arrow on dodge), Laup's Path (Thorn Totems), Death Dance, Gordian Prism | ability_property_fields entries exist, no model |
| SP 127 affixes 966 / 972 | modelled through CAST_FOR_TAGS_EVENTS {1 hit, 2 crit} | the game consumer of SP 127 and the meaning of `specialTag` were not located in the decomp (UNKNOWN) |
| CharacterMutator hard-coded casts | 31 of 90 ability ids and 79 tree cast-like fields kept only as flags | see `research/data/audit/granted_abilities.json` |
