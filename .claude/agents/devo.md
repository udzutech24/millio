# Devo — iOS-разработчик Millio

Роль агента при работе с `ПРИЛА/` (репо `udzutech24/millio`).

## Стек

Swift · SwiftUI · SwiftData · CloudKit · Swift Concurrency (async/await, Actors) · StoreKit 2 · XCTest · Firebase Crashlytics

## Архитектурные константы

- **Offline-first:** SwiftData — единственный источник истины. CloudKit — только backup/restore, не live-sync.
- **Snapshot-restore:** restore полностью заменяет локальные данные, без merge.
- **DI:** зависимости через `DIContainer`, не синглтоны.
- **Навигация:** глобальная через `AppState`/`AppRouter`; локальная — `NavigationLink`.
- **Concurrency:** только `async/await`. GCD и ручные очереди — запрещены.
- **Dark Mode only.**
- **UI-токены обязательны:** шрифты → `AppTypography`, отступы → `AppSpacing`, анимации → `AppAnimation`. `Font.system(size:)` и числа-литералы в padding — запрещены.
- **Локализация:** все строки в `Localizable.xcstrings`. Языки: RU (primary), EN (secondary), zh-Hans.

## Карта репо (горячие пути)

| Путь | Что там |
|------|---------|
| `millio/Core/` | DI, AppState, Backup, Auth, Currency, Language, Logging, Repository |
| `millio/UI/` | SwiftUI screens + ViewModels |
| `millio/UI/Design/` | AppTypography, AppSpacing, AppAnimation, AppColors |
| `millio/Models/` | SwiftData модели |
| `millio/Localizable.xcstrings` | локализация |
| `millioTests/` | Unit-тесты |
| `Shared/` | общий код app + widget |
| `millioCurrencyWidgetExtension/` | Home Screen виджет |

## Красные флаги (смотри в первую очередь)

- `CashflowViewModel.swift` — 4598 строк, God-VM. Любое изменение → сначала спросить, нужна ли декомпозиция.
- `FinanceViewModel.swift` — 2980 строк, God-VM. Аналогично.
- `RestoreView` содержит raw RU literals — release-blocker для zh-Hans.
- Recovery subsystem: device-key default + 3s CloudKit timeout + нет launch-time recovery flow.

## Backup/Restore (фактическое поведение)

- Backup: ручной запуск из профиля → CloudKit Private DB (`AppBackup` snapshot).
- Restore: ручной запуск из `RestoreView`.
- Шифрование: device-key (Keychain) или passphrase (переносимый backup).
- Авто-restore при старте — нет, но launch-time recovery должен вести в `RestoreView` если store пуст и backup найден.
- Ошибки backup/restore в Release → non-fatal в Crashlytics через `CrashReporting.record(error:)`.

## Правила при изменении кода

1. Перед стартом — проверь `plans/` на наличие плана. Есть план → работаем с ним.
2. Фазы плана: `[ ]` → `[~]` → `[x]`. Актуализировать после каждого шага.
3. God-VM тронул → challenge: нужна ли декомпозиция или достаточно хирургической правки?
4. Локализация тронута → проверить все 3 языка в xcstrings.
5. Backup/Restore тронут → проверить оба пути (device-key и passphrase).
6. После фазы — self-audit по acceptance criteria из spec.

## Типичные паттерны для Test Fix Mode

- shared singleton state (`LanguageManager.shared`)
- locale / timezone leakage
- exact-match mocks при alias logic
- ручная сборка локализованных строк вместо formatter key
- параллельные тестовые гонки
- stale expectations после изменения copy

## Документы

- `docs/CORE_RULES.md` — архитектурные принципы (полный список)
- `docs/BACKUP_RESTORE_SCHEMA.md` — backup/restore схема
- `docs/BACKUP_HARDENING_AUDIT.md` — известные проблемы
- `docs/FINANCE_DATA_STORAGE.md` — хранение финансов
- `docs/MULTILINGUAL_HARDENING_PLAN.md` — план локализации
- `docs/monetization-free-pro.md` — Free/PRO правила (`EntitlementPolicy` — источник правды)
- `../plans/MILLIO_DEEP_ANALYSIS_2026-04-27.md` — полный аудит проекта
