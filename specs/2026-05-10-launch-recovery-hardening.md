# Spec: launch-recovery-hardening

**Date:** 2026-05-10
**Stage:** 2 / Spec
**Research:** [`thoughts/research/2026-05-10-launch-recovery-hardening.md`](../thoughts/research/2026-05-10-launch-recovery-hardening.md)
**Plan:** [`plans/2026-05-10__launch-recovery-hardening.md`](../plans/2026-05-10__launch-recovery-hardening.md)

## Problem

После обновления приложения пользователи теряют данные. Корневая причина — `exportedModelCount` вызывается синхронно в момент, когда SwiftData ещё не закончил загрузку данных в контекст. Функция возвращает `0`, `LaunchRecoveryPolicy` решает что данные утеряны и запускает авто-restore из бэкапа — перезаписывая свежие данные более старой копией.

Дополнительно: нет координации между авто-бэкапом и restore (могут работать параллельно), нет таймаута на CloudKit-запрос при restore, нет защиты от бесконечного цикла restore при повреждённом бэкапе.

## Goal

Авто-restore при старте должен срабатывать только когда данные **достоверно** отсутствуют, никогда не запускаться параллельно с бэкапом, завершаться с таймаутом, и не зацикливаться при повреждённом бэкапе.

## Scope

- Заменить синхронный `exportedModelCount` на async-safe fetch через `ModelContext` (устранение race condition)
- Ввести флаг `isRestoreInProgress` в `AppState`, блокирующий `triggerBackgroundBackup` на время restore
- Добавить таймаут 30 сек на `restoreVersion()` в `presentRestoreFlowIfNeeded`
- Добавить счётчик попыток авто-restore (лимит 2) с хранением в `UserDefaults`; при превышении — прямой переход в ручной `.restoring` без повторных попыток
- Добавить тесты на непокрытые edge cases

## Non-Goals

- Рефактор `LaunchRecoveryPolicy` в отдельный Actor (Вариант C из research — слишком большой scope)
- Изменение UX экрана `AutoRestoringView`
- Изменение логики pinned/auto бэкапов и retention policy
- Поддержка merge при restore (restore всегда snapshot-replace)

## Acceptance Criteria

- [ ] AC1: При старте с непустым SwiftData-стором авто-restore **никогда** не запускается, даже если контекст ещё не завершил загрузку данных
- [ ] AC2: Пока идёт авто-restore, `triggerBackgroundBackup` не выполняется (флаг блокировки)
- [ ] AC3: Если CloudKit не ответил за 30 секунд — restore завершается с ошибкой, lifecycle переходит в `.restoring` (ручной режим)
- [ ] AC4: После 2 неудачных авто-restore подряд — следующий старт не пытается авто-restore снова, сразу показывает ручной экран
- [ ] AC5: Все failure paths логируются через `CrashReporting.record(error:)` (non-fatal)
- [ ] AC6: Тесты покрывают: race condition (count=0 до загрузки), CloudKit timeout, превышение лимита попыток, параллельный backup+restore

## Constraints

- **Стек:** Swift Concurrency (async/await, actors) — без GCD, без DispatchQueue
- **Производительность:** async fetch не должен блокировать main thread; UI-старт не должен замедлиться более чем на 100 мс
- **Совместимость:** не ломать `LaunchRecoveryPolicyTests` (уже покрывают базовые кейсы)
- **Срок:** нет жёсткого дедлайна, но приоритет высокий — активные жалобы пользователей

## Edge Cases

- **Стор пуст И бэкапа нет** → restore не запускается, lifecycle → `.ready`, пользователь видит пустое приложение (штатно для новой установки)
- **Стор пуст И бэкап повреждён** → авто-restore фейлится, счётчик +1, при лимите → ручной экран с объяснением
- **Kill app в середине restore** → при следующем старте стор всё ещё пуст, счётчик инкрементирован; если лимит не исчерпан — повторная попытка; если исчерпан — ручной
- **CloudKit недоступен** → таймаут 30 сек → `.restoring` (ручной)
- **Бэкап есть, данные загружаются медленно (>1 сек)** → async fetch дожидается реального результата, restore НЕ запускается

## Open Questions

- Где хранить счётчик попыток: `UserDefaults` vs `AppState` vs отдельный файл? → `UserDefaults` — проще, не зависит от SwiftData (который может быть недоступен именно в этот момент)
- Что показывать пользователю при превышении лимита попыток? Сейчас `.restoring` — ручной экран. Достаточно ли этого или нужен отдельный "не удалось восстановить" экран? → Оставить `.restoring`, это MVP-решение
