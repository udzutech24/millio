# Millio (iOS) — CLAUDE.md

Точка входа для любого чата по iOS-приложению Millio. **Не вываливай в контекст всю кодбазу** — ссылайся на пути, подгружай только то, что нужно для текущей задачи.

## Язык общения
**Всегда отвечай на русском.** Комментарии в коде — на русском. Имена файлов/путей — английские (kebab-case).

## Что это

**Millio iOS** — offline-first приложение для управления личными финансами (учёт расходов, бюджеты, инвестиции, cashback) на SwiftUI + SwiftData + CloudKit. Главный продукт компании, см. [`../.business/products/product-millio.md`](../.business/products/product-millio.md).

## Стек

Swift · SwiftUI · SwiftData · CloudKit · Swift Concurrency (async/await, Actors) · XCTest · Firebase Crashlytics · StoreKit 2

## Карта репозитория

| Путь | Назначение |
|------|-----------|
| [millio/](millio/) | Основной таргет приложения |
| [millio/Core/](millio/Core/) | Ядро (DI, AppState, Backup, Auth, Currency, Language, Logging, Repository, ...) |
| [millio/UI/](millio/UI/) | SwiftUI экраны, ViewModels |
| [millio/Models/](millio/Models/) | SwiftData модели |
| [millio/Localizable.xcstrings](millio/Localizable.xcstrings) | Локализация (RU/EN/zh-Hans) |
| [millioTests/](millioTests/) | Unit-тесты (Core + UI/policy + L10n + hapticsplan) |
| [millioUITests/](millioUITests/) | UI-тесты |
| [millioCurrencyWidgetExtension/](millioCurrencyWidgetExtension/) | Home Screen widget (курсы валют) |
| [Shared/](Shared/) | Общий код между app и widget |
| [docs/](docs/) | Доменная документация (см. ниже) |
| [AGENTS.md](AGENTS.md) | Роль ментора, инженерия, безопасность, диалог |
| [WORKFLOW-PROMPT.md](WORKFLOW-PROMPT.md) | Мастер-промпт для новой задачи (классификация S/M/L) |
| [prompts.md](prompts.md) | 15 промтов методологии (Continuous Improvement, Self-Audit, ...) |
| [specs/](specs/) | WHAT + WHY каждой фичи |
| [plans/](plans/) | HOW — технические планы фаз |
| [thoughts/research/](thoughts/research/) | Research-артефакты (Stage 1) |
| [progress/](progress/) | Handoff между сессиями |
| [improvements/](improvements/) | Наблюдения по росту (agents/tokens/process/business) |
| [templates/](templates/) | Шаблоны для research/spec/plan/handoff/reflection |
| [scripts/](scripts/) | new-feature.sh, telemetry, validate-placeholders |
| [.claude/](.claude/) | settings.json, hooks, commands, skills/CATALOG.md |

Бизнес-контекст (общий на компанию): [`../.business/INDEX.md`](../.business/INDEX.md).

## Принципы разработки

### KISS — Keep It Simple
- Простота превыше всего. Один метод/класс = одна ответственность. Не создавай абстракций «на будущее».

### SOLID
- **S:** ViewModel отвечает только за свою область, Service — только за свой API.
- **O:** Расширяемость через протоколы (`DataSource`, `BackupEncryptionProtocol`).
- **L:** Mock полностью заменяет реальный сервис (`MockUserService`).
- **I:** Узкие протоколы (`UserFetcher`, `UserDeleter`), а не один большой.
- **D:** Зависимости от абстракций (DI через `DIContainer`).

### Проектные правила (кратко)

- **Offline-first:** SwiftData — единственный источник истины.
- **CloudKit только для backup/restore.** Не для live-sync.
- **Snapshot-restore:** без merge, restore полностью заменяет локальные данные.
- **Навигация:** глобально через `AppState`/`AppRouter`; локальные переходы — `NavigationLink`.
- **Concurrency:** `async/await`, без GCD и ручных очередей.
- **Dark Mode only.**
- **UI-токены обязательны:** шрифты — только через `Font` extension (`AppTypography.swift`), отступы — только через `AppSpacing`, анимации — только через `AppAnimation`. `Font.system(size:)` и числа-литералы в padding/spacing в новом коде **запрещены**. Файлы: `millio/UI/Design/`.
- **Локализация:** все строки в `Localizable.xcstrings`. Подробности — [`docs/MULTILINGUAL_HARDENING_PLAN.md`](docs/MULTILINGUAL_HARDENING_PLAN.md).

Полный список правил — [`docs/CORE_RULES.md`](docs/CORE_RULES.md).

## Backup/Restore — фактическое поведение

- Backup запускается **руками** в профиле.
- Backup хранится в **CloudKit Private DB** (`AppBackup` snapshot history + legacy `latest_backup`).
- Restore запускается **вручную** из профиля (экран `RestoreView`).
- Авто-restore при старте — нет, но launch-time recovery flow должен переводить пользователя в `RestoreView`, если локальный store пуст, а backup найден.
- В профиле — экран управления backup: включение, статус, ручной backup/restore, выбор режима шифрования.
- Шифрование backup: **device-key** (Keychain) и **passphrase** (переносимый backup).
- В Release ошибки backup/restore — non-fatal в Crashlytics через `CrashReporting.record(error:)`.

Подробнее: [`docs/BACKUP_RESTORE_SCHEMA.md`](docs/BACKUP_RESTORE_SCHEMA.md). Известные проблемы и план hardening: [`docs/BACKUP_HARDENING_AUDIT.md`](docs/BACKUP_HARDENING_AUDIT.md).

## Документация (`docs/`)

- [`CORE_RULES.md`](docs/CORE_RULES.md) — архитектурные принципы
- [`CORE_STATUS.md`](docs/CORE_STATUS.md) — текущее состояние и компромиссы
- [`BACKUP_RESTORE_SCHEMA.md`](docs/BACKUP_RESTORE_SCHEMA.md) — backup/restore
- [`BACKUP_HARDENING_AUDIT.md`](docs/BACKUP_HARDENING_AUDIT.md) — известные проблемы recovery
- [`FINANCE_DATA_STORAGE.md`](docs/FINANCE_DATA_STORAGE.md) — хранение финансов
- [`MULTILINGUAL_HARDENING_PLAN.md`](docs/MULTILINGUAL_HARDENING_PLAN.md) — план локализации
- [`monetization-free-pro.md`](docs/monetization-free-pro.md) — Free/PRO правила (источник правды — `EntitlementPolicy`)
- [`TESTFLIGHT_RELEASE.md`](docs/TESTFLIGHT_RELEASE.md), [`CRASHLYTICS.md`](docs/CRASHLYTICS.md), [`AUTH_LOCAL_BACKEND.md`](docs/AUTH_LOCAL_BACKEND.md), и др.

## Управление контекстом (обязательно)

Правила важнее скорости. Лучше лишний `/clear`, чем работать в Dumb Zone.

**1. Правило 40%.** Держи контекст 40–60% окна. На **50% — ручной `/compact`**, не жди автокомпакта. Перегрузился — handoff в [`progress/`](progress/), `/clear`, начни заново.

**2. Progressive Disclosure.** Не вываливай всю кодбазу. Research — через `Explore`-агентов с саммари ≤200 слов. Planning — саммари + ключевые интерфейсы. Implementation — только файлы текущей фазы. В `CLAUDE.md` ссылайся на пути, не `@`-импортируй файлы.

**3. Read узкими диапазонами.** Сначала `Grep` по символу/строке, потом `Read` с `offset`/`limit` ±30–50 строк. Полный `Read` без параметров — только для файлов <200 строк. Для файлов >500 строк полный `Read` запрещён. Особенно: `CashflowViewModel.swift` (4598 строк) и `FinanceViewModel.swift` (2980 строк) — **никогда** полным Read'ом.

**4. Ресёрч — через `Explore`-агента.** Если >3 поисков или вопрос «где что / как работает X» — `Agent` с `subagent_type: Explore`, бери компактное саммари.

**5. Граф знаний.** Если построен `graphify-out/graph.json` — сначала `/graphify query "..."`, потом точечный Read.

**6. Антипаттерны.** Full Read крупных файлов «на всякий случай»; Bash с большим stdout (фильтруй `| head -20`); цепочки Grep без делегирования; thinking на раздутом контексте.

## Workflow для новой фичи

| Размер | Стадии | Артефакты |
|--------|--------|-----------|
| **S** (1-2 файла, багфикс) | research → implement → verify | self-audit |
| **M** (3-10 файлов) | research → spec → plan → phased impl → audit → impact | thoughts/ + specs/ + plans/ |
| **L** (10+ файлов, архитектура) | полный Bulletproof 12 стадий | + handoff/ + code review + security scan |

Инстанцирование артефактов — через `/new-feature <slug>` или `scripts/new-feature.sh <slug>`.

Детали: см. [`WORKFLOW-PROMPT.md`](WORKFLOW-PROMPT.md). Полный набор промтов: [`prompts.md`](prompts.md).

## Правила реализации

- **План для каждой функции** — `plans/YYYY-MM-DD__<feature-slug>.md`. Дата создания не меняется при обновлениях.
- **Перед стартом работы — проверь `plans/`.** Есть план — работаем с ним. Нет — создаём через `/new-feature`.
- **Состояния фаз:** `[ ]` / `[~]` / `[x]`. Под фазой — что сделано / что осталось.
- **Статусы плана:** `НЕ НАЧАТ` / `В РАБОТЕ` / `РЕАЛИЗОВАН` / `ЗАБЛОКИРОВАН`.
- **Любой агент обязан актуализировать план:** отмечать фазы, фиксировать итог.
- **Guard phrase:** без явной команды «Реализуй фазу N по плану» — только чтение и планы, код не пиши.
- **Challenge Loop** перед финализацией: (1) решает ли проблему? (2) самое эффективное? (3) нет ли кода ради кода?
- **Self-audit** после каждой фазы: все acceptance criteria из spec покрыты.
- **Impact analysis** перед мержем: регрессия, side effects, compatibility, edge cases.

## Git-дисциплина

- Каждая задача = feature-бранч `feature/<task>`.
- Коммит после каждого пройденного gate (checkpoint).
- НЕ пушить в `develop`/`master` напрямую без обсуждения. Squash merge на завершении.
- Remote: GitHub `udzutech24/millio`. GitLab отключён.

## Завершение каждой сессии (обязательно)

1. **Рефлексия** на русском — `../.business/история/YYYY-MM-DD-краткое-название.md` (шаблон [`templates/reflection.md`](templates/reflection.md)):
   - Задача / как решалась / решена ли / эффективно ли / было → стало / **идеи по улучшению**.
2. **Актуализация плана** — статус, чеклисты фаз, журнал.
3. **Continuous improvement** — если в сессии были:
   - неэффективные правки / лишние Read / перегруз контекста → [`improvements/tokens/`](improvements/tokens/) или [`improvements/process/`](improvements/process/);
   - тупой ответ агента / некорректный подход → [`improvements/agents/`](improvements/agents/);
   - возможность для бизнеса (новая ниша, оптимизация юнит-экономики) → [`improvements/business/`](improvements/business/).

Без этих трёх шагов чат не считается завершённым.

## Тест Fix Mode

При работе с падающими тестами / flaky tests / регрессиями — особый режим. См. секцию **Test Fix Mode** в [AGENTS.md](AGENTS.md).

Типичные паттерны для подозрения:
- shared singleton state (`LanguageManager.shared`)
- locale / timezone leakage
- exact-match mocks при alias logic
- ручная сборка локализованных строк вместо formatter key
- параллельные тестовые гонки
- stale expectations после изменения copy

## Ключевые точки внимания (по результатам анализа 2026-04-27)

См. полный отчёт: [`../plans/MILLIO_DEEP_ANALYSIS_2026-04-27.md`](../plans/MILLIO_DEEP_ANALYSIS_2026-04-27.md).

- **Recovery subsystem не пуленепробиваема** (device-key default + 3s CloudKit timeout + нет launch-time recovery). Перед публичным roll-out — Phase 0 из анализа.
- **God-VM:** `CashflowViewModel.swift` (4598 строк) и `FinanceViewModel.swift` (2980 строк). Любое изменение в Cashflow/Finance — сначала проверять, нужна ли декомпозиция.
- **`RestoreView` с raw RU literals** — release-blocker для zh-Hans.
- **Beta-флаги монетизации** открыты всем — закрытие требует grandfathering plan, см. [`../.business/products/pricing.md`](../.business/products/pricing.md).

## Ссылки

- [AGENTS.md](AGENTS.md) — инженерная дисциплина, диалог, безопасность, Test Fix Mode
- [WORKFLOW-PROMPT.md](WORKFLOW-PROMPT.md) — мастер-промпт
- [prompts.md](prompts.md) — 15 промтов методологии
- [`../.business/INDEX.md`](../.business/INDEX.md) — бизнес-контекст
- [`../CLAUDE.md`](../CLAUDE.md) — мастер-карта workspace
