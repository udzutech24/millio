# Plan: Custom Rate Source

**Slug:** custom-rate-source  
**Spec:** [specs/2026-05-23-custom-rate-source.md](../specs/2026-05-23-custom-rate-source.md)  
**Дата:** 2026-05-23  
**Статус:** В РАБОТЕ

---

## Журнал

| Дата | Фаза | Действие |
|------|------|----------|
| 2026-05-23 | — | Plan создан |
| 2026-05-23 | 1 | Реализована. Коммит 53126920. 16/16 тестов зелёные. |
| 2026-05-23 | 2 | Реализована. Коммит a8cf9f6c. Билд чистый, 16/16 тестов зелёные. |

---

## Затронутые файлы

### Новые
- `millio/Core/Currency/CustomRateStore.swift`
- `millio/UI/Profile/CustomRateEditorView.swift`

### Изменяемые
- `millio/Core/Currency/RateSource.swift` — добавить `.custom`
- `millio/Core/Currency/CurrencyRateService.swift` — обработка `.custom` в `setRateSource`, `getRate`, `refreshRates`, `buildFallbackChain`
- `millio/UI/Profile/RateSourcePickerView.swift` — кнопка «Редактировать» на custom-карточке + sheet
- `millio/UI/Profile/RateSourcePickerViewModel.swift` — preview для custom + `isCustomConfigured`
- `millio/Core/Services/DataResetService.swift` — сброс custom-курсов
- `millio/Localizable.xcstrings` — новые строки
- `millioCurrencyWidgetExtension/` — обработка `"custom"` rawValue

---

## Фазы

### Фаза 1 — Core: CustomRateStore + RateSource.custom + CurrencyRateService [x]

**Acceptance gate:** `getRate(from:to:)` возвращает custom-курс если задан; fallback если нет; тест зелёный.

**1.1** `CustomRateStore.swift`
```swift
struct CustomRateStore {
    static let shared = CustomRateStore()
    private let defaults: UserDefaults

    // rates: [code: Double] — "X primaryCurrency за 1 code"
    var rates: [String: Double] { get/set — UserDefaults "custom_rates" }
    var primaryForRates: String { get/set — UserDefaults "custom_rates_primary" }

    // Конвертировать в USD-base для CurrencyRateService.cachedRates
    func toUSDBase(currentPrimary: String) -> [String: Double]

    // true если USD задан (или primary = USD)
    var isConfigured: Bool

    func reset() // убрать оба ключа
}
```
Логика `toUSDBase`:
```
usdPerPrimary = (currentPrimary == "USD") ? 1.0 : (1.0 / rates["USD"])
for (code, xPerForeign) in rates:
    cachedRates[code] = (1.0 / xPerForeign) * usdPerPrimary
```

**1.2** `RateSource.swift` — добавить:
```swift
case custom

// title: L("rate_source.custom.title") → "Свой курс"
// subtitle: L("rate_source.custom.subtitle") → "Ручной ввод"
// latestURL: nil
// capability: .init(scope: .globalFiatDaily, baseCurrency: .usd,
//   requiresAPIKey: false, supportsMatrixFetch: false,
//   supportsHistorical: false, freshnessLabel: .realtime, legalLabel: .market)
```

**1.3** `CurrencyRateService.swift`:
- `setRateSource(.custom)`: после стандартного сброса кэша — загружаем `CustomRateStore.shared.toUSDBase(currentPrimary:)`
- `refreshRates()` для `.custom`: ранний return (ничего не грузим)
- `buildFallbackChain()`: уже работает (`allCases.filter { $0 != rateSource }`), `.custom` включится автоматически
- `getRate(from:to:)`: если `.custom` и кэш-miss → делегировать на первый `globalFiatDaily` источник из оставшейся цепочки (аналогично cbr → non-RUB паттерну)

**1.4** `DataResetService.swift` — вызвать `CustomRateStore.shared.reset()`

**1.5** Тесты в `millioTests/Currency/CustomRateStoreTests.swift`:
- `toUSDBase` при primary=RUB с USD+EUR+CNY
- `toUSDBase` при primary=USD
- `isConfigured` true/false
- `reset()` очищает

---

### Фаза 2 — UI: Редактор + Picker [x]

**Acceptance gate:** пользователь может открыть редактор, ввести курсы, сохранить → пикер показывает их; выбор `.custom` → весь UI пересчитывается.

**2.1** `CustomRateEditorView.swift`:
- `@State` копия rates + primaryCode + favoriteCodes
- `List` / `VStack` строк: `CurrencyFlag` + код + `TextField` (`.numberPad`, `.decimalPad`) + primaryCode-лейбл
- USD-строка обязательна если primary ≠ USD: выделить сноской, заблокировать Save пока пусто
- Кнопки тулбара: «Отмена» + «Сохранить»
- Сохранение: `CustomRateStore.shared.rates = ...` → если `.custom` уже выбран: `CurrencyRateService.shared.setRateSource(.custom)` (перезагружает кэш + постит notification)

**2.2** `RateSourcePickerView.swift`:
- В `sourceCard(_ source:)`: если `source == .custom` → добавить кнопку «Редактировать» в хедер (рядом с checkmark)
- Кнопка: `Button { viewModel.showCustomEditor = true } label: { ... }`
- `.sheet(isPresented: $viewModel.showCustomEditor) { CustomRateEditorView(...) }`

**2.3** `RateSourcePickerViewModel.swift`:
- `@Published var showCustomEditor = false`
- `var isCustomConfigured: Bool { CustomRateStore.shared.isConfigured }`
- Preview для `.custom`: синхронно из `CustomRateStore` — показываем текущие курсы
- В `visibleSources()`: `.custom` всегда видим (нет условий фильтрации)
- Tap на `.custom` пока `!isCustomConfigured` → не выбирать, показать hint (или сразу открыть редактор)

---

### Фаза 3 — Локализация + Widget + Полировка [ ]

**Acceptance gate:** билд без warnings на RU/EN/zh-Hans; widget не крашится; `DataResetService` тест зелёный.

**3.1** `Localizable.xcstrings` — добавить ключи:
```
rate_source.custom.title          RU: Свой курс       EN: Custom        zh: 自定义
rate_source.custom.subtitle       RU: Ручной ввод     EN: Manual        zh: 手动输入
rate_source_picker.custom_edit    RU: Редактировать   EN: Edit          zh: 编辑
rate_source_picker.custom_hint    RU: Сначала задайте курсы  EN: Set rates first  zh: 先设置汇率
custom_rate_editor.title          RU: Свой курс       EN: Custom Rates  zh: 自定义汇率
custom_rate_editor.usd_required   RU: Необходим курс USD  EN: USD rate required  zh: 需要美元汇率
custom_rate_editor.save           RU: Сохранить       EN: Save          zh: 保存
custom_rate_editor.cancel         RU: Отмена          EN: Cancel        zh: 取消
```

**3.2** Widget (`millioCurrencyWidgetExtension/`):
- `CurrencyWidgetShared.Keys.rateSource` уже читается как rawValue
- При `rawValue == "custom"`: `CurrencyWidgetSyncService` должен скопировать custom-rates в App Group UserDefaults
- В `CurrencyWidgetSyncService.bootstrapFromStandardDefaults` — добавить копирование `"custom_rates"` и `"custom_rates_primary"` в widget container
- Widget entry provider при `rateSource == "custom"`: читает custom-rates из App Group, конвертирует через `toUSDBase`, иначе fallback на millio

**3.3** Полировка UX:
- При выборе `.custom` пока `!isCustomConfigured`: автоматически открывать редактор вместо карточки-подтверждения
- При очистке всех custom-курсов и save: откат `preferred` на `.millio`
- Анимации: `withAnimation(AppAnimation.standard)` при смене состояния карточки

---

## Impact Analysis

| Область | Риск | Митигация |
|---------|------|-----------|
| `buildFallbackChain()` | `.custom` теперь в `allCases` → `visibleSources()` фильтрации нет → всегда видим | Ок, без условий |
| `DataResetService` | custom-курсы не сбросятся | Добавляем `CustomRateStore.shared.reset()` в Фазе 1 |
| Widget `RateSource(rawValue:)` | init вернёт `nil` для `"custom"` пока case не добавлен | В Фазе 1 добавляем case → nil уйдёт |
| Конвертер `converterOverride` | `.custom` rawValue будет корректно сохраняться/читаться | Автоматически — просто rawValue string |
| Тесты `RateSourceTests` | `allCases.count` изменится с 4 на 5 | Обновить assertions в Фазе 3 |
