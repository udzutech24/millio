# Handoff: перестройка ядра счетов — фазы 0–6a РЕАЛИЗОВАНЫ

**Дата:** 2026-07-05 (обновлён после закрытия релиз-блокера ModelTypeRegistry) · **Было:**
🔴 new-core модели (Account/AccountEvent/AccountGroup/AccountDailySnapshot/HistoricalAssetPrice)
не были зарегистрированы в `ModelTypeRegistry` → CloudKit-бэкап/export/restore их не переносили.
**Стало:** блокер ЗАКРЫТ. Детали — §ModelTypeRegistry блокер ЗАКРЫТ ниже и план §10.

Предыдущее обновление 2026-07-05 (закрытие Находки 2 — Вариант B, честная V5):
владелец выбрал Вариант B через `AskUserQuestion`; `AppSchemaV4.models` возвращён к исходному набору
(без `HistoricalAssetPrice`), создана `AppSchemaV5` с `HistoricalAssetPrice` + lightweight-миграция
V4→V5, `AppSchemaCurrent = AppSchemaV5`, добавлены guard-тесты `v4IsSupersetOfV3`/`v5IsSupersetOfV4`.
Находка 2 ЗАКРЫТА. Детали и поведение на «грязных» dev V4-сторах —
`plans/2026-07-04__accounts-core-rebuild-plan.md` §9.
Тест-гейт прогнан, сверен с baseline (см. §Тест-гейт 2026-07-05 ниже).

## Состояние
- Ветка **`feature/accounts-core`** (от develop), НЕ мержено, НЕ запушено — ждёт команды владельца.
- Коммиты: 09e0819 (Ф0 каркас) · 155b150/625a015 (Ф1a сервисы+UI+сид) · 5a719cc (Ф1b Cashflow→события) ·
  5864f79 (Ф2 кредит/долг) · 9642fdc (Ф3 вклад+налог) · ca39904 (Ф4 рынок/активы) · 473ec43 (Ф5 архив) ·
  a895155 (Ф6a пресеты/read-only) · 37a774b (AC10 курсы append-only) + тест-фиксы ff7014f/b41d02a.
- `feature/dynamics-chart-fix` — fallback, не тронута.
- Полный итог + аудит AC1–AC15 + открытые хвосты: **план, раздел 8** (`plans/2026-07-04__accounts-core-rebuild-plan.md`).
- Известные падения тестов и flaky-класс: `progress/accounts-core-baseline-failures.md`.

## Что построено (кратко)
`millio/Core/AccountsCore/` — Account/AccountEvent/AccountGroup/AccountDailySnapshot (схема V4),
AccountBalanceEngine (6 движков, детерминизм, redenomination), AccountsCoreService (единственная
точка записи), AccountSnapshotRebuilder (@ModelActor, инкрементальный кэш), AccountsTotalsService
(totalAt/seriesBetween, курс на дату точки), DepositInterestScheduler, DepositTaxCalculator,
AccountMarketPriceService + HistoricalAssetPrice (append-only цены, честная схема V5 — см. §Находка 2
ниже), AccountArchivePolicy, сид-полигон
(11 счетов, DEBUG-кнопка в AdminStatsDebugView). UI: AccountDetailView (+sheets), ArchivedAccountsView,
мосты AccountsCoreAdditionBridge / AccountsCoreCashflowBridge. Все 11 пресетов добавления создают
счета нового ядра. Grep-гейт: `scripts/check-balance-mutations.sh`.

## Следующие шаги (по приоритету)
1. **Трек guest→user (race + reconciliation + находки) — ЗАВЕРШЁН, кроме одного решения.**
   План: `plans/2026-07-04__guest-user-scope-race-fix.md`. Статус:
   ✅ Track A (race-фикс) — A1–A4 реализованы, тесты 1583/17 лучше baseline;
   ✅ Track D1 (удаление не обновляло список/тоталы) — оба слоя;
   ✅ Track C (конвертация легаси→ядро, MVP opening balance) — 17 тестов;
   ✅ Track B (reconciliation, B1+B1b+B2a-d+hardening) — РЕАЛИЗОВАН ПОЛНОСТЬЮ (коммиты
   e9a812d/466805a/4dacba9/56402e1/dc440ed), 26 reconciliation-тестов, все 8 митигаций B1b встроены;
   ✅ Находка 1 (race guest→user, документация была неактуальна) — закрыта проверкой 2026-07-05,
   код уже чинил Track A+B, см. §Сим-проверка выше;
   ✅ Находка 2 (V4 in-place, миграционный риск) — ЗАКРЫТА 2026-07-05 Вариантом B (честная V5),
   см. §Находка 2 ниже;
   ✅ мелочь «10 счетов»→«12 счетов» починена.
   ✅ **Релиз-блокер ModelTypeRegistry — ЗАКРЫТ 2026-07-05.** Все 5 моделей ядра зарегистрированы для
   полного CloudKit backup/restore; reconciliation (Track B) явно исключает 4 из них из своего
   legacyData, чтобы не задвоить merge с `copyNewCore`. Детали — §ModelTypeRegistry блокер ЗАКРЫТ ниже.
   Ручные проверки остаются: runtime login/logout/force-signout, fresh install+iCloud, UI-конвертация
   легаси — все требуют реального Apple ID, недоступного в этой среде. Следующий шаг по согласованной
   последовательности — `/stress-test` UI-флоу + эти ручные проверки владельцем (не часть этой сессии).
2. **Решение владельца по 6b** — физический снос Card/Credit/Investment/FinanceAccount (~90 файлов,
   backup-реестр, схема V5/V6 — зависит от решения по Находке 2). До решения легаси живёт read-only.
   Строго после Track A–C и /stress-test.
3. Ручная проверка на симуляторе: сид → Accounts/Analytics/Dashboard/Cashflow (сверка чисел),
   затем `/stress-test` UI-флоу перед мержем в develop.
4. Хвосты: StockBulkImport на ядро, UI редоминации, тест AC14, налог для валютных вкладов,
   пикеры Quick Entry/Bulk Import, LanguageManager-гонки в тестах (план §8, хвосты 1–14).

## Сим-проверка 2026-07-04 (вечер) — итоги и находки

Прогон: iPhone 17 Pro (3EC86784), Debug-сборка BUILD SUCCEEDED, сид залит через
DEBUG-кнопку AdminStatsDebugView (12 счетов + маркер, 45 событий в ZACCOUNT/ZACCOUNTEVENT
user-стора — подтверждено sqlite). Тест-гейт: 17 падений, ВСЕ из baseline/flaky-класса
(из baseline 2 прошли, включая починенный testIncomeBudgetSummary… 6cbe610) — «не хуже baseline» ПРОЙДЕН.

**✅ Находка 1 — ЗАКРЫТА проверкой 2026-07-05 (race guest→user).** Этот блок описывал состояние
ДО Track A (коммит написан в 22:28, Track A запушен в 23:04-23:30 того же вечера) и с тех пор не
обновлялся — текст был неактуален. Перепроверено по коду на HEAD `feature/accounts-core`:
1) `RootTabView.ensureFinanceViewModel()` (`RootTabView.swift:330-332`) по-прежнему создаёт VM один раз
   через `guard financeViewModel == nil`, НО это больше не проблема — при бампе `scopeIdentityToken`
   (millioApp.swift:534, сразу после свопа `activeModelContainer` в `rebindDataScope`) меняется
   `.id(RootSceneIdentity(language:scope:))` всего контентного поддерева (millioApp.swift:144) →
   SwiftUI полностью пересоздаёт `RootTabView`, его `@State financeViewModel` сбрасывается в `nil`,
   `ensureFinanceViewModel()` создаёт новый VM уже на актуальном `modelContext`. Ровно класс фикса,
   который требовала эта находка, — реализован в A1+A2 (2f543e3).
2) Историческая дупликация 34 legacy-счетов между guest/user (описанная в старом тексте как
   «симптом (в)») — это фактические ДАННЫЕ, накопленные ДО фикса; они закрываются не Track A
   (предотвращает НОВУЮ гонку), а Track B (`reconcileScopeIfNeeded`, millioApp.swift:420-470) —
   идемпотентный merge guest→user на каждом cold start с user-скоупом, включая легаси-модели
   (upsert по `*UniqueID`) и new-core (прямая копия по id). Проверено на копиях РЕАЛЬНЫХ сторов
   (B2d, коммит 56402e1): merge не задваивает базу, восстанавливает дельту, идемпотентен при повторе.
   Итого A (не допускает новую гонку) + B (лечит уже накопленное расхождение) закрывают находку
   полностью на уровне кода и логики.
**Остаётся ТОЛЬКО ручная проверка** реального cold-start с настоящим Apple ID login/logout/
force-signout на устройстве — недоступна в этой среде (нет Apple-логина), помечена как открытый
пункт ещё в Track A A4 (см. план, не новый блокер). Fix отдельно кодом не переделывался — он уже
был на branch до этой сессии, находка была задокументирована с опозданием (см. журнал плана 2026-07-05).

**✅ Находка 2 — ЗАКРЫТА 2026-07-05, Вариант B (честная V5).** Была: `HistoricalAssetPrice` добавлен
в `AppSchemaV4.models` задним числом, после того как реальный V4-стор с ДРУГИМ набором таблиц уже
существовал на dev-устройстве владельца → SwiftData не находил совпадения по версии → в DEBUG уходило
в `rebuildStorePreservingData` (переименовывает стор в `.bak`, создаёт пустой). V4 никогда не попадал
ни в TestFlight, ни в App Store — риск был ограничен dev/sim-окружениями. Владелец выбрал Вариант B
через `AskUserQuestion` (не Вариант A «заморозить V4 как есть» — это закрепило бы задне-числом-правку
как норму). Реализация (`millio/Core/Schema/AppSchemaVersions.swift`): `AppSchemaV4.models` вернули
к исходному набору (Account/AccountEvent/AccountGroup/AccountDailySnapshot, без HistoricalAssetPrice);
новая `AppSchemaV5.models = AppSchemaV4.models + [HistoricalAssetPrice]`; `AppMigrationPlan` — стадия
`.lightweight(V4→V5)`; `AppSchemaCurrent = AppSchemaV5`. Guard-тесты `SchemaConsistencyTests.
v4IsSupersetOfV3`/`.v5IsSupersetOfV4` добавлены — ловят повторение этого класса бага.
**Поведение на «грязных» dev/sim-сторах** (созданных ДО фикса, физически уже содержащих
`HistoricalAssetPrice` под версией 4.0.0): при открытии они снова не совпадут по декларации (это
неизбежно — нельзя задним числом исправить уже созданный физический стор), сработает тот же
DEBUG-путь `rebuildStorePreservingData` — `.bak`-переименование + пустой стор на V5. Losses ограничены
dev-окружением разработчика, поведение предсказуемо и задокументировано в плане §9. Полная запись
решения — `plans/2026-07-04__accounts-core-rebuild-plan.md` §9.

**🟢 Починено ранее:** стрей-текст `plotFrame` в `AccountBalanceChartView.swift:288`.

**✅ Мелочь — ПОЧИНЕНО 2026-07-05:** alert сида писал «Демо-портфель создан: 10 счетов»,
фактически создаётся 12 (подтверждено тестом `AccountsCoreSeederTests.seedCreatesTwelveRealAccounts`,
`accounts.count == 12`). Поправлен ключ `accounts_core.debug.seed_success` во всех 3 локалях
(en/ru/zh-Hans), тест переименован (был `seedCreatesTenRealAccounts` — вводил в заблуждение).

**Скриншоты прогона:** scratchpad сессии (step*.png); финальные 4 экрана с сид-данными — НЕ сняты
(экран Mac заблокировался, cliclick недоступен; и без Находки 1 сид в UI всё равно не виден).
Гостевой стор: перед экспериментом сделан бэкап `millio_guest.backup.store` в scratchpad;
в guest-стор скопированы 13 ZACCOUNT + 6 ZACCOUNTGROUP из user (для проверки Находки 1 —
результат проверить после разблокировки экрана; откат: восстановить из бэкапа).

## ModelTypeRegistry блокер ЗАКРЫТ (2026-07-05)

**Проблема:** Account/AccountEvent/AccountGroup/AccountDailySnapshot/HistoricalAssetPrice не были
зарегистрированы в `ModelTypeRegistry` → CloudKit-бэкап/export/restore их не переносили. Пользователь
нового ядра, сделавший backup и restore (напр. смена устройства), терял все счета/события ядра.

**Мини-стресс-тест ДО реализации выявил реальный конфликт с Reconciliation (Track B):**
`ScopeMergeReader.readGuestInput` строит `legacyData` через `DataRepository.exportAllData(from:)` —
ту же функцию, что читает `ModelTypeRegistry`. Простая регистрация core-моделей привела бы к тому,
что `ScopeMergeWorker.apply()` импортировал бы Account/AccountEvent/AccountGroup ДВАЖДЫ: один раз
через новый generic-импортёр (внутри `legacyData`), второй раз — через существующий выделенный
by-id merge `ScopeMergeDedup.copyNewCore` (спека §0.4). Риск — разъезд деталей реконструкции между
двумя путями (например, `dayKey` у `AccountEvent`, риск Т5). Решение согласовано с владельцем
(`AskUserQuestion` → «Да, расширить скоуп») и реализовано.

**Реализация:**
- `DataRepository.exportAllData(from:excluding:)` — новый опциональный параметр (по умолчанию пустой
  набор, обратная совместимость для существующих вызовов, включая полный backup).
- `ScopeMergeReader.newCoreTypeNames` = `{Account, AccountEvent, AccountGroup, AccountDailySnapshot}` —
  исключаются из `legacyData` reconciliation; единственный merge-путь для них остаётся
  `ScopeMergeDedup.copyNewCore` (Account/AccountEvent/AccountGroup) либо пересборка снапшотов после
  merge (AccountDailySnapshot). `HistoricalAssetPrice` в исключение НЕ входит — у него нет
  выделенного merge-пути, мержится через общий importer как `HistoricalRate` (upsert по symbol+dayKey).
- Все 5 моделей получили `Persistable`-конформанс (`export()`/`import(_:)` stub) в своих файлах —
  Decimal-поля (включая вложенные в 6 meta-структурах `AccountMeta.swift`) сериализуются СТРОКОЙ,
  не JSON-числом: экспортируемый словарь дважды проходит через `JSONSerialization` (внутри
  `ModelTypeRegistry.register` и в `DataRepository.exportAllData`), на этом пути `Decimal` бриджится
  в `NSNumber`/`Double` и теряет точность; строка переживает оба прохода без искажений.
- Новый файл `AccountsCoreFeatureRegistration.swift` — регистрация + 5 импортёров с приоритетом
  импорта (AccountGroup=30 → Account=31 → AccountEvent/AccountDailySnapshot=32), чтобы связи
  (group→id, account→id) резолвились корректно. `AccountEventImporter` явно восстанавливает `dayKey`
  из бэкапа вместо пересчёта из `date` (риск Т5).
- Вызов `AccountsCoreFeatureRegistration.register()` добавлен в `millioApp.registerFeatures()`.
- Комментарий-инвариант в `ScopeMergeSnapshot.swift:8` обновлён: core теперь В реестре, но исключён
  из reconciliation-пути (был: «НЕ в ModelTypeRegistry»).

**Known-behavior (не регрессия, задокументировано, не в скоупе этой сессии):** если backup сделан на
версии приложения С зарегистрированным ядром, а restore выполняется на СТАРОЙ версии (ядро ещё не
зарегистрировано) — `DataRepository.importAllData` бросает `AppError.restoreFailed` на ВЕСЬ бэкап
(«Неизвестные типы моделей в backup: ...», `DataRepository.swift:139-142`), а не игнорирует
только неизвестные типы. Это существующее (до этой сессии) поведение — защита от тихой потери
данных, действует для ЛЮБОГО когда-либо добавленного типа, не специфично для ядра счетов. На практике
маловероятно (App Store не позволяет откатить версию), но стоит иметь в виду при откате/TestFlight.

**Тесты (5 новых/изменённых, все зелёные):**
- `AccountsCoreBackupTests.testFullRoundTripAllAccountKinds` — round-trip export→clear→import всех
  8 kind Account + событие (dayKey сохранён) + группа + снапшот + HistoricalAssetPrice, данные идентичны.
- `AccountsCoreBackupTests.testRestoringOldBackupWithoutCoreEntitiesSucceeds` — старый бэкап без ядра
  восстанавливается без исключений на версии с зарегистрированным ядром.
- `ScopeMergeReaderExclusionTests` (новый файл, 2 теста) — `exportAllData(excluding:)` и
  `readGuestInput().legacyData` НИКОГДА не содержат new-core типы, даже когда те зарегистрированы.
- `ScopeMergeWorkerTests.registerFeatures()` дополнен `AccountsCoreFeatureRegistration.register()` —
  существующий `newCore_copiedByIdAndIdempotent` теперь реально проверяет отсутствие двойного импорта
  (раньше core-модели не были в реестре тестового окружения и баг не мог проявиться) — прошёл.

## Тест-гейт 2026-07-05 (после B2-верификации + закрытия находок)

Полный `millioTests` на iPhone 17 Pro, build ✅ 0 ошибок. Прогон 336 сек. Авторитетный summary-блок
xcodebuild («Failing tests:», с дедупом retry-попыток) — **19 уникальных падений**, ВСЕ объяснены:
- 15 из 16 baseline (`progress/accounts-core-baseline-failures.md`) — точное совпадение по имени;
- 1 baseline-тест (`CashflowViewModelTests.testPlannedExpenseAutoAppliesOnDueDate`) **теперь проходит**
  (был нестабильным и раньше — улучшение, не регрессия);
- 4 — задокументированный flaky-класс «LanguageManager.shared race»
  (`CashflowCategoryHelpContentTests.*`, `CashflowTransactionEditorViewLayoutTests.*`).

**Новых регрессий — 0.** Гейт «не хуже baseline» пройден (по факту — на 1 тест лучше).

## Тест-гейт 2026-07-05 (после закрытия блокера ModelTypeRegistry)

Полный `millioTests` на iPhone 17 Pro, build ✅ 0 ошибок, прогон ~311 сек, 1632 passed. Авторитетный
блок xcodebuild «Failing tests:» (дедуп по имени) — **19 уникальных падений, ИДЕНТИЧНО** предыдущему
гейту сессии (см. выше):
- 15 из 16 baseline (`progress/accounts-core-baseline-failures.md`) — точное совпадение по имени;
- 1 baseline-тест (`CashflowViewModelTests.testPlannedExpenseAutoAppliesOnDueDate`) по-прежнему проходит;
- 4 — задокументированный flaky-класс «LanguageManager.shared race»
  (`CashflowCategoryHelpContentTests.*`, `CashflowTransactionEditorViewLayoutTests.*`).

Прицельный прогон новых/изменённых тестов (`AccountsCoreBackupTests`, `ScopeMergeReaderExclusionTests`,
`ScopeMergeWorkerTests`, `AccountSchemaTests`, `BackupRestoreIntegrityTests`) — все зелёные, включая
регрессионный `ScopeMergeWorkerTests.newCore_copiedByIdAndIdempotent` (теперь с зарегистрированным
ядром в `ModelTypeRegistry` тестового окружения — доказывает отсутствие двойного импорта).

**Новых регрессий — 0.** Гейт «не хуже baseline» пройден (точное совпадение состава падений).

## Правила (без изменений)
Bulletproof — только через суб-агента; не пушить/не мержить без запроса; симулятор iPhone 17 Pro;
guard phrase для кода. Гейт тестов: «не хуже baseline» по файлу baseline-failures.
