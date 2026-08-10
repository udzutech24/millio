# Research: продуктовая вертикаль «Кредитная карта»

- Date: 2026-08-09
- Scope: iOS AccountsCore, creation/detail/edit, AccountEvent, totals/history, Cashflow, backup/schema, localization/accessibility.
- Baseline: текущее незакоммиченное дерево пользователя (включая save-boundary и real-estate vertical); эти правки не изменялись.

## Reproduction/evidence

1. Creation: `FinanceAddAccountView.createMoneyAccountOnNewCore` передаёт `cardData.balance` как `openingBalance`; resolver создаёт `.creditCard` и `CardMeta(bank,last4,creditLimit)`. Поля `statementDay`, `dueDay`, `minPayment`, `graceDays`, `overdraftLimit` существуют и backup-ready, но форма их не пишет. APR, minimum-payment mode и reminder policy в persisted contract отсутствуют.
2. Текущий `balance` — доступный остаток лимита, не signed debt. Доказательство: `AccountTotalsContribution.signedValue = rawBalance - creditLimit`; тест использует `1_374_000 - 1_500_000 = -126_000`. Generic `.expense` уменьшает raw balance, `.income` увеличивает. Header detail при этом показывает raw balance как «баланс», то есть пользователь видит доступный остаток вместо задолженности.
3. Current/historical totals используют общую contribution-функцию и `participates(on:)`: задолженность уменьшает капитал, лимит не становится активом, `includeInTotal=false` исключает current/history и не влияет на видимость активного списка. Этот путь согласован, но зависит от двусмысленной модели «available balance».
4. Event contract не различает credit-card purchase/refund/repayment/interest: catalog разрешает только cash events (`openingBalance/income/expense/transfers/adjustment/redenomination`). `interest` и `fee` для credit card запрещены catalog; refund приходится маскировать как income, repayment — как income/transferIn, purchase — как expense.
5. Cashflow → AccountsCore bridge создаёт AccountEvent из уже существующей `CashflowTransaction`. Покупка как `.expense` признаётся Cashflow один раз и меняет account event. Однако отдельного event-first credit-card writer нет; нет контракта, который атомарно создаёт purchase/refund/fee/interest и Cashflow projection. Repayment через generic transfer не является расходом Cashflow, но специальная same-currency/source-funds policy отсутствует. Half-linked rollback для будущего двунаправленного writer не доказан.
6. Detail — generic `AccountDetailView`: header показывает raw balance; actions — generic income/expense/adjust/transfer; edit — generic `AccountEditDetailsSheet`. Нет debt hero, available limit/utilization, due/grace status, fee/interest totals, typed card operations и step-line debt chart.
7. Archive: generic non-zero warning предлагает «перевести остаток» или «закрыть с остатком». Для кредитки raw balance обычно ненулевой даже при нулевом долге, поэтому warning семантически неверен; он проверяет не задолженность. После архива экран не даёт actions, история сохраняется.
8. Refresh: detail локально меняет `refreshToken`; edit/archive публикуют `investmentsUpdated`. Cashflow writer сохраняет transaction + bridge events в одном context/save path, но отдельные detail events не публикуют глобальный finance event. Поэтому local detail обновляется, а list/dashboard после generic detail operation не доказаны без relaunch.
9. Atomicity: текущий пользовательский baseline вводит disposable-context `AccountProductFactory` и `AccountsCoreSaveBoundary`; creation/update rollback tests проходят. Специализированного atomic metadata editor и atomic repayment/purchase projection пока нет.
10. Localization/accessibility/render: credit-card namespace и typed presentation API отсутствуют. Generic localized keys существуют, но credit-card copy, RU/EN/zh-Hans mapping, raw-key render gate, 375/390 and accessibility-Dynamic-Type fixtures отсутствуют. Фактические обрезки нельзя честно утверждать без реализации и simulator render matrix.
11. Schema/backup: `CardMeta` уже выражает limit, statement/due day, fixed min payment and grace days; export/import round-trip реализован. APR, percentage minimum payment и reminder policy не выражены. Это ещё не доказывает необходимость schema: первая безопасная версия может поддержать fixed minimum only и хранить reminders через существующий notification contract. APR следует добавлять только additive migration после отдельного schema decision.

## Characterization command

`xcodebuild test -project millio.xcodeproj -scheme millio -destination 'platform=iOS Simulator,id=9C13646E-1C3D-45F4-A959-172FFE7CC63B' -only-testing:millioTests/AccountTotalsContributionTests -only-testing:millioTests/AllPresetsOnNewCoreTests -only-testing:millioTests/AccountsCoreUpdateAccountTests CODE_SIGNING_ALLOWED=NO`

Result: `TEST SUCCEEDED`; creation identity, current contribution formula, includeInTotal and atomic update baseline pass.

## Options considered

1. Keep available-balance ledger and add UI adapters. Rejected: preserves two meanings of balance and makes every operation/sign consumer fragile.
2. Introduce a parallel CreditCardTransaction model. Rejected: duplicates AccountEvent, totals, history, backup and Cashflow integration.
3. Recommended: keep Account/AccountEvent, define credit-card-specific event semantics and a pure presentation adapter where canonical account balance is signed net position (`-debt`, overpayment positive). Use a single atomic coordinator for AccountEvent + Cashflow projection/transfer legs. Migrate legacy credit-card event interpretation only through an explicit additive migration if fixtures prove it necessary.

## Phase 3 decision

Migration/schema change is not required. Existing `AccountEvent.typeRaw` accepts additive semantic raw values, while legacy opening events remain replay-compatible. `CreditCardFinancialContract` is the only conversion boundary from persisted available balance to canonical signed net position. New typed events preserve the legacy raw ledger signs, so old and new histories can be replayed together without a version marker or silent data rewrite.

## Risks and mitigations

- Existing persisted credit cards use available-balance semantics. Impact critical; do not flip engine semantics in place. Add characterization fixtures and a versioned migration/compatibility marker before Phase 3.
- Current dirty baseline overlaps core writers and detail UI. Freeze/commit that work before code phases or rebase each phase deliberately.
- Cashflow loops/double count. Give every projected transaction a stable source ID and one ownership direction; test idempotency and rollback.
- Month-end/timezone errors. Pure Gregorian calendar policy with injected timezone/calendar and clamped day-of-month tests.
- Bank rules are unknowable. Grace UI reports dates/status from metadata only and never promises absence of interest.

## Relevant files/tests

- `millio/Core/AccountsCore/{Account,AccountMeta,AccountEventType,AccountBalanceEngine,AccountTotalsContribution,AccountsTotalsService}.swift`
- `millio/Core/AccountsCore/ProductCatalog/{AccountProductFactory,ProductDefinitionCatalog}.swift`
- `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift`
- `millio/UI/Services/Finances/AccountsCore/{AccountDetailView,AccountDetailSheets}.swift`
- `millio/UI/Services/Cashflow/{AccountsCoreCashflowBridge,CashflowPersistenceService}.swift`
- Existing baseline tests listed in the characterization command; dedicated credit-card suites do not exist.
