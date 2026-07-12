# План: self-heal легаси-миграции после restore/переустановки

**Дата:** 2026-07-12 · **Статус:** РЕАЛИЗОВАН И ПОДТВЕРЖДЁН НА УСТРОЙСТВЕ · **Размер:** M (5 файлов)
**Ветка:** `feature/legacy-migration-self-heal` → squash-merge в `develop` (`43dca91`), запушено в origin.

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

## Root cause #2 — НАСТОЯЩИЙ (найден на устройстве, 5 раундов, 2026-07-12): триггер-гэп при async scope-swap

Self-heal (Часть A/B ниже) был **необходим, но недостаточен**: он чинит логику миграции, но её надо
ещё и **вызвать** для нужного scope. Оказалось — не вызывается.

`runLegacyAccountsMigrationIfNeeded()` (`millioApp.swift:604`) исполнялся РОВНО ОДИН РАЗ — из
cold-start-замыкания `onScopeResolved` (`initializeColdStart:262`), на scope, что резолвится СИНХРОННО
на холодном старте. В реальном кейсе владельца это — `guest` (auth restore ещё не поднял user-сессию).
Переключение на `user` scope происходит ПОЗЖЕ, отдельным АСИНХРОННЫМ путём: `onSessionChanged`
(`:334-340`) → `synchronizeDataScope(with: user)` с `onScopeResolved: nil` (дефолт) → `rebindDataScope`
свопает `activeModelContainer`/`diContainer` на user, но миграцию **НЕ переигрывает**.

Итог (подтверждён логом устройства): user-стор (`millio_user_d977e6e…`) имеет `core.Account = 0` при
`legacy.Card = 17, legacy.FinanceAccount = 63, legacy.Investment = 44` (124 немигрированные легаси-записи) —
ровно тот случай, для которого self-heal и создавался (`storeReplacedWithoutCore`), но который для этого
scope НИКОГДА не запускался. Исходный план (стр. «millioApp.swift — БЕЗ изменений») промахнулся: он
проверял cold-start-вызов, не async-своп.

**Фикс #2:** `await runLegacyAccountsMigrationIfNeeded()` добавлен в `rebindDataScope` СТРОГО ПОСЛЕ свопа
`diContainer` (после `applyDependencyBinding`). `rebindDataScope` — единый choke-point активации
контейнера (и cold-start, и async login/logout идут через него), поэтому миграция гарантированно
запускается для КАЖДОГО scope, чей контейнер становится активным. Двойной вызов на cold-start (свор
через rebindDataScope + повтор через `onScopeResolved:262`) безопасен: повторный прогон — дешёвый no-op
(один `fetchCount(Account)` + флаг-short-circuit).

## Фикс — 2 части (self-heal логики) + Фикс #2 (триггер)

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
3. `millio/millioApp.swift` — **ИЗМЕНЁН** (правка исходного ошибочного вывода «БЕЗ изменений»).
   Root cause #2: вызов `await runLegacyAccountsMigrationIfNeeded()` добавлен в `rebindDataScope`
   ПОСЛЕ `applyDependencyBinding` (внутри `if let backendRuntime, let binding`) — миграция триггерится
   на КАЖДОМ свопе контейнера, не только на cold-start-замыкании. Сигнатура `migrateIfNeeded` не менялась.
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
- [x] **Root cause #2** — Юнит-тест: cold-start резолвит guest (без легаси) → миграция guest вхолостую,
      затем swap на user СО своими легаси (Card/FinanceAccount/Investment) и пустым ядром → после swap
      ядро user заполнено (migrateAll отработал). → `LegacyMigrationScopeSwapTriggerTests.
      coldStartGuestThenUserSwap_migratesUserCoreAfterSwap`.
- [x] **Root cause #2** — Юнит-тест: повторный триггер на уже мигрированном scope (двойной вызов
      cold-start) → флаг-short-circuit, лишней работы нет (только `fetchCount`). →
      `redundantSecondTriggerOnSameScope_isCheapNoOp`.
- [x] Ручная проверка на устройстве владельца: ПОДТВЕРЖДЕНО 2026-07-12 — после установки фикса
      Дашборд/Счета показывают верные 81 208 331 ₽ (вместо 0 / −100%). Владелец проверил лично,
      скриншоты присланы.

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
- 2026-07-12 (раунд 5, device): найден **настоящий root cause #2** — триггер-гэп при async scope-swap
  (см. секцию выше). Часть A/B чинили ЛОГИКУ миграции, но для user-scope миграция никогда не
  ВЫЗЫВАЛАСЬ (cold-start-замыкание висело на синхронно-резолвнутом guest). Фикс: вызов миграции
  добавлен в `rebindDataScope` после свопа `diContainer` (`millioApp.swift`). +2 юнит-теста
  (`LegacyMigrationScopeSwapTriggerTests`). Debug-инструментация — в отдельной ветке
  `debug/legacy-migration-instrumentation` (в feature-ветку не входит).
- 2026-07-12 (финал): ПОДТВЕРЖДЕНО на устройстве владельцем — Дашборд/Счета показывают верные
  81 208 331 ₽ (было 0 / −100%), скриншоты присланы. По явному разрешению владельца ветка
  `feature/legacy-migration-self-heal` смёржена squash в `develop` (`43dca91`) и запушена в origin.
  Debug-ветка `debug/legacy-migration-instrumentation` — throwaway, удаляется.
