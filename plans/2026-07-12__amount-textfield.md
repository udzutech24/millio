# План: AmountTextField (PR-2)

**Дата:** 2026-07-12 · **Спека:** `specs/2026-07-12-amount-textfield.md` · **Статус:** В РАБОТЕ
**Ветка:** `feature/amount-textfield` (от develop, HEAD 14d78c4)

Строгий порядок (утверждён владельцем после стресс-теста). Между шагами: `xcodebuild ... -quiet 2>&1 | tail -20` + релевантные unit-тесты. Красный/непадтверждённый гейт → стоп, не переходить дальше.

## Фаза 1 — компонент + тест [x] РЕАЛИЗОВАН
- `millio/UI/Shared/AmountTextField.swift` (рядом с AmountInputFormatter).
- Unit-тест round-trip: пустая строка, ведущий ноль, только разделитель, дробь > maxFractionDigits.
- Gate: build зелёный (только пред-существующие warnings) + AmountTextFieldTests 6/6 зелёные.

## Фаза 2 — InlineDepositCreateForm [ ] НЕ НАЧАТ
- amount (:101), rate (:120), penalty (:167) → `AmountTextField`.
- `parseNumber` (:42-44) → `AmountInputFormatter.parse`.
- Gate: build + FinanceAddAccountProductCounterTests, AllPresetsOnNewCoreTests, InlineCardDraftTests зелёные.

## Фаза 3 — InlineCreateForms (по одной форме) [ ] НЕ НАЧАТ
- Мигрировать :152–166, затем :934–977, затем :1142–1152 — build+тест после каждой.
- Проверять особенности формы (отрицательные суммы, иной separator) перед заменой.

## Фаза 4 — Cashflow (последним, рискованный) [ ] НЕ НАЧАТ
- `CashflowTransactionEditorView.swift`: inline-паттерн → `AmountTextField` c font-closure (:614).
- Сверить: курсор не прыгает, шрифт как раньше.
- Gate: все Cashflow-related unit-тесты зелёные.

## Журнал
- 2026-07-12: ветка создана, spec+plan заведены.
