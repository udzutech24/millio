# Plan: Backfill исторических снапшотов баланса (AccountDailySnapshot)

**Slug:** `snapshot-backfill`
**Дата создания:** 2026-07-05
**Связан с:** `plans/2026-07-05__account-detail-per-type.md` (блокер Фазы 1, Open Question №6 спеки `specs/2026-07-05-account-detail-per-type.md`)

## Статус

`РЕАЛИЗОВАН`

## Контекст

Экран деталей счёта (Ф1) хочет читать периоды графика «1Г»/«Всё» напрямую из `AccountDailySnapshot`,
не гоняя посуточный реплей `AccountsTotalsService.seriesBetween` вживую при открытии экрана.
Для этого кэш должен быть прогрет ЗАРАНЕЕ — от даты первого события каждого счёта до сегодня,
до того как пользователь откроет экран.

## Легаси-снапшоты — отдельная система, НЕ трогаем

`millio/UI/Services/Finances/AccountBalanceSnapshotService.swift` (коммит 1705922, 2026-06-21) —
независимая от ядра фича: пишет по одной точке в сутки в `AccountBalanceHistoryStore` (UserDefaults-backed,
не SwiftData) для **старых** `FinanceAccount`/`Card`/`Credit`/`Investment`. Не разделяет модели/схему
с `AccountDailySnapshot` (ядро AccountsCore), не конфликтует технически. Уходит целиком со сносом
легаси-мира в задаче 6b — этот backfill её не касается и не мигрирует.

## Решение

1. **Источник:** ядровой `AccountDailySnapshot` + существующий `AccountSnapshotRebuilder.rebuild(accountID:upTo:)`.
   У `rebuild` уже есть нужное свойство: на счёте без единого снапшота (`lastValidKey == ""`) он строит
   ВСЕ checkpoint-ы от первого события до `upTo` за один вызов — backfill не требует новой алгоритмики,
   только батчинг существующей и координацию по всем счетам.
2. **Батчинг** (`AccountSnapshotRebuilder.rebuildCheckpoints`): промежуточный `save()` каждые 200
   обработанных дней + `autoreleasepool` на каждой итерации. Раньше — одна большая транзакция на весь
   backfill счёта; уход в фон/kill системой посреди реплея откатывал всю проделанную работу. Теперь
   частичный прогресс валиден: повторный вызов продолжает с последнего РЕАЛЬНО сохранённого checkpoint-а.
3. **Триггер:** новый `AccountSnapshotBackfillCoordinator` (`millio/Core/AccountsCore/`) — вызывается
   fire-and-forget из `millioApp.runPostStartupRefreshes()` (после cold start, не блокирует UI).
   Однократно (per-scope UserDefaults флаг `migration.accountSnapshotBackfill.v1.<scopeIdentifier>`,
   `scopeIdentifier = activeDataScope.storeConfigurationName`) перебирает ВСЕ счета ядра и вызывает
   `rebuild(upTo: now)` для каждого. per-scope, а не глобальный флаг — тот же урок, что и в
   `DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded`: холодный старт сначала создаёт
   `DIContainer` на guest-сторе, общий флаг сгорел бы там и реальный user-стор не забэкфиллился бы.
4. **Дальнейшее поддержание** истории (новые события после первого забега) — НЕ зона координатора,
   этим продолжает заниматься существующий инкрементальный путь `AccountsTotalsService.balance(for:on:)`,
   вызываемый при любом обращении к тоталам/графику.

## Почему не отдельный флаг на каждый счёт / не "always re-scan"

- Отдельный per-account флаг — лишняя абстракция: `rebuild()` уже сам идемпотентен (быстрый выход по
  `lastValidKey`), per-scope флаг нужен только чтобы не гонять полный ПЕРЕБОР счетов на каждом холодном
  старте вечно (одноразовая миграция после этого релиза, не постоянный сервис).
- "Always re-scan без флага" (как `dedupeCashflowCustomCategoriesOnLaunch`) — рассмотрено и отвергнуто:
  та функция обязана гонять на каждом старте, потому что CloudKit-merge дублирует данные асинхронно вне
  контроля приложения. У backfill другая природа — это одноразовое «догнать историю до релиза», не
  постоянный защитный патч; после первого успешного прохода новых пробелов взяться неоткуда (кроме
  обычных новых событий, которые и так ловит `AccountsTotalsService`).

## Известные ограничения (приняты, не в скоупе)

- **Restore на то же устройство:** если backup был снят ДО полного backfill (частичная история снапшотов),
  а флаг для этого scope уже стоит true (создан до restore) — повторный полный забег не запустится
  автоматически после restore. Деградация не критична: `AccountsTotalsService` всё равно лениво достроит
  недостающий хвост при первом обращении к тоталам/графику этого счёта (просто первое открытие будет чуть
  медленнее, не потеря данных). Совпадает с поведением существующих миграционных флагов
  (`revertBadArchiveMigrationIfNeeded`/`archiveZeroQuantityInvestmentsIfNeeded`) — они тоже не сбрасываются
  restore.
- **Ошибка на одном счёте не блокирует остальные:** флаг ставится даже при частичных ошибках (лог
  `AppLogger` категории `AccountsCore`), чтобы единичный сбой не гонял полный бэкфилл всех счетов на
  каждом следующем старте.

## CloudKit backup — рост размера

`AccountDailySnapshot` уже зарегистрирован в `ModelTypeRegistry` (`AccountsCoreFeatureRegistration.swift`,
коммит из мержа ядра) — backfill-данные попадут в полный snapshot-бэкап автоматически, без доп. кода.

**Оценка размера:** `export()` кодирует id/dayKey/balance/isClosed/updatedAt (+account/quantity опционально)
как компактный JSON-словарь — грубо ~150–200 байт на запись. 1800 checkpoint-ов × 12 счетов ≈ 21 600 записей
× ~180 байт ≈ **~3.9 МБ** до сжатия/архивации бэкапа. Это заметно больше «сотен КБ», но не аномально для
приложения с 5-летней плотной историей — сравнимо по порядку с самими `AccountEvent` (у них сопоставимое
количество записей и больше полей). Reconciliation (guest→user merge) снапшоты НЕ импортирует через общий
путь (`ScopeMergeReader.newCoreTypeNames` явно их исключает, копирует по id через `ScopeMergeDedup.copyNewCore`
либо пересобирает после merge) — рост актуален только для ПОЛНОГО backup/restore, не для повседневного
reconciliation-потока при логине.

**Решение:** не исключать `AccountDailySnapshot` из бэкапа в этой задаче — 3.9 МБ на «тяжёлый» аккаунт с
12 счетами и 5-летней плотной историей (реалистичный верхний предел, а не типичный случай) не оправдывает
усложнение (исключение из бэкапа + гарантированная пересборка после restore — новый инвариант restore-флоу,
доп. риск в зоне повышенного риска Backup/Restore). Если после релиза телеметрия/жалобы покажут реальный
рост бэкапа за пределы разумного — отдельная задача на exclude-and-rebuild, не блокер этой фазы.

## Фазы

### `[x]` Фаза 1: Батчинг рёбилдера + координатор + триггер

**Файлы:**
- `millio/Core/AccountsCore/AccountSnapshotRebuilder.swift` — батч-save (200 дней) + autoreleasepool
- `millio/Core/AccountsCore/AccountSnapshotBackfillCoordinator.swift` — новый
- `millio/millioApp.swift` — wiring (AppDependencyBinding, prepareDependencyBinding, applyDependencyBinding, runPostStartupRefreshes)

**Тесты:** `millioTests/Core/AccountsCore/AccountSnapshotBackfillCoordinatorTests.swift`
- backfill строит снапшоты от первого события до `now` (разреженный кэш — только дни событий)
- второй забег — no-op после того как флаг стоит (даже если появилось новое событие)
- разные `scopeIdentifier` не делят флаг
- счёт без единого события не роняет бэкфилл
- архивный счёт — checkpoint-ы не строятся после `archivedAt`
- redenomination — снапшот хранит пост-деноминационное значение (совпадает с прямым реплеем `AccountBalanceEngine`)
- несколько счетов — каждый обработан независимо

**Self-audit:** batched save не меняет конечный результат (существующие `AccountSnapshotRebuilderTests`
проходят без изменений — проверяют только конечное состояние, не количество save-вызовов).

**Impact analysis:** батчинг применяется и к `rebuildAll`/`rebuildAllAccounts()` (debug-кнопка «Пересобрать
кэш», `ScopeReconciliationService`) — тот же выигрыш в безопасности для них бесплатно, без изменения их
публичного контракта.

## Открытые вопросы владельцу

Нет блокирующих. Ограничение по restore (см. выше) — принято как компромисс, не требует решения сейчас.
