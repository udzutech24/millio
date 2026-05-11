# Plan: backup-diagnostics

**Slug:** `backup-diagnostics`
**Дата создания:** 2026-05-10
**Stage:** 4 / Implementation → Verification
**Связан с:** `thoughts/research/2026-05-10-backup-environment-index-contamination.md`

## Статус

`В РАБОТЕ`

**Реализовано:** Фаза 1 (диагностика), Фаза 2 (snapshotQuery primary), Фаза 3 (nil guard, restoreLatest, size guard temp, алерт)
**Осталось:** Фаза 3.3 (preflight.modelCount → заменить TODO size guard), Фаза 4 (UX Dev/Prod)

## Цель

Выяснить и устранить причину, по которой последний Debug-билд показывает другой набор backup-версий, чем Release-версия. Research показал два независимых дефекта:

1. **CloudKit environment mismatch:** Debug-сборка из Xcode → CloudKit Development; TestFlight → CloudKit Production. Разный Apple ID Private DB = разные записи.
2. **backup_index как источник истины:** `listSnapshotVersions` возвращает данные индекса, даже если реальные `AppBackup` snapshot records отличаются.

## Acceptance Criteria

- [x] AC1: В Debug-сборке BackupManagementView показывает бейдж `CloudKit Development` / `Production`. ✅ Подтверждено скриншотом 2026-05-10.
- [x] AC2: Каждая строка версии показывает `src:index` / `src:snapshotQuery` / `src:legacyLatest`. ✅ Все 5 версий — `src:index`. snapshotQuery не вызывался ни разу.
- [x] AC3: Лог `CloudBackupStore` содержит `source` и `env` для каждой версии при вызове `listBackupVersions()`. ✅ (implied by AC2 — index-path логирование активно)
- [x] AC4: `listSnapshotVersions` использует snapshotQuery как primary, индекс только как fallback.
- [~] AC5: Авто-ресторе использует `restoreLatest(passphrase:)` вместо `restoreVersion(versions.first)` ✅ + preflight проверяет `modelCount > 0` [ ] (TODO: временный size guard ≥ 1024 пока нет preflightLatestBackup).
- [x] AC6: `triggerBackgroundBackup` при `exportedModelCount == nil` не запускает бэкап.
- [x] AC7: Кнопка «Продолжить без восстановления» показывает жёсткий алерт с предупреждением о потере данных.

## Фазы

### Фаза 1 — Диагностика [x]

**Цель:** видеть source и environment в UI и логах без изменения логики backup.

Изменённые файлы:
- `millio/Core/Backup/BackupInfo.swift` — добавлен `BackupVersionSource` enum + `source` поле в `BackupVersionInfo` (исключено из Codable/Equatable)
- `millio/Core/Backup/CloudBackupStore.swift` — `cloudKitEnvironment` статическое свойство; тегирование source в `listSnapshotVersions`, `autoBackupVersion`; итоговый лог в `listBackupVersions`
- `millio/UI/Profile/BackupManagementView.swift` — `#if DEBUG` env-бейдж (оранжевый, над versionsCard); `src:xxx` тег под каждой версией

**Как верифицировать:**
1. Запустить Debug-сборку из Xcode → должен появиться бейдж "CloudKit Development"
2. Открыть Backup экран → в каждой строке версии увидеть `src:index` или `src:snapshotQuery`
3. В Console.app отфильтровать по `CloudBackupStore` → увидеть строки `BackupVersion recordName=... source=... env=...`
4. Сравнить с данными из CloudKit Dashboard (Development vs Production Private DB)

### Фаза 2 — Починить источник истины [ ]

**Цель:** snapshotQuery = primary; backup_index = best-effort cache только при недоступности snapshotQuery.

Файл: `CloudBackupStore.swift` — `listSnapshotVersions` (строка 540)

**Текущая логика (дефект):**
```
if !indexEntries.isEmpty → return index data   // index wins — никогда не смотрим на реальные records
fallthrough → snapshotQuery
```

**Правильная логика:**
```
snapshotQuery → успех → вернуть AppBackup records (source: .snapshotQuery)
             → .unknownItem / isSnapshotQueryUnsupported → fallback: загрузить index (source: .index)
             → другая ошибка → throw (не глотать)
```

Ключевые изменения:
- Убрать `loadIndexEntries` из начала метода — он не должен быть gate для snapshotQuery.
- Запустить `database.records(recordType: snapshotRecordType)` безусловно.
- При успехе — возвращать только AppBackup records, даже если index непустой.
- `catch .unknownItem` или `isSnapshotQueryUnsupported` → загрузить index как fallback.
- При расхождении snapshotQuery и index — логировать, но НЕ перезаписывать index в read-path (лишний сайд-эффект при чтении).

Нужен тест: непустой stale index + свежие AppBackup records → возвращаются AppBackup, не index.

### Фаза 3 — Безопасный авто-ресторе [ ]

**Цель:** устранить три независимые дыры: nil-backup, ручной first-candidate, отсутствие preflight.

#### 3.1 — AC6: nil guard в `triggerBackgroundBackup` (millioApp.swift:655)

Текущий комментарий говорит: «nil → состояние неизвестно → бэкапим». Это неверно — неизвестное состояние нельзя перезаписывать в CloudKit.

```swift
// Было:
if let container = activeModelContainer, Self.exportedModelCount(in: container) == 0 { return }

// Стало: nil и 0 → не бэкапить
guard let container = activeModelContainer,
      let count = Self.exportedModelCount(in: container),
      count > 0 else { return }
```

#### 3.2 — AC5: Заменить `restoreVersion(first)` на `restoreLatest` (millioApp.swift:708–731)

Текущий код вручную берёт `versions.first` и вызывает `restoreVersion` — explicit restore без fallback. Плохо: если первая версия невалидна, восстановление падает.

`restoreLatest(passphrase:)` уже существует в `BackupManagerProtocol` и внутри использует `listBackupRecordNamesForRestore` — candidate loop с fallback по следующему recordName при ошибке.

```swift
// Было:
let versions = await diContainer.backupManager.listBackupVersions()
guard let latestVersion = versions.first else { ... }
try await diContainer.backupManager.restoreVersion(recordName: latestVersion.recordName, passphrase: nil)

// Стало:
try await diContainer.backupManager.restoreLatest(passphrase: nil)
```

Убирает ручной `listBackupVersions` + `versions.first` из auto-restore пути. Candidate fallback — в `BackupManager`, не в `millioApp`.

#### 3.3 — AC5 (preflight): `modelCount` проверка до restore

`size < 1024` — не настоящий критерий. Правильный критерий: envelope header содержит `modelCount > 0`.

Нужен метод `BackupManagerProtocol.preflightLatestBackup() async throws -> BackupPreflight` где:
```swift
struct BackupPreflight {
    let modelCount: Int
    let schemaVersion: String
    let requiresPassphrase: Bool
}
```

В auto-restore flow:
```swift
let preflight = try await diContainer.backupManager.preflightLatestBackup()
guard preflight.modelCount > 0 else {
    AppLogger.log(.warning, category: "App", "Auto-restore: backup пустой (modelCount=0), переходим к ручному")
    await MainActor.run { appState.lifecycle = .restoring }
    return
}
guard !preflight.requiresPassphrase else {
    // passphrase-защищённый backup нельзя auto-restore без ввода пользователя
    await MainActor.run { appState.lifecycle = .restoring }
    return
}
```

**Временный предохранитель (TODO, пока нет preflight):** допустим `size < 1024` guard с явным `// TODO(temp): заменить на preflight.modelCount` — только как заглушка.

#### 3.4 — AC7: Жёсткий алерт в RestoreView (RestoreView.swift:~70)

Кнопка «Продолжить без восстановления» → обязательный confirmation alert:
- Заголовок: «Данные не восстановлены»
- Тело: «Локальные данные недоступны. Приложение откроется пустым. Восстановить данные можно позже в настройках профиля, пока резервная копия существует в iCloud.»
- Кнопки: «Вернуться и восстановить» (primary) / «Продолжить без данных» (destructive)

Только при подтверждении `destructive`: `appState.lifecycle = .ready; dismiss()`.

#### Контекст: как работает recovery-trigger (зафиксировано 2026-05-10)

Recovery-trigger — намеренная фича, но реализация грубовата.

**Нормальная логика запуска:**
1. App открывает `DataScope` (guest или `user_<hash(id)>`) → локальный SwiftData store.
2. `exportedModelCount` считает локальные модели.
3. CloudKit запрашивается на наличие backup.
4. `LaunchRecoveryPolicy` возвращает `.presentRestore`, если: onboarding пройден + lifecycle `.ready` + `localCount == 0` + backup найден.

**Ключевые файлы:**
- `millioApp.swift:673` — `presentRestoreFlowIfNeeded()`
- `millio/Core/Backup/LaunchRecoveryPolicy.swift:39` — политика решения
- `millio/Core/AppState/DataScope.swift:11` — scope пользователя

**Сценарии, которые нужно различать:**
| Сценарий | `localCount` | Restore показывать? |
|----------|-------------|-------------------|
| Обычное обновление поверх | > 0 | Нет — store сохранился |
| Удалил + переустановил | 0 | Да — store исчез, backup в CloudKit остался |
| Restore появился при обновлении | 0 | Баг: другой DataScope или пересоздан store (schema-миграция в Debug) |

**Слабое место — кнопка «Продолжить без восстановления»:**
```swift
// RestoreView.swift:70
appState.lifecycle = .ready
dismiss()
```
Кнопка просто переводит lifecycle в `.ready` — пользователь оказывается в пустом приложении без данных и без явного предупреждения, что локальных данных нет. Backup в CloudKit при этом не удаляется.

**Что нужно зафиксировать в Фазе 3:**
- AC5 (size guard): фильтровать `latestVersion.size < 1024` до перехода в `.restoring` — не предлагать восстанавливать пустой backup.
- AC6 (nil guard): при `exportedModelCount == nil` не запускать фоновый backup — не создавать новую пустую версию.
- Дополнительно (не AC, но рекомендуется): кнопка «Продолжить без восстановления» должна явно предупреждать, что локальные данные недоступны, и предложить повторить попытку — `RestoreView.swift`.

### Фаза 4 — UX Dev/Prod [ ]

**Цель:** предупреждать, что Debug видит другой CloudKit dataset.

Минимально: бейдж из Фазы 1 уже решает это для разработчика.

## Challenge Log

### 1. Решает ли план проблему?
- AC1–AC3 → Фаза 1 позволяет подтвердить/опровергнуть Dev/Prod гипотезу до изменения архитектуры.
- AC4–AC6 → Фазы 2–3 устраняют архитектурные дефекты.

### 2. Самое эффективное?
- Сначала диагностика (без риска) → потом архитектурный фикс. Не наоборот.

### 3. Нет ли кода ради кода?
- `#if DEBUG` гарантирует нулевой impact на релизный билд.
- source-тег исключён из Codable и Equatable → no serialization impact.

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-10 | Research artifact создан (environment-index-contamination) |
| 2026-05-10 | Фаза 1 реализована, сборка успешна |
| 2026-05-10 | Фаза 1 верифицирована на устройстве. Результат: CloudKit Development подтверждён; все 5 версий `src:index` — snapshotQuery не вызывался. 456 B запись выбрана как Авто-кандидат из стейл-индекса. Оба дефекта (environment mismatch + index-as-source-of-truth) доказаны. |
| 2026-05-10 | Фаза 2 реализована: `listSnapshotVersions` инвертирована — snapshotQuery primary, index только fallback при .unknownItem / unsupported. Сборка успешна. |
| 2026-05-10 | Фаза 3 реализована (AC5 частично): nil guard в triggerBackgroundBackup; restoreLatest вместо restoreVersion(first); temp size guard ≥ 1024; жёсткий алерт в RestoreView. Сборка успешна. |
| 2026-05-11 | Наблюдение по логам build 51: `BackupList source=index (fallback) count=4` — в Production snapshotQuery падал с `Field 'recordName' is not marked queryable`. **ЗАКРЫТО:** индекс `recordName / ___recordID (queryable)` добавлен в Development и задеплоен в Production через CloudKit Dashboard. Фаза 2 теперь должна работать в проде. |
| 2026-05-11 | Наблюдение: `Missing or invalid DE_API_BASE_URL in runtime configuration` — env-переменная не прокинута в схему симулятора. В Release не влияет (bundled default). Для полноты тестирования конфигурации в Dev-схеме стоит прописать переменную. |
| 2026-05-11 | **🚨 Регрессия cold start после фикса Фазы 2:** `initializeColdStart` 30 359 ms (было 6 318 ms), `iCloud status refresh` 39 658 ms (было 2 646 ms). Причина: `snapshotQuery` возвращает **132 AppBackup records** по сети вместо чтения локального index (7 записей). `NSPredicate(value: true)` без лимита — все записи. **Два новых дефекта выявлены:** (1) snapshotQuery нужен лимит (достаточно последних ~10); (2) старые AppBackup не прунятся — 132 записи = утечка. Требует отдельного плана. |
