# Backup snapshotQuery: регрессия cold start + утечка записей

**Дата:** 2026-05-11  
**Источник:** логи устройства, build 51, после фикса CloudKit recordName queryable

## Наблюдение

После включения `snapshotQuery` как primary source:

```
BackupList source=snapshotQuery count=132 env=Production
BackupList: index diverged from snapshotQuery — index:7 query:132, serving snapshotQuery
initializeColdStart finished in 30359 ms   ← было 6318 ms
iCloud status refresh finished in 39658 ms ← было 2646 ms
```

## Два независимых дефекта

### 1. snapshotQuery без лимита

`CKQuery(recordType: "AppBackup", predicate: NSPredicate(value: true))` возвращает все 132 записи.
CloudKit возвращает их постранично, каждая страница — сетевой roundtrip.

**Фикс:** добавить `query.sortDescriptors = [NSSortDescriptor(key: "backupDate", ascending: false)]`
и ограничить выборку до ~10 записей через `CKQueryOperation.resultsLimit`.

### 2. Старые AppBackup не прунятся — утечка записей в CloudKit

132 записи AppBackup — это все бэкапы когда-либо созданные, ни одна не удалена.
При каждом бэкапе создаётся новая CKRecord, старые остаются навечно.

**Фикс:** при создании нового бэкапа — удалять записи, которые выходят за пределы retention window
(например, оставлять последние 10; или последние 10 + pinned).

## Влияние

| Метрика | До фикса (index) | После фикса (snapshotQuery) |
|---------|-----------------|----------------------------|
| cold start | ~6 с | ~30 с |
| iCloud status refresh | ~2.6 с | ~39 с |
| Источник данных | стейл индекс (7) | актуальные records (132) |

## Уточнённый диагноз

30 секунд = 125 последовательных `deleteRecord` в `pruneExcessSnapshotsIfNeeded`, который вызывается из `listBackupVersions()` (read-path). После прогона prune (уже произошёл) записей ≤ 7 — следующий cold start должен быть нормальным. Архитектурный дефект остаётся.

## Приоритет

**Высокий** — архитектурный дефект (write side effect в read-path). Одноразовая регрессия уже прошла, но повторится при следующем accumulation orphans.

## Что делать

→ **`plans/2026-05-11__backup-query-optimization.md`** — план с AC и тестовой матрицей.
