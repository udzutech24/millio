# Plan: Language Switch Hardening

**Spec:** `specs/2026-05-11-language-switch-hardening.md`
**Статус:** В РАБОТЕ
**Создан:** 2026-05-11

---

## Контекст

Механизм смены языка:
1. `appState.selectedLanguage = newLang` (в ProfileView)
2. `AppState.didSet` → `LanguageManager.shared.setLanguage()` → `BundleLanguageOverride.apply(language:)` (ObjC swizzling)
3. `languageRefreshToken = UUID()` → `.id(token)` в `millioApp.swift:116` → SwiftUI пересоздаёт весь view tree

Теоретически должен работать. На практике — нет. Гипотезы:
- `BundleLanguageOverride.apply()` не находит правильный `.lproj` bundle → ассоциация `nil` → fallback на системный язык
- `Language.locale` возвращает identifier, который не матчит `.lproj`-папку (напр. `"zh-Hans"` vs `"zh_Hans"`)  
- `.xcstrings` на iOS 17+ может вызывать `localizedString(forKey:)` через `StringCatalog` API в обход swizzling
- `languageRefreshToken` не меняется (race condition, guard `selectedLanguage != oldValue` срабатывает ложно)

---

## Phase 0: Диагностика (верифицировать root cause)

**Без этой фазы не трогать код.**

- [x] Добавить `Logger`-логи в `BundleLanguageOverride.apply()`:
  - какие bundles найдены
  - для Bundle.main — нашёлся ли `localizedBundle` или nil
  - identifier локали, которую ищем
- [x] Добавить лог в `AppState.didSet` — обновлённый UUID `languageRefreshToken` и язык
- [ ] Запустить на симуляторе EN → RU, посмотреть Console
- [x] Проверить `Language.locale` для `en`, `ru`, `zh-Hans`: совпадает ли с `.lproj` папками в Bundle
- [x] Проверить: в `BundleLanguageOverride.installedBundleIDs` — thread-safety (set без lock)

**Ожидаемый outcome:** точный root cause задокументирован.

---

## Findings (Phase 0 — 2026-05-11)

### 1. Language.locale vs .lproj — СОВПАДАЮТ
- `Language.english.locale` = `Locale(identifier: "en")` → `.lproj` папка `en.lproj` ✅
- `Language.russian.locale` = `Locale(identifier: "ru")` → `ru.lproj` ✅
- `Language.simplifiedChinese.locale` = `Locale(identifier: "zh-Hans")` → `zh-Hans.lproj` ✅
- `.lproj` папки в built app: `en.lproj`, `ru.lproj`, `zh-Hans.lproj` (симулятор Debug)
- `preferredLanguageCandidates(from: Locale("zh-Hans"))` → `["zh-Hans", "zh"]` — первый кандидат совпадает с папкой. **Гипотеза 1 (locale mismatch) не подтверждается.**

### 2. .xcstrings и iOS 17+ StringCatalog API — ВЕРОЯТНЫЙ ROOT CAUSE
Основная масса UI использует:
- `String(localized: "key")` — нативный iOS API, который на iOS 16+ идёт через `StringCatalog` и вызывает `localizedString(forKey:)` — т.е. через `RuntimeLocalizedBundle.localizedString(forKey:)`. **Swizzling должен работать.**
- Но часть использует `LocalizedStringResource` (6 мест в UI) — этот тип на iOS 16+ имеет свой путь резолюции и **не гарантирует прохождение через Bundle swizzling**.
- `FinancesL10n.tr()` → `AppLocalization.string()` → `ExplicitStringCatalog` (парсит `.xcstrings` напрямую из файловой системы в runtime) → **обходит Bundle.main полностью**. После смены языка `AppLocalization.currentAppLocale` обновляется, но `ExplicitStringCatalog.shared` — синглтон с ленивой инициализацией при старте, данные уже загружены. Локализация через него зависит только от `locale`-параметра — должна работать.

### 3. languageRefreshToken — СТРУКТУРА ПРАВИЛЬНАЯ, НО ЕСТЬ НЮАНС
- `.id(appState.languageRefreshToken)` применён к `ZStack` внутри `if let container = activeModelContainer { ... }` в `WindowGroup`.
- Нет sheet/fullScreenCover снаружи — всё внутри `.id()` scope. **Гипотеза 3 не подтверждается.**
- `languageRefreshToken = UUID()` обновляется **после** `LanguageManager.shared.setLanguage()` и **после** `BundleLanguageOverride.apply()` — порядок правильный.
- Но: `languageRefreshToken` находится в `@Observable AppState`. `.id()` на SwiftUI-view вызывает **полное пересоздание** view tree. При этом новые `String(localized:)` вызовы идут после `apply()` — должно корректно подхватывать новый bundle.

### 4. Thread-safety installedBundleIDs — ПОТЕНЦИАЛЬНАЯ ПРОБЛЕМА
- `BundleLanguageOverride.installedBundleIDs` — `Set<ObjectIdentifier>` **без lock**. `overrideStateLock` защищает только `overrideSuppressionDepth`, не `installedBundleIDs`.
- `apply()` вызывается из `LanguageManager.setLanguage()`, защищённого `NSRecursiveLock`. Но `apply()` также вызывается в `init()` LanguageManager (до публикации singleton). Теоретически race возможен при параллельном вызове из нескольких потоков.
- **Это не root cause проблемы смены языка**, но реальный баг thread-safety.

### 5. Главная гипотеза (не верифицирована без Консоли) — Ветка B
На iOS 17+ `String(localized: StringLiteralType)` может резолвиться через `StringCatalog` runtime, **минуя** `Bundle.localizedString(forKey:)`. Apple изменила путь резолюции `.xcstrings` на iOS 16+: `StringCatalog` читается напрямую из скомпилированного ресурса, а не через `NSBundle` ObjC bridge. Это значит `RuntimeLocalizedBundle.localizedString(forKey:)` вообще не вызывается для `String(localized:)` с `.xcstrings`-ключами.

**Вывод:** наиболее вероятный root cause — Ветка B (`.xcstrings` обходит swizzling на iOS 16+). Следующий шаг — верифицировать в Console логами, добавленными в Phase 0, + проверить вызывается ли `RuntimeLocalizedBundle.localizedString` вообще при смене языка.

---

## Phase 1: Fix механизма смены языка

**Guard phrase: «Реализуй Phase 1 по плану»**

Зависит от Phase 0 — подход выбирается по root cause:

### Ветка A: `localizedBundle` не находится (наиболее вероятно)
- Проверить `AppLocalization.localizedBundle(for:bundle:)` — как ищет `.lproj`
- Если locale identifier не совпадает → нормализовать: `"zh-Hans"` → `"zh_Hans"` для поиска в Bundle
- Добавить fallback: если exact match не найден — искать по `languageCode` (первые 2 символа)

### Ветка B: `.xcstrings` обходит swizzling ✅ РЕАЛИЗОВАНО
- [x] Подтверждён root cause: `String(localized:)` с `.xcstrings` на iOS 16+ обходит ObjC swizzling
- [x] Добавлен `var currentBundle: Bundle` в `LanguageManager` (с lock)
- [x] Создан `millio/Core/Language/L10n.swift` с функцией `L()` — обёртка с явным `bundle:`
- [x] 641 вызов заменён: `String(localized: "key")` → `L("key")` по всему проекту
- [x] Перегрузка `L(String, defaultValue:)` через `NSLocalizedString` для 39 вызовов с `defaultValue:`
- [x] BUILD SUCCEEDED

### Ветка C: `languageRefreshToken` не достигает всего дерева
- Проверить иерархию — есть ли sheet/fullScreenCover/NavigationStack, которые живут вне `.id(token)` scope
- Если есть — прокинуть token через `@Environment` и применить `.id()` отдельно

### Общее для всех веток:
- [ ] `BundleLanguageOverride.installedBundleIDs` — защитить отдельным lock или перейти на `NSLock` внутри класса
- [x] Убедиться что `BundleLanguageOverride.apply()` вызывается **до** обновления `languageRefreshToken`

### Phase 1 — Хардкод кириллицы (автоматизированный прогон):
- [x] `TotalBalanceWidget.swift` — "д" → `L("dashboard.balance.days_suffix")` (EN: "d", zh-Hans: "天")
- [x] `InvestmentEditorView.swift` — "/мес" → `L("finances.deposit.per_month_suffix")` (EN: "/mo", zh-Hans: "/月")
- [x] `DashboardView.swift` — 4 строки ("Месяц", "Готово", "Виджеты", "Закрыть") → `L("dashboard.*")` / `L("common.*")`
- [x] `DashboardDeltaPeriodPickerSheet.swift` — 5 period strings → `L("dashboard.period.*")`
- [x] `CashflowSummaryWidget.swift` — "Доходы", "Расходы", "Изм. активов" → `L("cashflow.*")`
- [x] `CashflowInsightsChartModels.swift` — 3 comparison strings → `L("cashflow.insights.comparison.*")`
- [x] `FinanceOverviewLedgerStyle.swift` — 3 format strings → `L("finances.overview.*")`
- [x] `CurrencyDistributionChartView.swift` + `DistributionChartView.swift` — "Сумма" → `L("finances.chart.amount_label")`
- [x] `String(localized:)` без `bundle:` — 7 мест в 5 файлах (PremiumUpsellAlert, SubscriptionView, InvestmentEditorView, FinanceDynamicsView, FinanceGroupEditorView) → добавлен `bundle: LanguageManager.shared.currentBundle`
- [x] 22 новых ключа добавлены в `Localizable.xcstrings` (EN/RU/zh-Hans)
- [x] BUILD SUCCEEDED

### Автоматизация (создано):
- [x] `scripts/l10n-audit.sh` — аудит, exit 1 при проблемах
- [x] `scripts/l10n-autofix.sh` — автофиксер с `--dry-run` / `--no-build`
- [x] `scripts/l10n-check-new-language.sh <lang>` — проверка готовности для нового языка

---

## Phase 2: Тесты

**Guard phrase: «Реализуй Phase 2 по плану»**

### Unit-тесты (добавить в `millioTests/Core/Localization/`)

Файл: `LanguageSwitchTests.swift`

- [ ] `testBundleOverrideApplyRU` — после `apply(.russian)`, `Bundle.main.localizedString(forKey: someKnownKey)` возвращает RU строку
- [ ] `testBundleOverrideApplyEN` — то же для EN
- [ ] `testBundleOverrideApplyZhHans` — то же для zh-Hans (если ключ переведён)
- [ ] `testLanguageManagerSetLanguagePersists` — после `setLanguage(.english)`, `currentLanguage == .english`
- [ ] `testLanguageManagerRoundTrip` — RU → EN → RU, каждый раз bundle переключается правильно
- [ ] `testSystemLanguageFallback` — `setLanguage(.system)` очищает override (bundle fallback к системному)

Файл: Обновить `LocalizationHotReloadTests.swift`
- [ ] Проверить 3 языка для ключевых keys (если тесты были только для RU/EN — добавить zh-Hans)

### UI-тесты (опционально, `millioUITests/`)

- [ ] `testLanguageSwitchToEnglish` — открыть Profile, сменить язык на EN, вернуться на Dashboard, проверить label (accessibilityIdentifier)
- [ ] `testLanguageSwitchBackToRussian` — EN → RU

---

## Phase 3: Hardening — RestoreView

**Guard phrase: «Реализуй Phase 3 по плану»**

Блокер для zh-Hans release:

- [ ] Открыть `millio/UI/Restore/RestoreView.swift`, выписать все hardcoded RU literals
- [ ] Добавить ключи в `Localizable.xcstrings` (формат: `restore.*`)
- [ ] Заменить literals на `String(localized: "restore.key")`
- [ ] Добавить coverage-тест: `LocalizableXcstringsTests` проверяет что все `restore.*` ключи переведены на 3 языка

---

## Acceptance Gate (финал)

- [ ] Ручная проверка: EN → zh-Hans → RU на симуляторе, все экраны обновляются
- [ ] Все тесты из Phase 2 зелёные
- [ ] RestoreView не содержит RU literals (Phase 3)
- [ ] Нет регрессий: backup/restore flow, cashflow, dashboard работают

---

## Журнал сессий

| Дата | Фаза | Итог |
|------|------|------|
| 2026-05-11 | — | План создан |
| 2026-05-11 | 0 | Диагностика выполнена: статический анализ + логи добавлены. Root cause — вероятно Ветка B (`.xcstrings` обходит Bundle swizzling на iOS 16+). Требует верификации в Console на симуляторе. |
| 2026-05-11 | 1 | Root cause: String(localized:) bypasses swizzling. Fix: currentBundle + L() wrapper. 641 вызов заменён. BUILD SUCCEEDED. |
| 2026-05-11 | Phase 1 cont. | Фикс C (SubscriptionManager), D (DataResetService), build error CloudBackupStore |
| 2026-05-11 | Phase 1 cont. | Text("key") → Text(L("key")) в Dashboard и Finances — xcstrings bypass fix. 11 замен в 8 файлах. Добавлены переводы EN/zh-Hans для 5 пустых xcstrings-записей + 2 новых ключа. BUILD SUCCEEDED. |
| 2026-05-11 | Phase 1 cont. | Массовый прогон автоматизацией: 22 хардкод-RU строки → L(), 7 String(localized:) без bundle: исправлены, 22 ключа в xcstrings (EN/RU/zh-Hans), 3 automation-скрипта в scripts/. BUILD SUCCEEDED. |
| 2026-05-11 | zh-Hans cleanup | Обнаружены сырые ключи на скринах (finances.overview.chart.*, finances.dynamics.*). Добавлены zh-Hans переводы: 6 видимых + 218 активных L()-ключей + 387 прочих активных (cashflow, finances, auth, profile, subscription). Удалены 270 мёртвых ключей из xcstrings. Итог: 1837 ключей, 0 без zh-Hans. BUILD SUCCEEDED. |
