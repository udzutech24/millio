# План: self-heal легаси-миграции после restore/переустановки

**Дата:** 2026-07-12 · **Статус:** РЕАЛИЗОВАН (ждёт ручной проверки на устройстве) · **Размер:** M (5 файлов)
**Ветка:** `feature/legacy-migration-self-heal` (локально, НЕ запушено)

## Контекст

Диагноз: `progress/2026-07-11-migration-flag-restore-bug.md` (доказан на симуляторе 2026-07-11).
Стресс-тест фикса: субагент millio-audit, 2026-07-12 (в сессии).

Воспроизведено на реальном устройстве владельца 2026-07-12: переустановка приложения → restore
старого CloudKit-бэкапа (снят до AccountsCore) → Дашборд/Счета показывают 0 (−100%), Динамика —
верные суммы (считает из легаси-скелета отдельным путём). Это единственный реальный пользователь
Millio сейчас, его личные финансовые данные (см. `millio-single-real-user-risk-calibration`).

## Root cause (два независимых гейта, оба переживают restore)

1. `migration.legacyAccountsPurge.v1.<scope>` — UserDefaults-флаг, ставится в
   `LegacyAccountsMigrator.swift:73–79` после успешной миграции (`summary.failures == 0`).
2. `legacy_account_conversions_v1` — реестр `LegacyConversionRegistry.swift:14–15` (тоже
   `UserDefaults.standard`), гейт `guard !registry.isConverted` в
   `LegacyAccountsMigrator.swift:225` пропускает уже сконвертированные легаси-ID **без проверки**,
   существует ли core-двойник в ТЕКУЩЕМ сторе — `Account` (`Core/AccountsCore/Account.swift`) не
   хранит `legacyUniqueID` вообще, связь легаси→core есть только в реестре
   (`LegacyAccountConverter.swift:59` `registry.record(...)`).

Restore заменяет стор (легаси-таблицы возвращаются из старого бэкапа, core пуст), но НЕ трогает
UserDefaults → оба гейта стоят → повторная миграция не выполняется → счета невидимы навсегда.

## Фикс — 2 части

### Часть A — coarse-detection в `LegacyAccountsMigrator`

Перед консультацией с флагом/реестром — дешёвая проверка (`fetchCount`, НЕ full-fetch):
`core Account count == 0 AND (Card+FinanceAccount+Investment) count > 0` → состояние "стор заменён
без ядра". В этом случае:
- Флаг `migration.legacyAccountsPurge.v1.<scope>` игнорируется/сбрасывается.
- Реестр `LegacyConversionRegistry` для этого scope сбрасывается (иначе гейт `:225` продолжит
  скипать те же legacy ID — это и есть слепое пятно исходного диагноза, найденное стресс-тестом).
- Затем — обычный `migrateAll` по уже существующей идемпотентной логике.

Если `core count > 0` (обычный холодный старт, ядро уже живое) — детект не срабатывает, флаг/реестр
работают как short-circuit как сейчас (без лишней нагрузки на диск).

**НЕ делать:** per-record проверку "есть ли core-двойник у каждого legacy ID" — `Account` не хранит
`legacyUniqueID`, обратное сопоставление дорогое и не нужно для этого сценария (полный вайп core).

### Часть B — restore вызывает детект инлайн

`BackupManager.swift:645–674` (restore-флоу) после успешного импорта стора — явный вызов
coarse-detection + при срабатывании миграции, а не только полагаться на следующий relaunch
(millio-audit: "без relaunch счета невидимы даже с self-heal").

## Файлы (фактические пути — уточнены при реализации)

1. `millio/UI/Services/Finances/LegacyAccountsMigrator.swift` — coarse-detection (`storeReplacedWithoutCore`,
   только `fetchCount`) + сброс флага (`defaults.removeObject`) и реестра (`resetRegistryForCurrentStore`)
   в начале `migrateIfNeeded`. Мигратор лежит в UI/Services/Finances, НЕ в Core/AccountsCore (план
   указывал условный путь).
2. `millio/Core/AccountsCore/LegacyConversionRegistry.swift` — `removeAll(legacyUniqueIDs:)` (точечный
   сброс записей текущего стора; другие scope в общем словаре не трогаются).
3. `millio/millioApp.swift:604` — БЕЗ изменений (сигнатура `migrateIfNeeded` не менялась, cold-start
   вызов работает как есть; проверено).
4. `millio/Core/Backup/BackupManager.swift` — хук `onDidReplaceStore: (@MainActor () async -> Void)?`
   (оба init) + вызов `await onDidReplaceStore?()` после успешного импорта в
   `replaceRepositoryDataWithBackup` (rollback-ветка перебрасывает ошибку → хук не срабатывает).
5. `millio/Core/DI/DIContainer.swift` — проводка хука: запускает `LegacyAccountsMigrator.migrateIfNeeded`
   на актуальном `modelContext`/`scopeIdentifier`. GroupsMigrator НЕ вызывается (его флаг после restore
   stale → гарантированный no-op, поля групп косметические, не баг видимости).

## Риски и обязательные проверки (из стресс-теста)

- Идемпотентность на уже мигрированных данных подтверждена (`archivedAt` STORED + реестр) — новый
  код не должен эту гарантию сломать.
- Гонки: нет (`@MainActor`, синхронный `migrateAll`, отдельные сторы per scope).
- Флаг НЕ синкается через iCloud (обычный `UserDefaults.standard`) — сброс на одном устройстве не
  затрагивает другие устройства владельца.
- CloudKit офлайн на старте не мешает (`millioApp.swift:599` — миграция без сети).
- Adversarial-хвост — РАЗОБРАН: `exportedModelCount` (`millioApp.swift:891`, primary-путь
  `sqliteUserDataCount` считает ВСЕ Z-таблицы, включая легаси) → легаси-only стор рапортует
  `localDataCount > 0`, т.е. `presentRestoreFlowIfNeeded` (`:979`) видит его «непустым» и НЕ предлагает
  свежий restore. Для нашего дизайна это КОРРЕКТНО: легаси-only стор лечится self-heal-миграцией
  (Часть A/B), а не restore-флоу — механизмы разделены правильно, доп. фикс в `presentRestoreFlowIfNeeded`
  НЕ нужен. Зафиксировано регресс-тестом `legacyOnlyStore_countsAsNonEmpty` (AC5), чтобы будущая правка
  счётчика не сломала разграничение.

## Acceptance criteria / тесты

- [x] Юнит-тест: core пуст + легаси непустой + флаг стоит + реестр непустой → миграция запускается,
      счета появляются в ядре. → `LegacyMigrationSelfHealTests.selfHeal_rebuildsCoreDespiteStaleFlagAndRegistry`.
- [x] Юнит-тест: core непустой (обычное состояние) → coarse-detection не срабатывает (гейт на
      `Account count == 0`), флаг-short-circuit сохранён. → `normalState_detectionDoesNotFire_flagShortCircuits`.
      (детект по построению делает только `fetchCount(Account)` на обычном старте — см. код-коммент).
- [x] Юнит-тест: повторный запуск после успешного self-heal → идемпотентно, без дублей. →
      `repeatedRunAfterSelfHeal_isIdempotent` (+ `emptyStore_doesNotTriggerSelfHeal`).
- [x] Тест на restore-флоу без relaunch: BackupManager дёргает `onDidReplaceStore` ровно 1 раз на успех
      и 0 раз на откат → `testRestoreFiresStoreReplacedHookOnSuccess` / `testRestoreDoesNotFireHookOnRollback`;
      сама работа хука (миграция легаси-only стора) покрыта AC1. Вместе доказывают «restore → счета видны».
- [x] Адверсариальный AC5: легаси-only стор считается «непустым» recovery-счётчиком →
      `legacyOnlyStore_countsAsNonEmpty` (разграничение self-heal vs restore-флоу зафиксировано).
- [ ] Ручная проверка на устройстве владельца: повторить сценарий (или дождаться подтверждения, что
      текущее сломанное состояние устройства самолечится после установки фикса). PENDING — нужен билд
      на устройство (владелец).

## Журнал

- 2026-07-12: план создан по итогам диагноза (progress/) + стресс-теста (millio-audit, opus).
- 2026-07-12: реализовано целиком на ветке `feature/legacy-migration-self-heal` (Александр).
  - Часть A: `LegacyAccountsMigrator.storeReplacedWithoutCore()` (только `fetchCount`) +
    `resetRegistryForCurrentStore()` в `migrateIfNeeded`; `LegacyConversionRegistry.removeAll(legacyUniqueIDs:)`.
  - Часть B: хук `onDidReplaceStore` в actor `BackupManager` (вызов после успешного импорта) +
    проводка в `DIContainer` (запуск мигратора на актуальном контексте/скоупе).
  - Уточнение путей: мигратор фактически в `millio/UI/Services/Finances/`, реестр/конвертер — в
    `millio/Core/AccountsCore/`.
  - Решение ментора (KISS): GroupsMigrator НЕ включён в self-heal-хук — его флаг после restore stale
    (гарантированный no-op), поля групп косметические, вне доказанного бага. Если позже потребуется
    самолечение косметики групп — отдельная задача.
  - 5 AC покрыты юнит-тестами (`LegacyMigrationSelfHealTests` + 2 хук-теста в `BackupManagerTests`);
    остаётся device-проверка владельца (PENDING).
