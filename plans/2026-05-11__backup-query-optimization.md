# Plan: backup-query-optimization

**Slug:** `backup-query-optimization`
**Дата создания:** 2026-05-11
**Stage:** 1 / Design
**Размер:** M (3–5 файлов: CloudBackupStore.swift, BackupManagerTests.swift + возможно millioApp.swift)
**Связан с:** `plans/2026-05-10__backup-diagnostics.md`, `improvements/process/2026-05-11__backup-query-regression.md`

## Статус

`РЕАЛИЗОВАН`

## Контекст и корневая причина

### Что произошло (диагноз)

После включения `snapshotQuery` как primary source (backup-diagnostics Фаза 2) cold start вырос с ~6с до ~30с.

**Причина не в query.** Причина — `listBackupVersions()` (line 468) вызывает `pruneExcessSnapshotsIfNeeded()` в первой строке (line 470). До фикса recordName queryable snapshotQuery не работал в Production → pruning всегда пропускался. После фикса впервые увидел все 132 AppBackup-записи, вычислил 125 stale и удалил их в `for` loop серийно. 125 сетевых roundtrip = 25–30 секунд на cold start.

Прогон уже произошёл; 125 orphan-записей удалены; следующий cold start должен вернуться к норме. Но архитектурный дефект остаётся.

### Структурный дефект

`listBackupVersions()` — это read-path. Он начинается с destructive write/delete side effect. Это нарушает KISS и предсказуемость: пользователь открыл экран — приложение удаляет CloudKit-записи.

### Двухуровневая retention — как работает сейчас

Сейчас в коде фактически два retention-механизма, но это нигде не названо явно:

**Layer 1 — Index-based retention (fast normal path):**
`storePinnedBackup` (line 312) и `storeAutoBackup` (line 372) — после каждого нового snapshot вызывают `mergeIndexEntries` + `deleteRecord` для stale-записей по индексу. Работает через индекс: знает только о записях, которые сам создавал/отслеживал.

**Layer 2 — Full snapshotQuery orphan cleanup:**
`pruneExcessSnapshotsIfNeeded` (line 623) — полный scan CloudKit через snapshotQuery, находит orphan-записи вне индекса (созданные старыми версиями логики, другими устройствами, migrated records и т.д.). Нужен, но не должен запускаться при каждом listing.

### 3 полных snapshotQuery scan за запуск

В логах build 51 `BackupList source=snapshotQuery` появляется **трижды** за один холодный старт. Это происходит потому что `listSnapshotVersions` вызывается из `pruneExcessSnapshotsIfNeeded` + из `listBackupVersions` + из отдельного iCloud status refresh.

После удаления pruning из list-path останутся минимум 2 scan (list + status). Это вторичная проблема — адресуется отдельно (см. секцию «Вне скопа»).

## Цель

Вынести destructive maintenance из read-path. `listBackupVersions` = чистый read. Prune = явный write-triggered maintenance после upload/import.

## Acceptance Criteria

- [x] AC1: `listBackupVersions()` не вызывает никаких write/delete операций в CloudKit. Метод — pure read. Верифицируется тестом (AC5).
- [x] AC2: `pruneExcessSnapshotsIfNeeded` вызывается только после успешного `uploadBackup` или `importBackup`. Вызов awaited в той же task-цепочке, best-effort (catch + warn, не rethrow). Upload/import считается успешным по завершении snapshot-записи, независимо от результата prune.
- [x] AC3: Если prune завершается ошибкой — ошибка логируется как warning, upload не откатывается и не выбрасывает ошибку наружу.
- [ ] AC4a: Cold start (устройство) с ≤ 10 записями в CloudKit — `initializeColdStart` ≤ 6000 ms (прежний baseline). (Верификация на устройстве — Фаза 3)
- [x] AC4b: Вызов `listBackupVersions()` при 100+ записях в mock-базе — `deleteRecord` не вызывается ни разу. Listing не блокирует на 30 секунд. (Верифицируется тестом AC5.)
- [x] AC5: **Тест `testListBackupVersionsDoesNotDeleteRecords`**: mock с 100 AppBackup-записями (mix авто + pinned), maxSnapshots = 3. Вызов `listBackupVersions()`. Assert: `db.deletedRecordNames.isEmpty`. ✅
- [x] AC6: **Тест `testUploadTriggersPruneAfterSuccess`**: mock с 5 авто-записями, maxSnapshots = 3. Вызов `uploadBackup(...)`. Assert: stale удалены. ✅
- [x] AC7: **Тест `testPruneRetainsPinnedRecords`**: 5 авто + 5 pinned, maxSnapshots = 3, maxPinnedSnapshots = 4. Вызов `uploadBackup(...)`. Assert: pinned retained = 4, auto retained = 3. ✅
- [x] AC8: `downloadLatestBackup()` и `listBackupRecordNamesForRestore()` не вызывают `deleteRecord`. Assert `db.deletedRecordNames.isEmpty` добавлен в `testSnapshotRecordsRemainSourceOfTruthWhenIndexIsCorrupted`. ✅
- [x] AC9: `testListBackupVersionsPrunesExistingExcessBackups` переписан в `testListBackupVersionsDoesNotDeleteRecords` — утверждает противоположное. ✅
- [x] AC10: В `storeBackup` комментарий явно разделяет Layer 1 (index-based) и Layer 2 (orphan scan). ✅

## Решения по открытым вопросам

### Prune after upload: awaited или deferred?

**Решение: awaited в той же task-цепочке, best-effort.**

Обоснование:
- В нормальном состоянии (после cleanup) после Layer 1 retention остаётся max 1 stale auto-запись и/или 1 stale pinned. Prune Layer 2 при N ≤ 10 — это 1–2 `deleteRecord`. **Но:** если у пользователя ещё есть orphan backlog (например, первый upload после фикса до полного прогона cleanup), Layer 2 может awaited-прожевать десятки записей. Это не смертельно, но честная оценка: Layer 2 latency пропорциональна числу orphans, не числу новых записей.
- При ручном backup пользователь уже ждёт upload — дополнительные 100–500 ms незаметны.
- При auto backup (`triggerBackgroundBackup` в millioApp) мы внутри background task с ограниченным временем. `Task { }` fire-and-forget рискует быть отменён при suspend. Awaited в той же задаче гарантирует завершение пока background task активен.
- Если orphan-записей нет (normal case) — prune делает полный snapshotQuery scan (fast, ~1–2с max 7 записей), находит 0 stale, выходит. Это допустимо.

**Если в будущем prune окажется медленным:** перевести на `Task.detached(priority: .background)` с отдельным cancellable handle. Сейчас преждевременно.

### Где вызывать prune?

`storeBackup(...)` — единственная точка входа для обоих типов. После успешного `return try await storePinnedBackup/storeAutoBackup` сохранить результат, запустить prune best-effort, вернуть результат.

```swift
private func storeBackup(...) async throws -> BackupVersionInfo {
    let result = if isPinned {
        try await storePinnedBackup(...)
    } else {
        try await storeAutoBackup(...)
    }
    // Layer 2: orphan cleanup после успешного snapshot-сохранения
    do {
        try await pruneExcessSnapshotsIfNeeded(using: container.privateCloudDatabase)
    } catch {
        logger.warning("Orphan prune after backup failed (non-fatal): \(descriptiveCloudKitError(error), privacy: .public)")
    }
    return result
}
```

### Дублирование retention — это ОК?

Да, осознанно. Layer 1 (index-based) — быстрый нормальный путь, работает без full CloudKit scan. Layer 2 (snapshotQuery prune) — safety net для orphans. Это нужно явно задокументировать в коде комментарием перед `pruneExcessSnapshotsIfNeeded` call site.

### Race между двумя параллельными upload → двойной prune?

Не блокирует реализацию. CloudKit delete формально **не идемпотентен** — повторный delete вернёт `unknownItem`. Но prune **tolerant к repeated/missing deletes**: ошибка в delete-цикле (line 641) логируется как warning, цикл идёт дальше. Поэтому два параллельных prune на одном и том же set — не ломают flow. Лок не нужен в этой фазе.

## Что вне скопа этого плана

**3 full scan за запуск (coalescing/cache):** после удаления prune из list-path остаются 2 scan (один из `listBackupVersions` в lifecycle, один из iCloud status refresh). Это отдельная задача. Варианты: TTL-кэш на результат snapshotQuery в памяти; объединение status-проверки и listing в один вызов; lazy iCloud status (только при открытии ProfileView). Зафиксировать как follow-up, не блокирует этот план.

**Server-side limited query:** `backupDate` как Sortable в CloudKit Dashboard + `CKQueryOperation.resultsLimit`. Не нужен пока records ≤ 20. Порог для revisit: если `snapshotQuery count > 20` в логах снова. Pinned records тогда потребуют отдельного query с `isPinned == 1` predicate — нельзя просто резать по общей дате.

## Фазы

### Фаза 1 — Вынести prune из read-path [x]

**Файл:** `CloudBackupStore.swift`

Изменения:
1. `listBackupVersions()` (line 468–470): удалить `try await pruneExcessSnapshotsIfNeeded(using: privateDB)`.
2. `storeBackup(...)` (line 257–276): рефакторинг с best-effort prune после успешного сохранения (см. выше).
3. Добавить комментарий к call site prune: объяснить двухуровневую retention-архитектуру (Layer 1 / Layer 2).

### Фаза 2 — Тестовая матрица [x]

**Файл:** `millioTests/Core/BackupManagerTests.swift`

1. Переписать `testListBackupVersionsPrunesExistingExcessBackups` (line 1090) → `testListBackupVersionsDoesNotDeleteRecords`: 100 записей в mock, assert `deletedRecordNames.isEmpty`.
2. Добавить `testUploadTriggersPruneAfterSuccess` (AC6).
3. Добавить `testPruneRetainsPinnedRecords` (AC7).
4. Расширить `testSnapshotRecordsRemainSourceOfTruthWhenIndexIsCorrupted` (line 1158): добавить явный assert `db.deletedRecordNames.isEmpty` после вызовов `listBackupVersions()` и `downloadLatestBackup()`. Этот тест покрывает AC8 — read-path не удаляет записи.

### Фаза 3 — Верификация [ ] (ожидает сборки на устройстве)

1. Собрать Debug-сборку.
2. Запустить, измерить `initializeColdStart`. Ожидаем ≤ 6000 ms (AC4a).
3. Проверить логи: нет `Prune after backup failed`, нет `deleteRecord` в listing-пути.
4. Сделать ручной backup → проверить, что prune запустился: в логах появится `Orphan prune` или prune без ошибки.

## Impact Analysis

| Риск | Оценка | Митигация |
|------|--------|-----------|
| Orphans не удалятся при старте — накопятся до следующего upload | Низкий в нормальном использовании | Orphans возникают только при schema-миграции или очень старых версиях логики; нормальный пользователь делает backup → prune сразу чистит |
| Prune в storeBackup добавляет latency к upload | Низкий (≤ 10 records → ~200–500 ms) | Awaited, но best-effort; пользователь видит spinner upload — разница незаметна |
| Существующий тест `testListBackupVersionsPrunesExistingExcessBackups` сломается | Ожидаемо | AC9 — явно переписать |
| Параллельный upload race → двойной prune | Очень низкий | CloudKit delete идемпотентен |
| Нужно проверить `downloadLatestBackup` / `listBackupRecordNamesForRestore` на прямые delete-пути | Обязательно до реализации | AC8 + grep перед стартом Фазы 1 |

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-11 | Plan v1 создан. Направление верное, но underspecified: не было AC4b, AC8, AC9, AC10; prune after upload не был явно описан (awaited vs deferred); двухуровневая retention не была названа. |
| 2026-05-11 | Plan v2 (bulletproof): добавлены AC4b, AC8, AC9, AC10; зафиксировано решение по prune-latency (awaited best-effort); двухуровневая retention architecture явно описана; 3 scan follow-up вынесен из скопа; тестовая матрица расширена. |
| 2026-05-11 | Plan v3 (три правки перед реализацией): (1) честно признано — Layer 2 latency пропорциональна orphan backlog, не только N ≤ 10; (2) "CloudKit delete идемпотентен" → prune tolerant к repeated/missing deletes (unknownItem логируется как warning); (3) AC8 усилен: явный `db.deletedRecordNames.isEmpty` добавляется в `testSnapshotRecordsRemainSourceOfTruthWhenIndexIsCorrupted`. |
| 2026-05-11 | Фазы 1 и 2 реализованы. Сборка успешна. CloudBackupStoreTests: все 27 тестов passed, включая 3 новых (testListBackupVersionsDoesNotDeleteRecords, testUploadTriggersPruneAfterSuccess, testPruneRetainsPinnedRecords) и усиленный testSnapshotRecordsRemainSourceOfTruthWhenIndexIsCorrupted. Фаза 3 (верификация на устройстве) — ожидает. |
