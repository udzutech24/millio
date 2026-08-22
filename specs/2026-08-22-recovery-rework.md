# Spec: Переработка backup/recovery (recovery-rework)

**Date:** 2026-08-22
**Author:** Алексей (владелец)
**Related:** `specs/2026-08-22-phase-9-reliable-recovery.md` (Phase 9 — предшественник), `plans/2026-08-22__phase-9-reliable-recovery.md`

## Контекст

Phase 9 доставила *компоненты* восстановления (`RecoveryCoordinator`, `RecoveryReceipt`, `RecoveryDataPresence`, verified restore, rollback, тесты). Но **путь запуска и путь импорта файла остались не перепрошиты на эти компоненты**: прод дергает только `restoreExplicit`, авто-restore идёт мимо координатора, импорт файла не ведёт к restore. Эта спека закрывает разрыв между построенным ядром и реальными пользовательскими сценариями.

## Problem

Пользователь с валидным бэкапом не может восстановить данные: файл, открытый из Files, попадает в тупик; авто-restore на старте не обновляет UI; экран восстановления мигает и переспрашивает CloudKit; ошибка сети неотличима от «бэкапа нет».

## Подтверждённые дефекты (верификация по коду 2026-08-22)

| # | Дефект | Доказательство (file:line) |
|---|--------|---------------------------|
| D1 | `presentRestoreFlowIfNeeded` не идемпотентна: вызывается из `synchronizeDataScope` на cold start и на `onSessionChanged`; между вызовами root пересобирается по `.id(RootSceneIdentity(...scope:))` → `@State` RestoreView сбрасывается, CloudKit-лукап повторяется, экран мигает | `millioApp.swift:1229`, `:625`, `:344`, `:459-461`, `:159`; `StartupCoordinator.swift:49` |
| D2 | Импорт файла ≠ restore. `importVersion` только добавляет версию в список | `BackupManagementView.swift:944-946` |
| D3 | `pendingIncomingBackupURL` потребляется только `BackupManagementView`; иначе тупик и навсегда заблокированы шиты выписок | `millioApp.swift:239`; `BackupManagementView.swift:287-288, 312-314`; `RootTabView.swift:187` |
| D4 | В `RestoreView` нет импорта файла вообще | `RestoreView.swift` (нет точки входа) |
| D5 | Расширение при `onOpenURL` — `millio-backup`, а экспорт пишет `.milliobackup` → входящий файл может не распознаться | `millioApp.swift:237-241` vs `BackupManager.swift:996`, `BackupManagementView.swift:37`; `Info.plist:48-73, 96-101` |
| D6 | Авто-restore публикует только `.restoreCompleted`, а `PostRestoreRefreshCoordinator` слушает `.restoreVerified` → root-rebuild/refresh не срабатывает, данные не видны без перезапуска | `BackupManager.swift:314` (restoreLatest) vs `:439-440` (restoreExplicit); `PostRestoreRefreshCoordinator.swift:21` |
| D7 | Отбор кандидата по размеру `size >= 1024` (есть TODO), а не по modelCount | `millioApp.swift:1276-1278` |
| D8 | Молчаливые пропуски recovery: guest-scope → skip; `localDataCount == nil` → выход; ошибка CloudKit глотается в `nil` = «бэкапа нет» | `LaunchRecoveryPolicy.swift:60-62`; `millioApp.swift:1232-1235`; `BackupManager.swift:909-916` |
| D9 | Строка таймаута лукапа — захардкоженный английский, не через L10n (кнопка Retry при этом есть) | `RestoreView.swift:508, 522-523`; retry — `:386-393` |
| D10 | Три флага одного состояния: `autoRestoreAttemptsKey`, `RecoveryPromptStore`, `activeScopeStoreExistedBeforeBinding` | `millioApp.swift:1128, 1239/1264/1270/1286`; `RecoveryPromptStore.swift`; `millioApp.swift:81/110/728, 1247/1263` |
| D11 | Мёртвый код в `RecoveryCoordinator`: `retry()`, `cancel()`, `reset()` не вызываются нигде; `discover`/`restoreConfirmed` — только из тестов | `RecoveryCoordinator.swift`; прод-вызовы только `restoreExplicit` (`:110`) из `BackupManagementView.swift:859`, `RestoreView.swift:426` |
| D12 | Прямые `CloudBackupStore()` мимо DI/`SwitchingBackupManager` | `RestoreView.swift:508`; `BackupManagementView.swift:791` |

## Goal

Валидный бэкап-файл или облачный бэкап **всегда доводится до восстановленных данных на экране** — из любой точки входа (cold start, Files, RestoreView, BackupManagementView), без перезапуска приложения, с отличимой диагностикой отказа.

## Scope

### In Scope
- Идемпотентная, переживающая remount точка входа launch-recovery; единый `RecoveryDecisionStore` вместо трёх флагов.
- Прошивка авто-restore через верифицированный путь координатора (receipt + `.restoreVerified` + refresh-барьер).
- Отбор кандидата по `modelCount`/метаданным вместо порога размера.
- Полный путь «файл → restore»: `onOpenURL` (оба расширения) → импорт → предложение restore → подтверждение → верифицированный restore → refresh; импорт файла доступен и из `RestoreView`.
- Разделение «бэкапа нет» / «CloudKit не ответил» / «нет доступа к iCloud» типизированным результатом; RU-локализация всех строк recovery; Retry.
- Разблокировка шитов выписок после потребления `pendingIncomingBackupURL`.
- Чистка: мёртвые методы координатора, прямые `CloudBackupStore()` → DI.

### Out of Scope
- `RecoveryDataPresence` (белый список 10 типов), financial-guard на трёх входах бэкапа, receipt ручного restore, legacy-совместимость v2.0.0 — **не трогаем**, покрыты тестами.
- Merge-restore, выбор моделей пользователем, включение живой CloudKit-синхронизации SwiftData.
- Изменения схемы бэкапа, backend, App Store/деплой.

## Acceptance Criteria

- [ ] **A1 (главный сценарий владельца).** Файл `millio-backup-2026-08-15_08-42-v1.9.milliobackup` (валиден, 1673 модели, не зашифрован, схема 2.0), открытый из Files **или** импортированный внутри приложения на пустой базе, приводит к явному предложению restore; после подтверждения данные видны на Dashboard / Счета / Analytics / Cashflow **без перезапуска**.
- [ ] **A2.** Экран recovery не мигает: при cold start + `onSessionChanged` лукап CloudKit выполняется один раз на поколение scope; повторный вызов `presentRestoreFlowIfNeeded` идемпотентен; состояние переживает remount root.
- [ ] **A3.** «Бэкапа нет» ≠ «CloudKit не ответил»: типизированный результат лукапа, разные RU-строки, Retry на восстановимых отказах.
- [ ] **A4.** Пустой авторизованный scope всегда получает предложение recovery до явного отказа пользователя; отказ фиксируется в едином `RecoveryDecisionStore` и переживает перезапуск; recovery остаётся доступен из Профиля.
- [ ] **A5.** Авто-restore успешен ⇒ публикуется `.restoreVerified` с receipt, refresh-барьер отрабатывает, UI обновлён без перезапуска. Неверифицированный restore не может считаться успехом.
- [ ] **A6.** Отбор кандидата не использует порог размера; при отсутствии `modelCount` в метаданных решение принимается явным правилом, а не молчаливым пропуском.
- [ ] **A7.** Оба расширения (`.millio-backup`, `.milliobackup`) распознаются на входе; `pendingIncomingBackupURL` потребляется recovery-путём, после потребления шиты выписок не заблокированы.
- [ ] **A8.** Импорт в `BackupManagementView` при непустой базе требует явного подтверждения перезаписи; при неудаче импорта отрабатывает rollback.
- [ ] **A9.** Мёртвые методы `RecoveryCoordinator` удалены или покрыты реальными вызовами; прямых `CloudBackupStore()` в UI не осталось (grep-чек = 0).
- [ ] **A10.** Три флага заменены одним стором; ни один старый ключ не читается (grep-чек), миграция существующего значения не ломает поведение при обновлении.
- [ ] **A11.** Все существующие тесты backup/restore зелёные (список из 25 файлов, см. план); новых красных нет.
- [ ] **A12.** Финальная приёмка: все пользовательские сценарии recovery (чек-лист фазы R7) помечены пройден/не пройден с доказательством.

## Constraints
- Snapshot replacement остаётся канонической семантикой restore; rollback обязателен.
- Координатор привязан к одному поколению scope; stale-колбэк не может опубликовать успех.
- Никакого PII в логах (user id, email, имена файлов store, record names).
- Обратная совместимость: legacy v2.0.0 бэкапы читаются как сейчас.
- Изменение затрагивает протестированное ядро ⇒ **обязателен `/stress-test` и явное «да» владельца до реализации** (правило 7 workspace CLAUDE.md).
- Реальных пользователей — один (владелец), бэкап есть; риск калибруется соответственно, но тестовая дисциплина сохраняется.

## Non-Goals
- Красота ради красоты в неподтверждённых местах: правим только дефекты D1–D12.
- Переписывание `BackupManager` целиком.
- Шифрование/пароли: меняем только классификацию и локализацию ошибок, не механику.
