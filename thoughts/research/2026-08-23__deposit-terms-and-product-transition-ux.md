# Research: UX условий вклада и смены типа продукта

- Date: 2026-08-23
- Scope: `AccountProductTransitionSection`, `DepositTermsEditSheet`, initial deposit form.

## Evidence

Пользовательские снимки показывают три наблюдаемые UX-сбоя: длинный системный product picker закрывает форму; поля ставки/штрафа выглядят как неподписанные числа; верхняя кнопка `Сохранить` оказывается за клавиатурой и после нажатия создаёт ощущение случайного выхода.

Код подтверждает функциональные дефекты:

- `AccountProductTransitionFormMapper.depositMetadata` всегда сохраняет `payoutDay: nil`, поэтому при переходе к вкладу нельзя указать, когда начисляется доход.
- `AccountProductTransitionSection` и `InlineDepositCreateForm` задают штраф досрочного закрытия как `100`, хотя владелец продукта зафиксировал безопасный default `0`.
- `DepositTermsEditSheet` уже инициализирует текущий штраф как `0`, но оставляет без контекстной подписи и использует верхнее `Сохранить`.

## Recommended UX

1. Смена типа — отдельный экран: текущий тип pinned сверху, целевые варианты как grouped rows/cards; при конверсии остаётся текущий confirmation dialog.
2. Условия вклада — отдельные блоки `Доходность`, `Срок`, `Пополнение и закрытие`. День начисления показывается только для monthly/quarterly и называется «День начисления процентов».
3. `Потеря процентов при досрочном закрытии` — самостоятельная строка с суффиксом `%`, дефолт `0`, крупное значение и hint, что процент применяется к уже начисленному доходу.
4. Сумма не входит в форму условий. Отдельная action-sheet из фазы 2 вызывает atomic adjustment command и не даёт смешать commit условий с финансовым событием.
5. Toolbar оставляет `xmark` для отмены; action внизу использует стандартный app-primary style, фиксируется над keyboard safe area и меняет текст согласно операции.

## Risks

- Смена типа — не просто визуальная настройка: существующая policy может выбрать in-place correction, replacement conversion или block. Новый экран обязан показывать это до CTA.
- Нельзя записывать payout day при capitalization `.none`; scheduler всё равно применяет payout day при monthly/quarterly.
- Нельзя менять уже подтверждённые начисления при правке условий; coordinator продолжает пересобирать только future schedule.

## Relevant files/tests

- `millio/UI/Services/Finances/AccountsCore/AccountProductTransitionSection.swift`
- `millio/UI/Services/Finances/AccountsCore/AccountDetailSheets.swift`
- `millio/UI/Services/Finances/AccountsCore/Deposit/DepositOperationSheets.swift`
- `millio/UI/Services/Finances/AccountsCore/InlineDepositCreateForm.swift`
- `millioTests/UI/Services/Finances/AccountProductTransitionPresentationTests.swift`
- `millioTests/UI/Services/Finances/DepositPresentationTests.swift`
