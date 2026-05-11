# Spec: Language Switch Hardening

## Статус: НЕ НАЧАТ

## Проблема

При смене языка внутри приложения (Profile → Language) UI не обновляется — или обновляется частично. Воспроизводится для EN и, предположительно, для zh-Hans.

## Цель

Все экраны приложения корректно отображают выбранный язык без перезапуска приложения.

## Acceptance Criteria

1. После смены языка в профиле **все** видимые экраны (Dashboard, Cashflow, Finances, Profile, Settings, onboarding-flows) отображают текст на выбранном языке.
2. zh-Hans: если ключ переведён в `Localizable.xcstrings` — показывается китайский текст.
3. Переключение туда-обратно (RU → EN → RU) не приводит к лингвистическим артефактам.
4. Unit-тесты покрывают: `BundleLanguageOverride.apply()` возвращает правильный bundle для каждого из 3 языков; `LanguageManager.setLanguage()` меняет `currentLanguage`; `LocalizationHotReloadTests` проходят для всех 3 языков.
5. Нет регрессий в backup/restore flow, onboarding, cashflow.

## Scope

**In scope:**
- Диагностика и фикс `BundleLanguageOverride` / `LanguageManager`
- Тесты механизма смены языка
- Фикс экранов, которые не получают `languageRefreshToken` в иерархии (если применимо)
- RestoreView — убрать hardcoded RU literals (блокер zh-Hans)

**Out of scope (отдельная задача):**
- Унификация 4 моделей локализации в одну
- Перевод Cashflow generic-keys на scoped keys
- Добавление новых переводов в xcstrings

## Риски

- `BundleLanguageOverride` использует ObjC swizzling — хрупко при обновлении iOS или Swift.
- `.xcstrings` на новых iOS может обходить `localizedString(forKey:)` — нужна верификация.
- Любое изменение в bundle-механизме может сломать работавшие сценарии.
