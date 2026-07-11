# Handoff 2026-07-11 (утро): итоги ночи 2 по 6b + следующий шаг — реплатформинг Finances

## Состояние репо
- Всё на **`develop` @ `aea084a`** (+1 незакоммиченный файл `improvements/process/2026-07-11-swiftdata-test-harness-container-retention.md`). **74 коммита впереди origin, НЕ запушено, НЕ задеплоено.** Отдельной фиче-ветки нет — `feature/legacy-accounts-purge` смержена ещё 2026-07-10 (`d4b0858`).
- Финальный гейт ночи: полный `millioTests` **1745 passed / 14 failed = 100% baseline, 0 новых** (только `xcrun xcresulttool`, подтверждено дважды — рабочими фазами и независимым QA-прогоном Дениса).
- Release-билд проверен визуально на симуляторе iPhone 17 Pro Max iOS 26.5 (скриншоты: `<scratchpad>/qa-2026-07-11/screenshots/`).

## Сделано ночью (коммиты на develop)
| Что | Коммиты |
|---|---|
| 5c.1 порт `PortfolioHeldSymbolsProvider` → core (попутно закрыт латентный баг held-symbols-sync) | `dbffcd3` |
| 5c.1a порт `SheetsDataMapper`/`SheetsConnectionView` → core | `394b212`+`cc5c658` |
| Багфикс «Assets at start of period = 0» на Cashflow (не было `legacyPredecessorContribution`, теперь общий путь с Dynamics через `coreContributionWithLegacyPredecessor`) | `86e9918` |
| 5c.2 `InlineCreateForms` DTO (`InlineCardDraft` вместо @Model `Card`) | `77eeb86`+`75d7d4a` |
| 5c.3 вариант A: снос **runtime-мёртвого** легаси-EDIT-пути (−382 строки) | `fca2d5e`, `1b4e60f`+`2a138bf` |
| 5c.4 Cashback-порт Card→Account (переиспользован `CashflowSelectableAccount`; закрыт баг пустого пикера у мигрированного юзера) | `2094126`+`1c8a94d` |
| 5c.5 finding-only: `CardCatalog`/`CardManager` живы → 5c.6-кластер | `7a8689b` |
| Декаплинг CREATE-формы от 3 легаси-VM (префилл был мёртвый, −187 строк) | `80c55d3` |
| 5c.6 finding-only: снос @Model ЗАБЛОКИРОВАН (см. ниже) | `676e5c5` |
| Ф2c finding-only: ЗАБЛОКИРОВАНА, слита с 5c.7 | `aea084a` |

## 🔴 Ключевая находка ночи — порядок фаз инвертирован
Ф5c.6 (снос @Model + схема V6) **корректно заблокирована**: Finances-слой до сих пор **первично** живёт на легаси-@Model — `FinanceViewModel` (65 ссылок, `state.groups:[FinanceGroup]`, `availableCards:[Card]`), `FinanceDynamicsViewModel` (56, `FetchDescriptor<Card/Credit/Investment>`), `FinanceAccountService` (45), `FinanceGroupService` (20) + reconciliation/reset (`ScopeMerge*`, `DataIntegrityCleaner`, `DataResetService` — их легаси-ветки нельзя удалять до сноса моделей). Классификация всех 136 файлов пред-гейт-грепа — в плане, секция «⛔ Блокер Ф5c.6».

**Следующий шаг (это и есть задача нового чата): Ф5c.7 — L-реплатформинг Finances на AccountsCore** (~2-3 сессии), слит с Ф6. Порядок из плана: 5c.7 (Finances + `AccountsCoreService.updateAccount`) → 5c.8 (Cashflow-резолв) → 5c.9 (MarketData) → 5c.10 (`ScreenshotDataSeeder`) → 5c.11 (собственно снос @Model + V6 + version-gate + миграторы + легаси-ветки reconciliation симультанно).

**Дополнительно по требованию владельца (2026-07-11 утро) — в скоуп нового чата:**
1. **Security-review на Fable** — полный проход по ночному диффу `a255f9b..aea084a` + затрагиваемым при реплатформинге поверхностям (данные пользователя в SwiftData, backup/restore-цепочка CloudKit, миграторы/ремапы, version-gate, Sheets-экспорт как исходящая поверхность) — через `/security-review` или Fable-агента в главном окне; findings с severity, фиксы доказанных проблем — субагентами.
2. **User usability улучшения** — проход по тронутым за две ночи экранам глазами пользователя (Счета/Cashflow/Динамика/Cashback/добавление счёта): вернуть потерянную полезную детализацию пикера Cashback (банк/тип/баланс — упрощение было санкционировано ночью, но UX обеднел), donut Analytics→Accounts (баг выше), дубль Ungrouped, «Скрытые»/пустые состояния, консистентность free/pro сортировки. Приоритизировать по видимости для реального юзера, не чинить всё подряд.

## ⚠️ Открытые вопросы владельцу (не решены)
1. **Rich-редактирование счёта (rename/валюта/группа/мета) недоступно юзеру вообще** — в ядре нет `updateAccount`-API, легаси-путь был мёртв. Пробел существует с Ф1, не регрессия ночи. Решение (автономное, вариант A): строить в 5c.7/Ф6. Нужно подтверждение.
2. **Push develop (74 коммита)** — по команде.
3. Ручная device-проверка Cashback-порта и отсутствия шестерёнки в Динамике (см. ревью ниже).

## Находки финального ревью (Fable, критичных нет)
- `limitedFreeCards` (free-лимит кэшбэка) отсортирован по `updatedAt` вместо `createdAt` (у `CashflowSelectableAccount` нет даты создания) — правка старой карты может сдвинуть границу free/pro. Не покрыто тестом.
- Кнопка-шестерёнка редактирования исчезла с экрана Динамики (вместе с мёртвым EDIT-путём) — проверить на устройстве, что не ожидалась.
- Докстринг `SheetsDataMapper.marketPosition()` неточен: не «точная реплика» — отличается в edge-case овер-продажи (влияет только на Sheets-экспорт).

## Известные баги вне скоупа ночи (диагностированы, не чинились)
- **Пустой donut на Analytics→Accounts** (легенда есть, чарт нет; Groups работает). НЕ ночная регрессия — старый баг, был скрыт до фиксов `350a190`/`fbf4029`. Гипотеза: `SectorMark` не рендерит при 9+ per-account слайсах (Groups агрегирует до ≤6). Не quick-fix: нужен repro с бинарным сокращением items в `DistributionChartView.swift:106-116`. Adversarial-хвост: проверить дедуп legacy+core id в `rows` (`FinanceDynamicsViewModel.swift:1417-1422`).
- Дубль «Ungrouped» на экране «Счета» (давний, в 5c.7/Ф6).
- Кластер `Card.balance` scheduled-тестов (6 красных в baseline).

## Регламент (как в прошлые ночи)
- Реализация/диагностика/верификация — субагенты (Александр=opus, research=дефолт, QA=Денис); главное окно — оркестрация. Ponytail.
- Тесты — ТОЛЬКО `xcrun xcresulttool`; параллельные xcodebuild — изолировать `-derivedDataPath` и удалять их после сессии.
- SwiftData-тест-харнесс держит `ModelContainer` живым (новое правило: `improvements/process/2026-07-11-swiftdata-test-harness-container-retention.md`).
- НЕ мержить, НЕ пушить, НЕ деплоить без явного «да».

## Артефакты
- План + журнал + классификация: `plans/2026-07-07__legacy-accounts-purge-path-b.md` (+ `.status.json`)
- Research Ф6 (implementation-ready, 10 шагов: stacked-полоса, секции, иконки групп `customIconName`, найдены паттерны `AccountIconPickerSheet`/`FinanceOverviewLedgerPresentation`) — в журнале сессии 2026-07-10→11; ключевое: `AccountGroup` поля добавляются additive без V6-бампа; не найдены — AccountsCore group-edit sheet и Dynamics icon render site (грепнуть перед шагами 6-7).
- QA-скриншоты: `/private/tmp/claude-501/-Users-alekseya---------3-millio-local/35f1d9de-301c-436f-9f86-89bd0523c957/scratchpad/qa-2026-07-11/`
- Память обновлена: `millio-6b-path-decision`
