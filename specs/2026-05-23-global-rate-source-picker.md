# Spec: Глобальный выбор источника курсов валют

**Slug:** `global-rate-source-picker`  
**Дата:** 2026-05-23  
**Статус:** НЕ НАЧАТ  
**Размер:** L (16 файлов, включая CBR-провайдер, capability model, dashboard invalidation и тесты)  
**План:** `plans/2026-05-23__global-rate-source-picker.md` *(создать перед реализацией)*

---

## Проблема

Пользователь не может влиять на то, какой источник курсов использует приложение для конвертации финансов, аналитики, баланса в иностранной валюте. `CurrencyRateService.shared` создаётся с `.millio`, но `refreshRates()` **игнорирует `rateSource`** и всегда идёт по фиксированной цепочке `.millio → .erapi → .frankfurter` (строка 196). Поэтому даже существующий выбор источника в конвертере (`conv_rate_source`) влияет только на его собственную загрузку — не на аналитику и баланс.

Конвертер сейчас является единственным владельцем виджет-синка: он пишет `CurrencyWidgetShared.Keys.rateSource` при каждой смене источника. Нет глобального ключа, нет глобального контракта.

---

## Архитектурный контракт (зафиксировать до реализации)

> **Обновить `docs/CURRENCY_POLICY.md`** — текущая секция «Converter Scope» (строки 24–31) описывает конвертер как полностью независимый. Этот контракт меняется.

### Источник истины: `preferred_rate_source`

- Один UserDefaults-ключ `preferred_rate_source` — глобальный выбор пользователя.
- `CurrencyRateService.shared` инициализируется из `preferred_rate_source` (дефолт — `.millio`).
- `refreshRates()` строит цепочку динамически: **`[preferred, ...остальные по стандартному порядку]`** без дубликатов. Пример: выбран `.frankfurter` → цепочка `[frankfurter, millio, erapi]`.
- Виджет синкается с `preferred_rate_source` (не с `conv_rate_source`).

### Конвертер: `useAppDefault` + опциональный `conv_rate_source`

- По умолчанию конвертер следует `preferred_rate_source` (`useAppDefault`).
- Пользователь может выбрать другой источник **внутри конвертера** — тогда записывается `conv_rate_source`. Этот override действует только для конвертера.
- UI конвертера обязан явно показывать активное состояние: `"По умолчанию (erapi)"` или `"Свой: Frankfurter"`. Скрытый override — запрещён.
- При смене глобального источника через `RateSourcePickerView`: если конвертер в `useAppDefault`, он автоматически переключается. Если конвертер имеет override — не затрагивается.
- Виджет всегда следует `preferred_rate_source`, не `conv_rate_source`.

### Историческая политика — без изменений

Историческая цепочка (`Frankfurter → CBR`) не зависит от `preferred_rate_source` и меняться не будет.

---

## WHAT — что делаем

### 0. `RateSource` — добавить `.cbr` и `capability`

В `millio/Core/Currency/RateSource.swift`:

- Добавить кейс `.cbr` с URL `https://cbr.ru/scripts/XML_daily.asp`.
- Добавить `var capability: RateSourceCapability` (см. capability-таблицу выше).
- `RateSource.allCases` теперь включает `.cbr`.
- Парсинг ответа CBR (XML) — отдельный `CBRLatestRateProvider` в `HistoricalRateProviders.swift` или рядом. `CBRHistoricalRateProvider` уже умеет парсить этот XML — переиспользовать логику.

### 1. `RateSourcePreferenceStore` — новый слой (1 файл)

Путь: `millio/Core/Currency/RateSourcePreferenceStore.swift`

```swift
struct RateSourcePreferenceStore {
    let defaults: UserDefaults

    static let shared = RateSourcePreferenceStore(defaults: .standard)

    var preferred: RateSource     // get + set (UserDefaults "preferred_rate_source", default .millio)
    var converterOverride: RateSource?  // get + set (UserDefaults "conv_rate_source", nil = useAppDefault)
    func reset()                   // используется DataResetService; удаляет оба ключа
}
```

- **DI через `defaults: UserDefaults`**: тесты создают `RateSourcePreferenceStore(defaults: UserDefaults(suiteName: "test")!)` без засорения `.standard`. Продовый код использует `.shared`.
- Нет бизнес-логики. Только get/set/reset.
- `CurrencyRateService` и `RateSourcePickerViewModel` принимают `store: RateSourcePreferenceStore = .shared`.
- Устаревший прямой доступ к `"conv_rate_source"` в `ConverterViewModel` мигрирует сюда.

### 2. `CurrencyRateService` — два изменения

**2a. `shared` инициализируется из `RateSourcePreferenceStore.shared.preferred`:**
```swift
static let shared = CurrencyRateService(
    rateSource: RateSourcePreferenceStore.shared.preferred,
    rateRepository: RateRepository.shared
)
```

**2b. `refreshRates()` строит динамическую цепочку:**
```swift
private func buildFallbackChain() -> [RateSource] {
    var chain = [rateSource]
    chain += RateSource.allCases.filter { $0 != rateSource }
    return chain
}
```
Вызывается в `refreshRates()` вместо хардкода `[.millio, .erapi, .frankfurter]`.

**2c. `setRateSource(_ source: RateSource)` — новый метод:**
- Обновляет `self.rateSource`.
- Сохраняет в `self.store.preferred`.
- **Инкрементирует generation-токен** (`private var cacheGeneration: Int`). `refreshRates` захватывает токен при старте и пишет в `cachedRates` только если токен не изменился — иначе результат in-flight refresh старого источника молча дропается. Это предотвращает гонку: старый task продолжает работу, но не перезапишет кэш нового источника.
- Обнуляет `refreshTask = nil`, чтобы следующий `getRate()` не ждал старый запрос.
- Сбрасывает `cachedRates` (кроме `["USD": 1.0]`) и `lastUpdateTS = 0` → следующий `getRate()` загрузит заново.
- НЕ вызывает `forceRefreshRates()` сам — это делает caller (`RateSourcePickerViewModel`).

### 3. `CurrencyWidgetSyncService` — два изменения

**3a.** `knownRateSources` заменить на автоматический список из `RateSource.allCases`:
```swift
private static let knownRateSources = RateSource.allCases.map(\.rawValue)
// → ["millio", "erapi", "frankfurter", "cbr"] — обновляется автоматически при добавлении нового кейса
```

**3b.** `bootstrapFromStandardDefaults` должен копировать `preferred_rate_source` в шаред-дефолты:
```swift
set(defaults.object(forKey: "preferred_rate_source"), forKey: CurrencyWidgetShared.Keys.rateSource, in: sharedDefaults)
```
Виджет читает `CurrencyWidgetShared.Keys.rateSource` — теперь он будет получать глобальный источник, а не конвертер-специфичный.

### 4. `ConverterViewModel` — рефакторинг источника

- Убрать прямой `defaults.string(forKey: "conv_rate_source")` — читать через `RateSourcePreferenceStore.converterOverride`.
- При `storedRateSource` = nil → `state.rateSource = RateSourcePreferenceStore.preferred` (useAppDefault).
- При `.setRateSource(source)`: если `source == RateSourcePreferenceStore.preferred` → записывать `converterOverride = nil` (useAppDefault), иначе `converterOverride = source`.
- Конвертер перестаёт писать `CurrencyWidgetShared.Keys.rateSource` при каждой смене. Виджет-синк источника переходит к `RateSourcePickerViewModel`.
- UI-label для кнопки источника: `"По умолчанию (\(preferred.title))"` или `source.title`.

### 5. `RateSourcePickerView` + `RateSourcePickerViewModel` — новые файлы

**`visibleSources(context:)`** — единый фильтр для всех пикеров:

```swift
enum RateSourceContext { case profile, converter }

func visibleSources(context: RateSourceContext, profile: UserProfile) -> [RateSource] {
    let rubInProfile = profile.primaryCurrencyCode == "RUB"
        || profile.favoriteCurrencyCodes.contains("RUB")
    return RateSource.allCases.filter { source in
        if source == .cbr { return rubInProfile }
        return true
    }
}
```

Этот метод используется и в `RateSourcePickerViewModel` (Profile), и в `ConverterViewModel` (inline picker). `ConverterView` не перебирает `RateSource.allCases` напрямую — только через `visibleSources(context: .converter, profile:)`. Таким образом CBR появится в конвертере только при наличии RUB в профиле.

**`RateSourcePickerViewModel`:**
- `@Published var previews: [RateSource: RatePreview]` — курсы 4–5 избранных валют к `SettingsManager.shared.primaryCurrencyCode`.
- `@Published var loadingStates: [RateSource: LoadState]` — per-source `.loading` / `.loaded` / `.failed(String)`.
- `@Published var selectedSource: RateSource` — инициализируется из `store.preferred` в `init`.
- `func loadPreviews()` — загружает все `visibleSources` **параллельно** (`async let` / `withTaskGroup`). Каждый источник загружается независимо: ошибка одного не блокирует остальные. Количество источников не фиксировано — итерация по `visibleSources`, не хардкод `× 3`.
- `func selectSource(_ source: RateSource)`:
  1. `selectedSource = source`
  2. `CurrencyRateService.shared.setRateSource(source)` → сохраняет в `store.preferred`, сбрасывает кэш, инкрементирует generation
  3. `CurrencyWidgetSyncService.setString(source.rawValue, forKey: CurrencyWidgetShared.Keys.rateSource)`
  4. `await CurrencyRateService.shared.forceRefreshRates()`
  5. Запись в виджет-кэш актуальных курсов: `CurrencyWidgetSyncService.setRates(...)`

> `store.preferred` НЕ пишется отдельно — `setRateSource` уже делает это. Единственный владелец записи — `CurrencyRateService.setRateSource`.

**Preview-структура:**
```swift
struct RatePreview {
    let rates: [(code: String, rate: Double)]  // избранные валюты → primaryCurrencyCode
    let updatedAt: Date?                        // updatedAt из snapshot (не fetchedAt устройства)
    let isStale: Bool                           // updatedAt > 24h
}
```

**Правила отображения ошибок / stale:**
- Источник загружается — показываем shimmer-скелетон.
- Загрузка упала — показываем карточку с меткой `"Недоступен"` и последней известной датой. Выбрать такой источник **можно** — пользователь сам решает.
- `isStale = true` → показываем оранжевую метку `"Данные устарели (>24ч)"`.
- Если источник не поддерживает валюту → показываем `"—"` для этой пары (не скрываем строку).

**`RateSourcePickerView`:**
- Открывается из Profile → раздел «Настройки» → «Источник курсов».
- Для каждого источника — карточка: название, описание, мини-таблица курсов, время обновления, radio-чекмарк.
- Смена источника — немедленно, без кнопки «Сохранить».
- Валюты в превью — `SettingsManager.shared.favoriteCurrencyCodes` (до 5) + `primaryCurrencyCode` как base. Строго: не session-only display currency.

### 6. Profile — навигация

- `ProfileMenuStructure.swift` → добавить пункт «Источник курсов» с subtitle = текущий `RateSourcePreferenceStore.preferred.title`.
- `ProfileView.swift` → `NavigationLink` к `RateSourcePickerView`.

### 7. `DataResetService` — cleanup

- При полном сбросе данных добавить: `RateSourcePreferenceStore.reset()`.

### 8. Dashboard invalidation — механизм пересчёта

`forceRefreshRates()` обновляет кэш, но не заставляет существующие ViewModel пересчитать суммы. Нужен явный сигнал.

**Механизм:**
- `CurrencyRateService` публикует `Notification.Name.currencyRateSourceDidChange` через `NotificationCenter.default.post` в конце `setRateSource`.
- **Подписчики** (конкретный список):
  - `FinanceViewModel` — пересчитывает баланс и аналитику в текущей валюте.
  - `CashflowViewModel` — пересчитывает суммы транзакций в `primaryCurrencyCode`.
  - `DashboardViewModel` (если есть) — обновляет виджеты баланса/аналитики.
- Подписчики подписываются в `.onAppear`/`init`, отписываются в `deinit`/`.onDisappear`.
- Порядок: сначала `setRateSource` (кэш сброшен) → потом уведомление → подписчики вызывают `getRate()`/`convert()` → получают новые курсы.

> Если `FinanceViewModel` или `DashboardViewModel` ещё не существует в момент смены источника — пересчёт произойдёт при следующем `.onAppear` (обычный init-flow).

---

## Source Capability Model

Каждый источник описывается набором свойств `RateSourceCapability`. Модель живёт в `RateSource.swift` как computed property `var capability: RateSourceCapability`.

```swift
struct RateSourceCapability {
    /// Семантика охвата данных
    enum Scope {
        case globalFiatDaily      // широкий фиат-охват, ежедневное обновление
        case rubOfficialDaily     // официальный курс ЦБ РФ, только RUB-пары
        case rubMarketDelayed     // рыночный курс (MOEX), с задержкой 15 мин
        case intradayPair         // intraday-котировки по конкретным парам
    }

    enum BaseCurrency {
        case usd       // все курсы через USD
        case eur       // все курсы через EUR
        case rub       // все курсы через RUB
        case pairOnly  // источник не даёт матрицу, только конкретные пары
    }

    enum Freshness: String {
        case daily     // обновляется раз в день (обычно рабочий день)
        case hourly    // обновляется каждый час
        case delayed   // рыночные данные с задержкой (~15 мин)
        case realtime  // потоковые котировки
    }

    enum LegalLabel: String {
        case official    // регуляторный курс (ЦБ РФ, ECB)
        case reference   // справочный курс (ECB-aligned агрегатор)
        case market      // биржевой/рыночный курс
        case aggregator  // агрегированный из нескольких источников
    }

    let scope: Scope
    let baseCurrency: BaseCurrency
    let requiresAPIKey: Bool
    let supportsMatrixFetch: Bool   // может вернуть все курсы одним запросом
    let supportsHistorical: Bool    // поддерживает исторические даты
    let freshnessLabel: Freshness
    let legalLabel: LegalLabel
}
```

### Capability-таблица текущих источников

| Источник | scope | base | apiKey | matrix | historical | freshness | legal |
|----------|-------|------|--------|--------|------------|-----------|-------|
| `.millio` | globalFiatDaily | USD | false | true | false | daily | aggregator |
| `.erapi` | globalFiatDaily | USD | false | true | false | daily | reference |
| `.frankfurter` | globalFiatDaily | EUR | false | true | true | daily | reference |
| `.cbr` | rubOfficialDaily | RUB | false | true | true | daily | official |

### Правила пикера на основе capability

1. **Условная видимость CBR**: источник `.cbr` показывается в пикере только если `primaryCurrencyCode == "RUB"` или хотя бы одна из `favoriteCurrencyCodes` включает `"RUB"`. Проверяется в `RateSourcePickerViewModel.visibleSources`.

2. **Неравнозначность источников**: карточка каждого источника показывает `legalLabel` как badge (`"Официальный"`, `"Справочный"`, `"Агрегатор"`). Источники не отображаются как однородный список без контекста.

3. **Дисклеймер для CBR**: под карточкой — фиксированный текст `"Официальный курс ЦБ РФ, не курс покупки/продажи банков"`. Локализуется только для RU/EN; zh-Hans — EN-текст как fallback.

4. **Частичная поддержка валют** (`supportsMatrixFetch = false`): зарезервировано для будущих источников типа `intradayPair`. Пикер показывает предупреждение `"Только для выбранных пар"` вместо таблицы курсов.

### Fallback с учётом capability

Если выбранный источник — `.cbr`, а запрашиваемая пара не включает RUB (например, `EUR → CNY`):

- `CurrencyRateService` детектирует ситуацию через `rateSource.capability.scope == .rubOfficialDaily && !pairInvolvesRUB`.
- Для такой пары используется **глобальный fallback**: первый источник из цепочки с `scope == .globalFiatDaily`.
- В логах: `"CBR: pair EUR→CNY not RUB-involved, routing to globalFiat fallback"`.
- В `getRate()` это прозрачно для caller — он получает курс, не ошибку.

---

## Инварианты кэша и нормализации

`CurrencyRateService` хранит `cachedRates: [String: Double]` в единой семантике:

```
// Инвариант: cachedRates[CODE] = количество единиц CODE за 1 USD
// Т.е.: USD=1.0, RUB=85.0 → 1 USD = 85 RUB
// getRate(from:to:) = cachedRates[to] / cachedRates[from]
```

**Все источники обязаны приводить данные к этому инварианту перед записью в `cachedRates`.**

### Нормализация CBR

CBR XML возвращает `RUB за N единиц валюты` (поле `Value`, поле `Nominal`). Нормализация в USD-base snapshot:

```swift
// Шаг 1: Получаем USD→RUB из CBR (или через erapi как fallback)
//   rubPerUSD = cbr.rates["USD"].value / cbr.rates["USD"].nominal

// Шаг 2: Каждую валюту приводим к USD-base:
//   rubPerCode = cbr.rates[code].value / cbr.rates[code].nominal
//   cachedRates[code] = rubPerUSD / rubPerCode
//   (например: EUR: rubPerUSD=85, rubPerEUR=92 → cachedRates["EUR"] = 85/92 ≈ 0.924)

// Шаг 3: Фиксируем базу:
//   cachedRates["USD"] = 1.0
//   cachedRates["RUB"] = rubPerUSD  (например, 85.0)
```

**Тест-кейсы для нормализации CBR** (добавить в `CurrencyRateServiceTests`):
- `getRate("USD", "RUB")` → `cachedRates["RUB"]` (например, 85.0)
- `getRate("RUB", "USD")` → `1 / cachedRates["RUB"]` (≈ 0.01176)
- `getRate("EUR", "RUB")` → `cachedRates["RUB"] / cachedRates["EUR"]`

### Последствие: CBR не знает USD→RUB напрямую

CBR публикует курс `USD/RUB`. При нормализации выше он превращается в `cachedRates["USD"] = 1.0`. Если CBR не опубликовал USD в XML (нестандартный ответ) — `rubPerUSD` берётся как fallback из первого `globalFiatDaily` источника через `buildFallbackChain()`.

---

## Out of scope

- Кастомный URL источника.
- Источник для исторических курсов (Frankfurter+CBR остаются безусловно; `.cbr` уже поддерживает `supportsHistorical = true`).
- Источники с `requiresAPIKey = true` (Open Exchange Rates, OANDA, Alpha Vantage) — отдельная задача.

---

## Граничные случаи

| Кейс | Поведение |
|------|-----------|
| Источник недоступен в пикере | Карточка с `"Недоступен"`, выбрать можно |
| Источник не поддерживает валюту пользователя | `"—"` для конкретной пары в превью |
| Быстрое переключение источников | `setRateSource` инкрементирует generation-токен; in-flight refresh старого источника завершается, но результат дропается (generation mismatch). Новый `forceRefreshRates` в `selectSource` стартует с нулевым кэшем нового источника. |
| Смена источника во время фоновой аналитики | `forceRefreshRates()` завершается, затем аналитика пересчитывается через `CurrencyRateService` |
| Конвертер открыт в момент смены глобального источника | Если у конвертера `useAppDefault` — он подхватит новый курс при следующем `getRate()` |
| Пользователь смотрит пикер без сети | `loadPreviews()` возвращает stale-данные из кэша с пометкой `isStale` |
| Виджет не обновился мгновенно | Допустимо: синк при следующем foreground |

---

## Acceptance Criteria

### Функциональные
- [ ] Экран выбора источника открывается из Profile → «Источник курсов».
- [ ] Для каждого из `visibleSources` отображается карточка с курсами 4–5 избранных валют к `primaryCurrencyCode`.
- [ ] Курсы всех `visibleSources` загружаются параллельно; у каждого — свой индикатор загрузки.
- [ ] Текущий глобальный источник визуально отмечен (radio/чекмарк).
- [ ] Смена источника применяется немедленно без кнопки «Сохранить».
- [ ] После смены: аналитика и баланс в Dashboard пересчитываются с новым источником.
- [ ] Выбор сохраняется между перезапусками.
- [ ] При перезапуске `CurrencyRateService.shared` инициализируется с `preferred_rate_source`.
- [ ] Виджет синкается с `preferred_rate_source`, а не с `conv_rate_source`.
- [ ] Все строки локализованы (RU/EN/zh-Hans).
- [ ] UI конвертера явно показывает «По умолчанию (X)» или «Свой: Y».

### Архитектурные
- [ ] `refreshRates()` использует динамическую цепочку `[preferred, ...fallback]` без хардкода порядка.
- [ ] Выбранный источник идёт **первым** в цепочке fallback — не пропускается.
- [ ] Смена источника сбрасывает in-memory кэш `CurrencyRateService` перед следующим `getRate()`.
- [ ] `setRateSource` инкрементирует generation-токен; in-flight refresh старого источника не перезаписывает кэш после смены.
- [ ] `setRateSource` постит `Notification.Name.currencyRateSourceDidChange`; `FinanceViewModel` и `CashflowViewModel` подписаны и пересчитываются.
- [ ] `CurrencyWidgetSyncService.knownRateSources` автоматически включает все `RateSource.allCases`.
- [ ] `bootstrapFromStandardDefaults` переносит кэш для всех источников из `RateSource.allCases`.
- [ ] `DataResetService` чистит `preferred_rate_source` через `RateSourcePreferenceStore.reset()`.
- [ ] `conv_rate_source` читается/пишется только через `RateSourcePreferenceStore`.
- [ ] `store.preferred` пишется строго внутри `CurrencyRateService.setRateSource` — нигде больше.
- [ ] `ConverterView` и `RateSourcePickerView` используют `visibleSources(context:profile:)` — не `RateSource.allCases` напрямую.
- [ ] `RateSourcePreferenceStore` принимает `defaults: UserDefaults` в init; тесты используют suite defaults.
- [ ] `docs/CURRENCY_POLICY.md` обновлён и не противоречит реализации.

### Capability и CBR
- [ ] `.cbr` показывается в пикере только если `primaryCurrencyCode == "RUB"` или `favoriteCurrencyCodes` содержит `"RUB"`.
- [ ] Карточки источников в пикере отображают `legalLabel` как badge — источники не представлены как равнозначные.
- [ ] Карточка `.cbr` содержит дисклеймер `"Официальный курс ЦБ РФ, не курс покупки/продажи банков"`.
- [ ] При выбранном `.cbr` и запросе `getRate("USD", "RUB")` — курс берётся из CBR snapshot.
- [ ] При выбранном `.cbr` и запросе `getRate("EUR", "CNY")` — пара не включает RUB, сервис прозрачно роутит на globalFiat fallback и возвращает курс (не ошибку).
- [ ] `CurrencyWidgetSyncService.knownRateSources` включает `"cbr"`; `bootstrapFromStandardDefaults` переносит кэш `.cbr` в app group.

### Тесты
- [ ] `RateSourcePickerViewModelTests`: загрузка превью, параллельность, ошибка одного источника не блокирует остальные, `selectSource` вызывает `setRateSource` (не пишет `preferred` отдельно).
- [ ] `RateSourceTests.visibleSources`:
  - без RUB в профиле → `.cbr` не включается ни для `.profile`, ни для `.converter` контекста;
  - с `primaryCurrencyCode == "RUB"` → `.cbr` включается;
  - с `favoriteCurrencyCodes.contains("RUB")` → `.cbr` включается.
- [ ] `CurrencyRateServiceTests`:
  - `buildFallbackChain()` ставит preferred первым без дубликатов для всех четырёх вариантов;
  - `setRateSource` сбрасывает in-memory кэш и инкрементирует generation;
  - in-flight refresh с generation N не пишет кэш после setRateSource (generation N+1);
  - выбран `.cbr`, `getRate("USD", "RUB")` → курс из CBR snapshot (нормализован к USD-base);
  - выбран `.cbr`, `getRate("EUR", "CNY")` → пара не RUB, роутинг на globalFiat, курс возвращается без ошибки.
- [ ] `CurrencyRateServiceTests.cbrNormalization`:
  - из mock CBR XML с `rubPerUSD=85`, `rubPerEUR=92`, `rubPerCNY=12`:
    - `getRate("USD", "RUB")` ≈ 85.0;
    - `getRate("RUB", "USD")` ≈ 0.01176;
    - `getRate("EUR", "RUB")` ≈ 92.0.
- [ ] `RateSourcePreferenceStoreTests`: get/set/reset; тест использует suite defaults (не `.standard`); миграция nil → default `.millio`.
- [ ] `ConverterViewModelTests`: `useAppDefault` при nil override; override не затрагивает виджет-ключ.
- [ ] `RateSourceCapabilityTests`: capability-значения для всех четырёх источников совпадают с таблицей из спека.

---

## Затронутые файлы

| Файл | Изменение |
|------|-----------|
| `millio/Core/Currency/RateSource.swift` | Добавить `.cbr`; добавить `RateSourceCapability` + `capability` property |
| `millio/Core/Currency/RateSourcePreferenceStore.swift` | **Новый** — единственный слой над UserDefaults для ключей источника |
| `millio/Core/Currency/CurrencyRateService.swift` | `shared` init из store; `setRateSource(_:)`; динамическая цепочка; RUB-routing для CBR |
| `millio/Core/Currency/HistoricalRateProviders.swift` | Переиспользовать XML-парсинг CBR для `CBRLatestRateProvider` (live) |
| `millio/Core/Widget/CurrencyWidgetSyncService.swift` | `knownRateSources` + `"millio"`, `"cbr"`; bootstrap пишет `preferred_rate_source` |
| `millio/UI/Services/Courses/ConverterViewModel.swift` | Читать `conv_*` через `RateSourcePreferenceStore`; убрать виджет-синк источника |
| `millio/UI/Profile/RateSourcePickerView.swift` | **Новый** |
| `millio/UI/Profile/RateSourcePickerViewModel.swift` | **Новый** — включает `visibleSources` с CBR-фильтром |
| `millio/UI/Profile/ProfileMenuStructure.swift` | Добавить пункт меню |
| `millio/UI/Profile/ProfileView.swift` | NavigationLink |
| `millio/Core/Reset/DataResetService.swift` | `RateSourcePreferenceStore.reset()` |
| `docs/CURRENCY_POLICY.md` | Обновить «Converter Scope»; добавить «Global Rate Source» и «CBR Routing» |
| `millioTests/Core/Currency/RateSourcePreferenceStoreTests.swift` | **Новый** |
| `millioTests/Core/Currency/CurrencyRateServiceTests.swift` | Дополнить: chain + setRateSource + CBR routing |
| `millioTests/Core/Currency/RateSourceCapabilityTests.swift` | **Новый** — snapshot-тест таблицы capability |
| `millioTests/UI/Profile/RateSourcePickerViewModelTests.swift` | **Новый** |

---

## Changelog

| Дата | Изменение |
|------|-----------|
| 2026-05-23 | Первая версия (оригинал) |
| 2026-05-23 | Ревизия: зафиксирован архитектурный контракт, устранено противоречие конвертера, исправлен fallback-chain, добавлен `RateSourcePreferenceStore`, расширены AC, виджет переведён на `preferred_rate_source` |
| 2026-05-23 | Ревизия 2: добавлен `Source Capability Model` (`RateSourceCapability`), `.cbr` как 4-й источник с условной видимостью и RUB-routing, AC расширены capability/CBR-тестами |
| 2026-05-23 | Ревизия 4: `loadPreviews` → `visibleSources` (убран хардкод `× 3`); все статические `RateSourcePreferenceStore.preferred` → `store.preferred` / `RateSourcePreferenceStore.shared.preferred` — стиль согласован с DI-struct |
| 2026-05-23 | Ревизия 3: исправлены 8 слабых мест — DI в `RateSourcePreferenceStore` (struct+init), generation-токен против race в `setRateSource`, `knownRateSources` → `RateSource.allCases`, дублирующий запись `preferred` убран из `selectSource`, добавлены инварианты кэша и нормализация CBR XML → USD-base, секция dashboard-инвалидации (`NotificationCenter` + список подписчиков), `visibleSources(context:profile:)` как единый фильтр для Profile и Converter, "три источника" → "visibleSources" в AC, размер M→L |
