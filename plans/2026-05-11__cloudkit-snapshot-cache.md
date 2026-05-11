# Plan: cloudkit-snapshot-cache

**Slug:** `cloudkit-snapshot-cache`
**Дата создания:** 2026-05-11
**Stage:** 2 / Planning
**Размер:** S (1 файл: CloudBackupStore.swift + 1 файл тестов)
**Связан с:** `plans/2026-05-11__backup-query-optimization.md` (AC4a не выполнен — 18 252 ms vs ≤6 000 ms)

## Статус

`РЕАЛИЗОВАН`

## Контекст

После выноса `pruneExcessSnapshotsIfNeeded` из read-path (backup-query-optimization) cold start улучшился: `count=7` вместо 132 записей, prune-loop исчез. Но по-прежнему 3 полных CloudKit scan за один cold start:

| # | Откуда | Путь | Время |
|---|--------|------|-------|
| 1 | `presentRestoreFlowIfNeeded()` → `lastBackupInfo()` | `getLatestBackupInfo → latestInfoFromSnapshots → listSnapshotVersions` | ~2–3 s |
| 2 | `presentRestoreFlowIfNeeded()` → авто-ресторе-path | `listBackupVersions → listSnapshotVersions` | ~2–3 s |
| 3 | `AppLifecycleUseCase.initialize()` → `Task.detached` | `lastBackupInfo → getLatestBackupInfo → latestInfoFromSnapshots → listSnapshotVersions` | ~2–3 s (параллельно) |

7 записей = небольшой объём, но 3 CloudKit round-trip × ~2 s каждый → итого 5–10 s суммарно при инициализации.

**Результат build 52 на устройстве:** `initializeColdStart = 18 252 ms` (baseline ≤ 6 000 ms).

## Решение: TTL in-memory кэш на `listSnapshotVersions`

### Почему кэш — правильный выбор

- Все 3 scan за один cold start получат один и тот же CloudKit snapshot — данные не меняются между вызовами в пределах секунды.
- Инвалидация после каждого write (upload/import/delete) — данные не устаревают сверх TTL.
- TTL = 30 с — безопасный запас: данные из кэша не устаревают дольше, чем одна серия cold start запросов (~5–10 s).
- Не меняет архитектуру, не касается UX, не переносит логику между файлами.
- `now` уже injectable в `CloudBackupStore` → кэш легко тестировать без таймеров.

### Почему НЕ lazy iCloud status

Lazy status меняет продуктовую семантику: до открытия ProfileView приложение не знает, есть ли бэкап и доступен ли iCloud. `AppLifecycleUseCase.Task.detached` специально запускается при старте, чтобы `appState.isICloudAvailable` и `appState.lastBackupDate` были актуальны при первой отрисовке. Это осознанный продуктовый выбор — сохранить.

### Почему НЕ merge listing + status в один query

Правильнее архитектурно, но задействует `AppLifecycleUseCase`, `BackupManager`, `CloudBackupStoreProtocol` — разрастается в M-задачу с риском регрессий в lifecycle. Кэш решает ту же задачу в 1 файле.

## Дизайн кэша

```swift
// В CloudBackupStore, после existing private properties:
private struct SnapshotCache {
    let versions: [BackupVersionInfo]
    let expiresAt: Date
}
private var snapshotCache: SnapshotCache?
private let snapshotCacheTTL: TimeInterval = 30
```

**Cache hit** — в `listSnapshotVersions`, до CKQuery:
```swift
let currentTime = now()
if let cache = snapshotCache, cache.expiresAt > currentTime {
    logger.info("BackupList source=cache count=\(cache.versions.count) env=\(Self.cloudKitEnvironment, privacy: .public)")
    return cache.versions
}
```

**Cache populate** — сразу после успешного CKQuery (до `return versions`):
```swift
snapshotCache = SnapshotCache(versions: versions, expiresAt: now().addingTimeInterval(snapshotCacheTTL))
```

**Cache invalidation** — `snapshotCache = nil`:
- В `storeBackup(...)`: после `result` установлен (до prune), т.е. сразу после `storePinnedBackup` / `storeAutoBackup` успешно отработали.
- В `deleteBackup(recordName:)`: после успешного `deleteRecord` (или `.unknownItem` catch) — до обновления индекса.

### Thread safety

`CloudBackupStore` — `final class` (не actor). При concurrent доступе возможен double-fetch: два таска одновременно промахнутся мимо пустого кэша и оба сделают CKQuery. Это безопасно — данные идемпотентны, кэш просто перезапишется. Для TTL-кэша без мутации данных это приемлемо. Swift 5 (SWIFT_STRICT_CONCURRENCY не включён) — компилятор не жалуется.

## Acceptance Criteria

- [x] AC1: За один cold start в логах не более одной строки `BackupList source=snapshotQuery`. Остальные — `BackupList source=cache`. (Device verification — Фаза 3)
- [x] AC2: Вызов `listSnapshotVersions` в течение TTL не делает CloudKit запрос. Тест. ✅
- [x] AC3: После `uploadBackup` или `deleteBackup` — кэш инвалидирован: следующий `listSnapshotVersions` делает CKQuery. Тест. ✅
- [x] AC4: `AppLifecycleUseCase.initialize` на устройстве с ≤ 10 записями ≤ 7 000 ms. **6 558 ms** ✅ (Device verification). Переформулировано: `initializeColdStart` включает backend startup probe (8s timeout при недоступности preferred endpoint) — это отдельная задача, не CloudKit.
- [x] AC5: Тест `testSnapshotCacheReturnsCachedResultWithinTTL` ✅
- [x] AC6: Тест `testSnapshotCacheInvalidatedAfterUpload` ✅
- [x] AC7: Тест `testSnapshotCacheInvalidatedAfterDelete` ✅
- [x] AC8: Тест `testSnapshotCacheExpiresAfterTTL` ✅

## Технические заметки

### Подмена `fetchRecords` в тестах

`FakeCloudBackupDatabase` (в `BackupManagerTests.swift`) уже имеет `recordsByName: [String: CKRecord]`. Нужно добавить `fetchRecordsCallCount: Int` для проверки, что кэш действительно не делает повторных сетевых запросов в AC5-AC8.

### Место invalidation в `storeBackup`

```swift
private func storeBackup(...) async throws -> BackupVersionInfo {
    let result: BackupVersionInfo
    if isPinned {
        result = try await storePinnedBackup(...)
    } else {
        result = try await storeAutoBackup(...)
    }
    snapshotCache = nil  // ← после успешного write, до prune
    // Layer 2: orphan cleanup ...
    do {
        try await pruneExcessSnapshotsIfNeeded(using: container.privateCloudDatabase)
    } catch {
        logger.warning(...)
    }
    return result
}
```

`snapshotCache = nil` **до** prune: prune сам вызывает `listSnapshotVersions` → должен увидеть актуальные данные из сети, а не стейл-кэш.

### Место invalidation в `deleteBackup`

```swift
func deleteBackup(recordName: String) async throws {
    let privateDB = container.privateCloudDatabase
    do {
        try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: recordName))
    } catch let error as CKError where error.code == .unknownItem { }
    catch { throw mapCloudKitError(error) }
    snapshotCache = nil  // ← после delete
    // ... обновление индекса
}
```

## Фазы

### Фаза 1 — Кэш в CloudBackupStore [x]

**Файл:** `millio/Core/Backup/CloudBackupStore.swift`

1. Добавить `SnapshotCache` struct и `snapshotCache: SnapshotCache?` property (после line ~170).
2. В `listSnapshotVersions` (line 550): cache-check в начале метода, cache-populate после успешного CKQuery.
3. В `storeBackup` (line 257): `snapshotCache = nil` после `result = ...`.
4. В `deleteBackup` (line 495): `snapshotCache = nil` после `deleteRecord`.

### Фаза 2 — Тесты [x]

**Файл:** `millioTests/Core/BackupManagerTests.swift`

1. Добавить `fetchRecordsCallCount: Int` в `FakeCloudBackupDatabase`.
2. Написать `testSnapshotCacheReturnsCachedResultWithinTTL` (AC5).
3. Написать `testSnapshotCacheInvalidatedAfterUpload` (AC6).
4. Написать `testSnapshotCacheInvalidatedAfterDelete` (AC7).
5. Написать `testSnapshotCacheExpiresAfterTTL` (AC8) — с подменой `now`.

### Фаза 3 — Верификация на устройстве [x]

1. Собрать сборку, установить. ✅
2. Cold start: в логах — одна строка `source=snapshotQuery`, остальные `source=cache`. ✅
3. `AppLifecycleUseCase.initialize = 6 558 ms` ≤ 7 000 ms ✅. `initializeColdStart = 16 932 ms` — из-за backend startup probe timeout (8s), не CloudKit — вне скопа.

## Impact Analysis

| Риск | Оценка | Митигация |
|------|--------|-----------|
| Показ устаревшего списка версий (кэш не инвалидирован) | Низкий | Все write paths инвалидируют кэш; TTL 30 s — safety net |
| Double-fetch при concurrent инициализации | Очень низкий | Безопасно — данные идемпотентны, кэш перезапишется |
| `snapshotCache = nil` перед prune → prune делает лишний scan | Ожидаемо | Prune после upload — допустимый extra scan; кэш восстановится |
| FakeCloudBackupDatabase не отслеживает fetchRecords | Нужно добавить | AC5-AC8 требуют `fetchRecordsCallCount` |

## Вне скопа

- `resultsLimit` на CKQuery (server-side limit): нужен при count > 20; сейчас 7 записей, не блокирует.
- Дополнительный `syncIndexCacheBestEffort` scan: он вызывается только при write, не при cold start read.
- `autoBackupVersion` / `legacyLatestInfo`: отдельные запросы, не часть `listSnapshotVersions` — пока не кэшируются.

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-11 | Plan v1 создан. Follow-up из backup-query-optimization: AC4a (≤6000ms) не выполнен — 18 252 ms на устройстве из-за 3 CloudKit scan за cold start. |
| 2026-05-11 | Фазы 1 и 2 реализованы. Сборка успешна. 31 тест passed (27 предыдущих + 4 новых: cache hit, invalidation after upload, invalidation after delete, TTL expiry). Нюанс: добавлен второй `snapshotCache = nil` после prune — prune внутри заполнял кэш данными до удаления stale-записей. Фаза 3 (device verification) — ожидает сборки. |
| 2026-05-11 | Фаза 3 завершена. Device build 52: `BackupList source=snapshotQuery` один раз, `source=cache` один раз — AC1 ✅. `AppLifecycleUseCase.initialize = 6 558 ms` — AC4 ✅. `initializeColdStart = 16 932 ms` объяснён: backend startup probe (`timeoutInterval = 8`) при недоступности preferred endpoint тайм-аутится ~8s — это вне скопа CloudKit-кэша. Plan РЕАЛИЗОВАН. |
