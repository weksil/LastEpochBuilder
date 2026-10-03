# 07f. Пассивные деревья классов, дерево Weaver и урон способностей, заданный кодом (клиент 1.5.0)

Результаты: `research/data/game/passive_node_effects.json`, `weaver_node_effects.json`, `abilities_code_damage.json`. Инструмент: `tools/extract/passive_tree_effects.py` (поверх `mutator_coeffs.py` и `isil_sym.py`, время работы ~8 с, перезапускается без правок).

## 1. Кратко

- Все 5 деревьев классов (Knight, Acolyte, Mage, Primalist, Rogue) разобраны: **541 узел, 0 узлов без эффекта**. Из них `auto` 312, `auto_threshold` 226 (бонус при `p >= N`), `auto_formula` 2 (нелинейная функция от p), `auto_after_loop_rule` 1. Ручного разбора не осталось.
- Weaver: 79 узлов с очками (80-й, `Node_None`, корень). У каждого есть эффект. Weaver не влияет на персонажа, он задаёт параметры эхо-контента (шансы дропа, спавна и т. п.).
- Найден и разобран ещё один слой: **базовые бонусы мастерств** (`switch(chosenMastery)` после цикла по узлам), поле `mastery_bonuses` в JSON.
- Попутно исправлены два дефекта символьного исполнителя (затронули и скилловые деревья, см. §6).

## 2. Как применяются узлы пассивок (D)

`LocalTreeData.updateMutator` вызывает `<Class>Tree.updateMutator(localTreeData, tree)`. Отличия от скилловых деревьев:
- Это не `switch` по хешу, а цепочка `if (gnode.name == "...")` (String.op_Equality). Очки берутся из `NodeData.points`.
- Стат создаётся прямо в нужном списке: `CharacterMutator.stats`, `statsWithWeaponRequirements`, `totemStats`, `statsPerMastery1Level`; для миньонов и скиллов это `ManifestArmorMutator.statListFromPassiveTree` и т. п. Поля `CharacterMutator.*` читаются позже самим игроком (условные эффекты, триггеры).
- Бонусы «при N очках»: `if (p >= N)` внутри блока узла. В JSON у такого эффекта есть `minPoints` и `when`.
- `AcolyteTree.updateMutator` обрезан Cpp2IL (нет `Return`, ~2.6 КБ); недостающий хвост декодируется из `GameAssembly.dll` (`mini_x64`) и дописывается к методу.
- `dump/decomp_extra/{Knight,Acolyte,Mage,Primalist}Tree__updateMutator.c` использовались только для сверки. `RogueTree.c` в обычной декомпиляции есть.
- Мастерство читается из `LocalTreeData+0xB0` (`chosenMastery`, byte). Индекс 0 — без мастерства, 1..3 — три мастерства класса, как в `masteries[1..3]`.

### Схема `passive_node_effects.json`
Массив из 5 деревьев:
```
{ tree, treeID, class, kind:"passive", masteries[], mutators[], errors[],
  mastery_bonuses: { "1"|"2"|"3": { mastery, fields{target: value}, stats[{target, stat}], calls[] } },
  after_loop{formulas, baseline_fields, baseline_stats, baseline_calls, loop_carried},
  field_usage_hints, code_node_names_not_in_tree[], tree_nodes_without_code[],
  nodes[ { id, name, displayName, maxPoints, mastery, masteryRequirement, status, review[], manual_note?,
           effects[], asset_noScaling{type, pointThreshold},
           tooltip_stats[], effects_without_tooltip[], tooltip[], tooltip_check{} } ] }
```
Эффект узла:
- `{target:"CharacterMutator.stats", op:"add_stat", stat:{...}, when?, minPoints?}`. Поле `stat.kind`: `added`, `increased`, `more`, `ailment_chance`, `ailment_duration`, `ailment_effect`, `ailment_effect_on_you`, `conditional_more_damage` (`condition`, например `ToBossesAndRareEnemies`), `player_property` / `more_player_property`, `ability_property` / `more_ability_property`, `ailment_conversion`.
- Значение: `added|increased|more|value: {per_point, flat}` или `{expr}` (`per_point` умножается на p).
- `stat.property`, `stat.tags`, `stat.ailment`, `stat.specialTag`.
- Обёртка `StatWithWeaponRequirement` (поля `wrapper`, `other`: тип оружия, `WeaponRequirementType`) для статов, которые работают только с оружием.
- `player_property`: `playerPropertyIndex`, `playerPropertyName`, `playerPropertyField`, `playerPropertyOp` (таблица `player_property_fields.json`, названо 169 из 169 вхождений).
- `ability_property`: `abilityID`, `abilityPropertyIndex`, `abilityPropertyField`, `abilityPropertyOp` из `ability_property_fields.json`, названо только 7 из 67 (остальных пар нет в таблице).
- Прямые записи в поля мутаторов: `{target:"CharacterMutator.<field>", type, value:{per_point, flat}}` (триггеры, шансы, стеки). Вызовы кулдаунов: `op:"cooldown"`.
- Статусы:
  - `auto`: эффект линейный по p;
  - `auto_threshold`: часть эффектов только при `p >= minPoints`;
  - `auto_formula`: нелинейная функция от p (например, `1/(1-0.05p)-1`);
  - `auto_after_loop_rule`: правило из хвоста метода, узел Rogue Marksman Concentration, см. `manual_note`.

### Базовые бонусы мастерств (`mastery_bonuses`, D)
Результат прогона хвоста метода с `chosenMastery = 1,2,3` минус результат для 0. Примеры:
- Void Knight: поле `chanceToRepeatMeleeThrowingAttacksAndVoidSpells = 0.1` и PlayerProperty 440 +0.01.
- Forge Guard: `stalwartWhenHitAndOnHit`, +35% Fire и Physical Resistance.
- Paladin: `moreDamagePerPercentHealth 0.15`, `increasedHealingPerAttunement 0.01`.
- Bladedancer: `createShadow` +1, +15 Physical Melee Damage, DodgeRating more 0.15.
- Falconer: +12 Dexterity, `falconry` property +1.
Остальные мастерства смотреть в JSON.

## 3. Гипотеза «increased-строки = INC, +N = ADDED» (проверена по коду)

Сопоставлено 1259 строк подсказок с эффектами кода (из них 628 надёжных: совпадение по свойству SP и тегам).

| Подсказка | Тип в коде | Строк |
|---|---|---|
| «Increased X», «Reduced X» | `increased`, либо `added` в специальный SP `Increased*` (IncreasedStunChance, IncreasedHealing, IncreasedLeechRate, IncreasedCooldownRecoverySpeed, IncreasedAreaForAreaSkills, ReducedBonusDamageTakenFromCrits), то есть INC-пул | 179 из 180 |
| «More / Less X» | `more` | 15 из 15 |
| «+N» (число со знаком) | `added` | 284 |
| «+N%» у скоростей и расхода (AttackSpeed, CastSpeed, Movespeed, Health миньонов, ManaCost, ReceivedStunDuration) | `increased` | 21 |
| «±N%» «Damage Taken ...» (от ближних врагов, в движении, при двух оружиях, DoT) | `more` | 11 |
| «N%» без знака (резисты, крит-множитель, шанс блока) | почти всегда `added` (38), редко `increased` (4: AttackSpeed, ManaRegen) | 42 |
| шансы «+N%» к ailment (Bleed, Chill, ...) | `ailment_chance` (аддитивный шанс, отдельный вид) | 49 |

**Вывод.** Для строк «Increased/Reduced» гипотеза верна. Единственное исключение, FG Strength and Damage: «Increased Melee Attack Speed With Sword» закодирован как `added` в AttackSpeed Melee; у AttackSpeed/CastSpeed база added = 1, поэтому это прибавка к базе, а не INC. Для «+N» гипотеза **неверна**: тип нельзя определять по тексту, нужно брать `stat.kind` из JSON. Damage Taken всегда `more`. У пассивных узлов урона `increased` встречается намного чаще, чем в скилловых деревьях (там почти везде `more`, 07c).

## 4. Сверка с `tree_node_stats.json` (tooltipStats)

- Совпали по числу и типу 1259 строк (`match: matched`), у 81 строки нет эффекта (`display_only`: строка только для отображения, `property = None`), у 100 строк нет «своего» эффекта (`no_code_effect`).
- `no_code_effect` — это не потерянные эффекты: в основном условные триггеры и поля `CharacterMutator.*` («per 5 Strength», «Cast Holy Symbol On Block», «Can Equip Swords in Offhand», лимиты и длительности). Они есть в `effects`, но автоматически не сопоставлены по значению.
- Расхождение числа (`value_ok: false`) осталось в **9** строках. Лечение (leech): процент в подсказке = значение стата ×10 (стат `HealthLeech` весит 0.1, 06c §5.2). Это подтверждено на 14 строках и учтено (`value_note`).
  Реальные расхождения код и подсказка (авторитетен код):
  - Knight VK Health And Void Protection: Health подсказка +8, код 10 на очко;
  - Mage SB Armor And Ward Per Second: Ward/s подсказка +3, код 4;
  - Primalist Shaman Totem Stun Immunity: Armor подсказка +10, код 30 на очко (у тотемов тоже 30);
  - Rogue BD Parry And Crit: Increased Crit подсказка 8%, код 10%;
  - Rogue BD Poison And Bleed: Increased DoT подсказка 7%, код 8%;
  - Rogue Falconer Throwing Damage And Speed: подсказка 7%, код 5%;
  - Rogue Falconer Spear Buffs: подсказка 6%, код 5%;
  - Rogue Falconer Damage And Slow Duration: подсказка 6%, код 5%.
  Девятая строка (BD Leech, DoT) — ложное сопоставление эффекта (подсказка 0.5% = 0.05×10, код корректен).
- `scaling_ok: false` (10 строк): подсказка без `noScaling`, а в коде константа не от p (например, «+1 Intelligence» с `flat 1`); это эффекты порога или триггера, смотреть `flat` и `minPoints`.
- `tooltip_check.unmatched` непуст у 110 узлов: числа лимитов, длительностей и «per N», а не стат на очко. Ни одно число не совпало у 5 узлов (Mage Sorc Ward On High Mana Use, Primalist BM Slow Melee и BM Shark Stacks, Rogue BD Dodge to Glancing Blow Conversion и BD Leech).
- `code_node_names_not_in_tree`: мёртвые ветки старых узлов (например, `FG Melee Physical And Fire Damage`, `BD Temp Node`). Узлов дерева без кода нет (`tree_nodes_without_code` пуст).

## 5. Weaver

`TheWeaver.UpdateWeaverTreeNode(effect, points)` @0x1820DDE40 — три jump-таблицы (эффекты 0..64, 101..131, 151..191). Cpp2IL обрезает метод, поэтому он декодируется из бинарника целиком, каждый кейс выполнен символьно.
- Результат: 79 узлов `auto` (флаги `p > 0`, целочисленные ранги, поля `p * k`), 0 ошибок.
- Схема `weaver_node_effects.json`: массив из одного объекта с `nodes[]` (`id, name, maxPoints, nodeEffect, nodeEffectName, effects[{target:"TheWeaver.<поле>", type, value, when?}], tooltip, tooltip_check`) и `effects_by_enum[]`.
- Три узла используют `p * TheWeaver.<X>PerPointAllocated`: поле `+0x80` инициализирует конструктор (`0x3e19999a` = 0.15, D), поля `+0x90` и `+0x94` сериализуются в ассете (не найден), значения взяты из подсказки (0.10 и 0.02, **D?**, поле `per_point_value`).
- Узлы 6/7/8 (`...RewardWeightRank`) хранят только ранг, веса групп наград читаются в другом месте (не разобрано). Подсказка (80%, 50%, 50%) совпадает со смыслом.
- Узел 42: константа кода 0.029, подсказка 6% (вероятно, накапливается по таблице `OnCacheOpenedChanceForSimilarItemsAmountWeights`, не разбиралось).

## 6. Исправления инструмента (затронули skill_node_effects.json)

1. `isil_sym.py`: `xorps xmm,[0x80000000-маска]` теперь даёт отрицание (раньше выражение `x ^ -0.0`). Это был дефект в 9 выражениях (3 в пассивках, 6 в скиллах).
2. `isil_sym.py`: арифметика `Subtract/Add/And/Or/Xor` теперь выставляет флаги (раньше `sub rcx,1; je` брал устаревшие флаги). Это дало корректный `switch(chosenMastery)` и поправило 7 скилловых узлов: Acid Flask Poison Pool (базовый кулдаун 6.0 стал 2.0, как в подсказке), Flay Cold/Necrotic/Poison Conversion (добавилась конверсия Bleed) и др.
3. `passive_tree_effects.py`: `typeof(C)` (float 2.0 @0x184561C38, коллизия имён Cpp2IL) заменяется на константу там, где выравнивание по asm не сработало (3 узла Knight, 1 узел Rogue). `EpochExtensions.safeQuotient(x)` = x (или 0.0001 при x == 0) сворачивается в выражение.
`skill_node_effects.json` пересчитан, 07c обновлён: auto 3568, auto_combined 212, auto_formula 29, conditional 2, manual 5, none 4.

## 7. Урон способностей, заданный кодом (`abilities_code_damage.json`)

Из 182 способностей игрока 54 без `damage[]`. «Урона нет в ассете» бывает трёх видов: урон ailment-а (в `ailments.json`), хит, собираемый в мутаторе, и урон под-способности.

| Способность | Откуда урон | База | ADE |
|---|---|---|---|
| Snap Freeze | `DamageEnemyOnHit` создаётся в `Mutate`, только если `addedColdDamage > 0` | Cold = 5 (узел) + 6 за очко (узел, до 5 очков), без узлов урона нет; крит 5%, множитель 2.0, Spell | 1.0 (константа) |
| Abyssal Echoes | ailment `AbyssalDecay` (id 12) и при узле `addedVoidSpellDamage = 60` хит | DoT Void 100 (Spell DoT, 5 с, макс. 1); хит Void 60 (Fire при конверсии) | DoT 5.0; хит 0.05·урон |
| Bone Curse | ailment `BoneCurse` (id 58): удар по проклятому врагу | Physical 4, крит 5% ×2, Spell Curse, 8 с; ×(1+2), если бьёт создатель (D?) | 0.2 |
| Spirit Plague | ailment `SpiritPlague` (id 59) | Necrotic 90, 3 с, Spell DoT Curse, спред 9 м; Intelligence × (узел) как added Spell Necrotic; `moreSpiritPlagueDamage` — множитель ailment | 4.5 |
| Aura of Decay | `Poison` (id 7) каждые 0.25 с в радиусе 4 | Poison 28 за стак, 3 с, added-урон не действует | 0 |
| Anomaly | `TimeWave` (AbilityID 368) и ailments `TimeRot` (id 9), `FutureAttack` (id 10) | Void 100 / Void 60 за стак / Void 60 | 2.5 / 0 / 0 |
| Focus | `FocusMutator` и `FocusEndMutator` | Lightning = 12% макс. маны за очко; в конце: мана × 0.25 за очко | 0.05·урон |
| Warcry | `addedPhysicalSpellDamage` | Physical 40 за очко (Cold при конверсии) | 0.05·урон |
| Shift | урон по пути рывка | Physical `addedTravelDamage = 2` при милли-оружии | 1.0 |
| Healing Hands | `setBaseDamage` при `dealsDamage` | Fire 40 (D?) плюс added за 20% healing | 0.05·урон = 2.0 |

Формулы `addBaseDamage`, `setStandardVariables`, `calculateAddedDamageScaling` (06b §1.7) подтверждены: ADE = `isWeapon ? 1.0 : 0.05 × Σ базового урона`; хит получает крит 5% и ×2.0, не-хит получает тег DoT. Остальные способности без урона — бафы, перемещения и призыв (урон у миньонов, 07d); список в JSON (`noDirectDamage`).

## 8. Значение `AbilityRef` по умолчанию (D)

`AbilityRef` — структура `{long key @0x0; Ability ability @0x8}` без инициализаторов полей. Для `default(AbilityRef)` ключ равен 0, а `GetAbility()` вызывает `AbilityManager.GetAbilityFromKey(0)`: `Dictionary.TryGetValue` не находит ключ и возвращается null. Среди 1044 способностей нет ни одной с ключом 0. Конструкторы: `AbilityRef(long)` и `AbilityRef(Ability)` (ключ берётся через `GetKeyForAbility`). **Ключ Fireball (−648846322) в сериализованных данных не следует из кода**: это значение, записанное в префаб при авторинге. Поэтому вывод 07b (считать ключ Fireball у компонента, не связанного с Fireball, пустым) верен, но причина не кодовый дефолт.

## 9. Не удалось установить

1. Поля `TheWeaver.WeaversWillLuckyRollChancePerPointAllocated` (+0x90) и `RareEnemiesChanceToWeaversWillItemPerPointAllocated` (+0x94): сериализуются в ассете (не найден), значения из подсказки.
2. Веса рангов наград Weaver (узлы 6/7/8) и таблица узла 42.
3. 60 из 67 `ability_property`-эффектов пассивок не имеют имени поля в `ability_property_fields.json` (в таблице нет этих пар).
4. Условные и триггерные эффекты в полях `CharacterMutator.*` (шансы, пороги, «per N attribute»): значения есть, но семантика срабатывания в методах `CharacterMutator` (`usedIn` в `player_property_fields.json`).
5. Snap Freeze: «Lightning Damage Per Second Of Freeze» требует длительность заморозки из префаба `FreezeEnemyOnHit` (не извлекалась); у Focus не уточнён интервал применителя (`increasedChannellingLightningDamageFrequency`).
6. Healing Hands: константа 40.0 (@0x184561E0C) принята без повторного чтения, условия moreDamage не прослежены.
7. Дополнительный урон, который код добавляет способностям с уроном в префабе (Meteor, Flay, Disintegrate, Black Hole и др.): не извлекался (список в JSON).
8. Для 8 узлов (§4) подсказка и код расходятся; код авторитетен для движка, но что показывает игра при этом, не проверено.