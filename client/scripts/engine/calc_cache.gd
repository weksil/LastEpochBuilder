class_name CalcCache

## Memoization of engine results that are pure functions of the build state (docs/ENGINE.md §11). A key is the binary
## serialization (var_to_bytes: exact, several times faster than var_to_str) of every Build field the calculation reads
## plus the locale (mod sources are translated), so a temporary change of the build (EnemyAilments.apply, ItemCompare
## snapshots, a skill input switched for a moment) gets its own entry and an edit never sees a stale value. Cached
## values are shared: callers must not modify them (StatMods are never changed after they are put into a store).
## Game data (GameData, model tables) is assumed fixed: code that changes it at run time (tests) calls clear().

## Entries kept per bucket; a full bucket is emptied (the UI works with a handful of build states at a time).
const LIMIT: int = 64

## Off: every call recomputes (tests compare both ways).
static var enabled: bool = true
static var _buckets: Dictionary = {}


## The build state the engine reads: class, level, passives, skills (trees, inputs), items, blessings, enemy, player
## state, defense settings, and the locale.
static func build_key(build: Node) -> PackedByteArray:
	return var_to_bytes([build.class_id, build.mastery, build.level, build.quest_passive_points, build.passives, build.skills,
		build.items, build.blessings, build.enemy, build.player_state, build.defense, TranslationServer.get_locale()])


## Cached value of `key` in `bucket`, null when absent (or the cache is off).
static func lookup(bucket: String, key: Variant) -> Variant:
	if not enabled:
		return null
	var b: Dictionary = _buckets.get(bucket, {})
	return b.get(key)


static func put(bucket: String, key: Variant, value: Variant, limit: int = LIMIT) -> void:
	if not enabled:
		return
	if not _buckets.has(bucket):
		_buckets[bucket] = {}
	var b: Dictionary = _buckets[bucket]
	if b.size() >= limit:
		b.clear()
	b[key] = value


static func clear() -> void:
	_buckets.clear()
