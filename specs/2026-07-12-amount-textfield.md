# Spec: AmountTextField — переиспользуемое поле денежного ввода

**Дата:** 2026-07-12 · **Размер:** M · **Статус:** В РАБОТЕ
**Источник:** research `thoughts/research/2026-07-12-account-forms-and-recurring-income.md` (находка 2, PR-2)
**Правило проекта:** `feedback-amount-input-formatter-global-rule` — любой денежный TextField только через `AmountInputFormatter`, helpers вынести в общий компонент.

## WHY

Живого форматирования разрядов (`10000` → `10 000`) нет в формах создания счётов: пользователь не может проверить крупную сумму на глаз. Рабочий raw+display паттерн уже есть только в `CashflowTransactionEditorView` (скопирован inline, не переиспользуется). Копии `Double(text.replacingOccurrences(of: ",", with: "."))` разбросаны по формам (`InlineDepositCreateForm.parseNumber`, `InlineCreateForms`).

## WHAT

Обёртка-View `AmountTextField` (НЕ ViewModifier) поверх существующего `AmountInputFormatter`.
Наружу — канонический raw-decimal (разделитель `.`), внутри — отформатированная display-строка.

### API
```swift
AmountTextField(
    placeholder: String,
    value: Binding<String>,        // канонический raw ("10000.5")
    maxFractionDigits: Int = AmountInputFormatter.defaultFractionDigits,
    font: ((String) -> Font)? = nil // размер шрифта по длине display-текста (сцена Cashflow)
)
```

### Семантика (скопирована из CashflowTransactionEditorView — эталон)
- Два состояния: внешний `value` (raw) + внутренний `@State displayText` (formatted).
- `onChange(displayText)`: `sanitize` → canonical; `display` → formatted; реассайн только при реальном отличии (курсор не прыгает).
- `onChange(value)` + `onAppear`: программная синхронизация raw → display (edit-режим, prefill).
- Разделитель дробной части — канонический `.` (как Cashflow `display()`), запятая нормализуется на входе.

## Acceptance criteria

1. Round-trip raw↔display: пустая строка, ведущий ноль, только разделитель, дробь длиннее `maxFractionDigits`.
2. Deposit-форма: amount/rate/penalty через `AmountTextField`; `parseNumber` → `AmountInputFormatter.parse`.
3. `InlineCreateForms`: 3 копии мигрированы по одной, build+тест после каждой.
4. Cashflow: inline-паттерн заменён обёрткой, поведение (курсор, font-closure :614) идентично; Cashflow-тесты зелёные.
5. Нет остаточных raw-паттернов `replacingOccurrences(of: ",", with: ".")` / дублирующего inline sanitize в мигрированных формах.

## Out of scope
- Локализованный decimal separator в поле (Cashflow его не использует — сохраняем паритет).
- FocusState-цепочка между полями (отдельная токен-чистка каркаса).
- Toggle авто-линковки Cashflow (PR-3, после спеки).
