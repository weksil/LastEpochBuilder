# 07i. Формулы особых эффектов уникальных и сетовых предметов (клиент 1.5.0)

Продолжение 07d (часть 2). Закрывает пункт 2.7 «Не удалось установить»: что именно делают обработчики PlayerProperty,
как скиллы читают AbilityProperty и какие AbilityID вызывают предметы.

Результаты:
- `research/data/game/unique_effects.json` (обновлён на месте): у каждого эффекта `PlayerProperty`/`AbilityProperty` добавлены `formula`, `plannerModel`, `plannerConstants`, `confidence`. Старые строки сохранены в `formulaGeneric` / `confidenceStructure`. Верхнеуровневый `ppFormulas` — справочник по ppIndex (359 записей), `apCoverage` — покрытие AbilityProperty.
- `research/data/game/item_procs.json` — предмет → AbilityID (38 записей PlayerProperty/Component + 52 ability-scoped шанса).
- `research/data/game/abilities.json` — у способностей добавлены `itemProcs` и `resolution` (поле для всех `abilityIdOnly`).
- `research/data/game/ability_property_fields_c.json` — новая карта (AbilityID, specialTag) → поле `AbilityStatsMutatorManager` (2242 записи вместо 490).
- Инструменты: `tools/extract/ap_switch_c.py`, `merge_unique_formulas.py`, `build_item_procs.py`. Рабочие каталоги: `dump/work_wave3/{notes,pp,pp_c,*.py}` (`notes/A..F.py` — рукописные формулы, `ctx.py`/`hint.py`/`lift2.py`/`statctor.py`/`auto.py` — читатели ISIL).

## 1. Покрытие

| Класс | Всего | Что сделано |
|---|---|---|
| PlayerProperty (уникальные поля) | 359 индексов (399 эффектов) | у каждого есть формула. По 399 эффектам: **D** (прочитано и проверено в коде) 141, **D(const)** (константы из кода, семантика триггера из тултипа) 33, **D?** (структура и имя; часть констант не разрешена) 225 |
| AbilityProperty | 385 эффектов (366 пар скилл+свойство) | поле `AbilityStatsMutatorManager` найдено у 374 (97%), операция, классы-читатели у 350. Семантика — по тултипу (**D?**) |
| Прок-способности предметов | 38 привязок предмет → AbilityID | `item_procs.json` |
| `abilityIdOnly` в abilities.json | 433 | 20 привязаны к предметам, остальные помечены `resolution` (в основном проки пассивок/Weaver/деревьев и монстры) |

Модели планировщика (`plannerModel`): `conv` (статы из атрибута/стата), `cond` (условный множитель/бонус), `buff` (баф на N с, моделировать аптаймом), `proc` (шанс + ICD + AbilityID), `stat` (плоский стат/ресурс), `flag`, `util` (без влияния на DPS/EHP).

## 2. Как читать обработчик PlayerProperty

Поле `CharacterMutator` заполняет `applyModifiersBeforeExternalStatsCalculation` (см. 07d 2.2), а читают его методы-триггеры. Типовые схемы (все **D**):

1. **Стат от атрибута** («X per N Y»). Блок в `applyModifiersBeforeExternalStatsCalculation` после switch:
   `current = pp · f(источник) · k`, затем `AddStatModifier(SP, value = current − previous, ModType, AT, specialTag, extra)` (Stats vtable +0x1c, аргументы в `r8`=SP, `xmm3`=значение, стек `0x20`=ModType, `0x28`=AT, `0x30`=specialTag). **Без округления вниз**: «per 2 Int» это `pp·Int·0.5`.
   - ModType: 0 ADDED, 1 INCREASED, 2 MORE.
   - ID атрибутов в `Stats.GetAttribute`: 0 Str, 1 Vit, 2 Int, 3 Dex, 4 Att.
   - Константы-делители: `0.5` (per 2), `0.2` (per 5), `0.1` (per 10), `/3`, `/40`, `/120`; резисты читаются как доля, «per 1%» = `·100`.
2. **Входящий урон** — `ApplyConditionalDefenses`: множитель `M` стартует с 1, каждое условие `M *= (1+x)`; возвращает кортеж (M, +block chance, more armor, crit avoidance, +endurance threshold, доля отложенного урона).
3. **Исходящие временные статы** — `ApplyConditionalTemporaryStats`/`ApplyPreMutationTemporaryStats`: статы добавляются в список статов конкретного каста; условие — теги способности (`uVar11 & маска`), «каждые N секунд» — поле `remainingCooldown…` (сбрасывается только при реальном применении `param_5`).
4. **Проки** — `OnHit`/`OnKill`/`OnCrit`/`OnBlock`/`HitDamageTaken`/`OnAbilityUse`…: `RngElement.Roll(pp)` (шанс = значение мода), ICD — поле `…Cooldown` (значение из `.ctor`, см. `character_mutator_init.json`) или `ProcTimeTracker` («N раз за T с»), затем `Ability.getAbility(ID)` + `AbilityObjectConstructor.constructAbilityObject`. Баф на событие: `Buff(stat, duration)`, длительность 4 с для всех «recently» (регистр `xmm13` = 4.0).

## 3. Заметные формулы (полный список — в `ppFormulas`)

Обозначения: `pp` — ролл мода; M — множитель входящего урона.

### 3.1 Условные множители урона и защиты
| PP | Предмет | Формула |
|---|---|---|
| 254/255 | Null Portent | для каждого типа урона: если резист > 0.75: `x = max(−pp255, (res−0.75)/0.02·pp254)`, `dmg_i *= 1+x` |
| 246 | Harbinger of Stars | `M *= 1 + min(18, недавние Meteor)·pp` |
| 259 | Aergon Refuge | `M *= 1+pp`, если Ward ≥ 1000 |
| 275 | Advent of the Erased | только DoT при Haste: `x = (1+TotalIncreased)·pp ≥ −0.75` |
| 281 | Gambit of an Erased Rogue | `Roll(1/6)`, `M *= 1 + n_shadows·pp` |
| 462 / 657 | Wall of Nothing / Exulis | шанс `pp` (или `pp·Guile/10`) обнулить урон хита |
| 587 | Wings of Discord | первый хит от каждого врага: `M *= 1+pp` |
| 598 / 682 | Spirit Xylem / Effusive Oath | босс/рар: `M *= 1+pp` (при мане ≤ 50% / для хитов) |
| 496 | Mantle of the Pale Ox | перенаправление `r_h = min(0.75,pp)` на самого здорового миньона, `M *= 1−r_h−r_l` |
| 498 | Immortal Vise/Effusive Oath | доля хита рар/босса растягивается на 4 с (`LeechTracker.slow`) |
| 524 | Countenance of Majasa | DoT: `M *= 1 − blockMitigation·pp` |
| 454/455/286 | Snowblind/Static Shell | `armorMore = (1+pp)(1+armorMore)−1` против атакующего с Chill/Blind/Shock |
| 129 | Titan Heart | `DamageTaken MORE = −pp` с двуручным ближним оружием |
| 240 | Red Ring of Atlaria | `DamageTaken MORE = pp` при сумме атрибутов ≥ 180 |

### 3.2 Исходящий урон
| PP | Предмет | Формула |
|---|---|---|
| 161–164 | Eternal Eclipse | раз в 2 с следующая void-melee атака: +pp added Fire\|Melee (и Ignite); следующая fire-melee: +pp Void\|Melee (и Time Rot) |
| 228 | Vaions Chariot | раз в 3 с следующий movement-скилл: MORE Damage +pp |
| 234 | Humming Bee | Elemental Melee: INCREASED Damage `pp·Ward/200` |
| 222 | Immolators Oblation | Spell added Damage `pp·min(стаки Ignite, 40)` |
| 419 | Gambler Fallacy | +pp crit chance, если нет крита ≥ 4 с и скилл не channelled |
| 89 | Gambler Fallacy | после крита 4 с: crit chance MORE −pp |
| 93 | Vaions Chariot | INCREASED Damage = `pp·TotalIncreased(MoveSpeed)` (pp=1: +100% на каждые +100% MS) |
| 154, 196 | Darkstride, Shattered Lance | MS inc `pp·addedMeleeVoid·0.1`; Melee Cold inc `min(20, pp·HealthRegen·0.1)` |
| 506 | Crystalwind | расход ≤ 4 стаков: MORE Damage `consumed·pp` |
| 631 | Jormuns Feast | crit multi `pp` за каждые 10 Bleed на цели, макс. 200 стаков |
| 180 | Longshot | +40 added Physical\|Bow при Dex ≥ 40 |

### 3.3 Статы от атрибутов (ADDSTAT)
Все «per N» из 3.3 имеют вид `pp · источник / N` без floor, примеры: `146` Lightning\|Spell added `pp·Int/2`; `185` Physical\|Spell added `pp·Att/3`; `413/414` Penetration `pp·Dex/5`; `431` crit multi `pp·Str/2`; `285` Health `pp·Vit`; `183` MS inc `min(0.2, pp·Dex/2)`; `220` Block `max(0,pp·(Endurance−0.6)/0.02)`; `474` WardRegen `pp·maxHealth`; `325` EnduranceThreshold `pp·maxMana`; `569` Ignite chance `pp·res·10` (res — доля неограниченного резиста); `686` Fire pen миньонов `pp·(res−0.75)·100/3`.

### 3.4 Проки (chance = ролл мода, если не указано; ICD/PTT из кода)
| PP | Предмет | Событие → AbilityID | ICD / PTT |
|---|---|---|---|
| 4 | Apiarists* | каждые `10/pp` с → summonBee (353) | — |
| 28 | Ucenui Sphere | hit по рар/боссу → waterOrb (92) | 3 с |
| 30 | Arek Bones | хит оставил < 50% HP → summonAreksFlesh (367) | 20 с |
| 32 | Dark Shroud of Cinders | получен хит → fireAura (162) | 3 раза/с |
| 37 | Sunforged Cuirass | получен хит → summonWeapon (220) | 2 с |
| 40 | Locket of the Forgotten Knight | hit → voidRift (87) | 3 с в коде (в тултипе 2 с, **D?**) |
| 42 | Fiery Dragon Shoes | вас крит → fireTrail (378) | 5 с |
| 68 | Halvar's | спелл-крит → avalancheSnowball (210) | 1 с |
| 76 | Alluvion | melee-атака → alluvionWave (426) | 1 с |
| 81 | Trident of the Last Abyss | melee-килл/hit по рар/боссу → abyssalEchoes (118) | 3 с |
| 83 | Dragonflame Edict | скилл миньона → dragonfireNova (427) | 3/с |
| 134 | Reign of Winter | hit луком → heorotUniqueBowIcicle (518) | — |
| 138 | Aurora Time Glass | ниже 30% HP → auroraAmuletSpell (530), Haste | 20 с |
| 155, 166, 184, 186, 203, 264, 265, 508 | см. `item_procs.json` | — | PTT/ICD там же |

Компоненты (константы из кода, 07d 2.4): Keepers Gloves swarmOfBees(63) 0.1/8 с; Arboreal Circuit summonIllusoryTree(62) 0.1/15 с; Volcanus flameShards(117) 0.3; Bone Harvester(122) 0.2 на килл; Torch of the Pontifex pontifexCremate(121) 1.0 на килл; Frozen Ire tundraNova(315) 0.15 (0.30 против нежити); Soul Bastion soulEruption(233) на 5 зарядах; Strong Mind lightningExplosion(67) при оглушении; Ignivar Head fireAura(162) раз в 1 с при ченнелинге.

## 4. AbilityProperty

Новая карта строится разбором полного декомпайла `UpdateAbilityStats` (`ap_switch_c.py`): `if (abilityID == X)` / `switch(abilityID)` и внутренние ветки по `specialTag` (`stat+0x11`). Запись `+= stat.added` — `add`, `ApplyMoreModifier` — `more-combine`, `0.1 < value` — булев флаг. Проверка: 483 пары, совпавшие со старым байтовым обходом, совпадают полностью (0 расхождений); неразобранные 11 эффектов — Swipe(19), SummonBee(353), Rebuke(173), Focus(175).

Для каждого эффекта в JSON: `field`, `fieldOffset`, `fieldOp` (add/more-combine/flag/set), `readers` (классы-мутаторы, читающие это поле в ISIL; отбор по совпадению токенов имени класса со скиллом: возможны ложные срабатывания, например для ThornShield попали классы Thorn/Shield-скиллов; это отправная точка, не доказательство) и `plannerModel`:

| plannerModel | Эффектов | Как моделировать |
|---|---|---|
| skillDamage | 68 | `+value` к полю скилла (added/increased/more — по тултипу и `fieldOp`); мутатор прибавляет поле к значениям дерева |
| skillProc/chance | 52 | шанс каста связанной способности (имя в тултипе); ICD — в тултипе |
| skillMisc / skillConversion/mechanic | 39 / 38 | конверсия элемента, замена скилла, булев переключатель — вкл при `value > 0.1` |
| skillCount/charges, skillArea/range, skillCooldown, skillCost, skillDuration, skillCrit, skillSpeed, skillPenetration, skillDefence | 29/28/21/13/8/7/15/14/27 | суммируются в поле; читатель применяет как слагаемое к соответствующему параметру скилла |
| skillMechanicFlag | 26 | флаг `|=`, без величины |

Общий механизм: значения всех `AbilityProperty` статов с одним (AbilityID, index) суммируются в поле `AbilityStatsMutatorManager`; скилл-мутатор (`<Skill>Mutator.Mutate`) читает поле в момент каста. В 07c описаны поля, которые пишут деревья; поля уникальных (`fireballPierceChance`, …) читаются теми же методами.

## 5. Тест-векторы

1. PP 146 (Vilatria's): Int 200 → added Lightning\|Spell Damage = 1.0·200·0.5 = 100.
2. PP 183 (Snowdrift): pp=0.01, Dex 300 → `min(0.2, 0.01·300·0.5)` = 0.15 → +15% MS.
3. PP 254/255 (Null Portent): pp254=−0.01, cap=0.3, Fire res 0.95 → `(0.95−0.75)/0.02 = 10` → x = −0.10 для огненного урона.
4. PP 220 (Face of the Mountain): pp=0.01, Endurance 0.80 → `(0.80−0.6)/0.02·0.01` = +0.10 Block.
5. PP 69: maxHP 1000, HP 400, pp 0.2: Ward/с = (1000−400)·0.2 = 120.
6. PP 70: HP падает по `HP·(1−0.2·dt)`: за 1 с ×0.8 (при HP > 1).
7. PP 28: hit по боссу, `rand < 1.0`, c последнего каста ≥ 3 с → waterOrb; иначе нет.
8. PP 161: каст void-melee скилла при `cooldown ≤ 0` → +pp added Fire\|Melee, cooldown = 2 с; повторный void-melee через 1 с без бонуса.
9. PP 462 (pp = 0.1): каждый хит независимо с шансом 10% обнуляется (M=0).

## 6. Не удалось установить / куда смотреть дальше

- **225 из 399 эффектов PlayerProperty помечены D?**: формула получена из имени свойства + констант кода (ability ID, ICD, PTT, длительности); точные шанс/ICD/тип стата уточняйте по `dump/work_wave3/pp_c/pp_<ppIndex>.txt` и `ctx.py CharacterMutator <метод> <поле>`.
- Статы из `ApplyConditionalTemporaryStats` (Stats.AddedStat/MoreStat): Ghidra теряет float-аргументы; для 161–164, 170, 173, 222–231, 234, 411, 419, 445, 506 тип (added/inc/more) и теги взяты из `statctor.py` (ISIL), значения `x2` — выражения над полем, часть без окончательной проверки.
- PP вне switch: 126, 127, 190, 507, 528, 551, 630, 665 (зелья/компаньоны) — только по имени; 309 «Endurance applies to all damage dealt to mana» читается не в CharacterMutator.
- 28 и др. «chance» в тултипе при `flag` (30 Arek's Flesh): значение 1.0 — флаг, шанс 100%.
- Расхождение тултипа и кода: PP 40 (ICD 2 с в тексте, 3 с в `.ctor`) — взят код.
- 215, 193, 141/142/149, 339, 566–568 (источник числа комплектов), 621 (floor или нет) — **D?**.
- AbilityProperty: для 11 эффектов поле не разрешено (Swipe, SummonBee, Rebuke, Focus); семантика остальных — по тултипу, построчно читатели не разбирались (список `readers` — отправная точка).
- Привязка «предмет → AbilityID» охватывает 31 способность; остальные `abilityIdOnly` (≈410) не связаны с уникальными: это проки пассивов/Weaver/деревьев и монстры. LE Tools `itemDB.triggeredAbilities` (85 ID) шире: сверить можно, взяв оттуда список.
- Компоненты Chains_of_Uleros, Hollow_Finger и пр. без кода — эффект целиком в модах (см. 07d).
