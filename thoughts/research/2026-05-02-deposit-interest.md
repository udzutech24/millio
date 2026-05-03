# Research: Процентный доход по вкладам

**Date:** 2026-05-02
**Stage:** 1 / Deep Research (read-only)
**Related:** [`specs/2026-05-02-deposit-interest.md`](../specs/2026-05-02-deposit-interest.md)

## Задача исследования

Изучить текущую реализацию типа "Вклад" в приложении и понять, как добавить поля процентной ставки + автоматическое планирование дохода в Cashflow.

## Findings from codebase

### Текущая реализация "Вклад"

**Пикер продуктов:** `UI/Services/Finances/Editors/FinanceAddAccountProductPicker.swift`
- `FinanceAddAccountProductKind.deposit` существует — это тип в UI-пикере
- При выборе "Вклад" создаётся: `accountType: .investment, investmentCategory: .other, investmentPreset: .deposit`
- Описание в пикере: "срок, ставка, проценты" — декларируется, но НЕ реализовано

**Пресет:** `UI/Services/Finances/Editors/FinanceAddAccountInvestmentPreset.swift`
- `enum FinanceAddAccountInvestmentPreset { case account, deposit, asset, category }`
- Пресет `deposit` передаётся в `InvestmentEditorView` через `FinanceAddAccountView`, но редактор его **игнорирует** (нет `guard` или `if isDeposit` внутри)

**Модель данных:** `UI/Services/Investments/Investment.swift` (430 строк)
- SwiftData `@Model final class Investment`
- Поля: `name`, `amount`, `currency`, `categoryRaw`, `investmentTypeRaw`, `includeInTotal`, `priorityRaw`, `isFavorite`, `archivedAt`, `uniqueID`, + рыночные данные (symbol, quantity, unitPrice, ...)
- **Deposit-специфичные поля ОТСУТСТВУЮТ**: нет `interestRate`, `depositStartDate`, `depositEndDate`, нет cashflow-линка

**Редактор инвестиций:** `UI/Services/Finances/InvestmentEditorView.swift`
- Не принимает параметр `investmentPreset` — нет условного UI для депозита
- `@State` не содержит `depositInterestRate`, `depositStartDate`, `depositEndDate`

### Cashflow — как устроено планирование

**Модель:** `UI/Services/Cashflow/CashflowTransaction.swift`
- `CashflowTransactionType`: income, expense, transfer, balanceAdjustment, cardBalanceAdjustment, creditDebtAdjustment
- `CashflowRecurrenceRule`: none, weekly, **monthly**, quarterly, semiannual, yearly
- `IncomeCategory.interest = "interest"` — категория "Проценты 🏦" уже есть
- `CashflowScheduledTransactionsView` — есть экран запланированных транзакций

**Scheduled transactions существуют** (`CashflowScheduledTransactionsView.swift`, `CashflowTransactionEditorView.swift`) — значит механизм повторяющихся доходов в системе уже есть.

### Зависимости

- `Investment.swift` — SwiftData @Model, требует миграции при добавлении полей
- `InvestmentEditorView.swift` — UI редактора, нужна новая секция
- `FinanceAddAccountView.swift` — передаёт preset, нужно прокидывать флаг isDeposit при создании
- `CashflowViewModel.swift` (4598 строк — God-VM!) — логика создания/обновления scheduled transactions, трогать точечно
- `Localizable.xcstrings` — новые строки

### Тесты

- `millioTests/` — unit-тесты. Нужно проверить, есть ли тесты на Investment.

## Alternatives

### Вариант A: Расширить Investment-модель (deposit-флаг + поля)
- **Плюсы:** Не нужна новая модель/миграция с нуля; deposit остаётся Investment (тот же список, те же группы, тот же backup); пресет уже передаётся
- **Минусы:** Модель Investment становится чуть жирнее (7 новых опциональных полей)
- **Трудоёмкость:** M

### Вариант B: Новая SwiftData-модель Deposit
- **Плюсы:** Чистое разделение ответственностей
- **Минусы:** Новая миграция схемы, дублирование логики (списки, группы, backup), перегруз контекста; FinanceAccount нужен новый тип
- **Трудоёмкость:** L

### Вариант C: Хранить параметры вклада в JSON-метаданных (userMetadata: String?)
- **Плюсы:** Нет изменения схемы
- **Минусы:** Нетипизировано, хрупко, не SwiftData-идиоматично, нет query поддержки
- **Трудоёмкость:** S (но плохо)

## Recommendation

**Выбран:** Вариант A — расширить Investment-модель.

**Почему:**
1. Минимальный blast radius: deposit уже является Investment по всей системе
2. Backup/restore, группы, списки — работают без изменений
3. Пресет уже передаётся через FinanceAddAccountView → можно проставить `isDeposit = true` при создании
4. SwiftData поддерживает добавление опциональных полей без явной миграции (lightweight migration)

**Что учесть при имплементации:**
- `isDeposit: Bool = false` нужен, чтобы редактор знал, что это депозит (иначе нет способа отличить от обычного Investment с category=other)
- При изменении `amount` или `depositInterestRate` — пересчитывать плановый доход в linked scheduled transaction
- При архивации вклада — удалять/деактивировать scheduled transaction
- CashflowViewModel (4598 строк) — трогать только точечно через конкретный метод
- `depositLinkedScheduledID` — нужен для обновления/удаления linked transaction при изменениях
