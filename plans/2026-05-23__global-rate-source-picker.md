# Plan: global-rate-source-picker

**Slug:** `global-rate-source-picker`
**Дата создания:** 2026-05-23
**Размер:** L (16 файлов: Core + UI + тесты + docs)
**Spec:** `specs/2026-05-23-global-rate-source-picker.md`

---

## Статус

`В РАБОТЕ`

**Реализовано:** Phase 1a (`8f48bdad`) · Phase 1c (`2e781fb2`) · Phase 1b (`b40bf0e2`)
**Осталось:** Phase 1 Finalize → 2a → 2b

---

## Цель

Добавить глобальный выбор источника курсов валют. Сейчас `CurrencyRateService.shared` всегда использует фиксированную цепочку `.millio → .erapi → .frankfurter`, игнорируя пользовательский выбор. После реализации:
- пользователь выбирает источник в Profile → «Источник курсов»;
- `refreshRates()` строит цепочку динамически, ставя preferred первым;
- смена источника сбрасывает кэш, Dashboard пересчитывается через `NotificationCenter`;
- виджет синкается с глобальным выбором, а не с конвертер-специфичным ключом;
- Phase 2 добавляет `.cbr` как 4-й источник с RUB-routing и capability model.

---

## Acceptance Criteria

### Phase 1 закрывает: Функциональные + Архитектурные AC

- [ ] F1: Экран выбора открывается из Profile → «Источник курсов»
- [ ] F2: Для каждого из `visibleSources` — карточка с курсами 4–5 избранных валют к `primaryCurrencyCode`
- [ ] F3: Курсы всех `visibleSources` загружаются параллельно; у каждого — свой индикатор загрузки
- [ ] F4: Текущий глобальный источник визуально отмечен (radio/чекмарк)
- [ ] F5: Смена источника применяется немедленно, без кнопки «Сохранить»
- [ ] F6: После смены — аналитика и баланс в Dashboard пересчитываются с новым источником
- [ ] F7: Выбор сохраняется между перезапусками
- [ ] F8: При перезапуске `CurrencyRateService.shared` инициализируется из `preferred_rate_source`
- [ ] F9: Виджет синкается с `preferred_rate_source`, не с `conv_rate_source`
- [ ] F10: Все строки локализованы (RU/EN/zh-Hans)
- [ ] F11: UI конвертера явно показывает «По умолчанию (X)» или «Свой: Y»

- [ ] A1: `refreshRates()` использует динамическую цепочку `[preferred, ...fallback]` без хардкода порядка
- [ ] A2: Preferred идёт первым в цепочке — не пропускается
- [ ] A3: Смена источника сбрасывает in-memory кэш `CurrencyRateService` перед следующим `getRate()`
- [ ] A4: `setRateSource` инкрементирует generation-токен; in-flight refresh старого источника не перезаписывает кэш
- [ ] A5: `setRateSource` постит `Notification.Name.currencyRateSourceDidChange`; `FinanceViewModel` и `CashflowViewModel` подписаны и пересчитываются
- [ ] A6: `CurrencyWidgetSyncService.knownRateSources` автоматически включает все `RateSource.allCases`
- [ ] A7: `bootstrapFromStandardDefaults` переносит кэш для всех источников из `RateSource.allCases`
- [ ] A8: `DataResetService` чистит `preferred_rate_source` через `RateSourcePreferenceStore.reset()`
- [ ] A9: `conv_rate_source` читается/пишется только через `RateSourcePreferenceStore`
- [ ] A10: `store.preferred` пишется строго внутри `CurrencyRateService.setRateSource` — нигде больше
- [ ] A11: `ConverterView` и `RateSourcePickerView` используют `visibleSources(context:profile:)` — не `RateSource.allCases` напрямую
- [ ] A12: `RateSourcePreferenceStore` принимает `defaults: UserDefaults` в init; тесты используют suite defaults
- [ ] A13: `docs/CURRENCY_POLICY.md` обновлён и не противоречит реализации

### Phase 2 закрывает: Capability и CBR AC

- [ ] C1: `.cbr` показывается в пикере только если `primaryCurrencyCode == "RUB"` или `favoriteCurrencyCodes` содержит `"RUB"`
- [ ] C2: Карточки источников отображают `legalLabel` как badge
- [ ] C3: Карточка `.cbr` содержит дисклеймер про официальный курс ЦБ
- [ ] C4: При выбранном `.cbr` и `getRate("USD", "RUB")` — курс из CBR snapshot
- [ ] C5: При выбранном `.cbr` и `getRate("EUR", "CNY")` — прозрачный роутинг на globalFiat fallback, возврат курса без ошибки
- [ ] C6: `CurrencyWidgetSyncService.knownRateSources` включает `"cbr"`; bootstrap переносит кэш `.cbr`

---

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 1a: Core — PreferenceStore + CurrencyRateService + DataResetService + тесты

**Что делаем:** фундамент. Без этой фазы ничего не работает — UI пикера нечего читать/писать.

**AC:** A1–A5, A8–A10, A12, F7, F8

**Файлы:**
- `millio/Core/Currency/RateSourcePreferenceStore.swift` — **новый**
- `millio/Core/Currency/CurrencyRateService.swift` — `shared` init из store; `setRateSource`; `buildFallbackChain`; generation-токен; `NotificationCenter.post`
- `millio/Core/Reset/DataResetService.swift` — добавить `RateSourcePreferenceStore.reset()`
- `millioTests/Core/Currency/RateSourcePreferenceStoreTests.swift` — **новый**
- `millioTests/Core/Currency/CurrencyRateServiceTests.swift` — дополнить

**Шаги:**

1. `[ ]` **`RateSourcePreferenceStore`**: реализовать struct с `defaults: UserDefaults`, `static let shared`, `var preferred: RateSource`, `var converterOverride: RateSource?`, `func reset()`.
   - `preferred` читает `"preferred_rate_source"`, дефолт `.millio`; пишет через `CurrencyRateService.setRateSource` — здесь только хранилище.
   - `converterOverride` читает/пишет `"conv_rate_source"`, nil = useAppDefault.
   - `reset()` удаляет оба ключа из `defaults`.

2. `[ ]` **`CurrencyRateService.shared`**: заменить хардкод на `CurrencyRateService(rateSource: RateSourcePreferenceStore.shared.preferred, ...)`.

3. `[ ]` **`buildFallbackChain()`**: реализовать как `[rateSource] + RateSource.allCases.filter { $0 != rateSource }`. Заменить хардкод `[.millio, .erapi, .frankfurter]` в `refreshRates()`.

4. `[ ]` **`setRateSource(_ source: RateSource)`**: реализовать метод:
   - `self.rateSource = source`
   - `self.store.preferred = source` (единственная точка записи preferred)
   - Инкрементировать `cacheGeneration: Int`
   - Обнулить `refreshTask = nil`
   - Сбросить `cachedRates` (оставить `["USD": 1.0]`)
   - `lastUpdateTS = 0`
   - `NotificationCenter.default.post(name: .currencyRateSourceDidChange, object: nil)`

5. `[ ]` **Generation-guard в `refreshRates()`**: захватить `let generation = self.cacheGeneration` перед async-работой; перед записью в `cachedRates` проверить `guard self.cacheGeneration == generation else { return }`.

6. `[ ]` **`DataResetService.reset()`**: добавить вызов `RateSourcePreferenceStore.shared.reset()`.

7. `[ ]` **`FinanceViewModel` + `CashflowViewModel`**: добавить подписку на `Notification.Name.currencyRateSourceDidChange` (в `init` или `.task`); отписка в `deinit`. При получении уведомления — вызывать соответствующий метод пересчёта (использовать уже существующие reload-методы этих VM, не добавлять новую логику).

8. `[ ]` **Тесты `RateSourcePreferenceStoreTests`**:
   - get/set preferred: записано → прочитано корректно
   - дефолт при nil в defaults — `.millio`
   - reset() удаляет оба ключа
   - тесты используют `UserDefaults(suiteName: "test.rate-source-pref")!`, не `.standard`
   - converterOverride: nil при отсутствии ключа; set/get round-trip

9. `[ ]` **Тесты `CurrencyRateServiceTests`** (дополнить):
   - `buildFallbackChain` ставит preferred первым без дубликатов для всех 3 вариантов (millio, erapi, frankfurter)
   - `setRateSource` сбрасывает `cachedRates` и инкрементирует generation
   - in-flight refresh с generation N не пишет кэш после `setRateSource` (generation N+1)

10. `[ ]` Коммит: `feat(currency): RateSourcePreferenceStore + CurrencyRateService setRateSource + generation guard`

**Gate 1a:** `RateSourcePreferenceStoreTests` все зелёные; `CurrencyRateServiceTests` (новые кейсы) зелёные; билд без ошибок; `DataResetService` включает reset источника.

---

### `[x]` Phase 1b: UI — RateSourcePickerView + ViewModel + Profile навигация

**Что делаем:** экран выбора источника и его подключение к Profile. Зависит от 1a (PreferenceStore + setRateSource).

**AC:** F1–F5, F10, F11, A10, A11

**Файлы:**
- `millio/UI/Profile/RateSourcePickerViewModel.swift` — **новый**
- `millio/UI/Profile/RateSourcePickerView.swift` — **новый**
- `millio/UI/Profile/ProfileMenuStructure.swift` — добавить пункт меню
- `millio/UI/Profile/ProfileView.swift` — NavigationLink
- `millioTests/UI/Profile/RateSourcePickerViewModelTests.swift` — **новый**

**Шаги:**

1. `[ ]` **`RateSourceContext`**: добавить enum `case profile, converter` в `RateSourcePickerViewModel.swift` (или рядом в Core/Currency).

2. `[ ]` **`visibleSources(context:profile:)`**: реализовать как статический метод или свободную функцию:
   ```swift
   // .cbr виден только при наличии RUB в профиле
   let rubInProfile = profile.primaryCurrencyCode == "RUB"
       || profile.favoriteCurrencyCodes.contains("RUB")
   return RateSource.allCases.filter { source in
       if source == .cbr { return rubInProfile }
       return true
   }
   ```
   Использовать в обоих пикерах — не перечислять `RateSource.allCases` напрямую нигде в UI.

3. `[ ]` **`RatePreview`**: реализовать struct с `rates: [(code: String, rate: Double)]`, `updatedAt: Date?`, `isStale: Bool`.

4. `[ ]` **`RateSourcePickerViewModel`**:
   - `@Published var previews: [RateSource: RatePreview]`
   - `@Published var loadingStates: [RateSource: LoadState]`
   - `@Published var selectedSource: RateSource` — init из `store.preferred`
   - `func loadPreviews()` — параллельная загрузка через `withTaskGroup`; ошибка одного источника не блокирует остальные; итерация по `visibleSources`, не хардкод
   - `func selectSource(_ source: RateSource)`:
     1. `selectedSource = source`
     2. `CurrencyRateService.shared.setRateSource(source)` — единственная точка записи preferred
     3. Синк виджета: `CurrencyWidgetSyncService.setString(source.rawValue, forKey: CurrencyWidgetShared.Keys.rateSource)`
     4. `await CurrencyRateService.shared.forceRefreshRates()`
     5. Запись актуальных курсов в виджет-кэш

5. `[ ]` **`RateSourcePickerView`**:
   - Список карточек для каждого `visibleSources` из ViewModel
   - Карточка: название, описание, мини-таблица курсов, время обновления, radio-чекмарк
   - Shimmer-скелетон при `.loading`
   - Карточка с `"Недоступен"` + последняя известная дата при ошибке (выбор при этом разрешён)
   - Оранжевая метка `"Данные устарели (>24ч)"` при `isStale`
   - `"—"` для пар, которые источник не поддерживает (не скрывать строку)
   - Смена источника — tap на карточку, без кнопки «Сохранить»
   - Все строки через `L(...)` + xcstrings (RU/EN/zh-Hans)
   - Только `AppTypography`, `AppSpacing`, `AppColors`, `AppAnimation` — без литералов

6. `[ ]` **`ProfileMenuStructure.swift`**: добавить пункт «Источник курсов» с subtitle = `RateSourcePreferenceStore.shared.preferred.title`.

7. `[ ]` **`ProfileView.swift`**: добавить `NavigationLink` к `RateSourcePickerView`.

8. `[ ]` **Тесты `RateSourcePickerViewModelTests`**:
   - `loadPreviews` завершается при 3 источниках
   - ошибка одного источника не блокирует остальные (mock: один источник кидает ошибку)
   - `selectSource` вызывает `CurrencyRateService.setRateSource`, не пишет `store.preferred` напрямую
   - `selectedSource` инициализируется из `store.preferred`
   - `visibleSources`: без RUB в профиле → `.cbr` не включается; с RUB → включается (оба контекста: profile, converter)
   - Тест использует mock `CurrencyRateService` или `RateSourcePreferenceStore(defaults: suite)`

9. `[ ]` Добавить строки в `Localizable.xcstrings`: «Источник курсов», «По умолчанию (%@)», «Свой: %@», «Недоступен», «Данные устарели (>24ч)», дисклеймер CBR (Phase 2 заполнит CBR-строки, зарезервировать ключи сейчас).

10. `[ ]` Коммит: `feat(ui): RateSourcePickerView + ViewModel + Profile navigation`

**Gate 1b:** экран открывается из Profile; источники загружаются параллельно; смена применяется немедленно и сохраняется; `RateSourcePickerViewModelTests` зелёные; билд без ошибок.

---

### `[x]` Phase 1c: Widget sync + ConverterViewModel рефакторинг

**Что делаем:** переключить виджет с `conv_rate_source` на `preferred_rate_source`; убрать виджет-синк из ConverterViewModel; мигрировать `conv_rate_source` на PreferenceStore. Зависит от 1a.

**AC:** A6, A7, A9, F9, F11

**Файлы:**
- `millio/Core/Widget/CurrencyWidgetSyncService.swift` — knownRateSources + bootstrap
- `millio/UI/Services/Courses/ConverterViewModel.swift` — рефакторинг

**Шаги:**

1. `[ ]` **`CurrencyWidgetSyncService.knownRateSources`**: заменить хардкод на `RateSource.allCases.map(\.rawValue)` — автоматически растёт при добавлении новых кейсов.

2. `[ ]` **`bootstrapFromStandardDefaults`**: заменить копирование `"conv_rate_source"` на `"preferred_rate_source"`:
   ```swift
   set(defaults.object(forKey: "preferred_rate_source"),
       forKey: CurrencyWidgetShared.Keys.rateSource,
       in: sharedDefaults)
   ```

3. `[ ]` **`ConverterViewModel`** — рефакторинг в три шага:
   - Убрать прямой `defaults.string(forKey: "conv_rate_source")` → читать через `store.converterOverride` (`RateSourcePreferenceStore`).
   - При `converterOverride == nil` → `state.rateSource = store.preferred` (useAppDefault).
   - При `setRateSource(source)`: если `source == store.preferred` → `store.converterOverride = nil`; иначе `store.converterOverride = source`.
   - Убрать `CurrencyWidgetShared.Keys.rateSource` запись из ConverterViewModel — виджет-синк источника теперь только в `RateSourcePickerViewModel.selectSource`.

4. `[ ]` **UI-label конвертера**: реализовать отображение `"По умолчанию (\(preferred.title))"` или `source.title` в кнопке источника.

5. `[ ]` Коммит: `feat(currency): widget syncs preferred_rate_source; ConverterViewModel uses PreferenceStore`

**Gate 1c:** виджет получает `preferred_rate_source`; конвертер не пишет виджет-ключ; `conv_rate_source` не читается напрямую нигде кроме `RateSourcePreferenceStore`; билд без ошибок.

---

### `[ ]` Phase 1 Finalize: docs + тесты + self-audit

**Что делаем:** финализация Phase 1 — документация и полная проверка AC.

**Файлы:**
- `docs/CURRENCY_POLICY.md` — обновить

**Шаги:**

1. `[ ]` **`docs/CURRENCY_POLICY.md`**: обновить секцию «Converter Scope» (строки 24–31) — описать новый контракт: конвертер больше не единственный владелец виджет-синка; добавить секции «Global Rate Source» (preferred_rate_source, buildFallbackChain, NotificationCenter) и «Widget Sync Source» (переход на preferred_rate_source).

2. `[ ]` Прогнать полный тестовый сьют:
   ```bash
   xcodebuild test -scheme millio \
     -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
     -quiet 2>&1 | grep -E "Test Suite|FAILED|passed|failed" | tail -10
   ```

3. `[ ]` Self-audit Phase 1 AC (F1–F11, A1–A13) — каждый закрыт.

4. `[ ]` Коммит: `docs(currency): update CURRENCY_POLICY.md — global rate source contract`

**Gate Phase 1:** все Phase 1 AC закрыты; тестовый сьют зелёный; docs обновлены; билд чистый.

---

### `[ ]` Phase 2a: `.cbr` кейс + `RateSourceCapability` + `CBRLatestRateProvider`

**Что делаем:** добавить 4-й источник `.cbr`, capability model, live-провайдер с XML-нормализацией. Зависит от Phase 1 (все фазы).

**AC:** C1–C6, часть тестовых AC по CBR

**Файлы:**
- `millio/Core/Currency/RateSource.swift` — добавить `.cbr`; добавить `RateSourceCapability` + `capability` property
- `millio/Core/Currency/HistoricalRateProviders.swift` — `CBRLatestRateProvider`
- `millio/Core/Currency/CurrencyRateService.swift` — RUB-routing для `.cbr`
- `millioTests/Core/Currency/RateSourceCapabilityTests.swift` — **новый**
- `millioTests/Core/Currency/CurrencyRateServiceTests.swift` — CBR-кейсы

**Шаги:**

1. `[ ]` **`RateSourceCapability`**: реализовать struct с вложенными enum'ами `Scope`, `BaseCurrency`, `Freshness`, `LegalLabel` в `RateSource.swift`.

2. `[ ]` **`RateSource.allCases` + `.cbr`**: добавить кейс с `rawValue = "cbr"`, `url = "https://cbr.ru/scripts/XML_daily.asp"`. Добавить `var capability: RateSourceCapability` для всех 4 кейсов согласно таблице из спека.

3. `[ ]` **`CBRLatestRateProvider`** в `HistoricalRateProviders.swift` (или отдельный файл рядом):
   - Переиспользовать XML-парсинг из `CBRHistoricalRateProvider`.
   - Нормализация к USD-base:
     - `rubPerUSD = cbr.rates["USD"].value / cbr.rates["USD"].nominal`
     - Для каждой валюты: `cachedRates[code] = rubPerUSD / (value / nominal)`
     - `cachedRates["USD"] = 1.0`; `cachedRates["RUB"] = rubPerUSD`
   - Если USD отсутствует в CBR XML — fallback на первый `globalFiatDaily` источник из `buildFallbackChain()`.

4. `[ ]` **RUB-routing в `CurrencyRateService`**: при `rateSource.capability.scope == .rubOfficialDaily && !pairInvolvesRUB(from:to:)` — использовать первый `globalFiatDaily` источник из цепочки. Логировать: `"CBR: pair \(from)→\(to) not RUB-involved, routing to globalFiat fallback"`. Для caller прозрачно — возвращает курс, не ошибку.

5. `[ ]` **Тесты `RateSourceCapabilityTests`**: snapshot-тест — для каждого из 4 кейсов проверить все поля capability согласно таблице из спека. При добавлении нового источника тест явно упадёт, напомнив заполнить capability.

6. `[ ]` **Тесты `CurrencyRateServiceTests`** (CBR-кейсы):
   - `buildFallbackChain` для `.cbr` ставит его первым без дубликатов
   - `setRateSource(.cbr)` сбрасывает кэш и инкрементирует generation
   - Из mock CBR XML с `rubPerUSD=85`, `rubPerEUR=92`, `rubPerCNY=12`:
     - `getRate("USD", "RUB")` ≈ 85.0
     - `getRate("RUB", "USD")` ≈ 0.01176
     - `getRate("EUR", "RUB")` ≈ 92.0
   - Выбран `.cbr`, `getRate("EUR", "CNY")` — пара не RUB, роутинг на globalFiat, курс возвращается без ошибки

7. `[ ]` Коммит: `feat(currency): CBR source + RateSourceCapability + CBRLatestRateProvider + RUB-routing`

**Gate 2a:** `RateSourceCapabilityTests` зелёные; CBR-нормализация тесты зелёные; RUB-routing тест зелёный; `RateSource.allCases` включает `.cbr`; билд чистый.

---

### `[ ]` Phase 2b: CBR в UI пикера + виджет + docs + финальный self-audit

**Что делаем:** показать `.cbr` в пикере при RUB-профиле, добавить capability badges и дисклеймер, финализировать docs. Зависит от 2a.

**AC:** C1–C6, F10 (zh-Hans для CBR)

**Файлы:**
- `millio/UI/Profile/RateSourcePickerView.swift` — capability badges, дисклеймер CBR
- `millio/UI/Profile/RateSourcePickerViewModel.swift` — Phase 2 не меняет логику, `visibleSources` уже фильтрует `.cbr`
- `millio/Localizable.xcstrings` — строки для CBR-дисклеймера и legalLabel
- `docs/CURRENCY_POLICY.md` — добавить секцию «CBR Routing»

**Шаги:**

1. `[ ]` **Capability badge** в карточке источника: показывать `legalLabel` как badge (`"Официальный"`, `"Справочный"`, `"Агрегатор"`, `"Справочный"` — согласно таблице). Источники визуально неравнозначны.

2. `[ ]` **Дисклеймер CBR**: фиксированный текст под карточкой `.cbr` — `"Официальный курс ЦБ РФ, не курс покупки/продажи банков"`. Локализовать для RU/EN; zh-Hans — EN-текст как fallback (зафиксировать в xcstrings явно).

3. `[ ]` **`Localizable.xcstrings`**: добавить ключи для legalLabel, CBR-дисклеймера; zh-Hans fallback для CBR-дисклеймера задокументировать как намеренный (не release-blocker).

4. `[ ]` **`docs/CURRENCY_POLICY.md`**: добавить секцию «CBR Routing» — описать `pairInvolvesRUB`, globalFiat fallback, нормализацию USD-base.

5. `[ ]` Финальный прогон полного тестового сьюта.

6. `[ ]` Self-audit Phase 2 AC (C1–C6) — каждый закрыт.

7. `[ ]` Коммит: `feat(ui): CBR capability badges, disclaimer, Phase 2 complete`

**Gate Phase 2 (финальный):** все AC (F1–F11, A1–A13, C1–C6) закрыты; полный тестовый сьют зелёный; docs актуальны; билд чистый; CBR отображается только при RUB в профиле.

---

## Impact Analysis

### Модули под риском регрессии

| Модуль | Риск | Проверка |
|--------|------|---------|
| **Converter** | `conv_rate_source` мигрирует на PreferenceStore; изменён виджет-синк | ConverterViewModelTests; ручной тест конвертера после Phase 1c |
| **Dashboard / FinanceViewModel** | Новая подписка на уведомление; неправильный пересчёт или двойной reload | Ручной тест смены источника; проверить отсутствие дублирования reload |
| **CashflowViewModel** | Та же подписка; горячий файл 4598 строк — минимальное вмешательство | Только добавить подписку в init/deinit; не трогать логику |
| **Widget** | Смена ключа с `conv_rate_source` на `preferred_rate_source` | Тест виджета после Phase 1c; bootstrap тест |
| **DataResetService** | Новый вызов `reset()` — не должен сломать существующий reset flow | Запустить существующие тесты DataResetService после Phase 1a |
| **Backup/Restore** | `preferred_rate_source` — UserDefaults ключ; при restore не восстанавливается (нормально — пользователь переустанавливает выбор) | Убедиться что restore не затирает preferred; не в scope исправлять |
| **CBR (Phase 2)** | RUB-routing может вернуть курс из другого источника для не-RUB пар | Тест: `.cbr` + `getRate("EUR","CNY")` → не nil, не crash |

### Edge cases

| Кейс | Обработка |
|------|---------|
| `preferred_rate_source` содержит неизвестный rawValue (например после удаления источника) | `RateSource(rawValue:)` вернёт nil → дефолт `.millio` в PreferenceStore getter |
| Быстрое переключение источников подряд | Generation-токен гарантирует, что только последний refresh пишет кэш |
| Смена источника при отсутствии сети | `setRateSource` сбрасывает кэш; `forceRefreshRates` завершится ошибкой; `getRate` вернёт nil / stale — штатное offline-поведение |
| Конвертер открыт в момент смены глобального источника, у конвертера нет override | Получит новый курс при следующем `getRate()` — уведомление проходит через ConverterViewModel подписку (если добавлена) или при следующем появлении |
| Widget не обновился мгновенно | Допустимо — синк при следующем foreground |

---

## Зависимости между фазами

```
Phase 1a (Core: PreferenceStore + setRateSource)
    └── Phase 1b (UI: PickerView + Profile)
    └── Phase 1c (Widget sync + ConverterViewModel)
        └── Phase 1 Finalize (docs + self-audit)
            └── Phase 2a (.cbr + Capability + CBRLatestRateProvider)
                └── Phase 2b (CBR в UI + docs + финал)
```

Phase 1b и 1c можно выполнять параллельно после 1a. Phase 2 не начинать до полного закрытия Phase 1.

---

## Журнал

| Дата | Действие |
|------|---------|
| 2026-05-23 | План создан на основе spec rev.4 |
| 2026-05-23 | Phase 1a реализована и закрыта (коммит `8f48bdad`). Все 14 новых тестов зелёные. Gate 1a пройден. |
| 2026-05-23 | Phase 1c реализована (коммит `2e781fb2`): knownRateSources → allCases, bootstrap → preferred_rate_source, ConverterViewModel → PreferenceStore, rateSourceDisplayLabel. |
| 2026-05-23 | Phase 1b реализована (коммит `b40bf0e2`): RateSourcePickerView+ViewModel, Profile навигация, visibleSources, 9 новых тестов, l10n RU/EN/zh-Hans, ConverterView→visibleSources. Gate 1b пройден. |
| 2026-05-23 | Замечание Phase 1c: SettingsManager.swift:453 делает прямой `removeObject(forKey: "conv_rate_source")`, обходя PreferenceStore. Исправить в Phase 2 cleanup. |
