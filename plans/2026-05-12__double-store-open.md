# Plan: double-store-open

**Slug:** `double-store-open`
**Дата создания:** 2026-05-12
**Stage:** 1 / Design
**Размер:** S (1 файл: millioApp.swift)
**Связан с:** обнаружен при анализе логов холодного старта (build 54, симулятор)

## Статус

`НЕ НАЧАТ`

## Контекст

При каждом холодном старте с авторизованным пользователем user store открывается дважды:

```
Opening store 'millio_user_....store' (existed=true)
Store opened OK
Opening store 'millio_user_....store' (existed=true)   ← дубль
Store opened OK
```

После двух открытий — `Active scope after sync: millio_guest` (scope не переключился).
Переключение на user scope завершается ПОСЛЕ `initializeColdStart` (DIContainer.create 46ms появляется после 4741ms).

### Root cause

В `initializeColdStart` ([millioApp.swift:206-208](../millio/millioApp.swift)) два конкурирующих пути ведут к `synchronizeDataScope` почти одновременно:

**Путь A** — `authManager.restoreSession()` (строка 206) при успехе вызывает зарегистрированный `onSessionChanged` callback через `Task { }` (fire-and-forget, не awaited).

**Путь B** — следующая строка 208: `await synchronizeDataScope(with: authManager.currentUser)` — явный вызов.

Оба пути попадают в `switchScopeIfNeeded` ([StartupCoordinator.swift:44](../millio/Core/AppState/StartupCoordinator.swift)):

```swift
scopeSwitchTask?.cancel()   // ← отменяет предыдущий task
let task = Task { @MainActor in ... }
scopeSwitchTask = task
return await task.value
```

**Последовательность событий на @MainActor:**

1. Путь B стартует первым → `rebindDataScope` → `makeModelContainer` → **store open #1** → `await prepareDependencyBinding` → yields.
2. Пока yields, Путь A (`onSessionChanged Task`) запускается → `switchScopeIfNeeded` → **отменяет task Пути B**, создаёт новый → `makeModelContainer` → **store open #2** → `await prepareDependencyBinding`.
3. Task Пути B видит `Task.isCancelled` → `return false` → `activeDataScope` не обновляется.
4. Результат: `Active scope after sync: millio_guest` (scope не обновился за время cold start).
5. Task Пути A завершается позже (после `initializeColdStart`) → создаёт второй DIContainer → scope наконец переключается.

### Следствия

- Пользователь видит гостевой/пустой экран часть времени после восстановления сессии.
- `Notification authorization granted` логируется трижды (три DIContainer инициализации).
- `initializeColdStart` не отражает реальное время готовности данных.

## Решение

Убрать явный вызов `synchronizeDataScope` на строке 208 — он дублирует `onSessionChanged`.

`restoreSession()` уже вызывает `onSessionChanged(user)`, который выполняет переключение. Явный вызов создаёт конкурирующий task который отменяет или отменяется сам.

**Вариант A (рекомендуется):** удалить строку 208 — `onSessionChanged` единственный путь.

```swift
// millioApp.swift
await useCase.initialize()
await authManager.restoreSession()
AppLogger.log(...)
// ← убрать: await synchronizeDataScope(with: authManager.currentUser)
AppLogger.log(.info, category: "App", "Active scope after sync: ...")
```

**Вариант B:** сохранить строку 208, но запретить `onSessionChanged` вызывать `synchronizeDataScope` во время `restoreSession`. Требует флаг `isRestoringSession` в authManager — сложнее, риск пропустить edge cases.

Вариант A проще и безопаснее: `onSessionChanged` уже тестируется как путь переключения scope при логине.

## Acceptance Criteria

- [ ] AC1: User store открывается ровно один раз за холодный старт.
- [ ] AC2: `Active scope after sync:` логирует `millio_user_...`, а не `millio_guest`.
- [ ] AC3: `Notification authorization granted` логируется не более одного раза.
- [ ] AC4: DIContainer для user scope создаётся до завершения `initializeColdStart`.
- [ ] AC5: Существующие тесты по DataScope / auth flow — все passed.

## Фазы

### Фаза 1 — Убрать дублирующий вызов [ ]

**Файл:** `millio/millioApp.swift`

1. Удалить строку 208: `await synchronizeDataScope(with: authManager.currentUser)`.
2. Убедиться что строка 209 (`Active scope after sync:`) логирует корректный scope — возможно перенести лог в `synchronizeDataScope` или убрать.
3. Прогнать `BackendStartupResolverTests`, тесты DataScope если есть.

### Фаза 2 — Верификация в симуляторе [ ]

1. Запустить симулятор с авторизованным пользователем.
2. Проверить логи: ровно одно `Opening store 'millio_user_...'`, `Active scope after sync: millio_user_...`.
3. Проверить `Notification authorization granted` — один раз.
4. Проверить что данные пользователя загружаются сразу (не мелькает пустой экран).

## Edge Cases

- **Logout → Login:** `onSessionChanged` должен по-прежнему работать — переключение guest → user в середине сессии не затронуто.
- **Auth fail на старте:** `restoreSession` не вызовет `onSessionChanged(user)` → scope останется guest. Явный вызов строки 208 не нужен, т.к. guest — правильный scope при auth fail.
- **ScopeCache fallback:** логика кэша в `synchronizeDataScope` (строки 332–344) должна работать как раньше — путь не меняется.

## Вне скопа

- Рефакторинг `onSessionChanged` / authManager callback architecture.
- `iCloud status refresh` (17ms, detached Task) — не связан.
- `Backup info lookup degraded` — отдельная проблема (симулятор без CloudKit).

## Журнал

| Дата | Событие |
|------|---------|
| 2026-05-12 | Plan v1 создан. Root cause обнаружен при анализе логов build 54 (симулятор). |
