# 07b — Способности игрока и деревья (скиллы, пассивки, Weaver) из ассетов LE 1.5.0

Источник: бандлы клиента `StreamingAssets/LEAssetBundles` (26 667 файлов). Читались напрямую через UnityPy: typetree встроены в бандлы. Сервер AssetRipper не использовался. Все скрипты перезапускаются после патча (порядок см. §6).

## 0. Коротко
- **Способности.** В `PermaLoad.bundle` лежат 4349 ассетов `Ability`. Из них 1044 связаны с игроком (категории описаны в §2.1), остальные 3305 вынесены в индекс монстров.
- **Где урон.** Базовый урон, крит, ADE и шансы айлментов **не хранятся в ассете `Ability`**. Они в префабе способности (`Ability.abilityPrefabSoftRef`), в компонентах `DamageStatsHolder` (`DamageEnemyOnHit` и др.) и `ChanceToApplyAilmentsOnHit`. Из 1044 префабов 989 лежат в `PermaLoad.bundle`.
- **Структура деревьев.** `Global Tree Data` задаёт структуру 150 деревьев: 144 скилловых, 5 пассивных и Weaver.
- **Где значения узлов.** Значения по узлам хранятся в компонентах `SkillTreeNode` / `WeaverTreeNode` UI-префабов деревьев. Это 176 бандлов, у каждого скилла свой. Для пассивок узлы лежат в 20 префабах-панелях мастерств.
- **Сверка.** С LE Tools и Maxroll данные совпадают практически полностью (§5).

## 1. Где лежат данные

| Что | Где | Класс / поле |
|---|---|---|
| Параметры способности (тайминги, скорость, мана, CD, теги, scaling) | `PermaLoad.bundle` | `Ability` (ScriptableObject) |
| Список способностей игрока | `PermaLoad.bundle`, ассет «Ability Manager» | `AbilityManager.playerAbilities` (184, из них 183 непустых, Focus повторяется) |
| Таблица AbilityID → ассет | там же | `AbilityManager.abilities[i]` = AbilityID `i` (enum `AbilityID`, 994 значения) |
| Ключ способности | там же | `AbilityManager.keyedArray[{ability, key}]`. На ключ ссылаются `AbilityRef{key}` в мутаторах и префабах |
| Урон, крит, ADE, айлменты | префаб способности. Soft ref → `AssetBundle.m_Container` → бандл + pathID. все 1044 префаба найдены: 989 в PermaLoad, 55 в `assets_*.bundle` | компоненты с полем `baseDamageStats` (подклассы `DamageStatsHolder`), `ChanceToApplyAilmentsOnHit.ailments[]` |
| Миньоны | префаб призыва → `SummonEntityOnDeath.ActorReference` → `ActorData` (PermaLoad) → `ActorData.ActorSoftRef` → префаб актёра | способности миньона: `AbilityList.abilityRefs[]`, `*Mutator.abilityRef`, `CastSpeedManager.overrides[]` и т. п. |
| Дефолты мутаторов игрока | `assets_d7321f5c187fdc63.bundle` (префаб игрока: единственный бандл с `UsingAbilityPlayer`) | 600 компонентов `*Mutator` |
| Структура деревьев | `PermaLoad.bundle`, «Global Tree Data» | `GlobalTreeData.skillTrees[144] / passiveTrees[5] / weaverTree` |
| Значения узлов | UI-префабы деревьев (§1.1) | `SkillTreeNode.stats[]` (`NodeTooltipStat`), `SkillTreeNode.nodeStats[]` (`AutomaticNodeStat`) |
| Названия категорий подсказок | «Node Tooltip Property List» (PermaLoad) | `NodeTooltipPropertyList.properties[150]` |
| Какие панели пассивок реально используются | PermaLoad, `PassivePanelData.classResources[].masteryPanels[]` | soft ref на 20 префабов `PassiveTree<Class>_Mastery<0..3>` |

**Soft ref → бандл.** Поле `SoftRef.guid {_0, _1}` (два ulong) превращается в ключ `m_Container` бандла так: `"%016x%016x" % (_0, _1)`. Проверено на всех 1044 префабах способностей, 20 панелях и 59 актёрах-миньонах. Ключи всех бандлов собраны в `dump/assets/bundle_index.jsonl`.

### 1.1 Бандлы с деревьями
Полный список: `research/data/game/tree_ui_sources.json` (поле `bundles`).
- **Скилловые деревья: 136 бандлов, по одному на дерево.** Компонент `<Skill>Tree` / `<Skill>SkillTree : SkillTree` с полями `treeID`, `version`, `ability`, `nodeList`. Примеры:
  - Fireball `fi9` → `assets_66d2336bd98608aa.bundle`;
  - Flame Reave → `assets_66f3ad81937aecba.bundle`;
  - Swarmblade → `assets_4b3ca2487b37f89c.bundle`.
  Ещё одна копия Dreamslash лежит в тестовой сцене `scene_Testing_Funtimes_Zone_unity.bundle`; она отброшена.
- **Пассивки.** Корневые компоненты `KnightTree` / `AcolyteTree` / `MageTree` / `PrimalistTree` / `RogueTree : CharacterTree` хранятся в `assets_6e80c7b01b3ea527` (kn-1), `assets_ece0c7bdeb7dd87f` (ac-1), `assets_0e889347fa33eb0a` (mg-1), `assets_8db0c9701e1ffc53` (pr-1) и `assets_a5a8b4de4c31ccfe` (rg-1). Их `nodeList` пуст.
  - Узлы лежат в 40 бандлах `PassiveTree<Class>_Mastery<N>`, по 2 копии каждой панели. Ссылка `SkillTreeNode.tree` у этих узлов равна null.
  - Нужную копию выбирает `PassivePanelData`: используются `masteryPanels`, а `masteryNodes` — это превью с устаревшими значениями (например, у mg-1:93 там 1% вместо 1.5%).
  - Пустые копии `*Tree` в PermaLoad без узлов игнорируются.
- **Weaver.** `LE.Factions.WeaverTree` + 80 `LE.Factions.WeaverTreeNode` лежат в `assets_39f854b235462baf` и в такой же копии `assets_73fcfbbb45576562`. У UI version 10, в GTD version 9.
- **Устаревшие деревья.** 8 деревьев из GTD без UI, у всех version 0: Fire Shield `fs11`, Thorn Burst `tb47`, Ice Ward `is58`, Mark For Death `md26kh`, Manifest Weapon `mw26fp`, Ephemeral Stance `of28ur`, Abyssal Echoes (пустой treeID; актуальное дерево `ab0lh`), Bladestorm `bs6d9` (актуальное `bl5st`). Это старые деревья.
- **Узлы только в UI.** В 43 деревьях 62 узла есть в UI `nodeList`, но отсутствуют в GTD (например, `ah443` 73–75 и `srk21` 14/26/32). Вероятно, это отключённые узлы. В выходе они перечислены в `uiOnlyNodes`.

### 1.2 Как узлы дерева превращаются в статы (связь с 06a §7.2–7.3)
1. **`AutomaticNodeStat` (`nodeStats`).** Это реальные статы, которые применяет `LocalTreeData.UpdateGlobalStatsFromTree`.
   - Они есть только у **31 узла в UI** и у **32 узлов в GTD `nodeStatsData`**. Всё это скилловые деревья.
   - У пассивок и Weaver их **нет вообще**.
2. **Остальное задаёт код.** Это `<Skill>Tree.updateMutator` и `<Class>Tree.updateMutator` (у `KnightTree.updateMutator` Ghidra упала по таймауту, функция огромная). Ассеты содержат только **подсказку** `NodeTooltipStat`:
   - `statName`;
   - `value` — строка **на одно очко**, если не задано `noScaling`;
   - `property`, `tags`, `downside`, `noScaling`.
3. **Подсказка совпадает с кодом.** Для Fireball (константы 06a §7.3) значения подсказок совпадают с константами кода:
   - Winged Fire «+7%» Damage = more 0.07·p;
   - Mana Sphere +3% = 0.03·p;
   - Immolated Core +10% pen;
   - Conflagration +30% ignite;
   - Magma Shell +15% fire res;
   - Plasma Ball +35% crit multi.

   Поэтому `tooltipStats` — надёжный источник **величин**. **Тип** модификатора (added / increased / more, глобально или на скилл) определяется только по коду. Этим занимается `tools/extract/mutator_coeffs.py` другого агента, выход `skill_node_effects.json`.
4. **Кодировка `NodeTooltipStat.property` (ushort)**, выведена из `NodeTooltipPropertyList.GetStatPropertyName` @ `NodeTooltipPropertyList.c`, **D**:
   - `< 5000` — SP;
   - `5000..9999` — `NodeTooltipPropertyList.properties[p−5000]`, например 5000 «Extra Projectiles»;
   - `≥ 10000` — `AilmentID` (`p−10000`), например 10001 Ignite. Эту ветку подтверждают данные; код подсказки не прослежен.

   `property = 54` (SP.None) означает строку только для отображения.

## 2. Схемы файлов (`research/data/game/`)

### 2.1 `abilities.json`
Массив из 1044 записей, отсортирован по категории, затем по имени.

**Категории** (`category`):
- `player` (182) — `AbilityManager.playerAbilities`, способности `CharacterClass` (known, default, unlockable, мастерства), корневые способности деревьев.
- `nodeGranted` (189) — `SkillTreeNode.abilityGrantedByNode`. Это способности, которые узел вызывает или на которые ссылается: Flame Burst, Spreading Flames и т. п.
- `sub` (177) — замыкание по ссылкам:
  - поля `Ability` (`replacementAbility`, `comboAbilities`, `sharedCooldownAbilities`…);
  - PPtr и `AbilityRef{key}` в компонентах префаба и во вложенных префабах (soft ref);
  - мутаторы игрока.
- `minion` (56) и `minionSub` (7) — способности префабов 59 актёров-миньонов, которых призывают способности игрока.
- `abilityIdOnly` (433) — есть в enum `AbilityID` (`AbilityManager.abilities`), но из ассетов не достигаются. Их вызывает код по AbilityID: проки уникальных предметов, пассивок, Weaver. Но среди них есть и монстровые (например, `Majasa Boss 07p3 …`).
  - По `itemDB.triggeredAbilities` из LE Tools: 85 AbilityID срабатывают с предметов. 29 из них попали в `abilityIdOnly`, остальные уже в player/sub/nodeGranted.
  - Пометка `abilityIdOnly` значит «используется кодом», а не «монстр».

**Поля:**
- **Идентификация:**
  - `pathID` — PathID ассета в PermaLoad, стабилен внутри билда;
  - `key` — `keyedArray.key`;
  - `name` — m_Name, ключ у Maxroll;
  - `abilityName`;
  - `playerAbilityID` — ID дерева и ключ LE Tools, например `fi9`;
  - `abilityIDEnum {value, name}`;
  - `reasons[]`, `parents[]`, `minionActors[]`, `classes[]`;
  - `skillTree` — treeID или `treeID:nodeID` для nodeGranted.
- **Теги:**
  - `tags` (маска AT) + `tagNames`;
  - `fakeTags`;
  - `skillTreeConversionDamageTags` + `…Names`.
- **Скорость** (06e §1):
  - `useDelay`, `useDuration`, `hasMinimumUseDuration`, `minimumUseDuration`;
  - `speedScaler` (SP: 2 AttackSpeed, 3 CastSpeed, 54 None) + `speedScalerName`. Отдельного «throw speed» нет: метательные атаки используют AttackSpeed без множителя скорости оружия (06e §1.2);
  - `speedMultiplier`, `maximumUseSpeed`, `speedScalerAppliedAsIncrease`, `speedScalerEffectiveness`, `instantCastForPlayer`.
- **Мана и канал:**
  - `manaCost`, `minimumManaCost`, `freeWhenOutOfMana`, `manaCostPerDistance`;
  - `channelled`, `channelCost`, `noManaRegenWhileChanneling`, `channelTimeLimit`.
- **Перезарядка:**
  - `maxCharges`, `chargesGainedPerSecond`;
  - `cooldown` — производное: `1/chargesGainedPerSecond`, без статов;
  - `sharedCooldown`.
- **Флаги:**
  - `companion`, `minionsUseAbility`, `isTransform`, `traversalSkill`, `evadeSkill`, `countsAsMovementAbility`;
  - требования к оружию: `requireWeaponType`, `permittedWeaponTypes`, `requiresSheild`, `requiresDualWielding`.
  - Миньон- и тотем-способность определяется по `tagNames` (Minion / Totem) и по категории.
- **Масштабирование:**
  - `attributeScaling [{attribute, stats:[Stat]}]` и `levelScaling [{stats}]` — в формате игрового `Stats.Stat`: property, specialTag, tags, extraTag, addedValue, increasedValue, moreValues;
  - `statsDuringUse`, `statsSource`.
- **Префаб:** `abilityPrefab {key, bundle, root, error}`. `key` — ключ m_Container (soft ref).
- **`damage[]`** — каждый компонент урона в префабе, включая дочерние объекты:
  - `class`, `go` (путь объекта);
  - `damage[7]` в порядке Phys, Fire, Cold, Lightning, Necrotic, Void, Poison, плюс `damageByType`;
  - `critChance`, `critMultiplier`, `critType`, `isHit`, `addedDamageScaling` (ADE);
  - `cullPercent`, `increasedStunChance`, `freezeRate`, `additionalLeech`;
  - `convertAllAddedDamage`, `damageTypeToConvertTo`, `penetration[]`, `conditionalEffects[]`;
  - `damageTags` + `damageTagNames`, `damageModifier`, `distanceScaling`;
  - `other` — скаляры компонента, например интервал у `Repeatedly…`;
  - `nestedPrefab` — если компонент найден во вложенном префабе.
- **`primaryDamage`** — первый компонент урона (для удобства).
- **`ailmentsOnHit[]`:** `{class, go, ailments:[{ailment(имя Ailment), chance, rolledSeparately, damageModifier, increasedDuration, increasedEffect}], other}`. Сюда попадают все компоненты с полем `ailments` (ailment PPtr), то есть и аура- / радиус-аппликаторы.
- **`summons[]`:** `{actor, actorName, field, go}`.
- **`subAbilities[]`.**
- **`mutator`:** `{class, bundle, matchedBy?, nonZeroDefaults, statLists}`.
  - Это сериализованные дефолты мутатора игрока, у большинства полей нули: их выставляют деревья.
  - Привязка мутатора к способности: по `abilityRef.key` (50 случаев) или по имени класса (`FireballMutator` → `Fireball`, `matchedBy:"className"`). Всего 150.
- **Текст:** `description`, `altText`.

### 2.2 `monster_abilities_index.json`
3305 записей `{pathID, key, name, abilityName, playerAbilityID|null}`. У части монстровых копий заполнен `playerAbilityID`: монстры переиспользуют игровые ID.

### 2.3 `minion_actors.json`
59 записей `{actorData, actorName, id, actorBundle, summonedBy[], abilities[]}`, например `PrimalWolf ← SummonWolf | [PrimalWolf 01 melee, BasicEnemyMelee]`.

### 2.4 `trees.json`
150 деревьев: `{kind: skill|passive|weaver, name, treeID, version, uiBundle, uiClass, panelBundles[] (пассивки), ability{name, playerAbilityID, pathID} (скилл), classes[{className, classID, masteries[]}] (пассивки), uiOnlyNodes[], nodes[]}`.

Поля узла:
- `id`, `name` (внутреннее имя из GTD, по нему `updateMutator` переключается), `displayName`;
- `maxPoints`, `requiredMastery`, `masteryRequirement`, `requirements[{nodeID, requirement}]`;
- `description`;
- `position` — `RectTransform.anchoredPosition` в своей панели. Совпадает с Maxroll `transform`; корень у Maxroll смещён на (0.23, −0.80);
- `panel` (родительский GameObject), `mastery` (из UI), `noScalingType` (0 SinglePoint, 1 PointThreshold), `noScalingPointThreshold`;
- `abilityGrantedByNode` (для Weaver `nodeEffect`), `hasUI`, `notInUINodeList`, `uiMismatch` (сейчас 0 случаев).

Структура (maxPoints, requirements, mastery) взята из GTD, это авторитетный источник: его использует `LocalTreeData`. UI-поля добавлены сверху.

### 2.5 `tree_node_stats.json`
Объект с ключом `"<treeID>:<nodeID>"`, 4725 узлов. Подсказки есть у 4423 узлов, всего 8038 строк статов.

Поля записи:
- `treeID`, `treeKind`, `nodeID`, `nodeName`, `displayName`, `maxPoints`;
- `noScalingType`, `noScalingPointThreshold`;
- `description`, `nodeDescription` (старое описание, значения в нём могут быть устаревшими), `pointBonusDescription`, `altText`;
- `automaticStats[]` — `AutomaticNodeStat` из UI: `{property, specialTag, tags, extraTag, modType, value, scaling, threshold}`;
- `globalTreeDataStats[]` — то же из GTD `nodeStatsData`;
- `tooltipStats[]` — `{statName, value, noScaling, downside, property, tags, tagNames, overrideSprite, icon, propertyKind: SP|TooltipList|Ailment, propertyName, num, unit (%, #, s, x, m или null), explicitSign}`. `num` — число на очко;
- `propertiesForAltText[]`.

### 2.6 Служебные файлы
- `tree_ui_sources.json`: выбранные бандлы, дубликаты, отброшенные копии.
- `dump/assets/bundle_index.jsonl`: индекс **всех** 26 665 бандлов. Строка: `{bundle, size, files:[{cab, externals, classes{}, scripts{класс: число}, container[{key, pathID, class, name}]}]}`.
  - Индекс строится за **63 с** (20 процессов): читаются только заголовки SerializedFile и `script_types`, данные объектов не парсятся.
  - Его стоит переиспользовать другим агентам для поиска любого класса в бандлах.

## 3. Скрипты (`tools/extract/`)
| Скрипт | Что делает |
|---|---|
| `bundle_index.py` | Индекс бандлов (multiprocessing, в памяти один бандл на процесс) |
| `common.py` | Пути, `load_scripts` (pathID MonoScript → класс из monoscripts.bundle), `open_bundle`, `script_class`, `softref_key`, `BundleIndex` |
| `extract_trees.py` | Строит `trees.json`, `tree_node_stats.json`, `tree_ui_sources.json` (около 10 с) |
| `extract_abilities.py` | Строит `abilities.json`, `minion_actors.json`, `monster_abilities_index.json` (около 25 с). Нужен `trees.json` |
| `jslit.py` | Парсер JS-литералов LE Tools (только для сверки) |
| `crosscheck_abilities_trees.py` | Сверка с Maxroll `data.json` и LE Tools `planner/js/<md5>.js`. Пути к файлам передаются аргументами, сторонние данные в репозиторий не кладутся |

Порядок после патча: `bundle_index.py` → `extract_trees.py` → `extract_abilities.py` → (по желанию) `crosscheck_abilities_trees.py`.

## 4. Тонкости, найденные при извлечении
- **`AbilityRef{key}`.** Мутаторы и многие компоненты ссылаются на способность не через PPtr, а через ключ из `keyedArray`. Неустановленный `AbilityRef` сериализуется ключом **Fireball** (AbilityID 1, key −648846322).
  - Без фильтра Fireball «использовали» 11 миньонов (`BasicMeleeMutator.abilityRef`) и Ice Rune.
  - Одиночное поле с этим ключом на компоненте, не связанном с Fireball, считается пустым (**D?**).
- **Мутаторы.** У 500 из 600 мутаторов на префабе игрока `abilityRef.key = 0`: способность привязывается в коде, отсюда эвристика по имени класса. Мутаторы боссов и монстров (в других бандлах) исключены.
- **Урон, заданный в коде.** У части скиллов в ассетах **нет урона**: Anomaly, Snap Freeze, Abyssal Echoes, Bone Curse, Spirit Plague, Aura of Decay. Урон у них идёт от айлментов или задаётся кодом (`setBaseDamage` в мутаторе, 06b §1.7).
  - У многих скиллов урон лежит в под-способностях. Например, Meteor → `MeteorAoe` 240 fire, ADE 12; Glacier → `Glacier1..3`.
  - Связи «скилл → под-способность» есть в `subAbilities` и `parents`.
- **`abilityGrantedByNode`** заполнен у 805 узлов. Это скорее «связанная способность для подсказки», чем выдача нового скилла.
- **Две копии панелей пассивок отличаются значениями.** Брать нужно `PassivePanelData.masteryPanels` (§1.1).

## 5. Сверка с LE Tools (version150) и Maxroll (data.json от 2026-10-02)
Сравнивались все пересекающиеся записи, а не выборка.

| Сравнение | Объём | Расхождения |
|---|---|---|
| Способности vs LE Tools (по `playerAbilityID` / `internalName` = AbilityID): tags, manaCost, channelCost, minimumManaCost, useDelay, useDuration, speedScaler, speedMultiplier, maxCharges, chargesGainedPerSecond, skillTreeConversionDamageTags, attributeScaling; урон корневого префаба (damage[7], crit, critMulti, ADE, isHit) | 555 способностей, 330 с уроном | **0** |
| Способности vs Maxroll (по m_Name): те же поля + шансы айлментов | 567 способностей, 337 с уроном | 42. Все 42 — компоненты, которые Maxroll не экспортирует: DoT- и аура-компоненты с `isHit=0` (Black Hole 48 cold ADE 2.4, Tornado 9 phys ADE 0.45, Infernal Shade, Devouring Orb DoT 5 void…), а также аппликаторы айлментов в радиусе (Aura of Decay Poison, Smoke Bomb Blind/Haste…). **Ошибок в общих полях нет** |
| Список playerAbilities vs Maxroll `playerAbilityList` | 183 | 0 |
| Скилловые и пассивные деревья vs Maxroll: maxPoints, masteryRequirement, displayName, requirements, все строки подсказок (value, property, tags), позиции | 142 дерева, 4577 узлов | 1: позиция корня `vo54` (смещение Maxroll 0.23 / −0.80) |
| Скилловые деревья vs LE Tools (`LESkillTrees` + UI) | 136 деревьев, 3956 узлов | 4 позиции (до 9 px: LE Tools хранит `rect` с другой опорной точкой) |
| Пассивки vs LE Tools (`LECharTrees`) | 5 деревьев, 541 узел | 0 |
| Weaver vs LE Tools | 80 узлов | 1: узел 191, первая строка подсказки: у нас `''`, у LE Tools `'50%'`. LE Tools, вероятно, подставляет значение сам |

Проверенные вручную примеры (совпадают с LE Tools, урон в порядке Phys, Fire, Cold, Light, Necr, Void, Poison):

| Способность | Урон | Крит | ADE | Длительность / скорость | Мана / CD |
|---|---|---|---|---|---|
| Fireball | Fire 25 | 5% | 1.25 | 0.75 Cast | 3 |
| Lightning Blast | Light 21 | | 1.0 | | |
| Smite | Fire 30 | | 1.5 | | 3 |
| Volcanic Orb | Fire 40 | | 2.0 | | 50 мана, CD 3.03 |
| Static | Light 50 | | 2.5 | | CD 4 |
| Javelin | Phys 50 | | 2.5 | 1.2 | 9 |
| Shurikens | Phys 25 | | 1.25 | | |
| Shield Throw | Phys 45 | | 2.25 | | |
| Hammer Throw | Phys 22 | | 1.1 | | |
| Heartseeker | Phys 20 | | 1.0 | | |
| Multishot | Phys 6 | | 1.2 | | |
| Rip Blood | Phys 20 | | 1.0 | | |
| Marrow Shards | Phys 25 | | 1.25 | | |
| Disintegrate | Fire 12 + Light 12 | 50% | 1.2 | 0.2 | CD 0.8 |
| Ghostflame | Fire 17.5 + Necr 17.5 | 50% | 1.75 | | |
| Forge Strike | Phys 2 | | 6.0 | | CD 4 |
| Erasing Strike hit | Void 2 | | 6.0 | | |
| Shadow Cascade | Phys 2 | 10% | 3.0 | | |
| Meteor (MeteorAoe) | Fire 240 | | 12 | | |
| Frost Claw main | Cold 20 | | 1.0 | | |
| Runebolt | Fire 25 | | 1.25 | | |
| Swipe | Phys 2 | | 1.0 | 0.7 | |
| Rive | Phys 2 | | 1.25 | | |
| Warpath hit | Phys 1 | | 0.6 | | |

## 6. Не удалось установить
1. **Тип модификатора и область действия узлов скилловых деревьев.**
   - Подсказка даёт только величину и SP / категорию. Added, increased или more, и куда пишется (поле мутатора или стат), задаётся кодом `*Tree.updateMutator`.
   - Это зона `mutator_coeffs.py` / 07c, выход `skill_node_effects.json`.
   - Для сверки там пригодится LE Tools `skillBonuses` / `passiveBonuses` (в том же planner.js): структурированные `{value, type 0/1/2, property, tags, per}` по узлам.
2. **Статы пассивных узлов в коде.** Узлы применяются в `<Class>Tree.updateMutator`, а `KnightTree.updateMutator` не декомпилировался (таймаут Ghidra). В ассетах есть только подсказки. Рабочая гипотеза: «increased»-строки — это INC, «+N» — ADDED; её нужно проверить по ISIL.
3. **Урон способностей, заданный кодом** (Anomaly, Snap Freeze, Abyssal Echoes, Bone Curse…). Искать `setBaseDamage` и `BaseDamageStats` в соответствующих `*Mutator` (ISIL).
4. **Полный список предметных проков.** Привязка «уникальный предмет → AbilityID» живёт в коде (PlayerProperty-обработчики) или в данных предметов. Из ассетов способностей она не выводится. Категория `abilityIdOnly` объединяет такие проки с монстровыми AbilityID. Разделить их можно через данные предметов (`uniques.json` другого агента) или по LE Tools `triggeredAbilities`.
5. **Иконки узлов.** `SkillTreeNode.icon` ссылается на Sprite во внешнем бандле (сохранено как `iconImage {cab, pathID}`), имя спрайта не разрешалось. Для строк статов есть имя иконки (`icon` = `subPath` soft ref).
6. **Статы самих миньонов** (здоровье, броня, урон базовых атак из `ActorData` и префабов актёров) не извлекались. Собраны только способности миньонов и бандлы их префабов (`minion_actors.json`).
7. **Значение дефолтного `AbilityRef`** (ключ Fireball) выведено эмпирически (**D?**). Подтвердить по конструктору `AbilityRef` в дампе.
8. **`nodeDescription`** — старое описание узла, значения в нём бывают устаревшими (Knight Vitality: «[10%]» против подсказки 5%). Использовать только `tooltipStats`.
