# Финансы: локализация создания продукта

## Что покрыто
- Экран создания/редактирования продукта (`FinanceAddAccountView`) переведен на ключи `finances.add_account.*`.
- Inline-формы (`InlineCreateForms`) переведены на ключи локализации для полей, секций и подсказок.
- `displayName` для enum'ов, участвующих в создании продукта, больше не захардкожен на русском:
  - `CardType`
  - `InvestmentType`
  - `InvestmentCategory`
  - `CreditType`
  - `CreditPaymentMode`
- Дополнительно переведены и переведены на ключи i18n:
  - `FinanceDynamicsView` (включая фильтры, trade-sheet, empty/pro states, custom period, валютный picker)
  - `DisplayCurrencySheet` и `SavingsGoalSettingsView`
  - `CardEditorView`, `CreditEditorView`, `InvestmentEditorView`, `FinanceQuickEditAccountView`
  - `FinanceGroupEditorView`, `GroupPriority`
  - заметка транзакции в `CreditViewModel` при ручной корректировке остатка долга

## Критичный фикс для i18n
Ранее плейсхолдеры зависели от сравнения с русской строкой `"Счет"`.
Теперь используется отдельный preset выбора (`FinanceAddAccountInvestmentPreset`), поэтому логика не зависит от языка.

## Как расширять на новые языки
1. Добавлять переводы только в `Localizable.xcstrings` для ключей `finances.add_account.*` и связанных enum-ключей.
2. Для финансовых экранов вне create-flow использовать префиксы:
   - `finances.editor.*`
   - `finances.dynamics.*`
   - `finances.display_currency.*`
   - `finances.savings_goal.*`
   - `finances.quick_edit.*`
   - `finances.group_editor.*`
3. Не добавлять логику, завязанную на отображаемый текст (`displayName`, `Text`, `String(localized:)`).
4. Для новых UI-полей сразу заводить ключи по доменной зоне экрана, а не по literal-строке.
