# Research: launch-recovery-hardening

**Date:** 2026-05-10
**Stage:** 1 / Deep Research (read-only)
**Related:** [`specs/2026-05-10-launch-recovery-hardening.md`](../specs/2026-05-10-launch-recovery-hardening.md)

## Задача исследования

Пользователи теряют данные после обновления приложения. Нужно найти и устранить уязвимости в потоке авто-восстановления (`LaunchRecoveryPolicy` + `presentRestoreFlowIfNeeded`), которые могут приводить к ложному триггеру restore, перезаписи свежих данных старым бэкапом или зависанию на экране восстановления.

## Findings from codebase

### Структура затронутых файлов

| Файл | Роль |
|------|------|
| `millio/Core/Backup/LaunchRecoveryPolicy.swift` | Решает: нужен ли restore при старте |
| `millio/millioApp.swift` (строки 640–712) | `triggerBackgroundBackup` + `presentRestoreFlowIfNeeded` |
| `millio/Core/Backup/CloudBackupStore.swift` (строки 583–630) | Pruning, `staleSnapshotEntries`, `retainedRecordNames` |
| `millio/UI/Restore/AutoRestoringView.swift` | Экран "Восстанавливаем данные" |
| `millio/Core/AppState/AppLifecycleState.swift` | `.autoRestoring` стейт |
| `millioTests/Core/LaunchRecoveryPolicyTests.swift` | Тесты политики |

### Уязвимость #1 — КРИТИЧЕСКАЯ: Race condition в `exportedModelCount`

**Строки:** `millioApp.swift:647, 669`

```swift
// triggerBackgroundBackup:
if let container = activeModelContainer,
   Self.exportedModelCount(in: container) == 0 { return }

// presentRestoreFlowIfNeeded:
let localDataCount = Self.exportedModelCount(in: activeModelContainer)
```

`exportedModelCount` — **синхронный** fetch на `mainContext`. SwiftData использует lazy-loading: при старте данные могут ещё не быть загружены из SQLite в память контекста. Fetch вернёт `0`, приложение решит что данные потеряны и запустит restore поверх живых данных.

**Почему это вероятная причина реальных потерь:** пользователь обновляет приложение → SwiftData поднимает новый контейнер → `exportedModelCount` вызывается до завершения загрузки → `0` → авто-restore перезаписывает данные бэкапом трёхдневной давности.

### Уязвимость #2 — ВЫСОКАЯ: Нет координации между restore и background backup

**Строки:** `millioApp.swift:131, 689`

```swift
// Старт приложения (.task):
initializeColdStart()
  → presentRestoreFlowIfNeeded()
    → Task { await restoreVersion(...) }  // НЕ await — уходит в фон

// willResignActive (пользователь уходит):
triggerBackgroundBackup()               // может запуститься пока restore ещё идёт
```

Если restore завершился быстро и пользователь успел свернуть приложение — бэкап запишет только-что-восстановленные данные, потенциально затирая более свежую копию в CloudKit, которая была до restore.

Обратный риск: если guard `exportedModelCount == 0` сработал пока restore не закончился — бэкап не создаётся. Но при следующем запуске count уже будет > 0, поэтому restore не повторится — это безопасно.

### Уязвимость #3 — СРЕДНЯЯ: Нет таймаута на CloudKit restore

**Строка:** `millioApp.swift:~697`

`restoreVersion()` вызывается без `withTimeoutSeconds`. В условиях плохой связи (2G, airplane mode снят наполовину) CloudKit-запрос может висеть минутами. Пользователь убивает приложение → на следующем старте стор всё ещё пуст → снова restore попытка.

### Уязвимость #4 — СРЕДНЯЯ: Бесконечный цикл при повреждённом бэкапе

**Строки:** `millioApp.swift:~703–705`

```swift
} catch {
    appState.lifecycle = .restoring  // переходим в ручной экран
}
```

При повреждённом бэкапе: авто-restore фейлится → ручной экран → пользователь закрывает → стор пуст → следующий старт: `LaunchRecoveryPolicy` снова говорит restore → зависание. Выхода нет, только переустановка.

### Существующие паттерны

- `AutoBackupPolicy.shouldRun(lastBackupDate:now:)` — уже есть паттерн "проверить условие перед действием".
- `CrashReporting.record(error:)` — non-fatal логирование ошибок backup/restore в Release.
- `AppLogger.log(.info, category: "App", ...)` — уже логируется `LaunchRecovery` решение (строка 679).
- Флаг `activeScopeStoreExistedBeforeBinding` — уже есть идея "знать о состоянии до действия".

### Тесты — что не покрыто

| Edge case | Покрыт |
|-----------|--------|
| Нормальный старт (данные есть) | ✅ |
| Data-wipe сценарий (count=0 + backup есть) | ✅ (добавлен в e97a1b1) |
| Race condition: count=0 до загрузки данных | ❌ |
| CloudKit недоступен при старте | ❌ |
| Повреждённый бэкап (бесконечный цикл) | ❌ |
| Kill app во время restore | ❌ |
| Параллельный backup + restore | ❌ |

## Alternatives

### Вариант A: Async-проверка с задержкой ("wait for store")
Добавить `Task.sleep` или polling перед `exportedModelCount` — подождать пока SwiftData закончит инициализацию.
- **Плюсы:** Минимальные изменения архитектуры.
- **Минусы:** Хрупко — нет гарантированного сигнала о готовности контекста. Время ожидания — magic number.
- **Трудоёмкость:** S

### Вариант B: Флаг `isRestoringInProgress` + async-safe count
Ввести actor-изолированный флаг блокировки (`isRestoring: Bool`), который выставляется до начала restore и снимается после. `triggerBackgroundBackup` проверяет флаг. `exportedModelCount` заменить на async fetch через `ModelContext.fetch`.
- **Плюсы:** Надёжная координация, нет race condition.
- **Минусы:** Чуть больше изменений (3-4 файла).
- **Трудоёмкость:** M

### Вариант C: Полный рефактор в отдельный `LaunchRecoveryCoordinator` Actor
Вынести весь поток restore в отдельный actor, который сериализует backup и restore, хранит счётчик попыток, имеет встроенный таймаут.
- **Плюсы:** Чистая архитектура, все проблемы решены системно.
- **Минусы:** Большой scope, риск регрессий, долго.
- **Трудоёмкость:** L

## Recommendation

**Выбран:** Вариант B — флаг блокировки + async-safe count.

**Почему:**
1. Решает главную причину потерь (#1) без хрупкого polling.
2. Устраняет race condition backup/restore (#2) через явный флаг — понятно при ревью.
3. Можно дополнить таймаутом (#3) и счётчиком попыток (#4) в рамках того же PR.
4. Scope ограничен — 4-5 файлов, тестируемо изолированно.

**Что учесть при имплементации:**
- `exportedModelCount` нужно сделать async и вызывать через `@MainActor` fetch, дождавшись загрузки контекста (можно через `context.fetchCount(FetchDescriptor<T>())`).
- Флаг `isRestoringInProgress` должен быть атомарным — вынести в `AppState` или отдельный `@Observable`.
- Таймаут на restore: 30 секунд достаточно для CloudKit при нормальной связи; при истечении — fallback в `.restoring` (ручной).
- Счётчик попыток авто-restore: хранить в `UserDefaults`, сбрасывать при успешном restore или при старте с непустым стором. Лимит: 2 попытки.
- Все новые failure paths → `CrashReporting.record(error:)`.
