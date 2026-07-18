# Plan: Archive Balance Warning

**Slug:** `archive-balance-warning`
**Дата создания:** 2026-05-17
**Stage:** 4 / Implementation
**Spec:** —
**Research:** —

## Статус

`РЕАЛИЗОВАН`

**Реализовано:** Phase 1 — проверка баланса и алерт в двух точках вызова
**Осталось:** —

## Цель

Предупреждать пользователя алертом при попытке архивировать счёт (карту, кредит, инвестицию) с ненулевым балансом, чтобы не потерять данные молча.

## Acceptance Criteria

- [x] AC1: При попытке архивировать ��чёт с балансом ≠ 0 — показывается алерт с суммой остатка
- [x] AC2: Алерт содержит кнопки «Всё равно архивировать» (продолжить) и «Отмена»
- [x] AC3: Если баланс = 0 — архивирование происходит без алерта (прежнее поведение)
- [x] AC4: Локализация RU / EN / zh-Hans
- [x] AC5: UI-компоненты проекта (`FinancesDestructiveConfirmationOverlay`, `FinanceAmountText`, `MonetaCurrency`)

## Challenge Log

### 1. Решает ли план проблему из spec?
Все AC покрыты Phase 1.

### 2. Это самое эффективное решение?
- **Вариант A:** Встроить проверку в `FinanceAccountService.archiveAccount` и возвращать enum-результат → усложняет сервис, требует propagation через VM.
- **Вариант B (выбран):** Проверка в UI перед показом существующего confirmation overlay → минимальные изменения, без изменения сервисного слоя.

### 3. Нет ли кода ради кода?
Каждое изменение обслуживает AC. Drive-by рефакторинг не производился.

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

### `[x]` Phase 1: Проверка баланса + алерт

**AC из spec:** AC1–AC5

**Файлы:**
- `millio/UI/Services/Finances/FinanceDynamicsView.swift` — @State переменные, новый overlay, логика в `deleteAccountFooterButton`, computed `archiveBalanceWarningMessage`
- `millio/UI/Services/Finances/Editors/FinanceGroupEditorView.swift` — аналогично, через `pendingAccountDeletionAfterWarning`
- `millio/Localizable.xcstrings` — 3 новых ключа: `finances.archive.balance_warning.title`, `.message`, `.confirm` (RU/EN/zh-Hans)

**Логика определения баланса:**
- `Card`: `financeViewModel.getAccountInfo(account:)?.amount` → для дебет-карты `availableAmount`, для кредитной `debtAmount`
- `Credit`: `remainingAmount`
- `Investment`: `amount`
- Порог: `abs(amount) > 0.001`

**Шаги:**
1. `[x]` Имплементация
2. `[x]` Self-audit (все AC покрыты)

**Что сделано:** Реализовано полностью в одной сессии.

---

## Edge Cases

- [x] Баланс = 0 → алерт не показывается
- [x] `getAccountInfo` возвращает nil → `amount = 0`, алерт не показывается (безопасный fallback)
- [x] `MonetaCurrency` не распознаёт код → fallback на сырой код валюты
- [x] Кредитная карта с долгом → `debtAmount` (позитивное число)

## Журнал изменений

- `2026-05-17` — создан план, Phase 1 реализована.

## Итог

**Результат:** `РЕАЛИЗОВАН`
**Что реализовано:** Алерт при ненулевом балансе в двух точках UI (FinanceDynamicsView + FinanceGroupEditorView), локализация RU/EN/zh-Hans
**Дата завершения:** 2026-05-17
