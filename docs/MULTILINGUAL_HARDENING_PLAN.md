# Multilingual Hardening Plan

## Goal

Сделать локализацию в `millio` системной, а не “местами поправленной”:

- `ru`, `en`, `zh-Hans` должны быть одинаково валидными product languages;
- UI не должен зависеть от `Locale.current` для product copy;
- UI не должен показывать raw localization keys;
- product text не должен жить на ручных `ru/en` и `ru/en/zh` ветках;
- новый язык должен добавляться через тот же контракт, а не через новые helper-обходы.

## Current status: 2026-03-31

### What is already genuinely hardened

- Runtime contract стал заметно лучше:
  - [`LanguageManager.swift`](/Users/alekseya/millio/millio/Core/Language/LanguageManager.swift)
  - [`BundleLanguageOverride.swift`](/Users/alekseya/millio/millio/Core/Language/BundleLanguageOverride.swift)
  - [`AppLocalization.swift`](/Users/alekseya/millio/millio/Core/Language/AppLocalization.swift)
  - [`LocalizationSupport.swift`](/Users/alekseya/millio/millio/Core/Language/LocalizationSupport.swift)
  - Итог: app language теперь реально важнее device locale, а `String(localized:)`/`LocalizedStringKey` переживают runtime switch.
- Крупные product domains уже не выглядят как локализационный хаос:
  - `Cashback` переведён на нормальный contract и больше не сидит на RU/EN-only metadata.
  - `Finances` critical surfaces дожаты до app-locale contract и убраны ключевые raw-key/device-locale regressions.
  - `QuickSetup` больше не живёт на старом RU/EN-only helper-е и хотя всё ещё helper-driven, уже держится на catalog-backed keys.
  - `Converter` и часть shared/root слоёв выпрямлены вокруг `AppLocalization` и live language switch.
- В repo уже есть полезные source guards и coverage tests:
  - [`LocalizationHotReloadTests.swift`](/Users/alekseya/millio/millioTests/Core/LocalizationHotReloadTests.swift)
  - [`LocalizableXcstringsTests.swift`](/Users/alekseya/millio/millioTests/Core/Localization/LocalizableXcstringsTests.swift)
  - Это уже не “верим на слово”, а хотя бы частично защищённый контракт.

### Hard truth

Repo больше не в аварийном состоянии по локализации, но до “bulletproof for +10 languages” ему ещё далеко.

Основная проблема теперь не в одном конкретном баге, а в том, что в проекте всё ещё одновременно живут четыре несовместимых модели:

- explicit locale resolution через `AppLocalization.string(...)`;
- implicit bundle-driven resolution через `Text("key")` / `String(localized:)`;
- manual multilingual helpers с прямыми строками;
- literal-driven localization keys вида `String(localized: "Month")`.

Пока эти модели смешаны, проект держится не на железном контракте, а на наборе частичных соглашений и regression guards.

## Repo-wide reassessment

### Release-critical

#### 1. Restore / recovery flow всё ещё не hardened

- Файлы:
  - [`RestoreView.swift`](/Users/alekseya/millio/millio/UI/Restore/RestoreView.swift)
- Почему это риск:
  - экран содержит прямые русские product-facing literals;
  - это startup/recovery flow, где пользователь особенно чувствителен к доверию и ясности;
  - при rollout новых языков тут не просто “неидеально”, тут гарантированно будет broken experience.
- Почему это важно для release:
  - restore/recovery нельзя считать второстепенным экраном;
  - если recovery flow не multilingual-safe, release нельзя честно называть hardened.
- Что делать следующей волной:
  - перевести `RestoreView` на scoped `backup.restore.*` / `restore.*` keys;
  - убрать все hardcoded RU literals;
  - вынести copy в `BackupL10n` или отдельный typed restore facade, без нового helper вида `text(locale: ru: en:)`;
  - добавить 3-language coverage test на restore keys и source guard против raw literals в этом файле.

#### 2. Cashflow всё ещё держит product copy на generic literal keys

- Файлы:
  - [`CashflowViewModel.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowViewModel.swift)
  - [`CashflowTransaction.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowTransaction.swift)
  - [`CashflowInsightsChartModels.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowInsightsChartModels.swift)
- Почему это риск:
  - строки вроде `String(localized: "Month")`, `String(localized: "Income")`, `String(localized: "Transfer")` не имеют domain scope;
  - это маскирует missing translation и создаёт коллизии между доменами;
  - такие keys плохо масштабируются на +10 языков и плохо ревьюятся.
- Почему это важно для release:
  - это не debug copy, а core labels в release-facing Cashflow;
  - даже если сейчас перевод есть, контракт всё равно слабый и хрупкий.
- Что делать следующей волной:
  - заменить literal-driven keys на scoped `cashflow.*` keys;
  - отдельно покрыть chart period / transaction type / insights labels тестом на `ru/en/zh-Hans`;
  - запретить новые literal-driven keys в Cashflow source guards.

### High-risk but non-critical

#### 3. Raw-key rendering всё ещё живёт в release-facing UI

- Файлы:
  - [`SubscriptionView.swift`](/Users/alekseya/millio/millio/UI/Subscription/SubscriptionView.swift)
  - [`ProfileView.swift`](/Users/alekseya/millio/millio/UI/Profile/ProfileView.swift)
  - [`ProfilePremiumDiagnosticsView.swift`](/Users/alekseya/millio/millio/UI/Profile/ProfilePremiumDiagnosticsView.swift)
  - [`RateAppBlock.swift`](/Users/alekseya/millio/millio/UI/Profile/RateAppBlock.swift)
  - [`CashflowPeriodSelectorView.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowPeriodSelectorView.swift)
  - [`CashflowScheduledTransactionsView.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowScheduledTransactionsView.swift)
  - [`CashflowOperationSheets.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowOperationSheets.swift)
- Почему это риск:
  - после `BundleLanguageOverride` это уже не mixed-locale root cause;
  - но это всё ещё implicit contract: если ключ удалят, переименуют или не закроют перевод, UI может отдать raw key;
  - тестировать и ревьюить такие места заметно тяжелее, чем explicit string resolution.
- Почему это пока не release-critical:
  - большая часть этих surface’ов уже опирается на рабочий runtime override;
  - прямого признака массового mixed-locale в этих файлах сейчас нет.
- Что делать следующей волной:
  - убрать `Text("key")` и `navigationTitle("key")` из release-facing поверхностей;
  - не тащить туда новый “universal helper”, а использовать либо `AppLocalization.string`, либо узкий domain facade.

#### 4. Manual multilingual helpers ещё не умерли, а только перестали быть RU/EN-only

- Файлы:
  - [`SmartDataResetLocalization.swift`](/Users/alekseya/millio/millio/UI/Profile/SmartDataResetLocalization.swift)
  - [`NotificationManager.swift`](/Users/alekseya/millio/millio/Core/Notifications/NotificationManager.swift)
  - [`ProfileFAQModels.swift`](/Users/alekseya/millio/millio/UI/Profile/ProfileFAQModels.swift)
- Почему это риск:
  - они уже знают про 3 языка, но это всё ещё ручная развилка по языку, а не масштабируемый contract;
  - для +10 языков это превращается в умножение веток и copy drift;
  - это особенно опасно там, где copy длинный и важный: destructive actions, reminders, FAQ/support text.
- Почему это пока не release-critical:
  - у этих файлов нет явной mixed-locale зависимости от `Locale.current`;
  - `zh-Hans` уже не отваливается в English fallback, то есть срочная авария закрыта.
- Что делать следующей волной:
  - `SmartDataResetLocalization` перевести на catalog-backed scoped keys;
  - `NotificationManager` перевести на key + format contract вместо ручной сборки предложений;
  - `ProfileFAQModels` оставить как structured content model, но вынести copy из ручных language branches в data source, который масштабируется без переписывания кода под каждый язык.

#### 5. Backup / restore cluster ещё слишком fallback-driven

- Файлы:
  - [`BackupLocalization.swift`](/Users/alekseya/millio/millio/UI/Profile/BackupLocalization.swift)
  - [`BackupManagementView.swift`](/Users/alekseya/millio/millio/UI/Profile/BackupManagementView.swift)
  - [`RestoreView.swift`](/Users/alekseya/millio/millio/UI/Restore/RestoreView.swift)
- Почему это риск:
  - в этом кластере уже есть полезный facade, но местами контракт всё ещё опирается на fallback-heavy подход вместо строгого key coverage;
  - это скрывает missing translations до runtime.
- Почему это пока не всё release-critical:
  - `BackupLocalization` сам по себе нормальнее старого состояния;
  - реально критичен сейчас именно `RestoreView`, а не весь backup слой целиком.
- Что делать следующей волной:
  - закрыть restore;
  - потом пройтись по backup keys и убрать места, где fallback маскирует обязательный перевод.

#### 6. Layout hardening пока слабее, чем string hardening

- Файлы/кластеры:
  - [`SubscriptionView.swift`](/Users/alekseya/millio/millio/UI/Subscription/SubscriptionView.swift)
  - [`CashbackView.swift`](/Users/alekseya/millio/millio/UI/Services/Cashback/CashbackView.swift)
  - [`FinanceDynamicsView.swift`](/Users/alekseya/millio/millio/UI/Services/Finances/FinanceDynamicsView.swift)
  - [`CashflowOperationSheets.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowOperationSheets.swift)
- Почему это риск:
  - локализация может быть правильной, а UI всё равно будет ломаться на длинных строках;
  - сейчас guards сильнее покрывают source anti-patterns, чем layout regressions.
- Почему это не immediate release blocker:
  - это уже следующий класс проблем, а не текущий системный mixed-locale bug.
- Что делать следующей волной:
  - добавить layout/policy tests на длинные строки и 3 языка для high-risk screens;
  - отдельно прогнать pseudo-locale/long-text stress scenarios.

### Acceptable / system-context-only

#### 7. System locale допустим только как input, не как product language source-of-truth

- Файлы:
  - [`QuickSetupViewModel.swift`](/Users/alekseya/millio/millio/UI/QuickSetup/QuickSetupViewModel.swift)
  - [`LocalizationSupport.swift`](/Users/alekseya/millio/millio/Core/Language/LocalizationSupport.swift)
- Что сейчас допустимо:
  - `QuickSetupSystemContext.locale = Locale.autoupdatingCurrent` допустим как system heuristic input для первичной рекомендации языка/валют;
  - parser/search aliases и system metadata тоже допустимы вне product copy contract.
- Где это уже acceptable:
  - recommendation logic;
  - OCR/search heuristics;
  - locale-sensitive format plumbing, если не выбирается словарь UI.
- Где нельзя расширять:
  - product-facing titles, buttons, alerts, CTA, empty states.

#### 8. Data/heuristics literals сами по себе не баг, пока они не лезут в product UI

- Файлы:
  - [`CashbackImportCategoryResolver.swift`](/Users/alekseya/millio/millio/UI/Services/Cashback/CashbackImportCategoryResolver.swift)
  - [`CashflowBulkExpenseImportParser.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/CashflowBulkExpenseImportParser.swift)
  - [`CurrencySelectionSupport.swift`](/Users/alekseya/millio/millio/UI/Services/Courses/CurrencySelectionSupport.swift)
  - [`ExpenseCategoryCatalog.swift`](/Users/alekseya/millio/millio/UI/Services/Cashflow/ExpenseCategoryCatalog.swift)
- Почему это acceptable:
  - это search/recognition aliases, а не UI contract;
  - там буквальные фразы неизбежны.
- Но:
  - это всё равно нужно держать отдельно от product-facing localization layer и не смешивать с UI copy.

## What was fixed in this iteration

- Убраны ещё два слабых raw-key usage в isolated views:
  - [`ErrorView.swift`](/Users/alekseya/millio/millio/UI/Error/ErrorView.swift)
  - [`ProfilePremiumCard.swift`](/Users/alekseya/millio/millio/UI/Profile/ProfilePremiumCard.swift)
- Добавлен source guard, чтобы эти regressions не вернулись:
  - [`LocalizationHotReloadTests.swift`](/Users/alekseya/millio/millioTests/Core/LocalizationHotReloadTests.swift)
- Обновлён этот документ под реальное состояние repo, а не под старую rollout-логику “прятать третий язык”.

## Recommended next wave

### Wave 1: release gates

1. Закрыть restore/recovery cluster.
   - `RestoreView`
   - restore/backup keys coverage
   - source guard против raw literals в startup recovery UI

2. Убрать literal-driven keys из core Cashflow models.
   - `CashflowViewModel`
   - `CashflowTransaction`
   - `CashflowInsightsChartModels`
   - new scoped `cashflow.*` keys

3. Вычистить raw-key rendering из release-facing UI.
   - `SubscriptionView`
   - `ProfileView`
   - `ProfilePremiumDiagnosticsView`
   - `RateAppBlock`
   - `CashflowPeriodSelectorView`
   - `CashflowScheduledTransactionsView`
   - `CashflowOperationSheets`

### Wave 2: architectural debt that will block +10 languages

1. Перевести manual multilingual helpers на catalog-backed contracts.
   - `SmartDataResetLocalization`
   - `NotificationManager`
   - `ProfileFAQModels`

2. Дожать backup cluster от fallback-driven contract к coverage-driven contract.

3. Добавить layout hardening suite на:
   - `SubscriptionView`
   - `CashbackView`
   - `FinanceDynamicsView`
   - `CashflowOperationSheets`

## Release gate before any further rollout

Новый язык или дальнейший public rollout нельзя открывать, пока не выполнены все пункты:

- нет hardcoded product-facing literals в startup/recovery flows;
- нет `Locale.current` / `Locale.autoupdatingCurrent` в product-facing copy paths;
- нет raw-key rendering в release-critical UI;
- все critical keys для `ru/en/zh-Hans` закрыты как минимум в:
  - restore/backup
  - cashflow core labels
  - subscription/legal
  - notifications/widget/shared critical copy
- есть source guards против:
  - raw `Text("key")`/`navigationTitle("key")` в release-facing screens
  - manual `ru/en` or `ru/en/zh` product branching
  - literal-driven localization keys в critical domains
- есть layout checks на high-risk screens с длинными строками.

## Engineering judgment

Что уже хорошо:

- базовый runtime contract теперь разумный;
- третьему языку больше не приходится выживать на чистом английском fallback;
- часть доменов действительно migrated, а не просто “подлатана”.

Что всё ещё плохо:

- repo всё ещё слишком зависит от implicit bundle magic;
- ручные multilingual helpers всё ещё маскируют архитектурный долг;
- часть важного UI до сих пор живёт на legacy-style contracts, которые не переживут +10 языков без новой волны переписывания.

Итог простой: локализация уже не развалена, но она ещё не пуленепробиваема. Следующая волна должна добивать не “отдельные строки”, а оставшиеся слабые контракты.
