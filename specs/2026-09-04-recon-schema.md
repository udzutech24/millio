# Recon: добавление @Model LoanContract + AppSchemaV12 (аддитивно)

Дата: 2026-09-04. Read-only разведка, код не менялся.

## 1. СХЕМА И МИГРАЦИИ

### Где объявлены версии

Все версии `AppSchemaV1...V11` объявлены в одном файле:
`millio/Core/Schema/AppSchemaVersions.swift`.

- V7: строки 134-142 (`AppSchemaV3.models + AppSchemaV7.frozenAccountsCoreModels + [HistoricalAssetPrice.self, HistoricalPortfolioValuation.self]`)
- V8: строки 148-154 (`AppSchemaV7.models + [RealEstateProfile.self, AccountAttachment.self]`)
- V9: строки 158-163 (`AppSchemaV8.models + [CashflowMonthClosureEvent.self]`)
- V10: строки 173-186 — первая версия, где граф снова указывает на продакшн `Account` напрямую (а не на frozen-копию); `models = AppSchemaV3.models + [Account.self, AccountEvent.self, AccountGroup.self, AccountDailySnapshot.self, HistoricalAssetPrice.self, HistoricalPortfolioValuation.self, RealEstateProfile.self, AccountAttachment.self, CashflowMonthClosureEvent.self]`
- V11 (текущая): строки 193-198 — `models = AppSchemaV10.models + [AccountAppearance.self]`, чисто аддитивная, `Account` не трогает.
- `typealias AppSchemaCurrent = AppSchemaV11` — строка 210.

Комментарий на строках 202-209 — это уже готовая инструкция "как добавлять новый @Model", ей и нужно следовать.

Frozen-копии AccountsCore графа для исторических версий (V5/V6/V7) лежат в отдельных файлах:
`millio/Core/Schema/AppSchemaV5AccountsCoreModels.swift`, `...V6AccountsCoreModels.swift`, `...V7AccountsCoreModels.swift` — они НЕ участвуют в V10/V11/V12, т.к. с V10 схема снова ссылается на живой `Account`.

### MigrationPlan

`AppMigrationPlan` — `millio/Core/Schema/AppSchemaVersions.swift:215-242`.
- `schemas` (216-228): плоский список всех `AppSchemaV1...V11.self` по порядку.
- `stages` (230-241): только `.lightweight(fromVersion:toVersion:)` для каждой смежной пары, ни одного `.custom` во всей истории проекта (грепом по репо `.custom(` в MigrationStage не найдено — все переходы аддитивные/lightweight).

Пример строки: `.lightweight(fromVersion: AppSchemaV10.self, toVersion: AppSchemaV11.self)` (строка 240).

### Готовый рецепт AppSchemaV12 = V11.models + [LoanContract.self]

В `millio/Core/Schema/AppSchemaVersions.swift`, после блока V11 (после строки 198), перед `// MARK: - Текущая схема`:

```swift
// MARK: - V12 (LoanContract — договоры по кредитам)

/// Аддитивная версия: добавляется ровно одна таблица `LoanContract`, декларации V11
/// остаются byte-for-byte (образец — V8/V11). `Account` не меняется, поэтому его checksum
/// обязан СОВПАДАТЬ с V10/V11 — это проверяет `AppSchemaFrozenGraphTests`.
enum AppSchemaV12: VersionedSchema {
    static var versionIdentifier = Schema.Version(12, 0, 0)
    static var models: [any PersistentModel.Type] = AppSchemaV11.models + [
        LoanContract.self,
    ]
}
```

Далее:
1. Заменить `typealias AppSchemaCurrent = AppSchemaV11` (строка 210) на `AppSchemaV12`.
2. В `AppMigrationPlan.schemas` (216-228) дописать `AppSchemaV12.self` последним элементом.
3. В `AppMigrationPlan.stages` (230-241) дописать `.lightweight(fromVersion: AppSchemaV11.self, toVersion: AppSchemaV12.self),`.
4. Прогнать `SchemaConsistencyTests` и `AppSchemaFrozenGraphTests` (см. ниже раздел 5).

### AppSchemaFrozenGraphTests — механика

Файл: `millioTests/Core/Schema/AppSchemaFrozenGraphTests.swift`.

- `stableEntityHashes` (строки 22-48) — словарь entity-name → base64 checksum для сущностей, чья форма не менялась ни разу (Card, Cashback, Item, RealEstateProfile, AccountAppearance и т.д.). НЕ включает LoanContract — его нужно будет туда добавить ПОСЛЕ того, как V12 станет исторической (т.е. в момент появления V13), а не сразу.
- `accountHashByVersion` (строки 51-59) — checksum именно `Account` по версии (`"10.0.0": "yWZTWJU6..."`), т.к. это единственная сущность, менявшаяся между версиями. Верхняя граница — `"10.0.0"`, для V11 checksum не хранится отдельно — вместо этого:
- `testCurrentAdditiveSchemaKeepsPreviousAccountChecksum()` (строки 118-133) — берёт **живой** `AppSchemaCurrent`, вычисляет его Account-checksum и сравнивает с зафиксированным `"10.0.0"`. Тест устроен так, что при добавлении V12 (если Account не менялся) он ПРОДОЛЖИТ проходить автоматически, т.к. `AppSchemaCurrent` просто станет V12, а Account в ней byte-for-byte как в V10/V11.
- `testCurrentSchemaOnlyAddsNewEntityOnTopOfPreviousVersion()` (строки 138-150) — сравнивает entity-set текущей схемы с `AppSchemaV10` (жёстко хардкожен `AppSchemaV10.models`!) и требует, чтобы разница была РОВНО `{"AccountAppearance"}`. **Это сломается при добавлении V12**, т.к. дифф станет `{"AccountAppearance", "LoanContract"}` — тест придётся обновить (baseline `V10` → `V11`, ожидаемая разница → `{"LoanContract"}`). Подробнее — раздел 5.
- Механика "почему новое поле в Account сдвигает checksum задним числом": SwiftData вычисляет entity-hash по составу всех атрибутов сущности **включая composite attributes** (комментарий строк 6-13) и хранит его в `NSStoreModelVersionHashesKey` метаданных стора. Если поле добавлено в уже опубликованную (или уже физически существующую на диске) версию, checksum этой версии задним числом меняется в decl, но НЕ на реальных дисках пользователей → расхождение → `NSCocoaErrorDomain 134504`. Именно поэтому LoanContract — только НОВАЯ сущность в НОВОЙ версии, Account/DepositMeta/LoanMeta и т.п. в существующих версиях трогать нельзя.


## 2. Что уже есть по кредитам сегодня

Кредит уже представлен в кодовой базе ДВУМЯ независимыми путями — риск дублирования с новым типом «Кредит» реальный.

- **`AccountKind.loan`** (`millio/Core/AccountsCore/AccountKind.swift:11`) — существующий kind счёта, engine-класс `.loan` («C: loan — обязательство, отрицательный итог не обрезается», строка 39). Метаданные — embedded struct **`LoanMeta`** (`millio/Core/AccountsCore/AccountMeta.swift:124-131`): `principal, rate, monthlyPayment?, paymentDay?, termEnd?, scheduleType (annuity/differentiated), insurance?`. Поле `Account.loanMeta: LoanMeta?` (`Account.swift:45`), участвует в export/import (`Account.swift:134`, `exportDict`/`init(exportDict:)` в `AccountMeta.swift:246-261`). Используется в форме создания (`FinanceProductCreationCommandResolver.swift:21,45,154`), сидере (`AccountsCoreSeeder.swift:100`), легаси-конвертере (`LegacyAccountConversion.swift:63`), мосте формы «Кредит» (`AccountsCoreAdditionBridge.swift:147-158`).
- **Кредитная карта** — НЕ отдельный kind, а `CardMeta.creditLimit: Decimal?` на денежном счёте (`kind == .cash`/`.debitCard`, `productType == .creditCard`). Долг определяется НАЛИЧИЕМ `creditLimit`, не kind'ом (см. §4б).
- **Ремонт «Это кредитная карта» (4c38a0e, 2026-09-03)** — точечная ручная миграция для дебетовых карт, ошибочно заведённых как кредитки старым `LegacyAccountConversion` (до 5ae6ff8): без `creditLimit` долг шёл в тотал ПЛЮСОМ. Новый изолированный сервис `DebitToCreditCardRepair` (не через `AccountProductTransitionCoordinator` — тот блокирует любой переход в/из `.creditCard`) пишет `productType → .creditCard`, `CardMeta.creditLimit` и ОДНО компенсирующее `.adjustment`-событие через `AccountsCoreService.adjustBalance`, append-only. `DebitCardOperationCoordinator.adjust()` получил гард: счёт с `creditLimit` не проходит дебетовую семантику `target >= 0`, кидает `.creditCardRequiresCreditSemantics`. 5 тестов в `DebitToCreditCardRepairTests.swift`.

**Риск дублирования.** Новый тип «Кредит» (потребительский/ипотека — тело долга + график платежей в `LoanContract`) пересекается по смыслу с `AccountKind.loan` + `LoanMeta`: обе модели хранят `principal/rate/monthlyPayment/paymentDay/termEnd/scheduleType`. Решать НЕ в рамках этой разведки, но нужно явно зафиксировать на этапе спеки: либо новый тип «Кредит» = `AccountKind.loan` + параллельная таблица `LoanContract` (тогда `LoanMeta` либо становится избыточной, либо LoanContract замещает её только для новых счетов), либо это два разных продукта (`AccountKind.loan` остаётся легаси/simple-режимом, а `LoanContract` обслуживает новый детальный тип). Второй независимый прецедент долга — кредитка через `creditLimit` — паттерна `LoanContract` не касается, но `AccountTotalsContribution` (§4б) уже показывает работающий шаблон «долг минусом от отдельного признака».

## 3. Прецедент «связь по id, не @Relationship»

Образец — `AccountAppearance` (`millio/Core/AccountsCore/Appearance/AccountAppearance.swift:16-39`):

```swift
// AccountAppearance.swift:16-24
@Model
final class AccountAppearance: Persistable {
    var id: UUID = UUID()
    var accountID: UUID = UUID()
    var presetRaw: String?
    var tintHex: String?
    var iconName: String?
    var isFavorite: Bool = false
    var updatedAt: Date = Date()
```

Причина явно задокументирована в комментарии файла (строки 9-13): `accountID` — обычное поле БЕЗ `@Relationship`, потому что ключ обслуживает два мира счетов сразу (core `Account.id` и легаси `Card.cardUniqueID`); `@Relationship` возможен только с одним из них. Для `LoanContract` (только core `Account`) это ограничение не действует, но паттерн (простой UUID + отдельная таблица, не завязанная на SwiftData relationship-граф) переиспользуется ради независимости checksum'а (см. §1).

Выборка — через хелпер-стор с приватным `#Predicate`, файл `AccountAppearanceStore.swift:104-109`:

```swift
private func existingRows(for accountID: UUID) throws -> [AccountAppearance] {
    var descriptor = FetchDescriptor<AccountAppearance>(
        predicate: #Predicate<AccountAppearance> { $0.accountID == accountID }
    )
    descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
    return try context.fetch(descriptor)
}
```

Публичные методы стора — `appearance(for:)`, `upsert(accountID:mutate:)`, `favoriteAccountIDs()` (`AccountAppearanceStore.swift:34-99`). Для `LoanContract` — завести аналогичный `LoanContractStore` с `id: UUID`, `accountID: UUID`, `#Predicate<LoanContract> { $0.accountID == accountID }`, upsert-хелпер вместо прямых `context.fetch` по коду.

## 4. Точки интеграции

### а) ModelTypeRegistry

Файл `millio/Core/Repository/ModelTypeRegistry.swift`: синглтон `ModelTypeRegistry.shared`, методы `register<T: Persistable>(_:typeName:)` и `registerImporter<T: ModelImporter>(_:)`. Регистрация всех core-моделей идёт НЕ в самом registry, а в `AccountsCoreFeatureRegistration.register()` (`millio/Core/AccountsCore/AccountsCoreFeatureRegistration.swift:20-46`) — по образцу `AccountAppearance` (строки 32, 46):
```swift
ModelTypeRegistry.shared.register(AccountAppearance.self, typeName: "AccountAppearance")
...
ModelTypeRegistry.shared.registerImporter(AccountAppearanceImporter.self)
```
Для `LoanContract` — дописать симметрично: `register(LoanContract.self, typeName: "LoanContract")` + написать `LoanContractImporter: ModelImporter` (образец — `AccountAttachmentImporter`/`RealEstateProfileImporter`, файл строки 66-89: находит `Account` по `accountID`, проверяет `productType`, upsert по `id`). Важно — файл предупреждает (комментарий 6-16), что reconciliation (guest→user merge) для core-типов Account/AccountEvent/AccountGroup/AccountDailySnapshot исключён из общего импортёра; `LoanContract` — новый тип вне этого исключённого списка, значит по умолчанию пойдёт через общий backup/restore путь (это ОК, но стоит явно решить на этапе спеки, нужен ли ему отдельный merge-путь как Account, или общий импортёр достаточен).

Round-trip backup/restore тест — нет единого файла именно "ModelTypeRegistry round-trip", ближайшие: `millioTests/Core/BackupVerifiedRestoreTests.swift`, `millioTests/Core/RecoveryEndToEndIntegrationTests.swift` (использует фикстуру `millioTests/Fixtures/owner-backup-1673-models.milliobackup`), `millioTests/Core/BackupRestoreIntegrityTests.swift`. Механические тесты самого registry (concurrent register, FeatureRegistry.configureAll) — `millioTests/Core/RegistryAndRouterTests.swift:10-52,190-211`; они типо-агностичны и не потребуют правки под LoanContract.

### б) AccountTotalsContribution — учёт в net worth

Файл `millio/Core/AccountsCore/AccountTotalsContribution.swift:6-28` — единая точка знакового вклада счёта в тотал (используется шапкой, группами, Динамикой, карточкой, списком). Текущая логика кредитки:
```swift
static func signedValue(rawBalance: Decimal, kind: AccountKind, creditLimit: Decimal?) -> Decimal {
    guard kind == .debitCard || kind == .cash, let creditLimit else { return rawBalance }
    return CreditCardFinancialContract.netPosition(rawAvailableBalance: rawBalance, creditLimit: creditLimit)
}
```
Признак долга — НАЛИЧИЕ `creditLimit`, не kind (урок Ф7b-2: форма «Новый продукт» иногда кладёт кредитку в `kind == .cash`). Для «Кредита» через `LoanContract` — по аналогии добавить ветку по признаку наличия `LoanContract` (или существующему `AccountKind.loan`/новому `productType`), считать вклад = `-остаток_тела_долга` (не `rawBalance` счёта — тело долга живёт в `LoanContract`, а не в `AccountEvent`-ленте, если решение "не трогать Account/LoanMeta" подразумевает отдельный источник остатка). Нужно на этапе спеки явно решить, откуда берётся "остаток тела" — из `LoanContract` напрямую или через отдельный calculator по образцу `CreditCardFinancialContract`.

### в) Cashflow — программное создание транзакции расхода

Прямого «create expense transaction» сервиса как отдельного файла нет; образец программной вставки — `DepositCashflowProjector.project()` (`millio/Core/AccountsCore/Deposit/DepositCashflowProjector.swift:53-63`), тип `income`, аналогично для `expense`:
```swift
try CashflowMonthMutationPolicy(modelContext: context).validate(.scheduledApply, date: event.date)
context.insert(CashflowTransaction(
    transactionType: .income,
    amount: NSDecimalNumber(decimal: amount).doubleValue,
    currency: account.currency,
    transactionDate: event.date,
    incomeCategory: .interest,
    note: account.name.isEmpty ? nil : account.name,
    importSourceRaw: importSource,
    importReferenceKey: sourceID,
    affectsCardBalance: false
))
```
Дедуп — через `importSourceRaw` + `importReferenceKey` (уникальный sourceID на событие), не даёт задвоить транзакцию при повторном прогоне. Для платежа по кредиту: `transactionType: .expense`, свой `expenseCategory`, `importSourceRaw` вида `"loanContractPayment"`, `importReferenceKey` = id платежа/периода. Обязательное предварительное условие — `CashflowMonthMutationPolicy.validate(...)` (месяц не закрыт задним числом).

### г) DepositAccrual / периодичность

Нет файла с именем `DepositAccrual` — логика периодов живёт в `DepositInterestScheduler` (`millio/Core/AccountsCore/DepositInterestScheduler.swift`) и enum `AccountDepositCapitalization` (`AccountMeta.swift:29-68`): кейсы `.none/.daily/.monthly/.quarterly/.customDays(Int)` — **нет `.semiannual`/`.annual`**, для кредита (ежемесячно/раз в 2 мес/квартал/полгода/год) enum нужно либо расширять, либо для credit использовать только `.customDays`/собственный enum.

Ключевые сигнатуры для переиспользования:
- `scheduledPeriodEnd(openingDate:months:payoutDay:calendar:) -> Date?` (строка 363) — считает дату конца N-го периода с учётом фиксированного дня месяца (`payoutDay`), обрабатывает короткие месяцы (`calendar.range(of:.day,in:.month,for:)`). Годится для месячного/2-месячного/квартального/полугодового/годового шага кредита — вызывать с `months: 1/2/3/6/12`.
- `buildSchedule(...)` (строка 241) — ветка `.monthly/.quarterly` (строки 267-291) итерирует `n * stepMonths` через `scheduledPeriodEnd`, на каждом шаге считает `balanceBefore = AccountBalanceEngine.balanceAt(...)` и `interest = round2(balanceBefore * periodRate / 100)`. Для аннуитетного/дифференцированного графика кредита нужна другая формула суммы (не проценты на баланс, а погашение по `LoanScheduleType`), но сам цикл «дата периода → сумма → sourceID → draft» переиспользуем.
- `round2(_:) -> Decimal` (строка 379) — округление до копейки, `.plain` (не bankers), явное решение проекта.
- `maxFixedStepDraftsPerRun = 400` (строка ~314) — потолок на прогон, чтобы не залить стор/бэкап/Cashflow при мелком шаге; для credit-графика с известным конечным `termEnd` это менее критично (график конечен), но стоит унаследовать паттерн роллингового горизонта, если хотим строить платежи "на лету", а не сразу всю таблицу амортизации.

## 5. Тесты

**Что ломается от V12 (кроме уже описанного в разделе 1):**

- `millioTests/Core/SchemaConsistencyTests.swift` (183 строки) — по образцу `v11PreservesEveryV10Entity()` (строки 148-165: сравнивает `AppSchemaV10.models` vs `AppSchemaV11.models`, ждёт разницу ровно `{"AccountAppearance"}`) нужно ДОПИСАТЬ симметричный `v12PreservesEveryV11Entity()`, сравнивающий V11→V12, ждущий разницу `{"LoanContract"}`. Существующие тесты V1-V11 не трогать — они не завязаны на V12.
- `testCurrentSchemaOnlyAddsNewEntityOnTopOfPreviousVersion()` (раздел 1, `AppSchemaFrozenGraphTests.swift:138-150`) — хардкожен на `AppSchemaV10`, ожидаемая разница `{"AccountAppearance"}`; после V12 разница станет `{"AccountAppearance","LoanContract"}` — тест красный, поправка: либо сменить baseline на `AppSchemaV11` и ждать `{"LoanContract"}`, либо расширить ожидаемое множество (baseline на V10 предпочтительнее, ближе к духу теста «эта версия против предыдущей»).
- `appSchemaCreateMatchesSchemaCurrent()` (`SchemaConsistencyTests.swift:166-174`) — тип-агностичен (сравнивает `AppSchemaCurrent.models` c `AppSchema.create().entities`), сам по себе не потребует правки, но упадёт, если `AppSchema.create()` не увидит `LoanContract` — сигнал, что регистрация неполная.
- Registry-механика (`RegistryAndRouterTests.swift`) — тип-агностична, правки не требует.
- Backup round-trip (`BackupVerifiedRestoreTests.swift`, `RecoveryEndToEndIntegrationTests.swift`, `BackupRestoreIntegrityTests.swift`) — не сломаются автоматически (LoanContract опционален в фикстурах), но нужно ДОБАВИТЬ новый кейс: экспорт/импорт счёта с LoanContract переживает `export()→import()` без потери полей (по образцу существующих тестов на `AccountAttachment`/`RealEstateProfile`).

**Образец для юнит-тестов графика платежей** — `millioTests/Core/AccountsCore/DepositInterestSchedulerTests.swift` (структура: строит `Account`+`DepositMeta`, гоняет `buildInitialSchedule`/`buildFutureSchedule`, проверяет даты и суммы драфтов). Смежные полезные образцы: `DepositCashflowProjectionTests.swift` (Cashflow-материализация), `DepositFinancialContractTests.swift` (формулы), `DepositOpeningDateRecalculationTests.swift` (edge-cases дат).

**Как запускаются тесты:** `make test` → `./scripts/coverage_gate.sh` (корень репозитория, `Makefile:8`). Прямой прогон конкретного файла — стандартный `xcodebuild test -only-testing:millioTests/<ClassName>` (Swift Testing framework, судя по `@Test`/`#expect` в просмотренных файлах), но точный invocation не в этой разведке — см. `scripts/coverage_gate.sh` для актуальных флагов схемы/симулятора.
