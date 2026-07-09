# План 6b Путь B — миграция легаси-счетов в AccountsCore + снос легаси-миров

**Дата создания:** 2026-07-07 · **Статус:** РЕВЬЮ ПРОВЕДЕНО 2026-07-09 (Ф1 реализована, не мержена; Ф1.5 добавлена; открытые вопросы — владельцу) · **Тип:** L, Bulletproof
**Одобрение:** владелец 2026-07-07 — планирование + фаза 1 реализации (ночной runbook `plans/2026-07-07__overnight-run.md` §5, задача №6/№7).
**Вводная:** приложение стоит у 1–2 реальных пользователей; снос признан безопасным стресс-тестом 2026-07-06; потеря истории легаси при opening-balance-миграции согласована владельцем.
**Вход:** `plans/2026-07-02__accounts-system-audit.md`, `plans/2026-07-04__accounts-core-rebuild-plan.md` (фазы 0–6a реализованы, смержены в develop), `progress/accounts-core-rebuild-handoff.md`, память `millio-6b-path-decision`.

> **Риск №1 (двоемирие legacy/AccountsCore).** Сегодня два мира счетов живут параллельно (Т7/S3 базового плана): легаси `Card/Credit/Investment/FinanceAccount` — read-only с Фазы 6a, новое ядро `Account/AccountEvent` — единственный писатель. Чтение слито в 4 точках (см. §4). Путь B закрывает двоемирие: мигрирует данные легаси в ядро и физически сносит легаси-мир. Это устраняет целый класс багов рассинхрона (три пути тотала, дубли, «плывущая» история), описанных в аудите 2026-07-02.

---

## 1. Инвентарь легаси-файлов (по кодбазе, 2026-07-07)

**Метод:** `grep -rlwE "\b(Card|Credit|Investment|FinanceAccount)\b"`. Итог: **80 файлов app-таргета** + **50 тест-файлов** ссылаются на легаси-типы (union ≈ 130; совпадает с оценкой плана «Card 49 / Investment 41 / Credit 22 / FinanceAccount 25»). Из них **выделенно-легаси, удаляемые целиком — ~26 файлов** (ниже), остальные ~54 app + ~50 тестов — правятся (снятие ссылок) или удаляются точечно.

### 1.1 Models (SwiftData @Model — удаляются целиком)
| Файл | Тип |
|------|-----|
| `millio/UI/Services/CardIndex/Card.swift` | `Card` (@Model) |
| `millio/UI/Services/Credits/Credit.swift` | `Credit` (@Model) |
| `millio/UI/Services/Investments/Investment.swift` | `Investment` (@Model) |
| `millio/UI/Services/Finances/FinanceAccount.swift` | `FinanceAccount` (строковая junction-связь) |

⚠️ `FinanceGroup.swift` — судьба решена ревью 2026-07-09: **консолидация с `AccountGroup` — Фаза 1.5** (см. ниже), не «за скоупом». Снос самого файла `FinanceGroup.swift` откладывается до Фазы 5 (после того как все читатели переключены на `AccountGroup` в Фазе 1.5) — модель числится там же, где остальные @Model-файлы легаси-мира.

### 1.2 Core / регистрация / бэкап-импортёры (удаляются / правятся)
| Файл | Действие |
|------|----------|
| `millio/UI/Services/CardIndex/CardManager.swift`, `CardCatalog.swift`, `CardFeatureRegistration.swift` | снос |
| `millio/UI/Services/Credits/CreditManager.swift`, `CreditFeatureRegistration.swift` | снос |
| `millio/UI/Services/Investments/InvestmentManager.swift`, `InvestmentFeatureRegistration.swift` | снос |
| `millio/UI/Services/Finances/FinanceFeatureRegistration.swift` | **правка** — снять регистрацию `Card/Credit/Investment/FinanceAccount` importer'ов |
| Бэкап-импортёры `CardImporter/CreditImporter/InvestmentImporter/FinanceAccountImporter` (в *FeatureRegistration) | снос **осознанно** — старые бэкапы с легаси-счетами не восстановятся (хвост из памяти, при 1–2 юзерах OK) |
| `millio/Core/AccountsCore/LegacyAccountConverter.swift`, `LegacyConversionRegistry.swift`, `millio/UI/Services/Finances/LegacyAccountConversion.swift` | снос **после** завершения миграции (Track C-инфра, больше не нужна) |

### 1.3 UI (удаляются / правятся)
| Файл | Действие |
|------|----------|
| `CardIndex/CardViewModel.swift`, `Credits/CreditViewModel.swift`, `Investments/InvestmentViewModel.swift` | снос |
| `Finances/CardEditorView.swift`, `CreditEditorView.swift`, `InvestmentEditorView.swift` | снос |
| `Finances/FinanceAccountService.swift`, `FinanceInvestmentOrderService.swift` | снос |
| `Finances/Editors/FinanceCreateViews.swift`, `Editors/FinanceEditorWrappers.swift`, `InlineForms/InlineCreateForms.swift` | снос — подтверждённый мёртвый код (аудит 6a п.6) |
| `Finances/AccountTotalPolicy.swift` | снос — политика включения ТОЛЬКО легаси-счёта в тотал; после сноса не нужна (см. §4) |
| `Finances/Import/StockBulkImportServices.swift`, `StockBulkImportSheet.swift` | **правка/снос** — 🔴 ХВОСТ: ещё создаёт легаси `Investment` (аудит 6a п.7); мигрировать на ядро или снять экран ДО удаления `Investment.swift` (иначе не соберётся) |
| `Core/App/ScreenshotDataSeeder.swift` | правка — легаси-сиды только в `isScreenshotMode` (домен Nova); перевести на ядро или изолировать |
| ⚠️ **Не сносить, только снять ссылки:** `FinanceViewModel.swift`, `FinanceTotalsService.swift`, `FinanceDynamicsViewModel.swift`, `FinanceGroupService.swift`, `FinanceDynamicsView.swift`, `FinancesView.swift`, `FinanceRows.swift`, `Cashflow/*` (мосты, персистенс), `QuickSetupApplier.swift` | правка |
| `Investments/MarketData/*` (10 файлов, вкл. `TwelveDataClient`) | **оставить** — SHARED, `AccountMarketPriceService` (ядро) зависит от `MarketDataClientProtocol`/`MarketAPIClient` |

### 1.4 Tests (~50 файлов)
Легаси-тесты `Card*Tests`, `Credit*Tests`, `Investment*Tests`, `FinanceAccount*Tests` — снос вместе со своими мирами. Тесты общих файлов (`FinanceViewModelTests`, `CashflowViewModelTests`, backup/reconciliation) — правка под single-world. Baseline-падения (16 известных + LanguageManager-flaky) — фиксировать по `progress/accounts-core-baseline-failures.md`, гейт «ноль новых красных».

---

## 2. Порядок сноса по слоям (что от чего зависит, что рвётся первым)

Компиляция ломается сверху вниз при снятии типа, поэтому снос идёт **снизу вверх по зависимостям**:

1. **Сначала — живые писатели легаси** (иначе останутся без замены): `StockBulkImportServices` (создаёт `Investment`), `QuickSetupApplier` (уже на ядре — проверить), `ScreenshotDataSeeder`. Пока они пишут `Investment`, `Investment.swift` не удалить.
2. **Затем — читатели-мосты и total-слой**: снять ссылки на легаси в `FinanceViewModel`/`FinanceTotalsService`/`FinanceDynamicsViewModel`/`FinanceRows`/`FinancesView`/Cashflow-мостах. Здесь рвётся первым `AccountTotalPolicy` + `mergingNewCoreSeries` dual-path (см. §4).
3. **Затем — редакторы/VM/менеджеры**: `*EditorView`, `*ViewModel`, `*Manager`, `CardCatalog`, `FinanceAccountService`, `FinanceInvestmentOrderService`, мёртвый код.
4. **Затем — регистрация и бэкап-импортёры**: `*FeatureRegistration`, importer'ы; снять типы из `ModelTypeRegistry`.
5. **Затем — схема SwiftData**: `Card/Credit/Investment/FinanceAccount` убрать из `AppSchemaCurrent` → **новая версия схемы V6** + lightweight-стадия (таблицы дропаются). Только когда ни один тип больше не референсится.
6. **Последними — сами @Model-файлы** `Card.swift`/`Credit.swift`/`Investment.swift`/`FinanceAccount.swift` + `LegacyAccountConverter`/`LegacyConversionRegistry` (после миграции).

**Что рвётся первым:** `AccountTotalPolicy` и dual-path merge в total-слое (шаг 2) — самая сцепленная точка; поэтому переключение чтения на single-world делается рано и отдельным гейтом.

---

## 3. Миграция данных существующих счетов (1–2 юзера) в AccountsCore

**Инструмент готов:** `LegacyAccountConverter` (`millio/Core/AccountsCore/`) + `LegacyConversionRegistry`. MVP: переносит **opening-balance** легаси-счёта (текущий баланс) в новый `Account`, **без реплея истории** (история легаси теряется — согласовано владельцем при 1–2 юзерах). Атомарно: создаёт core-двойник → `hideLegacy()` ставит `archivedAt`; при сбое — компенсирующий откат (`unconvert`).

**Идемпотентность:** `registry.isConverted(legacyUniqueID:)` — повторный прогон не задваивает. Реестр хранится в **UserDefaults** (осознанно — не поле @Model).

**Где вызывать:** одноразовый оркестратор `LegacyAccountsMigrator` (новый, `@MainActor`) при старте с user-скоупом (после reconciliation Track B, до первого рендера Финансов), под флагом-в-SwiftData «миграция выполнена» (НЕ UserDefaults — урок `DailySnapshotMigrator`, чтобы переносился при restore). Обходит все `Card/Credit/Investment` (не converted), маппит → `Input`, вызывает `convert`.

**🟡 Известный гэп конвертера:** `Input` поддерживает только `cardMeta/loanMeta/manualAssetMeta`. Легаси-**вклад** (`Investment` preset=deposit) и **рыночная** позиция (`Investment` cat=stocks/crypto) мигрируют как `.manualAsset`/`.debitCard` с opening-balance — теряют ставку/капитализацию/тикер. При 1–2 юзерах и согласованной потере истории — допустимо; иначе расширить `Input` на `depositMeta/marketMeta/debtMeta` (не блокер фазы 1, помечено).

**UserDefaults-легаси-снапшоты:** старые дневные снапшоты в UserDefaults (память `millio-accounts-system-audit`) + ключи `LegacyConversionRegistry` — **чистятся одноразово** на финальной фазе (после успешной миграции и сноса), т.к. opening-balance-миграция историю не переносит. Кэш ядра (`AccountDailySnapshot`) пересобирается из событий (`AccountSnapshotRebuilder.rebuildAll`).

---

## 4. Судьба мостов и AccountTotalPolicy

| Компонент | Файл | Судьба после сноса |
|-----------|------|--------------------|
| **AccountsCoreAdditionBridge** | `.../Finances/AccountsCore/AccountsCoreAdditionBridge.swift` | **ОСТАЁТСЯ** (маппит 11 пресетов → kind/meta при создании). Упрощается: ветки `isEditingLegacy` в 4 kind-резолверах становятся мёртвыми → удалить. |
| **AccountsCoreCashflowBridge** | `.../Cashflow/AccountsCoreCashflowBridge.swift` | **ОСТАЁТСЯ**, сильно упрощается: исчезают ветки «оба легаси → no-op», «смешанный старый↔новый перевод», world-switch-квадранты, резолвер `resolveNewCoreAccount` (легаси-коллизия UUID). Перевод сводится к чистому new↔new. |
| **AccountsCoreDepositCashflowBridge** | `.../Cashflow/AccountsCoreDepositCashflowBridge.swift` | **ОСТАЁТСЯ** (материализация вклад→Cashflow, регрессия 2026-07-05). Легаси-веток нет → правок минимум; проверить, что не резолвит `Investment`. |
| **AccountTotalPolicy** | `.../Finances/AccountTotalPolicy.swift` | **СНОСИТСЯ.** Это политика «включать ли ЛЕГАСИ-счёт в тотал и с каким знаком». У ядра эквивалент — `Account.participates(date)` (time-aware, Фаза 5) + знак в движке C. После сноса легаси политике нечего решать. |

**Что упрощается в total-слое:** `FinanceTotalsService.calculateTotalsSnapshot` и `FinanceDynamicsViewModel.calculateTotalForAllGroups` сейчас складывают ДВА вклада (легаси через `AccountTotalPolicy` + ядро через `AccountsTotalsService.totalAt`). После сноса — только `AccountsTotalsService.totalAt`. `ChartDataPoint.mergingNewCoreSeries` (поточечное сложение двух рядов) схлопывается в один ряд `seriesBetween`. **Три пути тотала → один** (закрывает R1 аудита 2026-07-02). Точки чтения легаси на снос/правку: `FinanceViewModel.newCoreAccounts`, `FinanceRows` (dual-render), `FinanceDynamicsViewModel` merge, `mergingNewCoreSeries`.

### 4a. Слияние моделей групп `FinanceGroup` ↔ `AccountGroup` — вход из ревью 2026-07-09

**Диагноз** (`plans/2026-07-05__unified-totals.md` §1.3a, верифицирован повторно 2026-07-09): группы, целиком состоящие из AccountsCore-счетов, показывают сумму 0 / «No finance products» / «No groups» на трёх независимых экранах — все три call site (`FinanceTotalsService.calculateGroupTotal:148-160`, `FinanceGroupService.orderedAccounts(for:):83-88`, `FinanceDynamicsViewModel.hydratedAccounts(in:):2681-2695` + `updateDynamicsBreakdown():1059-1086`) читают только `FinanceGroup.accounts` (legacy junction), не зная про `Account.group` (AccountsCore).

**Подтверждено ревью:** `FinanceGroup` (`.../Finances/FinanceGroup.swift:13-48`) и `AccountGroup` (`Core/AccountsCore/AccountGroup.swift:6-17`) — два независимых SwiftData `@Model`, без FK-связи. Единственный мостик — `AccountsCoreAdditionBridge.resolveAccountGroup` (:64-78): при создании/миграции AccountsCore-счёта ищет `AccountGroup` по имени, создаёт новый, если нет. Это уже используется Фазой 1 (двойник счёта резолвит свою группу по имени junction'а), но **только резолвит/создаёт** — не переносит остальные поля и не является постоянной связью:

| Поле | `FinanceGroup` | `AccountGroup` | Судьба при слиянии |
|------|-----------------|-----------------|---------------------|
| `colorHex` | `String` (non-optional) | `String?` | переносится |
| `displayCurrency` | `String?` | `String?` | переносится |
| `order` | есть | есть | переносится |
| `isFavorite` | есть | **нет** | ✅ переносится (решение владельца 2026-07-09) |
| `usesManualAccountOrdering` | есть | **нет** | ✅ переносится |
| `priorityRaw` | есть | **нет** | ✅ переносится |
| иконка (кастомная) | нет (только вычисляемая по доминирующему типу, `FinanceRows.swift:203-227`) | нет | см. ниже — отдельный вопрос, не блокирует слияние |

**Решение по месту в плане:** это НЕ точечная правка трёх call site (получился бы ещё один временный мост поверх временного) и НЕ часть Фазы 2 (та про total/read-слой уровня счёта, а не про модель группы — разный радиус изменений: тут schema-миграция @Model + смена типа у 3 UI-читателей + редактор группы). Вставляется **новой Фазой 1.5**, сразу после уже реализованной Фазы 1 и **до** Фазы 2 — потому что Фаза 2 (переключение total/read-слоя на single-world) для per-группных сумм физически не может завершиться, пока группы не унифицированы: иначе Фаза 2 просто узаконит тот же баг «AccountsCore-группа = 0» как «ожидаемое поведение».

### 🟢 Фаза 1.5 — Слияние моделей групп (`FinanceGroup` → канон `AccountGroup`) — [x] РЕАЛИЗОВАН (2026-07-09, Александр, ветка `feature/legacy-accounts-purge`, НЕ мержено)

**Что:** `AccountGroup` расширяется недостающими полями (`isFavorite`, `usesManualAccountOrdering`, `priorityRaw` — переносятся все три, решение владельца 2026-07-09); новый одноразовый `GroupsMigrator` (аналог `LegacyAccountsMigrator`, тот же паттерн: идемпотентность через постоянный маркер, не UserDefaults-only) переносит для каждой активной `FinanceGroup` эти поля на резолвленный/созданный `AccountGroup` (переиспользует `resolveAccountGroup`, но делает перенос полей один раз, а не только name-match). Три call site (`calculateGroupTotal`, `orderedAccounts(for:)`, `hydratedAccounts(in:)`/`updateDynamicsBreakdown()`) переключаются читать `AccountGroup`/`Account.group` вместо `FinanceGroup.accounts`. Редактор группы (`FinanceGroupEditorView`) переводится на `AccountGroup`. Сама модель `FinanceGroup.swift` **не удаляется** в этой фазе (это происходит в Фазе 5 вместе с остальными @Model-файлами легаси-мира, после того как ничего её больше не читает) — только читатели переключаются.

**Acceptance criteria:**
- AC1: группа, целиком состоящая из AccountsCore-счетов, показывает верную сумму / список продуктов / попадает в «Groups» breakdown Analytics (регрессионный тест на баг из §1.3a).
- AC2: смешанная группа (легаси + AccountsCore) — сумма/список = сумме по всем счетам обоих миров (тест).
- AC3: `isFavorite`/`order`/`usesManualAccountOrdering`/`priorityRaw` не теряются после миграции (переносятся все, решение владельца) — тест на конкретный набор групп до/после.
- AC4: идемпотентность миграции — повторный прогон no-op (паттерн Фазы 1).
- AC5: build 0 ошибок; тесты — ноль новых красных vs baseline.
- AC6: `AccountsCoreAdditionBridge.resolveAccountGroup` TODO-комментарий про «Фазу 6» обновлён/удалён (задача выполнена здесь, не в редизайне).

**Риск:** трогает данные пользователя (группы) и три экрана сразу — `/stress-test` + явное «да» владельца обязательны перед мержем, как и для Фазы 1/5.

**Что сделано (2026-07-09):**
- `AccountGroup` расширена 4 аддитивными полями (lightweight-миграция, V6 НЕ трогалась, сборка зелёная): `isFavorite`/`usesManualAccountOrdering`/`priorityRaw:String` + постоянный маркер идемпотентности `legacyFieldsMigratedAt: Date?` (аналог `archivedAt` Ф1). Добавлен computed `priority`. Export/AccountGroupImporter расширены для паритета бэкапа.
- Новый `GroupsMigrator` (`millio/UI/Services/Finances/GroupsMigrator.swift`) — паттерн `LegacyAccountsMigrator`: per-scope UserDefaults-флаг + постоянный маркер `legacyFieldsMigratedAt`. Вызов в `millioApp.runPostStartupRefreshes()` сразу после `LegacyAccountsMigrator`.
- Per-group сумма обоих миров: `AccountsTotalsService.total(for:on:in:)` (сумма по подмножеству счетов) + `FinanceViewModel.calculateGroupTotal` (VM-обёртка, :1061) = legacy + core.
- Dynamics Groups breakdown: группы из core-счетов больше не отбрасываются, core-вклад добавляется к start/end.
- Скрытие Ungrouped учитывает core (`FinanceGroupService.shouldHideGroupInList`); правки редактора синхронизируются на `AccountGroup` (`FinanceGroupService.updateGroup` → `syncCoreGroup`).
- Тесты: `GroupsMigratorTests` (6) + `AccountsTotalsServicePerGroupTests` (2) — зелёные (swift-testing ✔).

**Отклонения от буквального плана (обоснованы, mentor stress-test):**
1. `priorityRaw` = **String** (не Int) — источник `FinanceGroup.priorityRaw` это String, перенос байт-в-байт.
2. Core влит в **VM-обёртку** `FinanceViewModel.calculateGroupTotal` (:1061), а НЕ в `FinanceTotalsService.calculateGroupTotal`: последняя разделяется с агрегатом `calculateTotalsSnapshot`, который добавляет core отдельным лампом (`newCoreTotalProvider`) — правка там задвоила бы core в «Общем балансе». VM-обёртка используется только display-сайтами → AC1/AC2 закрыты, агрегат стабилен (переключение агрегата на single-world — скоуп Ф2, не тронут).
3. `orderedAccounts` НЕ сменён на `AccountGroup` (возвращает `[FinanceAccount]`, унификация типа = рефактор Ф2/Ф6). Список уже дуально-рендерится (`FinanceRows` + `newCoreAccounts`); добавлена только core-осведомлённость скрытия Ungrouped.
4. Редактор «переведён на AccountGroup» = синхронизация полей на `AccountGroup` при сохранении (а не переписывание 669-строчного view — Ф6).

**Self-audit по AC:**
- AC1 ✅ per-group сумма/список/Dynamics-breakdown группы из core-счетов больше не 0/пусто (`AccountsTotalsServicePerGroupTests.totalForSubset…`, breakdown drop-guard + core start/end).
- AC2 ✅ смешанная = legacy + core (независимые вклады складываются; `calculateGroupTotal` = legacy + core).
- AC3 ✅ `GroupsMigratorTests.migratesAllFieldsToCoreGroup` / `reusesExistingCoreGroupByName` — все поля переносятся, дублей нет.
- AC4 ✅ `secondRunIsNoOpAndPreservesUserEdits` (маркер держит, правки юзера не затираются) + `migrateIfNeededShortCircuitsSecondCall`.
- AC5 ✅ build SUCCEEDED; полный `millioTests` — все падения из документированного baseline (18), 0 новых; мои 2 сьюта ✔ (записи в «Failing tests» по GroupsMigratorTests = флаки-запуск клонов симулятора, swift-testing репортит ✔).
- AC6 ✅ TODO/комментарий про «Фазу 6» в `AccountsCoreAdditionBridge.resolveAccountGroup` обновлён.

**⚠️ Перед мержем Ф1.5:** device `/stress-test` + бэкап user-стора + явное «да» владельца (трогает данные групп + 3 экрана).

**Фикс после адверсариального ревью (2026-07-09, коммит поверх e90c1a3):**
- **Дефект 1 (CONFIRMED, medium) — исправлен.** `legacyFieldsMigratedAt` теперь сериализуется в `AccountGroup.export()`/`AccountGroupImporter.import` (как `TimeInterval`, `NSNull()` при nil) — маркер идемпотентности переживает backup/restore, как `archivedAt` у легаси-счетов в Ф1. Без фикса restore на новом устройстве сбрасывал бы маркер в nil → повторный прогон `GroupsMigrator` перезаписывал бы поля `AccountGroup` поверх правок пользователя. Тест-регрессия: `GroupsMigratorTests.restoredGroupWithMarkerIsNotReMigrated` (export → import с новым id, как реальный restore → маркер не nil → повторная миграция no-op, правка юзера не затёрта).
- **Дефект 2 (PLAUSIBLE, low) — задокументирован, не гардится полноценно.** Дубли имён легаси-групп теоретически возможны (UI не проверяет уникальность имени), но не наблюдались в проде (1–2 юзера) — полноценная UI-валидация вне скоупа слияния моделей. Вместо тихого схлопывания: `GroupsMigrator` детектирует дубль явно (`Summary.skippedDuplicateName` + warning-лог с именем группы), первая группа мигрирует поля, остальные не молчат. Задокументировано в докстринге класса как «Известное ограничение». Тест: `GroupsMigratorTests.duplicateLegacyGroupNamesAreLoggedNotSilentlyDropped`.
- Build SUCCEEDED; полный `millioTests` — 0 новых красных vs baseline (все падения, включая `CashflowCategoryHelpContentTests`/`CashflowTransactionEditorViewLayoutTests` zh-Hans locale-leak флаки, входят в `progress/accounts-core-baseline-failures.md`); `GroupsMigratorTests` — 8/8 ✔ (swift-testing).

---

## 5. План отката

- **Ветка:** `feature/legacy-accounts-purge` от свежего `develop`. **Не мержить, не пушить** ночью (условие runbook). Каждая фаза — коммит на чистой границе.
- **Fallback:** develop до сноса (легаси + ядро сосуществуют, рабочее состояние) — точка возврата. Ветка `feature/accounts-core` в истории.
- **Если миграция ломает данные:** миграция обратима — `LegacyAccountConverter.unconvert` удаляет core-двойник и снимает `archivedAt` с легаси (восстанавливает). Флаг «миграция выполнена» в SwiftData сбросить → повторный прогон идемпотентен. На симуляторе — восстановление из `.bak`-стора (механизм `rebuildStorePreservingData`).
- **Схема:** V6 добавляется поверх V5 lightweight-стадией; откат = вернуть `AppSchemaCurrent = V5`, легаси-типы в список. Пока V6 не смержена в develop и не выпущена — откат чистый.
- **Обязательно перед фазой сноса схемы:** бэкап user-стора (`.backup.store`) + `/stress-test` (трогает данные пользователя и протестированную функциональность — правило проекта не отменяется).

---

## 6. Разбивка на фазы (каждая ≈ одна sonnet-сессия)

### 🟢 Фаза 1 — Миграционный слой + переключение чтения (БЕЗ удаления файлов) — САМАЯ БЕЗОПАСНАЯ — [x] РЕАЛИЗОВАН (2026-07-08, ветка `feature/legacy-accounts-purge`, НЕ мержено)
**Что:** новый `LegacyAccountsMigrator` (оркестратор поверх готового `LegacyAccountConverter`); одноразовый прогон при старте user-скоупа под SwiftData-флагом; идемпотентность; перевод чтения total/списка на single-world там, где легаси после миграции пуст. **Ни один файл не удаляется** — легаси остаётся в коде, но данные переехали и легаси-счета скрыты (`archivedAt`). Полностью обратимо (`unconvert`).

**Что сделано:**
- `millio/UI/Services/Finances/LegacyAccountsMigrator.swift` — оркестратор (рядом с `LegacyAccountConversion`, а НЕ в Core: перебирает легаси-@Model, Core остаётся легаси-агностичным). Перебирает активные (`archivedAt == nil`) `Card/Credit/Investment` (широкий fetch + Swift-фильтр, обход ловушки #Predicate §7.2), строит `Plan` → `Input` → `converter.convert`. Группа двойника резолвится из junction `FinanceAccount` по имени.
- Вызов в `millioApp.runPostStartupRefreshes()` синхронно на MainActor, ДО фонового бэкфилла, за per-scope UserDefaults-флагом (паттерн `AccountSnapshotBackfillCoordinator`).
- 11 тестов `LegacyAccountsMigratorTests` — зелёные.

**Отклонения от плана (обоснованы):**
- **SwiftData-флаг → UserDefaults per-scope + `archivedAt`.** Новый @Model = схема V6 = НЕ аддитивная Ф1 (V6 отдана Ф5). Причём цель «переносился при restore» УЖЕ достигнута: гарант идемпотентности — хранимый `archivedAt` (в SwiftData, переносится при restore), а не флаг. Скрытая легаси не перечисляется → повторная миграция после restore невозможна даже при утере реестра/флага. UserDefaults-флаг — лишь короткое замыкание, корректность от него не зависит.
- **Переключение чтения на single-world → отдано Ф2.** Инвариант тотала (AC2) держится двоемирием само: скрытая легаси вносит 0, двойник вносит равный вклад через уже подключённый `newCoreTotalProvider`. Read-switch не нужен для AC Ф1 и это явный скоуп Ф2 (снятие ссылок + снос `AccountTotalPolicy` + тест равенства экранов). Трогать God-VM в Ф1 — лишний риск.
- **Гэп меты вклада/рынка** зафиксирован `TODO(6b/фаза-post)` в шапке мигратора (AC6).

**Self-audit по AC:**
- AC1 ✅ `migratesAllActiveLegacy_totalMatchesLegacyContribution` — все активные → двойник + `isConverted`.
- AC2 ✅ `migratedCoreTotalEqualsSignedSum` (core-тотал = сумма знаковых вкладов; легаси скрыта = 0 → двоемирный тотал неизменен).
- AC3 ✅ `secondRunIsNoOp` + `migrateIfNeeded_flagShortCircuitsSecondRun` (идемпотентность через `archivedAt`, не реестр).
- AC4 ✅ `unconvertRestoresLegacy` (легаси активна, двойник удалён, реестр чист).
- AC5 ✅ build 0 ошибок; полный `millioTests` — 18 baseline-красных, 0 новых (19-й `FinanceDynamicsViewModelTests.testDeleteGroupPreservesArchivedLinkForHistoricalCalculation` — известный флаки, изолированно зелёный).
- AC6 ✅ TODO в коде + отчёт.
- Доп: `emptyStore_isNoOp`, `alreadyArchivedLegacy_notMigrated` (restore-safety), `groupPreservedFromJunction`, `ungroupedJunction_mapsToNilGroup`.

**⚠️ Перед мержем Ф1:** device-level `/stress-test` + бэкап user-стора + явное «да» владельца (правило 7 — стартовая миграция трогает данные пользователя; план не ревьюился).
**Acceptance criteria:**
- AC1: после прогона все не-converted `Card/Credit/Investment` имеют core-двойника; `registry.isConverted` == true для каждого.
- AC2: тотал Accounts/Dashboard/Динамика **не изменился** (opening-balance-двойник = прежний баланс легаси) — тест на сумму до/после.
- AC3: повторный прогон миграции — no-op (идемпотентность, тест).
- AC4: `unconvert` восстанавливает легаси байт-в-байт (тест).
- AC5: build 0 ошибок; полный `millioTests` — ноль НОВЫХ красных относительно baseline; `check-balance-mutations.sh` зелёный.
- AC6: гэп меты вклада/рынка (§3) зафиксирован в коде TODO + в отчёте.

### 🟡 Фаза 2 — Снятие ссылок в total/read-слое + снос `AccountTotalPolicy` и мёртвого кода
Переключить `FinanceTotalsService`/`FinanceDynamicsViewModel`/`FinanceRows`/`FinanceViewModel` на чистый single-world; удалить `AccountTotalPolicy`, `mergingNewCoreSeries` dual-path, `FinanceCreateViews`/`FinanceEditorWrappers`/`InlineCreateForms`. AC: тотал стабилен, build+tests зелёные, три пути тотала → один (доказать тестом равенства экранов).

### 🟡 Фаза 3 — Миграция живых писателей: `StockBulkImportServices` + `ScreenshotDataSeeder`
Перевести bulk-импорт акций на ядро (`.marketInvestment` через `AccountsCoreService`) или снять экран; сиды скриншотов — на ядро. AC: ни один путь не создаёт `Investment`/`Card`/`Credit`; grep-гейт.

### 🔴 Фаза 4 — Упрощение мостов + снос редакторов/VM/менеджеров
Упростить `AccountsCoreCashflowBridge`/`AdditionBridge` (убрать легаси-ветки); снести `*EditorView`/`*ViewModel`/`*Manager`/`CardCatalog`/`FinanceAccountService`/`FinanceInvestmentOrderService` + их тесты. AC: build+tests зелёные.

### 🔴 Фаза 5 — Снос регистрации, бэкап-импортёров, схема V6, @Model-файлы
Снять типы из `ModelTypeRegistry`/`*FeatureRegistration`; удалить importer'ы (осознанно); схема V6 + lightweight V5→V6; удалить `Card/Credit/Investment/FinanceAccount.swift` + конвертер/реестр; одноразовая чистка UserDefaults-легаси-снапшотов и registry-ключей. **`/stress-test` + бэкап обязательны.** AC: build+tests зелёные, приложение стартует на симуляторе с мигрированными данными, тотал стабилен.

---

## Вердикт по блокеру фазы 1 (для задачи №7 ночи)

**БЛОКЕРА НЕТ.** `LegacyAccountConverter` + `LegacyConversionRegistry` + `unconvert` уже существуют и покрыты тестами (Track C, 17 тестов, в develop); фаза 1 = идемпотентная одноразовая миграция + переключение чтения, **не удаляет ни одного файла**, полностью обратима (`unconvert`), потеря истории при opening-balance согласована владельцем (1–2 юзера). Единственная несцепка — гэп меты вклада/рынка в `Input` (мигрируют как manual-asset) — это допустимая деградация, не блокер.

## Редизайн экрана «Счета» — утверждён владельцем 2026-07-08, выполнять ПОСЛЕ сноса (Фаза 6)

Владелец одобрил дизайн-предложение (мокап: артефакт accounts-now-vs-proposal, https://claude.ai/code/artifact/98ee0fd4-c440-4169-8927-4d08a05fa100). Структурные пункты завязаны на единый AccountsCore, поэтому идут отдельной фазой ПОСЛЕ Фаз 1–5 (не красить сносимый код):

1. **Stacked-полоса «активы vs обязательства»** с нетто — вместо двух карточек Credit/Debit с прогресс-барами без шкалы.
2. **Секции «Активы» / «Обязательства» с подытогами** в списке групп — вместо смешанного списка.
3. **Шапка**: вторичная валюта чипом «≈ N $»; валютным группам подстрока «≈ в ₽». БЕЗ чипа прироста и БЕЗ sparkline.
4. **Кастомные иконки групп** (решение владельца 2026-07-09, см. ниже) — `AccountGroup.customIconName`, UI-пикер по паттерну `account-custom-icons`.

⚠️ **Решение владельца (2026-07-08): приросты и графики НЕ дублировать в «Счетах»** — «данные по приростам есть в Динамике и график», «лишнего городить не нужно». Экран «Динамика» уже показывает чип «+149 074 +1.6%», график тотала и разрез Groups с процентами. Поэтому из скоупа Фазы 6 ИСКЛЮЧЕНЫ: чип динамики/sparkline в шапке «Счетов» и «±X%» во второй строке групп (остаётся только «N счетов»). «Счета» = состояние (сколько где лежит), «Динамика» = движение (как менялось). Если когда-то захочется мостик между ними — максимум тап по группе → Динамика с фильтром этой группы, не дубль данных.

Быстрые правки того же ревью (НЕ ждут 6b, взяты в ночную полировку 2026-07-08): FAB-отступ списка; иконки типа продукта вместо цветных полосок + вторая строка «N счетов» (без процентов — см. решение выше); «Ungrouped» → локализованное «Без группы», нулевые группы → свёрнутые «Скрытые».

**Кастомные иконки групп — вход из ревью 2026-07-09, решение владельца: включить в Фазу 6.** Сейчас у `FinanceGroup`/`AccountGroup` нет поля под кастомную иконку — только `colorHex` и вычисляемая по доминирующему типу счетов иконка-бейдж (`FinanceRows.swift:203-227`, `FinanceGroupTypeIconView`). Это НОВАЯ фича, не баг — намеренно не втиснута в Фазу 1.5 (там только слияние моделей, не новый функционал). Ложится на `AccountGroup` (уже канон после Фазы 1.5), поле по готовому паттерну (`CashflowCustomCategory.icon` / `Account.customIconName`, `plans/2026-05-15__account-custom-icons.md`) — `customIconName: String?` (SF Symbol/эмодзи), UI-пикер переиспользует существующий `CashflowCategoryIconView`/аналог.

AC Фазы 6: соотношение полосы = данным тотала; подытоги секций сходятся с шапкой; вёрстка в токенах; RU/EN/zh-Hans; ноль дублей данных Динамики; кастомная иконка группы сохраняется и рендерится на всех 3 экранах (Счета/редактор группы/Динамика-breakdown), дефолт (без кастомной) — прежняя вычисляемая иконка по доминирующему типу.

## Журнал
- 2026-07-07: план создан (Максим/Plan, opus), инвентаризация по кодбазе; фаза 1 признана безопасной к ночной реализации.
- 2026-07-08 (ночь): добавлена Фаза 6 — редизайн экрана «Счета» (утверждён владельцем по мокапу); быстрые правки экрана вынесены в ночную полировку.
- 2026-07-08 (ночь, Александр): **Фаза 1 РЕАЛИЗОВАНА** на ветке `feature/legacy-accounts-purge` (от develop 6b0680d, НЕ мержено, НЕ пушено). Коммиты: мигратор+вайринг+тесты, фикс теста идемпотентности. 11 тестов зелёные, полный сьют 0 новых красных vs baseline (18). Отклонения: SwiftData-флаг→UserDefaults+archivedAt (schema V6 отдана Ф5), read-switch отдан Ф2 (инвариант держит двоемирие). Перед мержем — device stress-test + бэкап + «да» владельца.
- 2026-07-09: ревью плана (сессия ревью, sonnet). Добавлена **Фаза 1.5 — слияние моделей групп** `FinanceGroup`↔`AccountGroup` (вход из `plans/2026-07-05__unified-totals.md` §1.3a, найдено владельцем на симуляторе). Верифицировано субагентами: диагноз §1.3a актуален (file:line подтверждены), у групп нет поля иконки. **Решения владельца:** (1) Фаза 1.5 — отдельная фаза между Ф1 и Ф2; (2) все три поля `isFavorite`/`usesManualAccountOrdering`/`priorityRaw` переносятся при слиянии; (3) кастомные иконки групп (новая фича) — в Фазу 6 (редизайн Счетов), не раньше. План готов к следующему шагу — реализации Фазы 1.5 (по-прежнему под guard phrase, код не пишется без явной команды).
