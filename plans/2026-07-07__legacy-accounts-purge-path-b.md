# План 6b Путь B — миграция легаси-счетов в AccountsCore + снос легаси-миров

**Дата создания:** 2026-07-07 · **Статус:** НЕ НАЧАТ (план готов, не ревьюился) · **Тип:** L, Bulletproof
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

⚠️ `FinanceGroup.swift` — **НЕ сносить**: новое ядро зеркалит группы по имени (`AccountGroup`), но UI-группировка и `FinanceGroupService` завязаны на `FinanceGroup`. Оценить отдельно (кандидат на консолидацию с `AccountGroup`, но за скоупом первого прохода).

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

---

## 5. План отката

- **Ветка:** `feature/legacy-accounts-purge` от свежего `develop`. **Не мержить, не пушить** ночью (условие runbook). Каждая фаза — коммит на чистой границе.
- **Fallback:** develop до сноса (легаси + ядро сосуществуют, рабочее состояние) — точка возврата. Ветка `feature/accounts-core` в истории.
- **Если миграция ломает данные:** миграция обратима — `LegacyAccountConverter.unconvert` удаляет core-двойник и снимает `archivedAt` с легаси (восстанавливает). Флаг «миграция выполнена» в SwiftData сбросить → повторный прогон идемпотентен. На симуляторе — восстановление из `.bak`-стора (механизм `rebuildStorePreservingData`).
- **Схема:** V6 добавляется поверх V5 lightweight-стадией; откат = вернуть `AppSchemaCurrent = V5`, легаси-типы в список. Пока V6 не смержена в develop и не выпущена — откат чистый.
- **Обязательно перед фазой сноса схемы:** бэкап user-стора (`.backup.store`) + `/stress-test` (трогает данные пользователя и протестированную функциональность — правило проекта не отменяется).

---

## 6. Разбивка на фазы (каждая ≈ одна sonnet-сессия)

### 🟢 Фаза 1 — Миграционный слой + переключение чтения (БЕЗ удаления файлов) — САМАЯ БЕЗОПАСНАЯ
**Что:** новый `LegacyAccountsMigrator` (оркестратор поверх готового `LegacyAccountConverter`); одноразовый прогон при старте user-скоупа под SwiftData-флагом; идемпотентность; перевод чтения total/списка на single-world там, где легаси после миграции пуст. **Ни один файл не удаляется** — легаси остаётся в коде, но данные переехали и легаси-счета скрыты (`archivedAt`). Полностью обратимо (`unconvert`).
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

⚠️ **Решение владельца (2026-07-08): приросты и графики НЕ дублировать в «Счетах»** — «данные по приростам есть в Динамике и график», «лишнего городить не нужно». Экран «Динамика» уже показывает чип «+149 074 +1.6%», график тотала и разрез Groups с процентами. Поэтому из скоупа Фазы 6 ИСКЛЮЧЕНЫ: чип динамики/sparkline в шапке «Счетов» и «±X%» во второй строке групп (остаётся только «N счетов»). «Счета» = состояние (сколько где лежит), «Динамика» = движение (как менялось). Если когда-то захочется мостик между ними — максимум тап по группе → Динамика с фильтром этой группы, не дубль данных.

Быстрые правки того же ревью (НЕ ждут 6b, взяты в ночную полировку 2026-07-08): FAB-отступ списка; иконки типа продукта вместо цветных полосок + вторая строка «N счетов» (без процентов — см. решение выше); «Ungrouped» → локализованное «Без группы», нулевые группы → свёрнутые «Скрытые».

AC Фазы 6: соотношение полосы = данным тотала; подытоги секций сходятся с шапкой; вёрстка в токенах; RU/EN/zh-Hans; ноль дублей данных Динамики.

## Журнал
- 2026-07-07: план создан (Максим/Plan, opus), инвентаризация по кодбазе; фаза 1 признана безопасной к ночной реализации.
- 2026-07-08 (ночь): добавлена Фаза 6 — редизайн экрана «Счета» (утверждён владельцем по мокапу); быстрые правки экрана вынесены в ночную полировку.
