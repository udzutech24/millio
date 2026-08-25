# Research: сумма вклада/долга и overflow-действия

- Date: 2026-08-23
- Scope: экран деталей вклада и кредитной карты в iOS-приложении Millio.

## Reproduction/evidence

На карточке вклада пользователь видит крупные кнопки `Изменить условия`, `Закрыть досрочно` и `Удалить`, но не может задать текущую сумму. В `DepositDetailPresentation` в доступных действиях отсутствует изменение суммы, а `DepositDetailSection` выводит все действия одной сеткой. Скриншот пользователя подтверждает перегруженный нижний блок действий.

У кредитной карты форма изменения суммы долга уже есть в `AccountDetailView`, но наряду с ней ряд общих действий выводит редактирование карточки и удаление как обычные кнопки. Это не соответствует запросу скрыть редкие/разрушающие действия в `…`.

## Current architecture and constraints

- `AccountDetailView` владеет sheet/alert-навигацией и является единственным UI-маршрутом действий продукта.
- `AccountsCoreService.adjustBalance` создаёт append-only `adjustment`-событие, а не меняет баланс напрямую.
- У вклада будущие проценты хранятся как сгенерированные forecast-события. Простое использование `adjustBalance` оставит их рассчитанными для старой суммы: прогноз и итог будут неверны.
- `DepositOperationCoordinator` уже является единственным атомарным writer-ом специфичных операций вклада и умеет пересобирать будущий график внутри одной save-boundary.
- `DepositDetailPresentationTests` проверяет pure mapping жизненного цикла и доступных действий; coordinator-тесты покрывают атомарные графы операций.

## Options considered

1. Добавить в UI вклада существующую `AccountAdjustBalanceSheet` и вызвать `AccountsCoreService.adjustBalance`.
   - Отклонено: проценты в будущем графике не пересчитываются, финансовый прогноз становится ложным.
2. Позволить редактировать начальное `openingBalance`-событие.
   - Отклонено: разрушает audit trail и может конфликтовать с историческими начислениями.
3. Добавить в `DepositOperationCoordinator` отдельную команду установки текущей суммы: вычислить дельту, создать `adjustment`, удалить/пересобрать forecast после даты операции, выполнить единый commit.
   - Рекомендовано: сохраняет event sourcing, историческую прозрачность и согласованный прогноз.

## Recommended option and why

Для активного вклада показывать две основные операции: `Пополнить` (только если это разрешено условиями) и `Изменить сумму`. Остальные действия — `Изменить условия`, `Закрыть досрочно`, действие по сроку и `Удалить` — перенести в `Menu` с кнопкой `…` в navigation bar. Для кредитной карты оставить основные денежные операции, включая `Изменить сумму долга`, и убрать редактирование/удаление в то же overflow-меню.

Изменение суммы вклада реализовать новой command-операцией coordinator-а, а не UI-обходом: создать дельту (`adjustment`) на выбранную дату, пересобрать последующие прогнозные проценты и сохранить всё атомарно.

## Risks and unknowns

- Корректировка задним числом после уже подтверждённых процентов должна пересчитывать только generated forecast после даты изменения, не переписывая подтверждённые банковские начисления.
- Для закрытого, созревшего или incomplete-вклада запись суммы недоступна: это состояние read-only/требует уже существующего закрывающего сценария.
- `Удалить` остаётся destructive и обязан сохранить текущие confirmation alerts; его перенос в меню не снижает защиту.
- Нужно проверить компактную и accessibility-верстку: `…` в toolbar не должен вытеснять название длинного вклада.

## Relevant files/tests

- `millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift`
- `millio/UI/Services/Finances/AccountsCore/Deposit/DepositDetailSection.swift`
- `millio/UI/Services/Finances/AccountsCore/Deposit/DepositPresentation.swift`
- `millio/Core/AccountsCore/Deposit/DepositOperationCoordinator.swift`
- `millioTests/UI/Services/Finances/DepositPresentationTests.swift`
- `millioTests/Core/AccountsCore/DepositOperationCoordinatorTests.swift`
