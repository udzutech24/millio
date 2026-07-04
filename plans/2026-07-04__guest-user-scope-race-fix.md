# План: фикс race guest→user + конвертация легаси-счетов

**Дата:** 2026-07-04 · **Статус: В РАБОТЕ** (Track A A1–A4 ✅, Track C C1–C3 ✅, Track D D1 ✅; Track B B2 не начат)
**Ветка:** feature/accounts-core (поверх фаз 0–6a rebuild'а) · **Родитель:** `plans/2026-07-04__accounts-core-rebuild-plan.md` §8, хвост №10
**Research:** millio-audit 2026-07-04 (карта ниже) · **Handoff:** `progress/accounts-core-rebuild-handoff.md` §Сим-проверка

## 1. Диагноз (подтверждён, file:line)

Холодный старт: `millioApp.init()` синхронно создаёт guest-контейнер (`millioApp.swift:78-81`).
`initializeColdStart` (`:194`): (1) `useCase.initialize()` ставит `lifecycle = .ready` (`AppLifecycleUseCase.swift:67,74`) →
(2) `restoreSession()` → `.authenticated` (`AuthService.swift:1505`) → (3) `synchronizeDataScope` → `rebindDataScope`,
где только после async `prepareDependencyBinding` (сетевой `await MarketAPIClient.configure`, `millioApp.swift:385`)
происходит `activeModelContainer = user` (`:397`). **Окно:** между (1) и (3) MainActor свободен → RootTabView
монтируется на guest → `FinanceViewModel`/`CashflowViewModel` создаются один раз (`RootTabView.swift:331-337`,
guard `== nil`) и снимают `modelContext` в `let` (`FinanceViewModel.swift:295`) → все их lazy-сервисы
(AccountsTotalsService `:326`, AccountSnapshotRebuilder `:329`, AccountsCoreService/мосты `CashflowViewModel.swift:110-116`,
recurring) навсегда на guest. `.id(appState.languageRefreshToken)` (`millioApp.swift:125`) пересоздаёт дерево только при смене языка.

**Раскол:** DI-сервисы (BackupManager, DataRepository — `millioApp.swift:237`) корректно пересоздаются на user,
VM-слой — нет. → UI-записи идут в guest мимо CloudKit-бэкапа; user-store после first-login миграции
(`migrateExistingStoresIfNeeded`, `millioApp.swift:628-663`, guard `targetCount == 0` `:634`) — заморожен.

**Смежная дыра:** `clearState()` НЕ вызывает `onSessionChanged` в путях `AuthService.swift:1298` (restore→nil),
`:1319` (restore error), `:1455` (401 на `me`); только `logout()` (`:1476`) вызывает вручную → force-signout
оставляет скоуп на user без ребинда. (= известный security-баг 2026-06-16.)

## 2. Стресс-тест (2026-07-04) — 10 причин провала и митигации

| # | Риск | Вероятность | Митигация (встроена в фазы) |
|---|------|-------------|------------------------------|
| 1 | **Перенос данных-невидимок:** после фикса UI читает user-store → всё, что залогиненные пользователи писали в guest после первого логина, «исчезает» = воспринимаемая потеря данных | Высокая (для когорты залогиненных) | Track B (reconciliation) обязателен в том же релизе; фичефлаг/гейт релиза |
| 2 | **Зависание старта:** блокировать `.ready` на `prepareDependencyBinding` с сетевым `MarketAPIClient.configure` → offline вечный LaunchingView / watchdog | Высокая | A1: вынести сетевой configure из критпути (defer/timeout), `.ready` ждёт только swap контейнера |
| 3 | **In-flight записи старых VM:** teardown по `.id` не отменяет задачи (recurring, @ModelActor rebuild, pending save) → короткая гонка записей в guest после свопа, риск крэша на снесённом контейнере | Средняя | A2: cancel/await задач VM перед бампом токена; drain AccountSnapshotRebuilder |
| 4 | **Тихий даунгрейд на guest по transient-ошибке:** A3 в лоб (onSessionChanged на всех clearState) → сетевая ошибка restore = пользователь молча видит чужой/старый guest-датасет | Высокая | A3: различать terminal (401) vs transient (network) — transient НЕ меняет скоуп; force-signout → явный экран re-login |
| 5 | **Restore-флоу ломается порядком:** `presentRestoreFlowIfNeeded` (`millioApp.swift:364`) и `activeScopeStoreExistedBeforeBinding` (`:398-405`) чувствительны к перестановке шагов | Средняя | A4: матрица cold-start сценариев (fresh install + бэкап, .bak-fallback V4) |
| 6 | **Watchdog на слабых устройствах:** V4 no-plan fallback (rebuildStorePreservingData) теперь в критпути старта | Средняя | A1: rebind вне блокировки main; замер длительности; связка с хвостом №11 (честная V5) |
| 7 | **UX-шок при смене скоупа:** полный сброс дерева (логин/логаут/force-signout) — потеря навигации, другие цифры без объяснения | Средняя | A2: переходный экран «Переключаю профиль…»; приемлемость сброса подтверждена владельцем |
| 8 | **Двойной счёт в тоталах после конвертации:** Track C создаёт new-core счёт, легаси остаётся → «Общий баланс» ×2 | Высокая (для C) | C1: конвертированный легаси исключается из тоталов/списков атомарно с созданием |
| 9 | **Конвертация не на том сторе:** если C уедет раньше A — конвертация выполнится на guest-сторе и потеряется | Высокая (при нарушении порядка) | Жёсткий порядок: A → B → C → 6b |
| 10 | **Слепое пятно — тесты/UI-тесты:** гейтинг `.ready` меняет момент монтирования RootTabView → XCUI-флоу и flaky-класс могут поплыть; сим-проверка делалась на user-сторе | Средняя | A4: тест-гейт «не хуже baseline» + прогон UI-смоука; сим-проверка обоих скоупов |

## 3. Фазы

### Track A — фикс race (класс «пересоздание VM при смене скоупа»)

- [x] **A1. Упорядочивание холодного старта.** РЕАЛИЗОВАН (коммит 2f543e3). `synchronizeDataScope`
  получил замыкание `onScopeResolved`, вызываемое ПОСЛЕ свопа контейнера и ДО `presentRestoreFlow`;
  `useCase.initialize()` (ставит `.ready`) перенесён в это замыкание в `initializeColdStart` — после
  `restoreSession`. RootTabView монтируется уже на финальном контейнере. `presentRestoreFlow` остаётся
  последним и видит `lifecycle==.ready` (LaunchRecoveryPolicy требует `.ready`) → порядок restore сохранён (риск №5).
  **Уточнение диагноза:** `MarketAPIClient.configure` (TwelveDataClient.swift:595) — НЕ сетевой (только запись
  в actor'ы), в критпуть сети НЕ добавлено; риск №2 в исходной формулировке переоценён.
- [x] **A2. Scope-token в identity.** РЕАЛИЗОВАН (коммит 2f543e3). `RootSceneIdentity(language, scope)` в `.id`
  контентной группы; `scopeIdentityToken` бампится в `rebindDataScope` ПОСЛЕ свопа `activeModelContainer` →
  SwiftUI пересоздаёт RootTabView и VM на новом modelContext. Отмена in-flight задач старых VM — в их `deinit`
  (FinanceVM `cancelBackgroundTasks`, CashflowVM `restoreReloadTask.cancel`) при teardown по `.id`; старый
  контейнер жив по ARC (риск №3). Переходный оверлей `ScopeSwitchOverlayView` («Переключение профиля…»,
  RU/EN/zh-Hans) на рантайм-смену скоупа (риск №7).
- [x] **A3. onSessionChanged во всех путях clearState.** РЕАЛИЗОВАН (коммиты f58bea7 + тесты 1b5a0d0).
  `finalizeSignOut()` = clearState + `ScopeCache.clearUserID()` + `onSessionChanged(nil)`; применён в `logout()`
  и в 401-на-`/me` (`reloadCurrentUser`, runtime — реальный security-путь). **Отклонение:** пути restoreSession
  `:1298/:1319` (только cold start) НЕ ребиндят — скоуп там разрешает явный `synchronizeDataScope`, а
  `onSessionChanged` дал бы лишний CloudKit-fetch в presentRestoreFlow (риск №2); добавлены комментарии.
  Transient-ошибки скоуп не меняют (`shouldKeepSessionOnRestoreFailure`, риск №4). Закрыт security-баг 2026-06-16.
- [x] **A4. Верификация.** РЕАЛИЗОВАН. build 0 ошибок ✅ (plotFrame-warning тоже устранён); grep-гейт
  `check-balance-mutations.sh` ✅; AuthManagerTests 100% (+2 новых A3-теста) ✅; полный millioTests
  **1583 passed / 17 failed** — лучше baseline (1576/20): все 17 = baseline(13)+flaky-класс(4), новых
  регрессий 0, auth/scope не затронуты ✅; сим-проверка cold start guest на iPhone 17 Pro (3EC86784) ✅ —
  Дашборд рендерит данные guest-стора (Общий баланс 158 230 663 ₽, Изм. активов 724 706 ₽ — core-счета
  прошлой сессии видны), процесс жив, краша нет. **Требуют ручной проверки** (нет Apple-логина в среде):
  cold start user / runtime login / logout / force-signout / fresh install + iCloud backup / V4 .bak-fallback.

### Track B — reconciliation данных guest↔user (прод-обязателен до/вместе с релизом A)

- [x] **B1. Дизайн merge.** Спека: `specs/2026-07-04-guest-user-reconciliation.md` (2026-07-04, ночь).
  Ключевое: детектор count+max(updatedAt) по-модельно; легаси через exportAllData→importAllData +
  расширенный DataIntegrityCleaner.dedupeAll (транзакции сейчас НЕ дедупятся — importAllData слепой INSERT);
  идентичность транзакций = вычисляемый content-fingerprint transactionUniqueID (CashflowTransaction.swift:921-923);
  new-core — прямая копия по id; снапшоты не мержим — rebuildAllAccounts. **🔴 Побочная находка (релиз-блокер отдельно):
  new-core модели НЕ в ModelTypeRegistry → CloudKit-бэкап и export/import новое ядро НЕ переносят.**
- [x] **B1b. /stress-test дизайна (2026-07-04, ночь)** — 10 рисков; обязательные митигации к реализации:
  (1) lineage-check перед авто-merge (guest∩user fingerprints; чужой guest на шаренном устройстве → спросить);
  (3) multiset-дедуп (max count по fingerprint, НЕ схлопывать до 1 — bulk-импорт даёт коллизии createdAt);
  (4) дедуп групп по UUID + fallback по имени с перецепкой счетов; (5) единственный save в дочернем контексте,
  done-маркер после; (6) НЕ ставить done при fallback-открытии стора (V4 no-plan), в маркере хранить counts;
  (7) НЕ one-shot: идемпотентный merge на каждом переходе guest→user (детектор first); merge асинхронно
  с progress-UI (watchdog); блокировка бэкапа флагом «merge в процессе»; sanity-abort + .premerge.bak.
  **Дефолты в отсутствие владельца:** guest после merge не трогаем; одна краткая сводка пользователю;
  регистрация new-core в ModelTypeRegistry — отдельный релиз-блокер, не в ночном скоупе; LWW принят.
- [ ] **B2. Реализация + прогон на копиях реальных сторов владельца** (guest/user с устройства, наход. 2 учтена).
  Строго с митигациями B1b. Открытые вопросы владельцу — в утреннем отчёте (§ спеки «Открытые вопросы»).

### Track C — конвертация легаси-счетов в новое ядро (вводная владельца 2026-07-04)

Легаси-счета (Card/Credit/Investment/FinanceAccount) с Ф6a read-only: ни удалить, ни изменить (скрин: счёт «ОГ»).
Нужен per-account выход в новое ядро.

- [x] **C1. Действие «Перевести в новое ядро»** РЕАЛИЗОВАН. Кнопка `convertToCoreFooterButton` рядом с
  «Удалить актив» в `FinanceDynamicsView` (оба футера — обычный + рыночный), подтверждающий оверлей
  (RU/EN/zh-Hans + de/es/fr/tr). Создаёт core-`Account` через `AccountsCoreService.createAccount` (grep-гейт ✅).
  **Маппинг типов (девиация от брифинга, обоснована):** Card→`.debitCard` (netWorthAmount, signed),
  Credit→`.loan` (opening=магнитуда `remainingAmount`, движок C инвертирует), Investment→**`.manualAsset`**,
  а НЕ `.marketInvestment` — рыночный движок E считает qty×price и ИГНОРИРУЕТ opening → двойник показал бы 0,
  ломая инвариант тотала; MVP запрещает реплей котировок; `.manualAsset` (движок F) замораживает значение
  одним opening-событием без meta/дрейфа. openingBalance приведён к знаку движка, `includeInTotal=true`
  (кредит вносит `-remaining` всегда, единственный способ гарантировать инвариант). Атомарность (риск №8):
  `LegacyAccountConverter.convert` создаёт двойник и скрывает легаси (`archivedAt`) одним синхронным актом;
  при сбое скрытия двойник откатывается (компенсация). Обновление списков/тоталов — D1-механикой
  (loadAccounts-триплет + `EventBus.investmentsUpdated`).
- [x] **C2. Опция переноса истории — РЕШЕНО: MVP = только opening balance**, без реплея. История остаётся
  видимой в легаси-архиве (`archivedAccountRows()`) до 6b. **Выбор converted-маркера:** НЕ поле в @Model
  (= изменение схемы V4, риск №11) — переиспользуем существующий `archivedAt` (скрывает легаси) + реестр
  соответствий `legacyUniqueID→coreAccountID` в UserDefaults (`LegacyConversionRegistry`, device-local:
  при утере откат недоступен, но double-count не возникает — инвариант держит хранимый `archivedAt`).
- [x] **C3. Откат un-convert** РЕАЛИЗОВАН. `LegacyAccountConverter.unconvert` удаляет core-двойник
  (`physicallyDelete` по реестру) + снимает `archivedAt` легаси. UI: `restoreArchivedAccount` роутит
  конвертированный легаси в un-convert (обычный restore оставил бы и легаси, и двойник → double-count, риск №8).

**Файлы:** `Core/AccountsCore/LegacyConversionRegistry.swift`, `Core/AccountsCore/LegacyAccountConverter.swift`
(новые, legacy-агностичны), `UI/Services/Finances/LegacyAccountConversion.swift` (маппинг), правки
`FinanceViewModel.swift` (action `.convertAccountToCore` + методы + роутинг restore), `FinanceDynamicsView.swift`
(кнопка + оверлей + confirm), `Localizable.xcstrings` (+4 ключа ×7 языков).
**Тесты:** `LegacyAccountConverterTests` (9: инвариант тотала конвертации/un-convert/re-convert/валюта!=primary,
loan/manualAsset знак, rollback, реестр) + `LegacyAccountConversionMappingTests` (8: card/credit/investment→plan) — зелёные.
**Гейты:** build ✅ 0 ошибок/warning, grep-гейт ✅, целевые сьюты Finance*/Account* зелёные (кроме
предсуществующего `FinanceAccountArchivePolicyTests.exactThresholdTriggerWarning` — не связан, файл не трогали).
**Вручную (не покрыто автоматикой):** UI-прокрутка конвертации на устройстве/симуляторе — DEBUG-сидер сеет
только new-core, легаси-счёт нужно создать руками + требуется Apple-login окружение; логика доказана юнит-тестами.

**Зависимость:** C строго после A (иначе конвертация пишет в guest-стор — риск №9). B и C независимы, но
для владельца B раньше C (его данные разошлись).

### Track D — удаление счёта не обновляет список (репорт владельца 2026-07-04, 22:38; research millio-audit ГОТОВ)

«Удалить актив» в деталке счёта («ОГ») — счёт остаётся в списке Счетов и тоталах до перезапуска приложения.

**Root cause (диагноз 2026-07-04):** `removeAccountFromGroup` (`FinanceAccountService.swift:415-434`)
архивирует актив (`archivedAt` + save), но вызывает только `onLoadGroups()`+`onCalculateTotal()` и
**НЕ вызывает `onLoadAccounts()`** — единственное место пересборки `@Published investmentByID`
(`FinanceViewModel.swift:313,421`); связь `FinanceAccount`↔группа тоже не разрывается. Список рендерится
через `getAccountInfo` (`FinanceViewModel.swift:1058-1081`), читающий устаревший `investmentByID` без
фильтра `archivedAt` → строка остаётся. Тотал: `FinanceTotalsService.calculateGroupTotal` (`:146-169`,
`getAccountAmount:274-298`) итерирует живую `group.accounts` и тот же словарь → сумма не меняется.
Для сравнения: `addAccountToGroup` (`FinanceAccountService.swift:404-408`) и `restoreArchivedAccountToGroup`
(`FinanceViewModel.swift:1504-1511`) корректно зовут весь триплет.

**Смежное (adversarial):** (а) тот же паттерн в `deleteAccountPermanently` (`FinanceAccountService.swift:437-454`);
(б) новое ядро: `AccountDetailView.archiveAccount()` (`:816-823`) → `AccountsCoreService.archiveAccount`
(`:466-470`) инвалидирует только снапшот-кэш, явного UI-refresh нет (в отличие от `perform(_:)` с
`refreshToken = UUID()` `:806-814`); реактивность списка ядра через @Query НЕ подтверждена (grep пуст) —
проверить при фиксе; (в) воспроизводить фикс-тест на user-сторе, чтобы не пересечься с race-багом.

**Механизмы-кандидаты:** триплет `loadAccounts/loadGroups/calculateTotalAmount`;
`EventBus.shared.publish(FinanceEvent.investmentsUpdated)` (подписка `FinanceViewModel.swift:882-909` уже есть,
`removeAccountFromGroup` не публикует); `refreshToken` в AccountDetailView.

- [x] **D1. Фикс.** РЕАЛИЗОВАН (коммит 20d05f6). Легаси-путь: `FinanceAccountService.removeAccountFromGroup`
  и `deleteAccountPermanently` (`:415-459`) теперь вызывают `onLoadAccounts()` первым в триплете (симметрично
  `addAccountToGroup`) — пересобирает `cardByID/creditByID/investmentByID`, единственное место фильтра
  `archivedAt`, до этого список и тотал группы («ОГ» из репорта) оставались устаревшими без перезапуска.
  Новое ядро: **воспроизведено, не «уже работает»** — `AccountDetailView.archiveAccount()` (`:816-825`)
  не хранит ссылку на `FinanceViewModel` (только `modelContext`), поэтому `state.totalAmount`
  (пересчитывается лишь явным `calculateTotalAmount()`) никогда не обновлялся после архивации нового
  ядра; список счетов ядра (`newCoreAccounts(matching:)`, живой fetch без @Query/кэша) мог случайно
  «подхватывать» изменение при навигационном re-render, но тотал — гарантированно нет. Фикс: одна строка
  `EventBus.shared.publish(FinanceEvent.investmentsUpdated)` после `service.archiveAccount(account)` —
  переиспользует существующий канал (`FinanceViewModel.subscribeToFinanceEvents`, уже дергает
  `loadAccounts()` + `refreshGroupTotalsAndAmounts()` → `calculateTotalAmountAsync()` → `newCoreTotalProvider`
  → `accountsTotalsService.totalAt`, которая уже фильтрует `participates(on:)`); EventBus-паблиш в
  `AccountsCoreService` (Core-слой) сознательно НЕ добавлен — сервис остаётся независим от UI-шины
  (комментарий в `AccountsTotalsService`: «не трогает старый FinanceTotalsService»), паблиш — в UI-слое
  (`AccountDetailView`), единственная точка вызова `archiveAccount` в UI (grep подтвердил).
  **Тесты:** 2 новых регрессионных в `FinanceViewModelTests.swift` (легаси-путь: `getAccountInfo == nil`
  + `calculateGroupTotal == 0` сразу после `.removeAccountFromGroup`/`.deleteAccountPermanently`, без
  повторного `loadAccounts`). Новое ядро отдельным тестом не покрыто — приватный метод SwiftUI View,
  смешение схем (легаси-контейнер теста без `Account`/`AccountEvent`) сделало бы тест хрупким ради
  однострочного side-effect; корректность канала (`investmentsUpdated`→пересчёт тоталов) уже покрыта
  существующим `testEventBusCardsUpdatedTriggersLoadAccountsAndUpdatesInfo`. Рекомендация: подтвердить
  на симуляторе/устройстве при следующей ручной прогонке (как незакрытые пункты Track A).
  **Гейты:** build 0 ошибок ✅; `FinanceViewModelTests`/`FinanceAccountArchivePolicyTests`/
  `FinanceGroupServiceAccountsCoreTests`/`FinanceInvestmentOrderServiceTests` — все зелёные, кроме
  `FinanceAccountArchivePolicyTests.exactThresholdTriggerWarning()` — **предсуществующий, не связанный
  дефект** (`FinanceDynamicsView.shouldShowBalanceWarning` = `abs(balance) > 0.01`, детерминированно
  не совпадает с тестовым `== true` на границе 0.01; файл не менялся в этой сессии, `git status` чист) —
  вне скоупа D1, не трогали.

## 4. Порядок и релизный гейт

A → B → C → (решение по 6b). Релиз в TestFlight — только A+B вместе (риск №1). C может ехать следом.
D — после мини-research, удобно паровозом с A2 (общая инвалидация FinanceViewModel).

## 5. Журнал

- 2026-07-04: research (millio-audit, карта держателей контекста), /stress-test (10 рисков → митигации в фазы),
  план создан. Реализация не начиналась — ждёт утверждения владельца (правило 7 мастер-карты).
- 2026-07-04 (вечер): **Track A A1–A4 реализован** по команде владельца. Коммиты на feature/accounts-core
  (НЕ мержено, НЕ пушено):
  - `f17a799` chore — изоляция pre-existing правок (unused-var cleanup, ре-сериализация Localizable +1 ключ,
    xcodeproj). **Находка:** «plotFrame-фикс в working tree» из брифинга не существовал — AccountBalanceChartView
    был чист; реальный «stray plotFrame» = deprecated `proxy.plotAreaFrame` (iOS 17) в билд-warning.
  - `548772a` fix — plotAreaFrame→plotFrame (устранён deprecation-warning).
  - `2f543e3` A1+A2 (в одном файле millioApp.swift, поэтому один коммит) — гейтинг `.ready` по свопу скоупа
    + `RootSceneIdentity(language,scope)` в `.id` + оверлей `ScopeSwitchOverlayView` (RU/EN/zh-Hans).
  - `f58bea7` A3 + `1b5a0d0` тесты — `finalizeSignOut` (clearState+ScopeCache.clearUserID+onSessionChanged)
    в logout и 401-на-/me; закрыт security-баг 2026-06-16.
  - **Уточнения диагноза:** (1) `MarketAPIClient.configure` не сетевой → риск №2 в исходной формулировке
    переоценён, сеть в критпуть не добавлена; (2) `restoreSession` вызывается только на cold start, поэтому
    пути `:1298/:1319` скоуп не ребиндят (это делает явный synchronizeDataScope) — отклонение от буквы A3
    ради избежания лишнего CloudKit-fetch (риск №2); (3) риск №3 (in-flight записи) закрыт существующим
    `deinit`-cancel VM при teardown по `.id` + ARC-удержанием старого контейнера, без нового API.
  - **Гейты:** build ✅, grep ✅, тесты 1583/17 (лучше baseline) ✅, сим cold start guest ✅.
  - **Открыто:** ручная проверка сценариев с Apple-логином; Track B (reconciliation) обязателен до релиза
    A вместе (риск №1); Track C/D не трогались.
- 2026-07-05: **Track C C1–C3 реализован** по команде владельца (feature/accounts-core, НЕ мержено/пушено).
  Per-account «Перевести в новое ядро» + un-convert. **Ключевое инженерное решение (ментор-девиация):**
  Investment→`.manualAsset`, а НЕ `.marketInvestment` из брифинга — market-движок E игнорирует opening
  (показал бы 0, ломая инвариант тотала), MVP запрещает реплей котировок; manualAsset (F) замораживает
  значение. **Converted-маркер:** `archivedAt` (без изменения схемы V4) + реестр в UserDefaults
  (`LegacyConversionRegistry`). Атомарность риска №8 — компенсирующий rollback двойника при сбое скрытия
  легаси; риск восстановления конвертированного через архив закрыт роутингом `restoreArchivedAccount`→un-convert.
  Новые: `LegacyConversionRegistry`, `LegacyAccountConverter` (Core, legacy-агностичны), `LegacyAccountConversion`
  (маппинг). Тесты: 9 конвертер/инвариант + 8 маппинг — зелёные. Build ✅ 0 w, grep ✅, Finance*/Account* ✅
  (кроме предсуществующего `exactThresholdTriggerWarning`). **Открыто:** UI-прокрутка конвертации вручную
  (сидер сеет только new-core; нужен Apple-login + ручной легаси-счёт) — логика доказана юнит-тестами.
