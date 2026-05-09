# Plan: backup-restore-fix

**Slug:** `backup-restore-fix`
**Дата создания:** 2026-05-05
**Stage:** 3 / Planning → Implementation
**Связан с:** `BACKUP_HARDENING_AUDIT.md`, анализ 2026-05-09

## Статус

`В РАБОТЕ`

**Реализовано:** —
**Осталось:** Phase 1 → Phase 2 → Phase 3

## Цель

Починить backup/restore flow: данные из iCloud-бэкапа не восстанавливаются ни автоматически (нет launch-time recovery), ни надёжно вручную (UI просит "закройте и откройте приложение" вместо авто-перезагрузки).

## Acceptance Criteria

- [ ] AC1: Integration test round-trip проходит — Card/Group/Account создан, экспортирован, store очищен, импортирован, FinanceViewModel видит данные через fetch.
- [ ] AC2: После ручного restore через BackupManagementView данные видны в UI **без перезапуска** приложения.
- [ ] AC3: При запуске с пустым store + существующим iCloud-бэкапом приложение автоматически переходит в `.restoring` flow.
- [ ] AC4: "Close and reopen the app" сообщение удалено / заменено на адекватное.

## Challenge Log

### 1. Решает ли план проблему из spec?
- AC1 → Phase 1 (integration test)
- AC2+AC4 → Phase 2 (UI reload после ручного restore)
- AC3 → Phase 3 (presentRestoreFlowIfNeeded)

### 2. Самое эффективное решение?
- **Вариант A:** Принудительно перезапускать app после restore (UIApplication reset). Минус: плохой UX, сложно тестировать.
- **Вариант B:** После restore publish event → VMs перечитывают store. Плюс: уже частично реализовано, тестируемо, zero-restart. **Выбрано.**

### 3. Нет ли кода ради кода?
Каждая фаза закрывает конкретный AC. Drive-by рефакторинг — нет.

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[ ]` Phase 1: Integration test — round-trip Card+Group через DataRepository

**AC:** AC1

**Файлы:**
- `millioTests/Core/BackupRestoreIntegrityTests.swift` — добавить тест `testFullRoundTripCardAndGroupVisibleAfterRestore`

**Шаги:**
1. `[ ]` Написать тест: insert Card + FinanceGroup + FinanceAccount → exportAllData → clearAllData → importAllData → fetch и проверить count + конкретные значения
2. `[ ]` Запустить — убедиться что проходит (data layer работает)
3. `[ ]` Написать тест: то же + FinanceViewModel.loadAccounts() → проверить state
4. `[ ]` Коммит: `test(backup): round-trip integration test for Card+Group restore`

---

### `[ ]` Phase 2: Убрать "Close and reopen" — надёжный UI reload после ручного restore

**AC:** AC2, AC4

**Файлы:**
- `millio/UI/Profile/BackupManagementView.swift` — убрать showRestoreSuccessPrompt с "Close and reopen", заменить на dismiss + navigation back
- `millio/UI/Services/Finances/FinanceViewModel.swift` — убедиться что `restoreCompleted` → `loadGroups` + `loadAccounts` вызывается на MainActor после save

**Шаги:**
1. `[ ]` Проверить: `FinanceViewModel.loadGroups()` + `loadAccounts()` на MainActor после restoreCompleted — fetch видит новые объекты?
2. `[ ]` Обновить BackupManagementView: убрать "Close and reopen" alert
3. `[ ]` Коммит: `fix(backup): remove restart-required prompt, reload UI after restore`

---

### `[ ]` Phase 3: Подключить presentRestoreFlowIfNeeded — launch-time auto-recovery

**AC:** AC3

**Файлы:**
- `millio/millioApp.swift` — вызвать `presentRestoreFlowIfNeeded()` после `synchronizeDataScope` и в `rebindDataScope`

**Шаги:**
1. `[ ]` Добавить вызов в `initializeColdStart` (line ~196) после `synchronizeDataScope`
2. `[ ]` Добавить вызов в `rebindDataScope` (line ~382) после `applyDependencyBinding`
3. `[ ]` Добавить тест LaunchRecoveryPolicy для сценария "пустой store + есть бэкап + онбординг завершён"
4. `[ ]` Коммит: `feat(backup): auto-present restore flow on launch when store is empty`

---

## Журнал

| Дата | Что сделано |
|------|------------|
| 2026-05-09 | Диагноз: presentRestoreFlowIfNeeded мёртвый код, "close and reopen" UX, нет e2e теста |
