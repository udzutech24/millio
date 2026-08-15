# Итог: кредитная карта — research/spec/plan

## Какая задача была поставлена

Исследовать, спроектировать и реализовать полноценную продуктовую вертикаль кредитной карты.

## Как задача решалась

Прочитаны инструкции и `$millio-bulletproof`, сохранён dirty baseline пользователя, трассированы Account/CardMeta/AccountEvent/catalog/factory/totals/Cashflow/creation/detail/edit/backup/schema и запущены baseline characterization tests. Созданы research, spec, phased plan и status.

## Решена ли задача

Частично: фазы 1–4 завершены. Signed contract, typed events и specialized creation/detail/edit реализованы; linked Cashflow/transfer writers остаются в фазе 5.

## Эффективно ли решение

Да: продуктовый код и пользовательские незакоммиченные изменения не затронуты; неоднозначный финансовый контракт не закреплён импровизацией. Масштаб L оправдан риском миграции финансовых данных и двойного Cashflow.

## Как было до и как стало

До: кредитка — generic cash account с available-balance semantics и без специализированных операций/UX. После фазы 3: legacy ledger сохранён, но все consumers получили чистый signed contract; purchase/refund/repayment/fee/interest имеют отдельные persisted event types и guarded writer. Schema не менялась.

## Проверки фазы 3

- 23 serial semantic/catalog/totals-revision tests — passed, включая historical event-boundary replay.
- Account product/Core backup, SchemaConsistency, SchemaMigration — passed.
- Полный `AccountsTotalsServiceTests` сохранил два baseline failure: stale historical-FX characterization и старое ожидание `.cash` вместо канонического `.debitCard`. Они не вызваны фазой 3 и не маскировались изменением тестов.

## Фаза 4 — specialized UX

Добавлены отдельные credit-card detail/edit surfaces, расширен creation draft поддерживаемыми CardMeta terms, восстановлено управляемое `includeInTotal`, добавлены строгая валидация и атомарный rollback editor. 18 targeted tests прошли; после финальных creation assertions чистый Debug app build прошёл. Повторный test-target build заблокирован несвязанными committed-тестами `FinanceOverviewLedgerStyleTests`, которые вызывают отсутствующий `balanceComposition`; чужой baseline не менялся.

## Идеи по улучшению

Перед фазой 3 завершить или зафиксировать текущий real-estate/save-boundary baseline, чтобы не смешивать владельцев пересекающихся правок. Отдельная improvement-запись не создана: этот риск уже отражён в research и plan.
## Фаза 5 — 2026-08-10

1. **Какая задача была поставлена.** Реализовать фазу 5 продуктовой вертикали кредитной карты: purchase/refund/repayment, Cashflow, атомарность и idempotency.
2. **Как задача решалась.** Добавлен единый `CreditCardOperationCoordinator` с одной SwiftData save boundary. `operationID` связывает Cashflow и AccountEvent; refund группируется с исходной покупкой; repayment создаёт transfer-out и typed card leg. Добавлены проверки source policy, funds, currency, refund remainder, conflicting retry и rollback.
3. **Решена ли задача.** Да. Шесть targeted-сценариев прошли; app и test target скомпилировались. Схема не изменялась.
4. **Эффективно ли решение.** Да: переиспользованы текущие `AccountEvent`, `CashflowTransaction`, `AccountsCoreSaveBoundary` и snapshot invalidation; новой persisted-модели и drive-by refactor нет.
5. **Как было до и как стало.** До: typed card event сохранялся отдельно от Cashflow, repayment policy и refund cap отсутствовали. Стало: весь денежный граф коммитится атомарно, retry не плодит дубли, а settlement не искажает Cashflow expense.
6. **Идеи по улучшению.** UI-формы операций, localization и render QA остаются в фазе 8; календарь и reminders — в фазе 6. Отдельная improvement-запись не нужна: нового повторяющегося класса проблем не выявлено.
## Фаза 6 и продуктовый feedback — 2026-08-10

1. **Какая задача была поставлена.** Вводить в корректировке именно сумму долга, добавить дату начала/дни отсрочки, точную дату платежа, reminder, форматирование лимитов и качественный UI.
2. **Как задача решалась.** Долг преобразуется в legacy available balance через `CreditCardFinancialContract`. Денежные поля переведены на `AmountTextField`. Добавлены typed payment settings, pure calendar policy, payment-status card и одноразовое локальное уведомление через существующий `NotificationManager`.
3. **Решена ли задача.** Да. Targeted тесты и build прошли. Два старых Cashflow notification-теста падают на устаревшем текстовом ожидании; они не менялись.
4. **Эффективно ли решение.** Да: финансовая SwiftData-схема не раздута UI-настройками; календарь детерминирован и протестирован.
5. **Как было до и как стало.** До: пользователь видел технический «баланс», не мог указать точную дату и reminder, а лимит вводился без grouping. Стало: debt-first wording/input, два режима payment date, typed reminder и адаптивные glass-секции.
6. **Идеи по улучшению.** Фаза 7 должна явно решить, включать ли payment preferences в backup/sync. Фаза 8 — полная RU/EN/zh-Hans localization и simulator render QA.
