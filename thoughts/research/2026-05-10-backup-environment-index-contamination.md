# Research: backup list shows old versions in latest build

Дата: 2026-05-10

## Проблема

Пользователь сравнил 4 скриншота:

- старая версия приложения показывает актуальные backup-версии: 10 мая 2026 04:48, 9 мая 15:19, 9 мая 11:40, 7 мая, 5 апреля, размеры 37-57 KB, v1.7;
- последний билд при том же Apple ID показывает другой набор: 9 мая 2026 22:45, 456 B, v1.7, затем 27/26/24/19 марта, v1.2-v1.5, размеры 17-29 KB.

Нужно понять, почему последний билд видит старые backup-ы и откуда могли попасть старые данные.

## Вывод

Самая вероятная причина: старый билд и последний билд смотрят в разные CloudKit environment-ы.

- TestFlight/App Store обычно используют CloudKit Production.
- Запуск из Xcode по текущей shared scheme использует `LaunchAction buildConfiguration="Debug"`.
- Debug-сборка с CloudKit entitlement обычно работает с CloudKit Development.
- В коде используется `CKContainer.default()`, а значит environment определяется подписью/provisioning profile, а не runtime-кодом.

Это хорошо объясняет симптом: тот же Apple ID, но другой набор записей в Private DB. Мартовские v1.2-v1.5 похожи на старый Development dataset, а актуальные майские v1.7 — на Production dataset.

Вторая реальная проблема: `backup_index` фактически используется как источник списка версий, хотя документация говорит, что source of truth — snapshot records `AppBackup`.

## Доказательства по коду

### CloudKit container/environment

- `CloudBackupStore.init(container: CKContainer = .default(), ...)` использует default container.
- Entitlements задают контейнер `iCloud.com.millio.app`, но не фиксируют runtime environment.
- Shared scheme запускает приложение в Debug: `millio.xcscheme`, `LaunchAction buildConfiguration="Debug"`.
- Bundle ID одинаковый: `com.millio.app`, version `1.7`, поэтому отличие списка не объясняется bundle id/version.

### `backup_index` против source of truth

`CloudBackupStore.listSnapshotVersions()`:

```swift
let indexEntries = try await loadIndexEntries(from: database)
if !indexEntries.isEmpty {
    return indexEntries.map(...).sorted { $0.date > $1.date }
}

let records = try await database.records(recordType: snapshotRecordType)
```

Это противоречит `docs/BACKUP_RESTORE_SCHEMA.md`, где `backup_index` описан как best-effort cache, который нельзя считать source of truth.

### Auto-restore может выбрать неверный кандидат

`presentRestoreFlowIfNeeded()` при пустом store:

```swift
let versions = await diContainer.backupManager.listBackupVersions()
guard let latestVersion = versions.first else { ... }
try await diContainer.backupManager.restoreVersion(recordName: latestVersion.recordName, passphrase: nil)
```

Проблема: используется `restoreVersion`, а это explicit mode. Он не делает fallback по списку кандидатов так же безопасно, как `restoreLatest`. Если `versions.first` пришёл из старого/чужого/stale index, авто-восстановление может попытаться восстановить не тот backup.

## Почему могла появиться запись 456 B

456 B очень похоже на envelope/metadata почти без моделей, то есть backup пустого или почти пустого store. В коде есть guard, который не должен делать background backup при `exportedModelCount == 0`, но остаются сценарии:

- `exportedModelCount` вернул `nil` из-за fetch/serialization failure; комментарий в коде прямо говорит, что при `nil` backup всё равно допускается;
- пользовательский manual/import path мог создать маленькую запись;
- Development environment мог уже содержать старую маленькую `latest_backup` из прошлых тестов;
- `backup_index` мог показывать metadata записи, которая не соответствует текущему реальному набору snapshot records.

Без выгрузки CloudKit Dashboard или логов `recordName`/environment это нельзя доказать на 100%, но по симптомам это не выглядит как актуальная майская Production-история.

## Что исправлять

### Фаза 1: диагностика, без риска для данных

1. Добавить debug-only экран/лог backup diagnostics:
   - build configuration: Debug/Release;
   - container identifier;
   - recordName/date/size/version/isPinned/source для каждой записи;
   - source: `index`, `snapshotQuery`, `legacyLatest`.
2. В CloudKit Dashboard вручную сравнить Production и Development Private DB:
   - есть ли в Development записи v1.2-v1.5 из марта;
   - есть ли в Production записи v1.7 от 10 мая;
   - что лежит в `backup_index.entriesJSON` в обоих environment-ах.

### Фаза 2: починить источник истины списка

1. Сделать snapshot query основным источником.
2. `backup_index` использовать только как fallback, когда snapshot query недоступен из-за schema/queryable ограничения.
3. Если индекс непустой, но snapshot query доступен, пересобрать индекс из реальных snapshot records.
4. Перед показом версии из index проверять, что record реально существует и содержит `backupData`.
5. Тест: непустой stale index + свежие snapshot records => UI/list возвращает snapshot records, а не index.

### Фаза 3: обезопасить auto-restore

1. В auto-restore не использовать `restoreVersion(versions.first)`.
2. Использовать `restoreLatest(passphrase:)`, чтобы работал candidate fallback.
3. Не auto-restore passphrase/keychain snapshot без предварительного preflight статуса.
4. Добавить telemetry: какой record восстановлен, source списка, encryption mode, schemaVersion, modelCount.

### Фаза 4: разделить Dev/Prod backup UX

1. В Debug показывать явный бейдж `CloudKit Development`.
2. В backup UI добавить предупреждение, что Debug может видеть другой CloudKit dataset.
3. Для релизной проверки использовать Archive/TestFlight или Release-подписанный install, а не Xcode Run Debug.

## Вердикт

Это не один UI-баг. Здесь два слоя:

1. Вероятное различие CloudKit Development/Production объясняет, почему последний билд видит мартовскую историю вместо майской.
2. Ошибка архитектуры `backup_index` объясняет, почему даже внутри одного environment список может быть старым и почему auto-restore может выбрать неправильную версию.

Исправлять надо не "обновить экран", а контракт backup list/restore source of truth.
