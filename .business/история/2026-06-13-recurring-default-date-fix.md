# Рефлексия сессии: fix recurring default date

**Дата:** 2026-06-13
**Ветка:** develop
**Коммит:** 33927e9

## 1. Задача

Пользователь заметил, что при создании recurring income/expense транзакция сразу попадает в доходы/расходы, хотя дата ещё не подошла (на экране "Recurring income" у ЗП ББР стояло "Next: Jul 1, 2026").

## 2. Как решалась

- Исследовал цепочку: `CashflowScheduledTransactionsView` → `CashflowTransactionEditorView` → `CashflowPersistenceService` → `CashflowScheduledService.generateRecurringTransactionsIfNeeded()`
- Нашёл корень: при нажатии `+` на экране recurring `createInitialDate = Date()` (сегодня). Генератор создаёт occurrence для всех дат ≤ today, включая текущий месяц.
- Правка: `CashflowScheduledTransactionsView.swift:860` — дефолтная дата теперь 1-е следующего месяца.

## 3. Решена ли

- [x] Полностью (для новых recurring)
- Частично: если пользователь редактирует дату шаблона — orphaned occurrences не удаляются (нет cleanup в `CashflowScheduledService`). Требует отдельной задачи.

## 4. Эффективно ли

Да, исследование заняло ~10 итераций чтения кода. Можно было быстрее, если бы сразу проверил дефолтное значение `createInitialDate` в `handleCreateTapped`.

## 5. Было → стало

- **Было:** `createInitialDate = Date()` → occurrence за текущий месяц генерируется сразу
- **Стало:** `createInitialDate` = 1-е следующего месяца → пользователь создаёт "ЗП monthly" и первая occurrence появится только 1 июля

## 6. Идеи по улучшению

- **process:** При дебаге "почему транзакция появляется сразу" — первым делом смотреть на default-дату в точке открытия редактора, а не разбирать всю цепочку генерации.
- **business:** Стоит добавить cleanup orphaned occurrences при изменении даты шаблона (отдельная задача).
- **UX:** В редакторе recurring показывать хинт "Первое вхождение: [дата]" чтобы пользователь понимал, когда появится первая транзакция.
