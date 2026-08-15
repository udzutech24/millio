# Research: смена типа финансового продукта

## Вердикт

Произвольная in-place смена `Account.productType` опасна: поле не time-aware и применяется ко всей истории. Вместе с `kind` оно выбирает replay engine, знак, metadata contract, valuation и UI. Универсальный setter перепишет смысл уже сохранённых событий без единой новой транзакции.

Нужны два разных сценария:

1. **Correction** — безопасная переклассификация внутри доказанно эквивалентной семантической семьи.
2. **Conversion** — архив старого продукта и атомарное создание нового с явным переносом подтверждённого остатка на дату перехода. История старого продукта не меняется.

## Текущие источники истины

- `AccountProductType` хранит пользовательский подтип.
- `Account.kind` выбирает replay engine через `AccountKind.engine`.
- `ProductDefinitionCatalog` задаёт canonical kind, metadata shape, allowed events, capabilities и valuation policy.
- `AccountBalanceEngine` использует разные sign/replay правила для cash/deposit/debt, loan, market и manual asset.
- `Account.productType` и `kind` не имеют периода действия. In-place изменение ретроспективно меняет весь account.
- `AccountProductIdentityMigrator` предназначен для классификации legacy rows, а не пользовательской конверсии живого продукта.

## Матрица переходов

| Семья | Типы | Решение | Причина |
|---|---|---|---|
| Cash-like correction | `cash`, `debitCard`, `bankAccount` | In-place при валидной target metadata | Один sign/replay engine и одинаковый набор базовых событий. Kind меняется, но финансовая семантика истории сохраняется. |
| Credit card | `creditCard` ↔ любые | Только conversion | Opening ledger означает available balance относительно limit; простой flip искажает signed position и totals всей истории. |
| Manual asset subtype | `realEstate`, `business`, `vehicle`, `otherManualAsset` | In-place | Один kind/engine/event contract; subtype меняет профиль/UX, не сумму истории. Target-specific обязательные поля проверяются отдельно. |
| Market subtype | `marketStock`, `marketCrypto`, `marketBond`, `marketMetal`, `genericMarketInvestment` | In-place только при согласованном `MarketMeta.assetClass` и доступном quote identity; иначе conversion/block | Replay одинаков, но изменение asset class может переинтерпретировать symbol, цены и историческую valuation. |
| Debt direction | `receivable` ↔ `payable` | Только conversion | Знак и экономический смысл всей истории меняются. |
| Deposit | `deposit` ↔ cash-like | Correction только для pristine ошибочно созданного account; иначе conversion | Replay суммы похож, но generated schedule, interest provenance, maturity и capabilities делают историю семантически другой. |
| Loan | `loan` ↔ любые | Только conversion | Loan sign map отличается; in-place flip переписывает долг в актив или наоборот. |
| Cross-engine | cash/deposit/debt/loan/market/manual между семьями | Только conversion или block | Разные replay/valuation и event payloads. |
| `unknownLegacy` | → доказанный resolved type | Только существующий migration workflow | Нельзя выдавать пользовательскую догадку за подтверждённую историю. |

## Pristine account

Узкое исключение для correction между deposit и cash-like допустимо только если:

- account активен;
- существует ровно один `.openingBalance`;
- нет других подтверждённых событий, Cashflow links, transfers, generated/confirmed interest или snapshots;
- target metadata полностью валидна;
- change preview показывает итоговый тип/kind и удаляемую metadata;
- весь tuple `productType + kind + metadata + revisions` сохраняется одним commit.

Если хоть один пункт не доказан — только conversion.

## Архитектура

### Pure classifier

`AccountProductTransitionPolicy` принимает source definition, target definition, metadata и event summary и возвращает:

- `.inPlaceCorrection(requiredMetadata, warnings)`;
- `.replacementConversion(balancePolicy, warnings)`;
- `.blocked(reasonCode)`.

UI не решает безопасность самостоятельно.

### In-place coordinator

`AccountProductTransitionCoordinator.correct(...)`:

- чистый caller/disposable context;
- stable operation ID;
- повторная валидация stored identity и target tuple;
- атомарная замена product type, canonical kind и полного metadata set;
- invalidation membership/financial revisions;
- один save, rollback при любом отказе.

### Replacement conversion

`convert(...)` не мутирует прошлое:

- вычисляет подтверждённый source balance на effective date;
- создаёт новый target account через `AccountProductGraphBuilder`;
- добавляет явные closing/opening/transfer legs только если их семантика поддержана;
- архивирует source на ту же дату;
- сохраняет весь граф одним disposable-context commit;
- не конвертирует неподдерживаемые quantities, lots, debt/loan signs или FX без отдельной policy.

## Основные риски

| Failure mode | Impact | Mitigation |
|---|---|---|
| Flip credit card → debit | Лимит становится активом | Всегда replacement conversion. |
| Flip receivable → payable | Полная инверсия смысла долга | Всегда replacement conversion. |
| Market class сменён без symbol/price policy | Историческая стоимость использует другой рынок | In-place только с доказанной quote identity; иначе block. |
| Deposit schedule остаётся после смены | Проценты продолжают появляться у cash account | Pristine-only correction или atomic cleanup during conversion. |
| Product type изменился, metadata нет | Corrupt/unknown product | Полный target tuple валидируется до mutation. |
| Retry создал второй replacement account | Дублирование капитала | Stable operation ID + graph lookup before build. |
| Conversion failure после archive | Потеря активного продукта | Один disposable context/save. |

## Рекомендация

Не добавлять generic `updateAccount(productType:)`. Сначала pure transition matrix и adversarial tests. Затем только две явные команды: `correctType` и `convertToNewProduct`. UI должен называть действие честно: «Исправить тип» или «Перенести в новый продукт», а не одинаковое «Сменить».

