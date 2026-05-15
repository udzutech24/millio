# Research: startup store switch and backend probe necessity

**Date:** 2026-05-11
**Stage:** 1 / Deep Research (read-only)
**Related:** [`plans/2026-05-11__backend-probe-timeout.md`](../../plans/2026-05-11__backend-probe-timeout.md)

## Задача исследования

Проверить, действительно ли нужны две задачи из заметки: сокращение backend probe timeout и разбор двойного открытия SwiftData store после `restoreSession`.

## Findings from codebase

### Backend probe timeout

- `millio/Core/Backend/BackendRuntime.swift`: `BackendStartupResolver.probe()` выставляет `request.timeoutInterval = 8`.
- `millio/millioApp.swift`: `initializeColdStart` первым делом вызывает `resolveBackendRuntimeIfNeeded()`, поэтому timeout backend probe блокирует весь cold start до `AppLifecycleUseCase.initialize`.
- `plans/2026-05-11__backend-probe-timeout.md` уже содержит корректный small-scope plan: поменять timeout на 3s и проверить `BackendStartupResolverTests`.
- `improvements/process/2026-05-11__backend-probe-cold-start.md` фиксирует наблюдение: build 52 на устройстве показал `initializeColdStart = 16 932 ms`, где `AppLifecycleUseCase.initialize = 6 558 ms`, а оставшаяся задержка объясняется backend probe timeout.

Вывод: задача нужна. Это не архитектурный пожар, но это доказанный performance defect на cold start при недоступном preferred endpoint. Правильный первый шаг - маленький фикс timeout, без кэша endpoint и без параллелизации.

### Double store / data scope switch race

- `millio/Core/Auth/AuthService.swift`: `AuthManager.restoreSession()` при успешном restore вызывает `apply(session)`.
- `apply(session)` обновляет `currentUser/status`, затем запускает `onSessionChanged` через fire-and-forget `Task { @MainActor ... }`.
- `millio/millioApp.swift`: сразу после `await authManager.restoreSession()` выполняется явный `await synchronizeDataScope(with: authManager.currentUser)`.
- `synchronizeDataScope` вызывает `startupCoordinator.switchScopeIfNeeded`.
- `StartupCoordinator.switchScopeIfNeeded` отменяет предыдущий `scopeSwitchTask` при новом вызове и обновляет `activeScope` только если task не отменен и sequence актуален.

Это означает, что после успешного restore есть два независимых пути к одному и тому же user scope:

1. `restoreSession -> apply -> Task -> onSessionChanged -> synchronizeDataScope`
2. `initializeColdStart -> restoreSession -> synchronizeDataScope`

Если путь 2 начал `rebindDataScope` и завис на `prepareDependencyBinding`, а затем запускается путь 1, `StartupCoordinator` отменяет первый task. Внутри `rebindDataScope` уже мог быть открыт первый user store через `makeModelContainer`, но `activeDataScope` еще не обновлен. Второй путь открывает store повторно.

Вывод: задача нужна, но она не должна решаться "на глаз" одной строкой без spec. Гипотеза подтверждается кодом: есть реальная гонка между явным sync и callback-ом `onSessionChanged`. Симптом "пользователь временно видит guest/empty screen после логина" правдоподобен, потому что `activeDataScope` остается старым до конца успешного `rebindDataScope`.

## Tests

- `millioTests/Core/BackendStartupResolverTests.swift` покрывает выбор backend и probe failure, но не проверяет timeout value.
- `millioTests/Core/StartupCoordinatorTests.swift` покрывает "latest wins", но не покрывает конкретную интеграцию `restoreSession -> onSessionChanged Task -> explicit synchronizeDataScope`.
- Для double-store нужен unit-level тест на координацию restore/sync или минимальный extractable coordinator/use case. Тестировать это только логами на устройстве слабо: гонка останется незафиксированной.

## Recommendation

1. Реализовать `backend-probe-timeout` первым: small, low-risk, доказанный cold-start выигрыш.
2. Затем создать отдельный spec + plan для `double-store`:
   - выбрать один источник scope sync после restore;
   - предпочтительно убрать явный sync после `restoreSession`, если `restoreSession` гарантированно вызывает `onSessionChanged` при успешной сессии;
   - либо сделать `restoreSession` не вызывающим `onSessionChanged`, а sync оставить строго в `initializeColdStart`;
   - обязательно добавить тест, который доказывает отсутствие двух конкурирующих switch-операций.

Жесткая оценка: делать только timeout и считать задачу закрытой - слабое решение. Оно ускорит cold start, но не устранит race в data scope. Делать double-store без теста - тоже слабое решение: можно просто поменять порядок гонки и получить flaky startup позже.
