# Аудит системы счетов, архивации, снапшотов и валют — 2026-07-02

**Статус:** АНАЛИЗ ГОТОВ, реализация не начата (guard phrase)
**Источник:** 3 параллельных расследования millio-audit + проверка незавершённого фикса 2026-06-24
**Симптомы пользователя:** ошибки при создании/ведении счетов; «потеря» данных при удалении; «No data to display» на Analytics 1W при живой дельте −136 481; расхождение тоталов Accounts 29 599 291 ₽ vs Analytics 29 599 294 ₽; «плывущая» историческая аналитика при изменении курсов; баннер «Quote backend auth error».

---

## 0. Состояние репозитория (само по себе проблема)

- Вся система дневных снапшотов (~1200 строк: `AccountDailySnapshot`, `DailySnapshotState`, `PortfolioDailySnapshot`, `DailySnapshotMigrator`, правки в 14 файлах) — **не закоммичена**, висит в рабочем дереве `develop` с 2026-06-21.
- Последний коммит `729eec5` — «revert bad archive migration»: с архивацией уже был инцидент.
- Готовый, но не применённый фикс: `specs/2026-06-24-dynamics-chart-empty-fix.md` + `plans/2026-06-24__dynamics-chart-empty-fix.md`. **Актуален**: баг на месте.

---

## 1. Архитектурный диагноз — 4 корневые причины

### R1. Три независимых пути вычисления «одного и того же числа»
| Экран | Источник | Курс |
|---|---|---|
| Accounts (тотал) | stored-поле `netWorthAmount` через `FinanceTotalsService.getAccountAmount` (FinanceTotalsService.swift:261-285) | live-курс `currencyService.getRate` (:148), учитывает custom-курсы |
| Analytics (Total + дельта) | replay всех транзакций `calculateBalanceAtDate` (FinanceDynamicsViewModel.swift:2163+) | исторический `historicalRateStore.getRate(on:)` (:2834-2844), custom-курсы НЕ учитывает |
| Analytics (график) | снапшоты `AccountDailySnapshot` через `buildAccountSnapshotSeries` (:1592-1655) | зафиксированный `fxRateToBase` на дату закрытия дня |

Отсюда: расхождение 3 ₽ (разные кэши курсов + фильтр «пыли» `> 0.01` только в Accounts-пути + раздельное округление в replay), и возможность «дельта есть / график пуст».

### R2. Архивация вместо удаления + несогласованный учёт archivedAt
- «Delete permanently» (`FinanceAccountService.swift:437-454`) фактически = архивация; физического удаления нет.
- Главный тотал `FinanceTotalsService.getAccountAmount` **не фильтрует** `archivedAt` → архивные счета продолжают влиять на суммы. Параллельная функция `isIncludedCurrentAccount` (FinanceViewModel.swift:1004-1016) фильтрует. Минимум 3 разные фильтрующие функции по кодбазе.
- `deleteGroup` (FinanceGroupService.swift:123-169) архивирует счета и складывает в Ungrouped, где они учитываются в тотале → **объяснение отрицательного Ungrouped −6 685 776 ₽** (архивные кредиты дают `-remainingAmount`).
- UI-кнопка «Удалить» с текстом «Это действие нельзя отменить» (`FinanceDeleteProductCopy.swift:19-27`) на деле вызывает `.removeAccountFromGroup` (FinanceDynamicsView.swift:2257) — мягкую обратимую архивацию; `restoreArchivedAccountToGroup` существует. «Необратимость» в тексте — ложная. `deleteAccountPermanently` из UI, судя по grep, вообще не вызывается (мёртвый код с вводящим в заблуждение именем).
- **Архивные счета продолжают ежедневно плодить снапшоты**: `DailySnapshotClosingService.closingAccountInputs` (:126-155) докидывает все исторические `accountID`, а во всём файле (504 строки) нет ни одной проверки `archivedAt` → невидимый рост БД + застывшие/дрейфующие по курсу балансы в агрегатах.
- Группа при создании счёта — `recommended`, не `required` (`FinanceAddAccountView.swift:1055-1097`): счёт без группы молча уходит в Ungrouped (`addAccountToGroup:374-375`) — второй механизм «денег из ниоткуда» в Ungrouped.
- `DataIntegrityCleaner.swift:23-86` хранит след прошлого инцидента (revert bad archive migration, авто-архивация нулевых инвестиций) — зона уже давала массовые регрессии.
- Архивация ретроактивно меняет форму ВСЕГО исторического графика: `buildAccountSnapshotSeries` суммирует снапшоты только по текущему множеству видимых счетов (:1605,1613), а не по составу на дату точки. Сырые снапшоты не удаляются никогда (нет ни одного `context.delete` над снапшотами; связь по строковому `accountID`, без `@Relationship`).

### R3. Хрупкая механика снапшотов
- **BUG строка 1714** (`existing <= date` вместо `>=`): `earliestClosedSnapshotDateByAccount` возвращает произвольную (порядок обхода Dictionary!) вместо самой ранней даты → `requiredSnapshotAccountIDs` ломается → `.gap` → пустой график. Нестабильно от сессии к сессии — «то есть, то нет».
- `baseCurrency` снапшота = **текущая displayCurrency** (`FinanceViewModel.swift:338`), а fetch фильтрует по точному совпадению → переключение ₽↔$ «прячет» всю историю (нет снапшотов под новой валютой) → `.gap` + fallback на replay.
- Снапшоты закрываются только «до вчера», триггер — фоновая задача при открытии экрана Finances; если приложение не открывалось — дыры, а `hasInternalDailyGap` превращает дыру в полностью пустой график.
- `DailySnapshotMigrator` мигрирует legacy-JSON с `fxRateToBase: 1` без реальной конвертации (DailySnapshotMigrator.swift:56-58) → искажённые исторические точки для мультивалютных счетов; one-shot флаг в UserDefaults (не переносится при restore).

### R4. «Плывущая» историческая аналитика — механизм найден
Не «текущий курс вместо исторического», а: fallback-путь replay читает `HistoricalRate` из SwiftData, который **перезаписывается** (`upsertRate`, HistoricalRateStore.swift:150-177) при получении более точного курса (`.previous`→`.exact`, иногда другой провайдер) → одна и та же историческая сумма меняется между открытиями экрана. Плюс C4: custom-курсы влияют на «сейчас», но не на прошлые даты — ещё одна асимметрия.

### Прочее
- «Quote backend auth error» — НЕ курсы валют: 401/403 от millio-back (прокси TwelveData) для котировок акций (`MarketDataErrorPresentation.swift:33-46`, `TwelveDataClient.swift:843-859`) — истёкшая auth-сессия. Курсы валют работают. Риск: при 401 `liveConvertedBalance` инвест-счёта может вернуть `nil` → счёт выпадает из тотала Dynamics (ещё один источник расхождений).
- Дубли `FinanceAccount`-связей допускаются и чистятся реактивно при каждой загрузке (`FinanceAccountService.swift:259-273`), а не предотвращаются.

---

## 2. Предложение: доработать, не переписывать

Данные пользователя целы (снапшоты и транзакции физически не удаляются) — «бардак» это рассинхрон точек вычисления, а не потеря. Переписывание с нуля не нужно; нужна консолидация. Фазы:

**Фаза 1 — готовый фикс графика (S, спека готова).** Применить `plans/2026-06-24__dynamics-chart-empty-fix.md`: строка 1714 + requiredSnapshotAccountIDs + логирование .gap/.insufficient. Тесты по AC1–AC6 спеки.

**Фаза 2 — гигиена репо (S).** Закоммитить снапшот-систему на feature-бранч (сейчас 29 файлов незакоммичено = риск потери и невозможность bisect).

**Фаза 3 — единая точка истины по archivedAt/includeInTotal (M).** Один предикат «участвует ли счёт в тотале» (уровень FinanceBalanceScope — контракт уже начат, коммит a42c8c1), использовать во всех 3+ местах. Решение продукта: должны ли архивные учитываться в тотале (сейчас — да в Accounts, нет в Dashboard). Починит Ungrouped-аномалию.

**Фаза 4 — фиксированная baseCurrency снапшотов (M).** Писать снапшоты в `primaryCurrencyCode` (не displayCurrency); конвертацию в отображаемую валюту делать на чтении. Миграция существующих снапшотов. Убирает «пропажу истории» при переключении ₽↔$.

**Фаза 5 — единый путь тоталов (M/L).** Accounts и Analytics Total считают через один сервис и один кэш курсов; фильтр «пыли» и округление — общие. Убирает расхождение 3 ₽.

**Фаза 6 — стабилизация исторических курсов (M).** `upsertRate` не перезаписывает курс, уже использованный в закрытых снапшотах/отчётах, либо версионирование; custom-курс — решить, распространяется ли на историю. Убирает «плывущую» аналитику.

**Фаза 7 — семантика удаления и архива (M, продуктовое решение).** Либо честное физическое удаление (счёт + транзакции + снапшоты, с подтверждением), либо переименовать в «Архивировать» в UI и убрать ложное «нельзя отменить». Остановить генерацию снапшотов для архивных счетов (фильтр archivedAt в DailySnapshotClosingService). Сделать выбор группы обязательным или показать Ungrouped явно. Чистка осиротевших снапшотов в DataIntegrityCleaner.

Отдельно (не фаза): разобраться с auth-сессией к millio-back (баннер котировок) — возможно просто протухший токен на девайсе.

**Порядок:** 1→2 сразу (мелкие, разблокируют график); 3–7 — по Bulletproof с /stress-test, т.к. трогают протестированную функциональность и данные пользователя.

---

## 3. Ссылки на отчёты агентов
Полные диагнозы (P1–P5, S1–S5, C1–C4) — в тексте этого файла выше; ключевые файлы: FinanceAccountService.swift, FinanceGroupService.swift, FinanceTotalsService.swift, FinanceViewModel.swift, FinanceDynamicsViewModel.swift, AccountDailySnapshotReader.swift, DailySnapshotClosingService.swift, DailySnapshotMigrator.swift, HistoricalRateStore.swift, CurrencyRateService.swift, MarketDataErrorPresentation.swift, TwelveDataClient.swift.
