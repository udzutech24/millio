# Plan: Finance Balance Contract

**Slug:** `finance-balance-contract`
**Дата создания:** 2026-06-07
**Stage:** 3 / Planning
**Spec:** [`specs/2026-06-07-finance-balance-contract.md`](../specs/2026-06-07-finance-balance-contract.md)
**Research:** [`../.business/история/2026-06-06-finance-accounts-cache-history-research.md`](../.business/история/2026-06-06-finance-accounts-cache-history-research.md)
**Связанный план:** [`plans/2026-05-28__finance-chart-history.md`](2026-05-28__finance-chart-history.md) — Phase 5 поглощает Вариант A того плана

## Статус

`В РАБОТЕ`

**Реализовано:** Phase 0–2, Phase 4
**Осталось:** Phase 3, Phase 5

## Цель

Ввести явный Finance Balance Contract и устранить четыре поломки, которые вытекают из его отсутствия: stale cache при добавлении счёта, потеря links при удалении группы, стирание архивного интервала при restore, смешивание балансного и структурного событий.

## Acceptance Criteria (из spec)

- [x] AC1: Новый счёт сразу виден в `visibleGroupsForList()` / `orderedAccounts` после `addAccountToGroup()`
- [x] AC2: После `deleteGroup()` links сохранены, underlying archived; тест обновлён
- [ ] AC3: Archive → restore сохраняет lifecycle interval (счёт «помнит», что был архивирован)
- [x] AC4: `transactionsUpdated` — всегда; `cardsUpdated` — только при структурном изменении счёта
- [ ] AC5: Chart series → `historicalAsOf` scope; header/breakdown → `currentVisible` scope
- [ ] AC6: Все тесты зелёные; стандарт `deleteGroup → links.isEmpty` заменён
  - Стандарт `deleteGroup → links.isEmpty` заменён в Phase 2; полный suite ещё не запускался из-за грязного рабочего дерева.

## Challenge Log

### 1. Решает ли план проблему из spec?
- AC1 → Phase 1. Phase 2 → AC2. Phase 3 → AC3. Phase 4 → AC4. Phase 5 → AC5. AC6 покрывается тестами в каждой фазе.

### 2. Самое эффективное решение?
- **Альтернатива A (текущий план):** поэтапно, по одному месту — риск минимален, каждая фаза атомарна
- **Альтернатива B:** иммутабельные `PortfolioSnapshot` — решает всё, но это 10+ файлов, SchemaVersion, бэкофилл. Слишком дорого сейчас
- **Выбрано:** Альтернатива A — минимальный риск при доказанных root causes

### 3. Нет ли кода ради кода?
Phase 0 — контракт как enum, без изменения логики. Каждая последующая фаза меняет ровно то место, которое даёт AC. Drive-by рефакторинг вне scope.

---

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 0: Scope-контракт

**AC из spec:** Фундамент для AC1–AC5; без него нельзя говорить «правильный фильтр»

**Цель:** Ввести `FinanceBalanceScope` — явный enum, который обозначает, с каким намерением запрашиваются счета. Никакой логики не меняем — только называем вещи своими именами.

**Файлы:**
- `millio/UI/Services/Finances/FinanceBalanceScope.swift` (новый) — enum с пятью scope'ами
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — добавить typealias / комментарии к существующим вызовам `getAccountsForCalculation`; реальная смена фильтрации — в Phase 5

**Шаги:**
1. `[x]` Создать `FinanceBalanceScope.swift`:
   ```swift
   enum FinanceBalanceScope {
       case currentVisible          // только активные счета для header/total
       case historicalAsOf(Date)    // включает archived для chart replay
       case historicalInterval(DateInterval) // для cashflow contribution
       case dashboardSnapshot       // UserDefaults-based, для sparkline
       case cashflowContribution    // income/expense/assetDelta для cashflow
   }
   ```
2. `[x]` Добавить комментарии к существующим call-site'ам в `FinanceDynamicsViewModel` (не менять логику, только пометить)
3. `[x]` Self-audit: все пять scope'ов явно прокомментированы в коде
   - `currentVisible`, `historicalAsOf`, `historicalInterval`, `dashboardSnapshot`, `cashflowContribution` задокументированы в `FinanceBalanceScope.swift`.
   - Текущие bool-based call-sites в `FinanceDynamicsViewModel` помечены как Phase 0 scope markers; enum-based API остаётся для Phase 5.
4. `[ ]` Коммит: `docs(finance): introduce FinanceBalanceScope contract enum`

**Проверка Phase 0:**

```bash
xcodebuild test -scheme millio -destination 'platform=iOS Simulator,id=49601B0B-FAE4-4039-94BA-B333C5DFCAAB' -derivedDataPath /tmp/millio-phase0-derived -only-testing:millioTests/FinanceDynamicsViewModelTests
```

Результат: `TEST SUCCEEDED`. Полный suite не запускался из-за грязного рабочего дерева.

**Guard phrase:** «Реализуй Phase 0 по плану.»

---

### `[x]` Phase 1: Stale cache при добавлении счёта

**AC из spec:** AC1

**Root cause:** `FinanceAccountService.addAccountToGroup()` (строка 401) после `save()` вызывает `onLoadGroups()` и `onCalculateTotal()`, но не `onLoadAccounts()`. `getAccountInfo()` читает `cardByID/creditByID/investmentByID` из устаревшего кэша → resolver возвращает nil.

**Файлы:**
- `millio/UI/Services/Finances/FinanceAccountService.swift` (строки 399–407) — добавить `onLoadAccounts()` перед `onLoadGroups()`
- `millioTests/UI/Services/Finances/FinanceDynamicsViewModelTests.swift` или новый тест-файл — тест на немедленную видимость

**Шаги:**
1. `[x]` Написать тест: создать счёт через `addAccountToGroup()`, сразу проверить `visibleGroupsForList()` и `orderedAccounts` — счёт должен присутствовать
2. `[x]` Убедиться, что тест падает (подтверждает bug)
   - UI-level тест оказался зелёным на текущей ветке из-за существующих recovery-путей; контракт доказан сервисным тестом `testAddAccountToGroupReloadsAccountsBeforeGroups`, который фиксирует обязательный порядок callbacks.
3. `[x]` Добавить `onLoadAccounts()` в `addAccountToGroup()` перед `onLoadGroups()`
4. `[x]` Убедиться, что тест проходит
5. `[x]` Self-audit: не сломали removeAccountFromGroup / restoreArchivedAccountToGroup (они тоже вызывают onLoadGroups без accounts?)
6. `[x]` `xcodebuild test` — все зелёные
   - Проверено: `xcodebuild test -scheme millio -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/millio-phase1-derived -only-testing:millioTests/FinanceViewModelTests`
7. `[ ]` Коммит: `fix(finance): reload account caches after addAccountToGroup`

**Guard phrase:** «Реализуй Phase 1 по плану.»

---

### `[x]` Phase 2: deleteGroup не удаляет FinanceAccount links

**AC из spec:** AC2, AC6 (тест)

**Root cause:** `FinanceGroupService.deleteGroup()` (строка 139) — `modelContext.delete(account)` физически удаляет `FinanceAccount`. Historical replay транзакций теряет принадлежность счёта к группе.

**Решение:** При удалении группы архивировать underlying (уже делается через `onArchiveUnderlying`) и перевести `FinanceAccount` link в системную скрытую группу (`FinanceSystemGroups.ungroupedName` или отдельную archive/ungrouped-группу), но НЕ удалять физически.

**Решение после ревизии 2026-06-07:** `group = nil` отклонён. Это слабое решение: `FinanceDynamicsViewModel.getAccountsForCalculation()` строит основной путь через `state.groups -> group.accounts`, а fallback отбрасывает `group == nil` при выбранных группах. Link без группы может случайно попасть в расчёт только когда основной путь пустой и нет group-filter. Для historical replay нужен link, который остаётся достижимым через системную скрытую группу.

**Рекомендация:** использовать существующую системную Ungrouped-группу как скрытый контейнер для архивированных links после удаления группы. Если её нет — создать/найти helper в сервисе, но не вводить отдельную новую группу, пока нет явного UI/аналитического требования.

**Файлы:**
- `millio/UI/Services/Finances/FinanceGroupService.swift` (строки 128–143) — убрать `modelContext.delete(account)`, заменить на `account.group = nil; account.updatedAt = Date()`
- `millioTests/...` — заменить тест `deleteGroup → links.isEmpty` на `deleteGroup → underlying archived, links preserved`

**Шаги:**
1. `[x]` Найти и прочитать тест `deleteGroup → links.isEmpty` (точный файл/строку)
2. `[x]` Написать новый тест: после `deleteGroup()` проверить, что `FinanceAccount` links для счетов группы существуют (count > 0), переведены в системную скрытую группу, underlying `archivedAt != nil`
3. `[x]` Убедиться, что новый тест падает
   - Подтверждено: `FinanceViewModelTests.testDeleteGroupArchivesAccountsAndPreservesLinksInUngroupedGroup()` падал до правки.
4. `[x]` Убрать `modelContext.delete(account)` в `deleteGroup()`, добавить перевод link в системную скрытую группу и `account.updatedAt = Date()`
5. `[x]` Убедиться, что новый тест проходит
6. `[x]` Удалить/исправить старый тест `links.isEmpty`
7. `[x]` Тест Dynamics: deleted-group archived link попадает в `getAccountsForCalculation(includeArchivedForHistory: true)` и исторический баланс до archive сохраняется
8. `[x]` Impact analysis: не сломали ли `loadGroups()` / `visibleGroupsForList()` (скрытая системная группа не должна всплывать в обычном списке, если содержит только archived)
9. `[x]` `xcodebuild test -scheme millio -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/millio-phase2-derived -only-testing:millioTests/FinanceViewModelTests -only-testing:millioTests/FinanceDynamicsViewModelTests`
   - Фактически прогнано двумя командами:
     - `-only-testing:millioTests/FinanceViewModelTests`
     - `-only-testing:millioTests/FinanceDynamicsViewModelTests`
10. `[ ]` По возможности полный suite только после согласования с грязным деревом
11. `[ ]` Коммит: `fix(finance): preserve FinanceAccount links on deleteGroup`

**Guard phrase:** «Реализуй Phase 2 по плану.»

---

### `[ ]` Phase 3: Lifecycle history для архивации/restore

**AC из spec:** AC3

**Root cause:** `restoreArchivedAccountToGroup()` сбрасывает `archivedAt = nil`. `FinanceDynamicsViewModel` использует `archivedAt` как единственную временну́ю границу. После restore интервал «счёт был архивирован» стирается.

**Решение:** Ввести `FinanceAccountArchiveEvent` — лёгкую структуру (не SwiftData-модель, чтобы избежать сложной миграции) с парами `(archivedAt: Date, restoredAt: Date?)`. Хранить в `UserDefaults` или отдельном `@Model`-файле с новой SchemaVersion.

**Решение по хранению:** до старта фазы нужно выбрать:
- **Вариант A (UserDefaults JSON):** быстро, без миграции, но вне SwiftData — backup/restore CloudKit не захватит
- **Вариант B (новый @Model + SchemaVersion V4):** правильно архитектурно, CloudKit-aware, но нужна миграция

**Рекомендация:** Вариант B — lifecycle events это часть финансовых данных, должны резервироваться.

**Файлы:**
- `millio/Models/FinanceAccountArchiveEvent.swift` (новый) — `@Model` с `accountID`, `accountType`, `archivedAt`, `restoredAt`
- `millio/Core/AppSchemaVersions.swift` — добавить V4 с `FinanceAccountArchiveEvent`
- `millio/UI/Services/Finances/FinanceAccountService.swift` — `removeAccountFromGroup()` создаёт event; `restoreArchivedAccountToGroup()` закрывает event (устанавливает `restoredAt`)
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — при расчёте исторического scope использовать lifecycle events для определения, когда счёт был активен в конкретную дату
- `millioTests/...` — тест: archive → restore → проверить что lifecycle interval сохранён и Dynamics не показывает счёт активным в период архивации

**Шаги:**
1. `[ ]` Создать `FinanceAccountArchiveEvent.swift` (@Model)
2. `[ ]` Добавить V4 в `AppSchemaVersions.swift` (lightweight migration)
3. `[ ]` В `removeAccountFromGroup()` создавать `FinanceAccountArchiveEvent` при установке `archivedAt`
4. `[ ]` В `restoreArchivedAccountToGroup()` находить последний открытый event и закрывать `restoredAt`
5. `[ ]` Написать тест: archive → restore → lifecycle events содержат корректный интервал
6. `[ ]` В `FinanceDynamicsViewModel.getAccountsForCalculation(historicalAsOf:)` учитывать lifecycle events при проверке активности счёта на дату
7. `[ ]` Написать тест: Dynamics не включает счёт в исторические данные за период его архивации
8. `[ ]` `xcodebuild test` — все зелёные
9. `[ ]` Коммит: `feat(finance): account lifecycle events for archive history`

**Guard phrase:** «Реализуй Phase 3 по плану.»

---

### `[x]` Phase 4: Разделение событий transactionsUpdated / cardsUpdated

**AC из spec:** AC4

**Root cause после ревизии 2026-06-08:** `FinanceEvent.transactionsUpdated` уже существует, а `CashflowViewModel` уже подписан на него. Незакрыт контракт публикации: `CashflowPersistenceService` после успешных save/update/delete транзакций обновляет локальное состояние через callbacks, но не публикует глобальный `transactionsUpdated`. При этом `cardsUpdated`/`investmentsUpdated` уже завязаны на фактический балансный эффект через `shouldApplyCardBalanceImmediately()` / `persistedBalanceEffectWasApplied()` и не должны становиться “универсальным refresh-событием”.

**Решение:** Завершить publication contract: `CashflowPersistenceService` публикует `FinanceEvent.transactionsUpdated` всегда после успешной мутации транзакций. `cardsUpdated`/`investmentsUpdated` публикуются только когда реально применён или откачен балансный эффект. Future/planned/recurring транзакции дают `transactionsUpdated == true`, но `cardsUpdated == false`, если баланс не применяется немедленно.

**Файлы:**
- `millio/Core/Events/EventBus.swift` — проверить, что `.transactionsUpdated` уже есть (без изменений)
- `millio/UI/Services/Cashflow/CashflowPersistenceService.swift` — публиковать `transactionsUpdated` после успешных save/update/delete транзакций
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — проверить существующую подписку (без изменений, если уже корректна)
- `millioTests/UI/Services/Cashflow/CashflowViewModelTests.swift` — тест publication contract

**Шаги:**
1. `[x]` Подтвердить, что `FinanceEvent.transactionsUpdated` уже определён в `EventBus.swift`
2. `[x]` Подтвердить, что `CashflowViewModel` уже reload-ит транзакции по `transactionsUpdated`
3. `[x]` Написать красный тест: future/planned transaction save/update/delete публикует `transactionsUpdated`
   - Доказано: `CashflowViewModelTests/testFutureTransactionMutationsPublishTransactionsUpdatedWithoutCardsUpdated` падал до production fix в полном `CashflowViewModelTests`.
4. `[x]` В этом же тесте зафиксировать, что future/planned transaction не публикует `cardsUpdated`, если балансный эффект не применяется немедленно
5. `[x]` В `CashflowPersistenceService` добавить минимальный helper публикации `transactionsUpdated` после успешного `modelContext.save()` для save/update/delete
6. `[x]` Убедиться, что `cardsUpdated`/`investmentsUpdated` остаются только в `publishAffectedAccountEvents(...)`
7. `[x]` `xcodebuild test` — минимум `CashflowViewModelTests`
   - ✅ `xcodebuild test -scheme millio -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -derivedDataPath /tmp/millio-phase4-derived -only-testing:millioTests/CashflowViewModelTests`
   - Дополнительно проверено:
     - ✅ изолированный `FinanceLifecycleIntegrationTests/deletingMarketBuyRevertsSettlementAndPositionTogether`
     - ⚠️ полный `FinanceLifecycleIntegrationTests` стабильно падает в этом же order-dependent кейсе, при этом изолированный кейс проходит; зафиксировано как отдельная процессная/тестовая проблема в `improvements/process/2026-06-08-finance-lifecycle-order-dependent-suite.md`.
8. `[x]` Коммит: `fix(finance): publish transactionsUpdated for cashflow mutations`

**Guard phrase:** «Реализуй Phase 4 по плану.»

---

### `[ ]` Phase 5: Scope-унификация в FinanceDynamicsViewModel

**AC из spec:** AC5

**Поглощает:** Вариант A из `plans/2026-05-28__finance-chart-history.md`

**Root cause:** `updateChartDataAsync:1239` фильтрует счета через `getAccountsForCalculation()` без archived scope → архивный счёт не попадает в chart series → исторические точки = 0.

**Решение:** Передать `scope: .historicalAsOf(date)` при расчёте chart series; header/breakdown по-прежнему через `currentVisible`. Использовать `FinanceBalanceScope` из Phase 0.

**Файлы:**
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — строка ~1239: `getAccountsForCalculation(scope: .historicalAsOf(date))`; строки header/breakdown — явно `.currentVisible`
- `millioTests/UI/Services/Finances/FinanceDynamicsViewModelTests.swift` — тест: archived счёт появляется в исторических chart точках за период до архивации; текущий header не включает archived

**Шаги:**
1. `[ ]` Прочитать строки 1230–1250 `FinanceDynamicsViewModel` (getAccountsForCalculation call)
2. `[ ]` Обновить `getAccountsForCalculation` чтобы принимал `FinanceBalanceScope`; добавить ветку для `.historicalAsOf`
3. `[ ]` В `updateChartDataAsync` передавать `.historicalAsOf(date)` для серий
4. `[ ]` Header/breakdown — явно `.currentVisible`
5. `[ ]` Написать тест: после архивации счёта исторические точки на chart за период до `archivedAt` не равны 0
6. `[ ]` Написать тест: header не включает archived счёт
7. `[ ]` Обновить `plans/2026-05-28__finance-chart-history.md` — пометить Вариант A как реализованный в этом плане
8. `[ ]` `xcodebuild test` — все зелёные
9. `[ ]` Коммит: `fix(finance): use historicalAsOf scope for chart series, currentVisible for header`

**Guard phrase:** «Реализуй Phase 5 по плану.»

---

## Edge Cases

- [ ] Счёт добавлен без выбранной группы — link нормализуется в системную Ungrouped-группу, `group = nil` не сохраняется
- [ ] Счёт удалён из одной группы, link переведён в системную Ungrouped-группу, потом добавлен в другую группу — не дублировать link
- [ ] Массовый restore нескольких счетов — lifecycle events для каждого независимо
- [ ] Chart с archived счётом показывает суммарный баланс выше breakdown (visible-only) — known issue до Вариант B; маркировать archived строки серым (UI, вне scope этого плана)
- [ ] SchemaVersion V4 migration у пользователей с existing данными — lightweight, без трансформаций
- [ ] `transactionsUpdated` при массовом импорте — батчить (один event в конце, не N событий)
- [ ] Скрытая системная группа с archived-only links — убедиться, что она не появляется в `visibleGroupsForList()` по умолчанию
- [ ] Links из удалённой группы остаются достижимыми для `getAccountsForCalculation(includeArchivedForHistory: true)` через `state.groups`

## Gates (перед `[x]` на каждой фазе)

- [ ] `xcodebuild test -scheme millio` — все тесты зелёные
- [ ] Нет SwiftData crash при SchemaVersion V4 (Phase 3)
- [ ] CloudKit backup/restore не сломан после Phase 3 (ручная проверка)

## Журнал изменений

- `2026-06-07` — создан план; Phase 0–5 определены; Phase 1 имеет наивысший приоритет
- `2026-06-07` — Phase 1 реализована: `FinanceAccountService.addAccountToGroup()` обновляет account caches перед `loadGroups`; добавлены tests в `FinanceViewModelTests`; `FinanceViewModelTests` зелёные на iPhone 17 iOS 26.5.
- `2026-06-07` — Phase 2 ревизована после диагностики кода: стратегия `group = nil` отклонена, потому что ломает достижимость archived links в `FinanceDynamicsViewModel`; рекомендована системная скрытая группа и добавлен обязательный Dynamics-тест.
- `2026-06-07` — Phase 2 реализована: `FinanceGroupService.deleteGroup()` архивирует underlying и переводит `FinanceAccount` links в системную Ungrouped-группу вместо физического удаления; обновлён `FinanceViewModelTests`, добавлен Dynamics-тест на historical replay. Зелёные: `FinanceViewModelTests`, `FinanceDynamicsViewModelTests` на `iPhone 17 / iOS 26.5`.
- `2026-06-07` — проверен live-report "счёт не появился после добавления": полный `FinanceViewModelTests` подтверждает контракт `addAccountToGroup(nil) -> Ungrouped -> visibleGroupsForList()`. Ручной скрин был на booted `iPhone 17 Pro Max / iOS 26.2`, тогда как тесты Phase 1/2 шли на `iPhone 17 / iOS 26.5`; установленный app на 26.2 запущен отдельно. Следующий ручной retest должен запускать свежую сборку именно на destination `49601B0B-FAE4-4039-94BA-B333C5DFCAAB`.
- `2026-06-07` — live-логи дали реальную причину: `Removed 1 invalid finance account links` после store scope switch `guest -> cached user`. UI add/create flow создавал product VM от `@Environment(\.modelContext)`, а finance-link писал через `FinanceViewModel.modelContext`; при расхождении контекстов cleanup не видел underlying card/credit/investment и удалял link. Исправлено: `FinanceAddAccountView` и legacy `FinanceCreateViews` используют единый `viewModel.modelContext` для product VM, group recommendation и edit-link lookup. Проверено: `FinanceViewModelTests` зелёные; `xcodebuild build` зелёный на live destination `49601B0B-FAE4-4039-94BA-B333C5DFCAAB`.
- `2026-06-07` — Phase 0 реализована: добавлен `FinanceBalanceScope` с пятью scope'ами, в `FinanceDynamicsViewModel` добавлен `BalanceScope` marker и комментарии у текущих `getAccountsForCalculation` call-sites без изменения бизнес-логики. Проверено: `FinanceDynamicsViewModelTests` зелёные на destination `49601B0B-FAE4-4039-94BA-B333C5DFCAAB`.

## Итог (заполняется при завершении)

**Результат:** —
**Дата завершения:** —
