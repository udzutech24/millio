# План: AmountTextField (PR-2)

**Дата:** 2026-07-12 · **Спека:** `specs/2026-07-12-amount-textfield.md` · **Статус:** В РАБОТЕ
**Ветка:** `feature/amount-textfield` (от develop, HEAD 14d78c4)

Строгий порядок (утверждён владельцем после стресс-теста). Между шагами: `xcodebuild ... -quiet 2>&1 | tail -20` + релевантные unit-тесты. Красный/непадтверждённый гейт → стоп, не переходить дальше.

## Фаза 1 — компонент + тест [x] РЕАЛИЗОВАН
- `millio/UI/Shared/AmountTextField.swift` (рядом с AmountInputFormatter).
- Unit-тест round-trip: пустая строка, ведущий ноль, только разделитель, дробь > maxFractionDigits.
- Gate: build зелёный (только пред-существующие warnings) + AmountTextFieldTests 6/6 зелёные.

## Фаза 2 — InlineDepositCreateForm [x] РЕАЛИЗОВАН
- amount, rate, penalty → `AmountTextField`. `parseNumber` → `AmountInputFormatter.parse`.
- Gate зелёный (build чистый, 3 тест-сьюта без падений).

## Фаза 3 — InlineCreateForms (по одной форме) [x] РЕАЛИЗОВАН
- 3a Card: balance/creditLimit/creditDebt — side-effect пересчёт перенесён в onChange(of:rawText).
- 3b Credit: amount/remaining/monthlyPayment — убраны 3 DisplayText+handler.
- 3c Investment: amount(программная запись через onChange value)/marketQuantity(maxFrac=12)/purchaseUnitPrice.
- Каждый под-шаг: build чистый + тесты без падений, отдельный коммит.
- Особенность Investment: amountText пишется программно (positionTotal) — покрыто onChange(of:value) обёртки.

## Фаза 4 — Cashflow (последним, рискованный) [ ] НЕ НАЧАТ
- `CashflowTransactionEditorView.swift`: inline-паттерн → `AmountTextField` c font-closure (:614).
- Сверить: курсор не прыгает, шрифт как раньше.
- Gate: все Cashflow-related unit-тесты зелёные.

## Журнал
- 2026-07-12: ветка создана, spec+plan заведены.
