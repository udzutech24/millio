# Plan: launch-recovery-hardening

**Slug:** `launch-recovery-hardening`
**Дата создания:** 2026-05-10
**Stage:** 3 / Planning
**Spec:** [`specs/2026-05-10-launch-recovery-hardening.md`](../specs/2026-05-10-launch-recovery-hardening.md)
**Research:** [`thoughts/research/2026-05-10-launch-recovery-hardening.md`](../thoughts/research/2026-05-10-launch-recovery-hardening.md)

## Статус

`РЕАЛИЗОВАН`

**Реализовано:** Phase 1, 2, 3, 4
**Осталось:** —

## Цель

Устранить 4 уязвимости в потоке авто-restore, из-за которых пользователи теряют данные после обновления приложения.

## Acceptance Criteria (из spec)

- [ ] AC1: При старте с непустым стором авто-restore не запускается даже при медленной загрузке контекста
- [ ] AC2: Пока идёт авто-restore, `triggerBackgroundBackup` не выполняется
- [ ] AC3: Если CloudKit не ответил за 30 секунд — restore завершается ошибкой, lifecycle → `.restoring`
- [ ] AC4: После 2 неудачных авто-restore подряд — сразу ручной экран, без новых авто-попыток
- [ ] AC5: Все failure paths — `CrashReporting.record(error:)` non-fatal
- [ ] AC6: Тесты покрывают race condition, timeout, лимит попыток, параллельный backup+restore

## Challenge Log

### 1. Решает ли план проблему из spec?

| AC | Фаза |
|----|------|
| AC1 — race condition | Phase 1 (изменить `exportedModelCount` → возвращать `nil` при ошибке) |
| AC2 — блокировка бэкапа | Phase 2 (флаг `isRestoreInProgress` в AppState) |
| AC3 — таймаут 30 сек | Phase 3 (обернуть `restoreVersion` в `withTimeout`) |
| AC4 — счётчик попыток | Phase 3 (UserDefaults-счётчик) |
| AC5 — Crashlytics | Phase 3 (добавить в catch-блоки) |
| AC6 — тесты | Phase 4 |

### 2. Это самое эффективное решение?

- **Альтернатива — polling/sleep перед count:** хрупко, magic number, не гарантирует готовность контекста.
- **Альтернатива — полный рефактор в LaunchRecoveryCoordinator Actor:** правильнее архитектурно, но L-задача, риск регрессий.
- **Выбрано:** минимальный хирургический fix — nil-safe count + флаг + таймаут + счётчик. M-задача, все AC покрыты.

### 3. Нет ли кода ради кода?

Каждое изменение привязано к конкретному AC. Рефакторинг `DataRepository` или `LaunchRecoveryPolicy` не входит.

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 1: Nil-safe `exportedModelCount` (AC1)

**Суть проблемы:** `exportedModelCount` при любой ошибке возвращает `0` → ложный триггер restore.

**Принцип fix:** «Если мы не уверены — НЕ восстанавливаем». Возвращаем `nil` при ошибке, caller пропускает restore.

**Файлы:**
- `millio/millioApp.swift` — изменить сигнатуру, обновить вызовы на строках 647, 669, 576, 588

**Шаги:**
1. `[ ]` Изменить `exportedModelCount(in:) -> Int` → `exportedModelCount(in:) -> Int?`
   ```swift
   private static func exportedModelCount(in container: ModelContainer) -> Int? {
       let repository = DataRepository(
           modelContext: container.mainContext,
           modelContainer: container
       )
       guard
           let payload = try? repository.exportAllData(),
           let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let models = json["models"] as? [[String: Any]]
       else {
           AppLogger.log(.warning, category: "App", "exportedModelCount: fetch failed, count uncertain")
           return nil  // ← nil вместо 0
       }
       return models.count
   }
   ```
2. `[ ]` Обновить `triggerBackgroundBackup` (строка 647):
   ```swift
   // Было:
   if let container = activeModelContainer, Self.exportedModelCount(in: container) == 0 { return }
   // Стало:
   if let container = activeModelContainer {
       let count = Self.exportedModelCount(in: container)
       if count == 0 { return }       // достоверно пусто — не бэкапим
       // count == nil → неизвестно → бэкапим (лучше лишний бэкап, чем нет)
   }
   ```
3. `[ ]` Обновить `presentRestoreFlowIfNeeded` (строка 669):
   ```swift
   // Было:
   let localDataCount = Self.exportedModelCount(in: activeModelContainer)
   // Стало:
   guard let localDataCount = Self.exportedModelCount(in: activeModelContainer) else {
       AppLogger.log(.warning, category: "App", "LaunchRecovery: count uncertain, skipping restore")
       return  // ← не можем достоверно определить потерю — НЕ восстанавливаем
   }
   ```
4. `[ ]` Обновить строки 576 и 588 (restore-flow scope): аналогично — `nil` трактуем как "данные есть" (не перезаписываем)
5. `[ ]` Self-audit: все вызовы `exportedModelCount` обновлены, нет старых `== 0` без nil-check
6. `[ ]` Коммит: `fix(backup): treat uncertain model count as non-empty to prevent false restore trigger`

---

### `[x]` Phase 2: Флаг блокировки restore (AC2)

**Суть:** `triggerBackgroundBackup` может запуститься пока restore идёт в фоне (Task без await).

**Файлы:**
- `millio/Core/AppState/AppState.swift` — добавить `var isRestoreInProgress: Bool`
- `millio/millioApp.swift` — выставлять флаг до Task, снимать в обоих ветках завершения; проверять в `triggerBackgroundBackup`

**Шаги:**
1. `[ ]` Добавить в `AppState`:
   ```swift
   var isRestoreInProgress: Bool = false
   ```
2. `[ ]` В `presentRestoreFlowIfNeeded` (строка 688) перед запуском Task:
   ```swift
   appState.isRestoreInProgress = true
   appState.lifecycle = .autoRestoring
   Task {
       defer { Task { @MainActor in appState.isRestoreInProgress = false } }
       do {
           ...
           await MainActor.run { appState.lifecycle = .ready }
       } catch {
           ...
           await MainActor.run { appState.lifecycle = .restoring }
       }
   }
   ```
3. `[ ]` В `triggerBackgroundBackup` добавить guard:
   ```swift
   guard !appState.isRestoreInProgress else { return }
   ```
4. `[ ]` Self-audit: флаг снимается в обоих ветках (success + error)
5. `[ ]` Коммит: `fix(backup): block background backup while auto-restore is in progress`

---

### `[x]` Phase 3: Таймаут + счётчик попыток (AC3, AC4, AC5)

**Файлы:**
- `millio/millioApp.swift` — обернуть `restoreVersion` в таймаут, добавить счётчик

**Константы:**
```swift
private static let autoRestoreTimeoutSeconds: TimeInterval = 30
private static let autoRestoreMaxAttempts = 2
private static let autoRestoreAttemptsKey = "autoRestoreAttemptCount"
```

**Шаги:**
1. `[ ]` Добавить helper-функцию таймаута в `millioApp.swift`:
   ```swift
   private func withTimeout<T: Sendable>(
       seconds: TimeInterval,
       operation: @escaping @Sendable () async throws -> T
   ) async throws -> T {
       try await withThrowingTaskGroup(of: T.self) { group in
           group.addTask { try await operation() }
           group.addTask {
               try await Task.sleep(for: .seconds(seconds))
               throw CancellationError()
           }
           let result = try await group.next()!
           group.cancelAll()
           return result
       }
   }
   ```
2. `[ ]` Добавить счётчик попыток перед запуском авто-restore:
   ```swift
   let attempts = UserDefaults.standard.integer(forKey: Self.autoRestoreAttemptsKey)
   guard attempts < Self.autoRestoreMaxAttempts else {
       AppLogger.log(.warning, category: "App", "Auto-restore attempt limit reached (\(attempts)), falling back to manual")
       appState.lifecycle = .restoring
       return
   }
   UserDefaults.standard.set(attempts + 1, forKey: Self.autoRestoreAttemptsKey)
   ```
3. `[ ]` Обернуть `restoreVersion` в таймаут:
   ```swift
   try await withTimeout(seconds: Self.autoRestoreTimeoutSeconds) {
       try await diContainer.backupManager.restoreVersion(
           recordName: latestVersion.recordName,
           passphrase: nil
       )
   }
   ```
4. `[ ]` При успешном restore — сбросить счётчик:
   ```swift
   UserDefaults.standard.set(0, forKey: Self.autoRestoreAttemptsKey)
   ```
5. `[ ]` В catch-блоке — добавить `CrashReporting.record(error:)` (AC5):
   ```swift
   } catch {
       CrashReporting.record(error: error)
       AppLogger.log(.error, ...)
       await MainActor.run { appState.lifecycle = .restoring }
   }
   ```
6. `[ ]` Self-audit: таймаут работает при `CancellationError`, счётчик сбрасывается при успехе
7. `[ ]` Коммит: `fix(backup): add 30s restore timeout and attempt limit to prevent infinite loop`

---

### `[x]` Phase 4: Тесты (AC6)

**Файлы:**
- `millioTests/Core/LaunchRecoveryPolicyTests.swift` — новые тест-кейсы для политики
- `millioTests/Core/BackupManagerTests.swift` — тест параллельного backup+restore (через флаг)

**Новые тест-кейсы:**

1. `[ ]` `nilCountSkipsRestore` — `exportedModelCount` возвращает `nil` → `presentRestoreFlowIfNeeded` не запускает restore
2. `[ ]` `restoreInProgressBlocksBackup` — `isRestoreInProgress = true` → `triggerBackgroundBackup` возвращает без действий
3. `[ ]` `autoRestoreAttemptLimitFallsBackToManual` — после 2 попыток → `lifecycle == .restoring`, не `.autoRestoring`
4. `[ ]` `autoRestoreResetCounterOnSuccess` — после успешного restore `autoRestoreAttemptsKey == 0`
5. `[ ]` `autoRestoreTimeoutFallsBackToManual` — mock restore висит >30 сек → lifecycle → `.restoring`

**Шаги:**
1. `[ ]` Написать тесты
2. `[ ]` Убедиться что все зелёные
3. `[ ]` Коммит: `test(backup): cover race condition, timeout, attempt limit, parallel backup+restore`

---

## Edge Cases

- [x] Стор пуст + бэкапа нет → `LaunchRecoveryPolicy` не триггерит restore (покрыто существующими тестами)
- [x] `exportedModelCount` бросает ошибку → Phase 1 возвращает `nil`, restore не запускается
- [x] Kill app в середине restore → счётчик уже инкрементирован; при следующем старте: попытка #2 или fallback
- [x] CloudKit недоступен → timeout 30 сек → `.restoring`
- [x] Бэкап повреждён → restore фейлится → счётчик растёт → лимит → ручной экран
- [x] Параллельный backup + restore → флаг `isRestoreInProgress` блокирует backup

## Gates (перед `[x]` на каждой фазе)

- [ ] `xcodebuild test -scheme millio` — все тесты зелёные
- [ ] Нет новых warnings в компиляторе
- [ ] Self-audit по AC после каждой фазы

## Журнал изменений

- `2026-05-10` — создан план, исследование завершено, 4 уязвимости задокументированы.
- `2026-05-10` — Phase 1 реализована: коммит `66867e35`. BUILD SUCCEEDED, нет новых warnings.
- `2026-05-10` — Phase 2+3 реализованы: коммит `b00ec95f`. BUILD SUCCEEDED.
- `2026-05-10` — Phase 4 (тесты): коммит `92d3805f`. 7 новых тестов — все зелёные. TEST SUCCEEDED.

## Итог (заполняется при завершении)

**Результат:** УСПЕШНО
**Что реализовано:** Все 4 фазы, 6 AC покрыты, 7 новых тестов зелёные, полный тест-сьют TEST SUCCEEDED.
**Дата завершения:** 2026-05-10
