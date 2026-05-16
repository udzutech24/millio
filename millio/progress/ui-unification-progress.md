# UI Unification — Phase 1+2+3 Progress

Дата: 2026-05-16
Статус: РЕАЛИЗОВАН (Phase 1+2+3)
Ветка: develop (смержено из feature/ui-unification-foundation)

## Что создано (Phase 1)

- **AppTypography.swift** — 19 Font-токенов (display, title, headline, subheadline, body, callout, caption, micro)
- **AppSpacing.swift** — 8 констант (xs=4, s=8, m=12, ml=14, l=16, xl=20, xxl=24, xxxl=32)
- **AppAnimation.swift** — 6 анимаций (standard, medium, fast, easeOut, spring, springGentle)

## Мигрированные экраны (Phase 2+3)

### AppLockScreenView.swift (Phase 2 — POC)
- Файл: `millio/UI/Security/AppLockScreenView.swift` (171 строк)
- Заменено Font хардкодов: 5
- Заменено padding/spacing хардкодов: 11

### Phase 3 — дополнительные экраны и компоненты

| Файл | Fonts | Spacing | Animation |
|------|-------|---------|-----------|
| `millio/UI/Shared/ToastView.swift` | 2 | 5 | 1 |
| `millio/UI/Shared/InlineSearchBar.swift` | — | 2 | — |
| `millio/UI/Services/Cashflow/CashflowCategoryHelpSheet.swift` | 2 | 4 | — |
| `millio/UI/Dashboard/Widgets/QuickActionsWidget.swift` | 2 | — | — |
| `millio/UI/Dashboard/DashboardDeltaPeriodPickerSheet.swift` | 1 | 4 | — |

**Итого Phase 3:** 7 font-токенов, 15 spacing-токенов, 1 animation-токен

## Research-находки

### Font паттерны (до унификации)
- `size: 52, .semibold` → millioDisplayLarge (hero-иконка AppLock)
- `size: 30, .bold` → millioDisplay
- `size: 24, .bold` → millioTitle / `size: 24, .medium` → millioTitle2
- `size: 20, .semibold` → millioTitle3
- `size: 16, .semibold/.bold` → millioHeadline / millioHeadlineBold
- `size: 15, .semibold/.medium` → millioSubheadline / millioSubheadlineMedium
- `size: 14, .semibold/.medium/.regular` → millioBodySemibold / millioBody / millioBodyRegular
- `size: 13, .semibold/.medium/.regular` → millioCalloutSemibold / millioCallout / millioCalloutRegular (наиболее частый)
- `size: 12, .medium/.regular` → millioCaption / millioCaptionRegular
- `size: 11, .semibold` → millioCaption2
- `size: 10, .medium` → millioMicro

### Spacing паттерны (до унификации, топ по частоте)
- `.padding(16)` — 34 вхождения → AppSpacing.l
- `.padding(14)` — 20 вхождений → AppSpacing.ml
- `.padding(12)` — 20 вхождений → AppSpacing.m
- `.padding(10)` — 7 вхождений (нет в системе — ближайший AppSpacing.s=8 или m=12)
- `.padding(20)` — 4 вхождения → AppSpacing.xl
- `.padding(4)` — 4 вхождения → AppSpacing.xs
- `.padding(24)` — 2 вхождения → AppSpacing.xxl

### Animation паттерны (до унификации)
- `.easeInOut(duration: 0.2)` — 5× → AppAnimation.standard
- `.easeInOut(duration: 0.25)` — 4× → AppAnimation.medium
- `.easeOut(duration: 0.2)` — 2× → AppAnimation.easeOut
- `.easeInOut(duration: 0.18)` — 2× → AppAnimation.fast
- `.spring(response: 0.3, dampingFraction: 0.8)` — 2× → AppAnimation.spring
- `.spring(response: 0.42, dampingFraction: 0.88)` — 2× → AppAnimation.springGentle

## Билд и тесты

- **BUILD SUCCEEDED** — все фазы не нарушили компиляцию
- **TEST FAILED (pre-existing)** — следующие тесты падали до UI-unification и не связаны с ним:
  - `QuickSetupViewModelTests` → ПОЧИНЕНО: обновлена сигнатура `SupportContactConfig` (убран `whatsappNumber`, добавлен `telegramChannelHandle`)
  - `CashflowCategoryHelpContentTests` → L() vs String(localized:) несовместимость в тестах
  - `AppLockPinStoreTests` → Keychain нестабильно в симуляторе без прав
  - `ProfileLocalizationTests/testProfileNestedFlowLocalizationInSimplifiedChinese` → zh-Hans gap
  - `CashflowTransactionEditorViewLayoutTests` → L() vs String(localized:) несовместимость

## Что осталось

- [ ] Продолжить миграцию оставшихся экранов (OnboardingView, ProfileView верхняя часть и др.)
- [ ] Добавить правило в CLAUDE.md: новый код использует только AppTypography/AppSpacing/AppAnimation
- [ ] Отдельная задача `color-hardcode-cleanup` — заменить 840+ `Color.white` на AppColors
- [ ] Отдельная задача `accessibility-audit` — поднять a11y с ~10% до 80%+
- [ ] Починить pre-existing баги тестов: L() vs String(localized:) несовместимость (отдельный тикет)
- [ ] AppLockPinStoreTests — нужен флаг entitlement или mock для Keychain в тестах
