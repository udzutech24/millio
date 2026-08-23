# Plan: Переработка backup/recovery (recovery-rework)

**Spec:** `specs/2026-08-22-recovery-rework.md`
**Status:** planning (код не писать до guard phrase «Реализуй фазу N по плану» + «да» после stress-test)
**Ветка:** `feature/recovery-rework`
**Предшественник:** Phase 9 (`plans/2026-08-22__phase-9-reliable-recovery.md`) — ядро построено, пути не прошиты

## ⚠️ База пересмотрена 2026-08-22 (после отката Phase 9)

Владелец откатил незакоммиченную работу Phase 9 («там всё сломалось») — 81 файл сохранён в ветке
`archive/phase9-broken-2026-08-22` (коммит `2e0777e`), `develop` вернулся на `f007705` (TestFlight 2.0).
Ниже — фактическое состояние; разделы «Inputs» и «Problems → Solutions» писались до отката и частично
опираются на код, которого в `develop` НЕТ.

**Есть в develop:** `BackupManager` (919 стр, `importVersion:124`), `LaunchRecoveryPolicy` (78 стр),
`CloudBackupStore`, `SwitchingBackupManager`, `BackupEnvelope/Metadata/Monitor/Transfer`,
`AutoBackupPolicy`, `RestoreCandidateTelemetry`, `RestoreFailureCode`; UI — `RestoreView` (532 стр),
`AutoRestoringView`; launch-recovery — `millioApp.swift:544` → `:1063 presentRestoreFlowIfNeeded`,
lifecycle `.restoring` (`:1096/:1109/:1121/:1126`); открытие файла из Files — `millioApp.swift:223-225`
→ `pendingIncomingBackupURL`, потребитель ТОЛЬКО `BackupManagementView.swift:286,311-313`, блокировка
шитов выписок — `RootTabView.swift:187`; 14 тест-файлов backup/recovery.

**НЕТ вообще (создавать с нуля, а не «чинить»):** `RecoveryCoordinator`, `RecoveryDataPresence`,
`RecoveryPromptStore`, `RecoveryModels`, `PostRestoreRefreshCoordinator`, `ChangeDrivenBackupCoordinator`,
`ColdStartPresentationPolicy`, `ScopeTransitionDiagnostics`; **verified-restore и receipt**
(`restoreVerified`, `expectedModelCount`, `RestoreReceipt` в коде отсутствуют).

**Отпавшие дефекты** (относились к откаченному коду): D6 (`.restoreCompleted` vs `.restoreVerified`),
D10 в старой формулировке (три флага — их источников в develop нет), D11 (мёртвые методы
`RecoveryCoordinator`). **Остались подтверждёнными на чистом develop:** D2 (импорт ≠ restore),
D3 (`pendingIncomingBackupURL` в тупике + блокировка шитов), D4 (нет импорта в `RestoreView`),
D12 (прямые `CloudBackupStore()` в UI). D1/D7/D8/D9 — переформулировать под фактический код.

**Идеи из архива** переиспользовать можно (`git show archive/phase9-broken-2026-08-22 -- <path>`), но
только как черновик: код был сломан и не проходил проверку владельца.

### R-1 — Зелёная база (НОВЫЙ блокер, до R1)

Прогон на чистом `develop` (iPhone 17 Pro, 2026-08-22): **всего 2334, упало 392**.
Причина каскада — краш `FinanceGroupServiceAccountsCoreTests.failedDeleteIsAllOrNothing()` роняет
прогон (359 падений вторичны). Прочее: 8 × «Tab bar did not appear» (UI), 1 × отсутствует `en`
для ключей `finances.*`, 5 точечных. Пока прогон красный, гейт «регресс-набор зелёный» недоказуем —
**R1 не начинается до закрытия R-1** (ветка `fix/baseline-green`).

⚠️ Симулятора `iPhone 16` в системе НЕТ — во всех гейтах `iPhone 17 Pro`.

## Inputs

- Два аудита backup/recovery (2026-08-22), точечно верифицированы по коду; таблица дефектов D1–D12 — в спеке.
- Существующие компоненты Phase 9: `RecoveryCoordinator`, `RecoveryReceipt`, `RecoveryDataPresence`, `PostRestoreRefreshCoordinator`, `LaunchRecoveryPolicy`, `SwitchingBackupManager`.

## Challenge Log

**Problem:** ядро восстановления есть и покрыто тестами, но пользовательские пути (cold start, Files, импорт) к нему не подключены; в результате валидный бэкап не доходит до экрана.

**Chosen solution:** *прошивка существующего ядра*, а не новая подсистема — единая идемпотентная точка входа `launch recovery` + один `RecoveryDecisionStore` + все три UI-входа и `onOpenURL` идут через `RecoveryCoordinator` с verified-receipt и refresh-барьером.

**Alternatives considered:**
1. **Точечные патчи по каждому дефекту** (добавить флаг, добавить событие, добавить кнопку) — отклонено: D1/D6/D10 — симптомы одной причины (нет единого владельца состояния recovery), патчи вернут баг при следующем изменении startup.
2. **Новая recovery-подсистема с нуля** — отклонено: Phase 9 уже дала домен и тесты; переписывание уничтожит покрытие (25 тест-файлов) без выигрыша. Нарушает ponytail-лестницу (переиспользуй существующее).
3. **Всегда авто-restore без подтверждения на пустой базе** — отклонено: снимает у пользователя контроль над деструктивной операцией, конфликтует с R9-06.

**Why chosen is better:** максимум переиспользования протестированного кода, минимум новых сущностей (1 стор + 1 типизированный результат лукапа), каждый шаг привязан к доказанному дефекту.

## Problems → Solutions

| # | Дефект | Решение | Фаза |
|---|--------|---------|------|
| D1 | Двойное открытие RestoreView | идемпотентный вход по поколению scope, состояние вне `@State` | R1 |
| D10 | 3 флага одного состояния | `RecoveryDecisionStore` + миграция ключей | R1 |
| D8 (часть) | `count == nil` → молчаливый выход | явное решение + диагностика | R1 |
| D6 | `.restoreCompleted` вместо `.restoreVerified` | авто-restore через verified-путь координатора | R2 |
| D7 | отбор по size ≥ 1024 | отбор по `modelCount`/метаданным | R2 |
| D5 | несовпадение расширений | принимать оба, один источник константы | R3 |
| D3 | `pendingIncomingBackupURL` в тупике | потребление recovery-путём + разблокировка шитов | R3 |
| D2 | импорт ≠ restore | после импорта — предложение restore с подтверждением перезаписи | R3 |
| D4 | нет импорта в RestoreView | точка входа «Восстановить из файла» | R3 |
| D8 (часть) | ошибка CloudKit = «нет бэкапа» | типизированный `BackupLookupOutcome` | R4 |
| D9 | англ. хардкод таймаута | RU/EN через L10n + Retry | R4 |
| D11 | мёртвые методы координатора | удалить или подключить | R5 |
| D12 | прямые `CloudBackupStore()` | через DI/`SwitchingBackupManager` | R5 |

## Гейты (для каждой фазы, Tier 1 — блокирующие)

```bash
xcodebuild build -project millio.xcodeproj -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/dd-recovery -quiet 2>&1 | tail -20

xcodebuild test -project millio.xcodeproj -scheme millio \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/dd-recovery -quiet 2>&1 | tail -20
```
Результаты тестов читать **только** через `xcresulttool`. Изолированный `-derivedDataPath` обязателен (параллельные агенты).
Дополнительно: `swiftlint lint --quiet` и grep-чеки, указанные в фазах.

**Регрессионный набор (должен оставаться зелёным во всех фазах):**
`millioTests/Core/`: RecoveryCoordinatorTests, LaunchRecoveryPolicyTests, LaunchRecoveryHardeningTests, RecoveryDataPresenceTests, BackupVerifiedRestoreTests, BackupRestoreIntegrityTests, BackupImportValidationTests, BackupEnvelopeTests, BackupManagerTests, SwitchingBackupManagerTests, PostRestoreRefreshCoordinatorTests, RestoreCandidateTelemetryTests, RestoreFailureCodeTests, BackupFailureCodeTests, BackupExporterValidationTests, AutoBackupPolicyTests, BackupMonitorTests, ChangeDrivenBackupCoordinatorTests, PassphraseBackupEncryptionTests;
`millioTests/UI/Profile/`: BackupExperienceModelsTests, ProfileBackupStatusFormatterTests, BackupLocalizationTests;
`millioTests/Core/AccountsCore/`: AccountsCoreBackupTests, AccountProductBackupTests, AccountsCoreBackupEdgeCaseTests.

---

## Фазы

### R0 — Stress-test и решение владельца *(без кода)*
- **Оценка:** ~30 мин
- **Действия:** `/stress-test` по плану (10 причин провала), отдельное внимание: потеря данных при неудачном импорте на непустой базе; гонка scope-generation во время restore; миграция трёх флагов в один стор при обновлении с установленной версии; регресс шитов выписок.
- **Гейт:** `AskUserQuestion` владельцу с риском и вариантами (продолжить / отложить / пересмотреть). **Без явного «да» — реализация не начинается.** Правило 7 workspace CLAUDE.md; guard phrase не отменяет его.
- **Артефакт:** раздел «Stress-test» в конце этого плана.

### R1 — Единый владелец состояния recovery *(D1, D8-часть)* — [x] РЕАЛИЗОВАН (2026-08-22)
- **Оценка:** ~2 ч
- **Фактическая реализация** (переформулировано под код `develop` после отката Phase 9):
  - **Причина двойного открытия доказана:** `presentRestoreFlowIfNeeded()` вызывается безусловно
    в конце `synchronizeDataScope` (`millioApp.swift:544`), а сам `synchronizeDataScope` дёргается
    дважды за старт: cold start (`:328`) и `onSessionChanged` (`:418`), который прилетает от
    `restoreSession()` (`:339` → `AuthService.swift:1544`). `StartupCoordinator.switchScopeIfNeeded`
    гасит только своп контейнера, но не сам вызов recovery. Второй проход при свопе guest→user
    дополнительно бампит `scopeIdentityToken` (`:671`) → меняется `RootSceneIdentity` (`:150`) →
    RestoreView пересоздаётся с чистым `@State` (список версий, выбранная версия, пароль).
  - **`LaunchRecoveryGate`** (новый, `millio/Core/Backup/LaunchRecoveryGate.swift`, ~80 стр) —
    App-level `@State`, переживает remount. Токен на поколение scope; повторный вызов = no-op;
    `bumpGeneration()` в `rebindDataScope` после свопа; `shouldPublishRestoreOutcome` отсекает
    stale-колбэки (S16). Транзиентные исходы (`lifecycleNotReady`, `onboardingIncomplete`,
    `noBackupAvailable`) не фиксируются как решение (SR7).
  - **`LaunchRecoveryPolicy`:** `localDataCount` стал `Int?`; `nil` → `.presentRestoreManualOnly(.localDataCountUnknown)`
    (экран показывается, деструктивный авто-restore запрещён) вместо молчаливого `return`.
    Добавлены `allowsAutomaticRestore` и `locksLaunchRecovery`.
  - **`RecoveryDecisionStore` и миграция 3 флагов НЕ делались** (ponytail + условие владельца №2):
    объединение глобального `autoRestoreAttemptsKey` с per-scope-флагами — это риск SR3
    без выигрыша для D1; ключи оставлены как есть. D10 переносится в отдельную фазу, если
    вообще понадобится.
- **Тесты (все зелёные):** `millioTests/Core/LaunchRecoveryGateTests.swift` (7, включая блокирующий
  S16 «Stale-колбэк не публикует успех восстановления в чужой scope»), +4 в `LaunchRecoveryPolicyTests`.
- **Гейт:** 2346 тестов, 35 красных (фон ≈37, до правки 392 из-за краша-каскада — воспроизведён
  не был); НИ ОДНОГО красного в backup/recovery-сюитах, новых красных нет.

#### Исходная формулировка (писалась до отката Phase 9)
- **Файлы:** `millio/millioApp.swift` (81, 110, 159, 237-241, 344, 459-461, 625, 728, 1128, 1229-1290), `millio/Core/Backup/RecoveryPromptStore.swift` → `RecoveryDecisionStore.swift`, `millio/Core/Backup/LaunchRecoveryPolicy.swift`, `millio/Core/Startup/StartupCoordinator.swift:49`
- **Changes:**
  - `RecoveryDecisionStore` — единственный владелец: `attemptsCount`, `userDeclined`, `storeExistedBeforeBinding`, `lastEvaluatedScopeGeneration`. Миграция значений старых ключей при первом чтении.
  - `presentRestoreFlowIfNeeded` идемпотентна: no-op, если для текущего поколения scope решение уже принято/в процессе. Состояние живёт вне `@State` RestoreView, переживает remount по `RootSceneIdentity`.
  - `localDataCount == nil` → не молчаливый выход, а явная ветка (диагностика + блокировка деструктивного restore, A2/A6).
- **Tests:** новые `RecoveryDecisionStoreTests` (миграция 3 ключей, идемпотентность по поколению), расширение `LaunchRecoveryHardeningTests` (двойной вызов cold start + onSessionChanged ⇒ один лукап), `LaunchRecoveryPolicyTests` (count == nil).
- **Grep-чек:** `autoRestoreAttemptsKey`, `RecoveryPromptStore`, `activeScopeStoreExistedBeforeBinding` — 0 вхождений вне стора и миграции.
- **Impact:** startup-путь, guest→user переход, экран онбординга. Риск: пропуск recovery из-за слишком строгой идемпотентности — покрыть тестом «отказ → перезапуск → recovery всё ещё доступен из Профиля».

### R2 — Верифицированный авто-restore *(D6, D7)* — [x] РЕАЛИЗОВАН (2026-08-22)
- **Оценка:** ~2 ч
- **Фактическая реализация** (переформулировано: в `develop` receipt'а не было вообще — создан с нуля):
  - **`RestoreReceipt` + `RestoreVerificationFailure` + `RestoreModelCensus`** — новый файл
    `millio/Core/Backup/RestoreReceipt.swift`. Пересчёт моделей по типам в снимке формата backup;
    после импорта стор экспортируется повторно (тот же формат) и сравнивается с бэкапом.
  - **Критерий успеха** (не строгое равенство — `DataIntegrityCleaner.dedupeAll` законно схлопывает
    дубли): бэкап непустой И стор непустой И ни один тип не потерян целиком. Иначе — типизированный
    провал, откат к до-restore снимку, ошибка с локализованным текстом
    (`backup.restore.verification.*`, ru/en/zh-Hans + de/es/fr/tr).
  - **Пустой бэкап отсекается ДО деструктивной фазы** (`BackupManager.replaceRepositoryDataWithBackup`):
    удалять локальные данные ради нуля моделей нельзя ни при каком исходе.
  - **`.restoreCompleted` публикуется только после verified-receipt.** Отдельное событие
    `.restoreVerified` НЕ вводилось (ponytail): у него не было бы ни одного потребителя, а
    существующее событие теперь и означает подтверждённый успех.
  - **Отбор кандидата по содержимому (D7):** порог `size >= 1024` и TODO в `millioApp.swift` удалены.
    Пустой/неполный снимок теперь отбраковывает receipt, а в автоматическом режиме перебираются
    более старые кандидаты (`RestoreVerificationFailure` ловится отдельной веткой до общих catch).
  - **Гейт R1 задействован:** результат авто-restore публикуется через
    `LaunchRecoveryGate.shouldPublishRestoreOutcome` (без изменений, проверено трассировкой).
  - **Обновление UI после restore — механизм уже есть, новый не строился:** `CashflowViewModel:620`,
    `FinanceViewModel:818`, `FinanceDynamicsViewModel:409` перезагружаются по `.restoreCompleted`;
    Dashboard — presentational-view, данные приходят из этих же VM через `RootTabView:437`.
  - **Найден и исправлен реальный блокирующий баг:** `CashbackImporter.importPriority` был 20, то есть
    кешбэк импортировался ДО `Account` (31), не находил core-счёт (ремап Ф5b плана 6b) и ронял ВЕСЬ
    restore в `backupCorrupted`. Эталонный файл владельца не восстанавливался вовсе — ровно жалоба
    «результат пустой». Priority → 40.
- **Тесты:** `millioTests/Core/BackupVerifiedRestoreTests.swift` (12, все зелёные), включая
  интеграционный на реальном файле владельца — фикстура
  `millioTests/Fixtures/owner-backup-1673-models.milliobackup` (137 КБ, MBKP/format 2, схема 2.0,
  lzfse, без шифрования): **ожидалось 1673 → импортировано 1673, receipt verified, missingTypes пуст**.
  Тестовые payload'ы в `BackupManagerTests` заменены на валидные снимки (`makeRestorablePayload`):
  прежние произвольные байты «успешно восстанавливались», чего verified-restore больше не допускает.
- **Гейт:** сборка без ошибок; backup/recovery-сюиты 67/67 зелёные; полный прогон 2358 тестов, 36
  красных против фона 35 — оба «лишних» (`FinanceDynamicsViewModelTests`) проходят в изоляции
  (45 тестов, 1 фоновый красный), то есть order-flake, не регрессия. Новых красных в backup/recovery — 0.

#### Исходная формулировка (писалась до отката Phase 9)
- **Файлы:** `millio/Core/Backup/BackupManager.swift` (249-320, 417-442, 909-916), `millio/Core/Backup/RecoveryCoordinator.swift`, `millio/Core/Backup/PostRestoreRefreshCoordinator.swift:21`, `millio/millioApp.swift:1276-1290`
- **Changes:** авто-restore идёт тем же verified-путём, что и `restoreExplicit`: receipt → `.restoreVerified` → refresh-барьер. `.restoreCompleted` остаётся, но не является признаком успеха. Отбор кандидата — по `modelCount`/валидированным метаданным, порог `size >= 1024` и TODO удаляются.
- **Tests:** `BackupVerifiedRestoreTests` (+ авто-путь), `PostRestoreRefreshCoordinatorTests` (барьер срабатывает после авто-restore), `RestoreCandidateTelemetryTests` (отбор по modelCount, кандидат без modelCount), **интеграционный тест пути** «пустая база → авто-restore → счётчики моделей на Dashboard-источниках» (правило из памяти: при знаковых/структурных фиксах инвариант-теста мало).
- **Impact:** любые слушатели `.restoreCompleted`; проверить grep по обоим событиям.

### R3 — Путь «файл → восстановленные данные» *(D2, D3, D4, D5)* — главный сценарий A1
- **Оценка:** ~3 ч
- **Файлы:** `millio/millioApp.swift:237-241`, `millio/Core/Backup/BackupManager.swift:996`, `Info.plist:48-73, 96-101`, `UI/Profile/BackupManagementView.swift` (37, 287-288, 312-314, 791, 859, 942-946), `UI/.../RestoreView.swift`, `UI/RootTabView.swift:187`
- **Changes:**
  - Одна константа расширений бэкапа; `onOpenURL` принимает `.milliobackup` и `.millio-backup`; Info.plist приведён в соответствие.
  - `pendingIncomingBackupURL` потребляется recovery-путём (а не только `BackupManagementView`); после потребления — сброс, шиты выписок разблокированы (`RootTabView.swift:187`).
  - После `importVersion` — предложение restore: на пустой базе сразу, на непустой — подтверждение перезаписи с датой/размером/modelCount; отказ = версия просто остаётся в списке.
  - В `RestoreView` — точка входа «Восстановить из файла» (fileImporter) через тот же координатор.
- **Tests:** `BackupImportValidationTests` (оба расширения), новый `IncomingBackupRoutingTests` (URL при закрытом приложении / на любом экране / повторное открытие), интеграционный `ImportThenRestoreTests` на фикстуре 1673 моделей (пустая база и непустая + rollback), регресс `RootTabView` шитов выписок.
- **Impact:** share-extension выписок, deep links. Риск регресса шитов — покрыт тестом.

### R4 — Отличимая диагностика и RU-строки *(D8, D9)* — [x] РЕАЛИЗОВАН (2026-08-23)
- **Фактическая реализация:**
  - **`BackupLookupOutcome`** (`millio/Core/Backup/BackupLookupOutcome.swift`): `.found([versions])` /
    `.empty` / `.failed(reason)` / `.timedOut`. Причина (`iCloudUnavailable` / `network` / `serviceBusy` /
    `unknown`) классифицируется по домену и коду `NSError` (`CKErrorDomain`, `NSURLErrorDomain`) —
    без рантайма CloudKit, поэтому проверяется тестом. `BackupManager.lookupBackupVersions()` больше не
    превращает ошибку облака в `[]`; старый `listBackupVersions()` оставлен как обёртка (совместимость
    с BackupMonitor/автобэкапом), `SwitchingBackupManager` форвардит явно, для моков — дефолт протокола.
  - **Таймаут** ушёл из `RestoreView` в `lookupBackupVersions(timeout:)` — «облако молчит» стало исходом,
    а не пустым списком.
  - **`RestoreView`**: одно состояние `lookupOutcome` вместо пары «список + флаг таймаута»; экран без версии
    строится `BackupExperiencePresenter.restoreLookupPresentation` — разные заголовок/текст/иконка для
    «копий нет», «поиск не удался (причина)» и «iCloud не ответил», **кнопка «Повторить» на всех трёх**
    (раньше только pull-to-refresh + один общий текст). Исход лукапа пишется в лог
    (`RestoreView: backup_lookup failed=network`), при неразрешённом исходе `appState.lastBackupDate`
    НЕ перетирается — неизвестность не выглядит как «копий нет».
  - **Тексты граничных случаев (новых типов ошибок не заводилось):** `RestoreFailureCode.message` и
    `AppError` в UI пошли через каталог. Новый `RestoreErrorPresenter` (`millio/UI/Restore/`) —
    единственный источник текста ошибки на экране: `AppError.localizedDescription` («Restore failed: …»)
    в UI больше не попадает. Покрыты: неверная кодовая фраза, нет ключа в Keychain, несовместимая схема,
    повреждённый файл, провал pre-restore снимка, провал отката (R2), пустой бэкап (R2).
  - **Локализация:** 30 новых ключей в `Localizable.xcstrings` по образцу `backup.restore.verification.*`
    (ru/en/de/es/fr/tr/zh-Hans). L10n-гейт `BackupLocalizationTests` расширен на `RestoreView.swift` и
    `RestoreErrorPresenter.swift` — расширение сразу вскрыло **5 ключей экрана восстановления вообще без
    перевода** (`backup.restore.skip.*`, `backup.restore.passphrase.toggle*`), они добавлены.
    В `RestoreView` не осталось строковых литералов, идущих в UI (grep-чек).
  - **Guest-scope (S10):** `LaunchRecoveryPolicy` получил `isGuestScope` и `.skip(.guestScopeBeforeSignIn)`.
    Раньше гость с пройденным онбордингом и пустым стором получал предложение восстановить облачную копию
    В ГОСТЕВОЙ стор (после входа она уехала бы в reconciliation guest→user). Теперь до логина recovery не
    предлагается, облако до логина не опрашивается, исход транзиентный (после входа оценка повторяется),
    причина видна в логе: `scope=guest … → skip(guestScopeBeforeSignIn)`.
  - **Изменение поведения (принято осознанно):** пользователь, который никогда не входит в аккаунт, больше
    не увидит launch-recovery; ручной путь из Профиля и «Восстановить из файла» (R3) ему доступны.
- **Отклонение от плана:** `RestoreFailureCodeTests` менял ожидания на английские литералы — старое ожидание
  было неверным (эта строка идёт прямо в UI и обязана быть локализованной, тест фиксировал сам баг D9);
  вместо литералов проверяются стабильные ключи, непустой текст и различимость сообщений.
- **Тесты (+18):** `millioTests/Core/BackupLookupOutcomeTests.swift` (9: классификация причин, ошибка ≠ `.empty`,
  совместимость `listBackupVersions`, таймаут, **Retry делает новый запрос**, диагностика),
  `millioTests/UI/Restore/RestoreDiagnosticsLocalizationTests.swift` (7: полнота переводов всех кодов и причин,
  различимость экранов, Retry на всех неразрешённых исходах, тексты граничных случаев),
  +2 в `LaunchRecoveryPolicyTests` (guest skip + транзиентность), переписан `RestoreFailureCodeTests`.
- **Гейт:** полный прогон 2392 теста, 37 красных при фоне 34–36 (все — Finance/Cashflow/migration/
  UI-screenshot/l10n, ни один не касается backup/recovery); **все сюиты backup/recovery/router зелёные**
  (BackupLookupOutcome, BackupManager, BackupVerifiedRestore, BackupLocalization, RestoreDiagnostics,
  RestoreFailureCode, LaunchRecovery×3, SwitchingBackupManager, ScopeMerge×4, AppRouter — Passed).

#### Исходная формулировка
- **Оценка:** ~1.5 ч
- **Файлы:** `BackupManager.swift:909-916`, `RestoreView.swift` (386-393, 498, 507-525), `Localizable.xcstrings` (ru/en/zh-Hans)
- **Changes:** `BackupLookupOutcome` = `.found(version)` / `.none` / `.failed(reason)` / `.timedOut` вместо `nil`. Разные экраны/строки для «бэкапа нет» и «CloudKit не ответил», Retry на восстановимых. Английский хардкод таймаута → L10n.
- **Tests:** `RestoreFailureCodeTests`, `BackupLocalizationTests` (нет непереведённых ключей recovery), новый `BackupLookupOutcomeTests` (ошибка сети ≠ «нет бэкапа»).
- **Grep-чек:** в `RestoreView.swift` нет строковых литералов, идущих в UI.

### R5 — Чистка и ponytail-проход *(D11, D12)* — [x] РЕАЛИЗОВАН (2026-08-23)
- **Оценка:** ~1 ч
- **Файлы:** `RecoveryCoordinator.swift` (мёртвые `retry`/`cancel`/`reset`; `discover`/`restoreConfirmed` — подключить или удалить вместе с тестами), `RestoreView.swift:508`, `BackupManagementView.swift:791`
- **Changes:** прямые `CloudBackupStore()` → инъекция `SwitchingBackupManager`/DI. Мёртвые ~120 строк удаляются **только** если после R1–R4 они действительно не нужны (retry может стать живым в R4 — решать по факту).
- **Grep-чек:** `CloudBackupStore(` вне DI-слоя = 0.
- **Tests:** `RecoveryCoordinatorTests` приведены в соответствие (тесты на удалённый код удаляются вместе с ним, не «обходятся»).
- **Факт (2026-08-23):** D11 закрыт как *неприменимый*: `RecoveryCoordinator` в базе нет (откат Phase 9), а
  у всех пяти файлов R1–R4 (`LaunchRecoveryGate`, `RestoreReceipt`, `BackupFileFormat`,
  `BackupLookupOutcome`, `RestoreErrorPresenter`) каждый публичный член имеет живого потребителя —
  удалять нечего. D12 закрыт. Вместо мёртвого кода схлопнуты три дубля (см. Changelog).
- **SwiftLint не запускался:** бинаря нет в системе, `.swiftlint.yml` в проекте отсутствует —
  пункт неисполним, тулинг не ставился без решения владельца.

### R6 — Интеграционный гейт
- **Оценка:** ~1 ч
- **Действия:** полный прогон всех 25 регресс-файлов + новых; сверка каждого acceptance criterion A1–A11 спеки с местом в коде; `/security-review`; проверка отсутствия PII в новых логах.
- **Гейт:** 0 новых красных, отчёт «критерий → file:line / имя теста».

### R7 — Финальная приёмка (агент на модели Fable) *(A12)*
- **Оценка:** ~1.5 ч
- **Кто:** отдельный агент **на модели Fable** — вызывать `Agent` **без параметра `model`** (наследует модель главной сессии = Fable); в брифе указать явно: «модель Fable, унаследована от родителя, не переопределять».
- **Задача агента:** пройти ВСЕ пользовательские сценарии recovery, не только главный; по каждому — вердикт **пройден / не пройден** с доказательством: имя теста, `file:line` трассировки кода, либо отметка «требует device-проверки владельца» + что именно смотреть.

#### Чек-лист сценариев R7

| # | Сценарий | Шаги | Ожидаемый результат | Где проверяется |
|---|----------|------|---------------------|-----------------|
| S1 | Свежая установка + есть CloudKit-бэкап | логин → пустой user-scope | предложение recovery до онбординг-контента; после подтверждения — данные | тест + device |
| S2 | Свежая установка + бэкапа нет | логин → лукап `.none` | явный экран «бэкапа нет», онбординг, без ошибки | тест |
| S3 | `.millio-backup`/`.milliobackup` из Files, приложение **закрыто** | тап по файлу | cold start → предложение restore | трассировка + device |
| S4 | То же, приложение **открыто на любом экране** | тап по файлу | маршрутизация в recovery с текущего экрана, без тупика | тест + device |
| S5 | Импорт файла из `RestoreView` на пустой базе | кнопка «Восстановить из файла» | импорт → restore → данные | тест |
| S6 | Импорт из `BackupManagementView` при непустых данных | импорт | подтверждение перезаписи; отказ = версия в списке, данные целы | тест |
| S7 | Авто-restore успешный | старт с пустым scope | receipt, `.restoreVerified`, refresh без перезапуска | тест |
| S8 | Авто-restore упал 2 раза → ручной | 2 отказа | переход в ручной сценарий, счётчик в `RecoveryDecisionStore` | тест |
| S9 | CloudKit не ответил / таймаут | сеть off | `.failed/.timedOut`, RU-строка, Retry работает | тест |
| S10 | Guest-scope до логина | старт без логина | recovery не предлагается, деструктива нет, причина в диагностике | тест |
| S11 | Отказ «продолжить без данных» + повторный запуск | отказ → рестарт | не переспрашивает навязчиво; recovery доступен из Профиля | тест + device |
| S12 | Зашифрованный бэкап: неверный пароль / нет ключа в Keychain | restore | различимые ошибки, данные не тронуты | тест |
| S13 | Несовместимая схема бэкапа | restore | явный отказ до деструктивной фазы | тест |
| S14 | Rollback при неудачном импорте | импорт с порчей | предыдущие данные восстановлены; провал rollback = отдельная высшая severity | тест |
| S15 | После restore — Dashboard / Счета / Analytics / Cashflow | restore | все 4 экрана обновлены **без перезапуска** | интеграционный тест + device |
| S16 | Повторный вход / смена аккаунта | logout → вход другим | scope-generation сменился, stale-колбэк не публикует успех, чужие данные не подмешались | тест |
| S17 | Legacy v2.0.0 бэкап | restore | читается как раньше | `BackupEnvelopeTests` |

#### Отдельный пункт брифа Fable (вне build/test-гейта)
Найти и перечислить: (а) временные compat-шимы и переходные слои, оставшиеся после R1–R5; (б) неидиоматичный Swift (лишние обёртки, ручные диспетчеры вместо async/await, дублирование состояния); (в) bloat — код, не привязанный ни к одному критерию A1–A12. Отдельным разделом отчёта, не смешивая с результатами сборки/тестов.

- **Гейт фазы:** каждый из S1–S17 помечен пройден/не пройден с доказательством; непройденные — с решением владельца (чинить сейчас / принять / отложить). Device-пункты — скрин или подтверждение владельца.

---

## Итого оценка

~12 ч работы агентов + stress-test и device-проверки владельца. Порядок обязателен: R0 → R1 → R2 → R3 → R4 → R5 → R6 → R7 (R3 зависит от R1/R2 по единому пути координатора).

## Условия владельца (R0 пройден, решение 2026-08-22: «да, с условиями»)

Обязательны до старта R1; невыполнение любого = стоп фазы.

1. **Safety-снимок и точка невозврата (R3).** Перед деструктивной фазой любого restore — снимок текущих данных; в коде явно обозначена точка невозврата; провал rollback — отдельный высший уровень severity с сообщением пользователю, что делать. Тест S14 обязателен в гейте R3, а не только в R7.
2. **Атомарная версионированная миграция флагов (R1).** Старые ключи (`autoRestoreAttemptsKey` — глобальный, `RecoveryPromptStore` — per-scope, `didLocalStoreExistBeforeLaunch`) НЕ удаляются; миграция версионирована и идемпотентна; семантика `attemptsCount` (глобальная vs per-scope) зафиксирована в спеке письменно до кода. Тест: частично прочитанные/отсутствующие ключи.
3. **S16 (смена аккаунта в середине restore) — блокирующий гейт R1**, а не R7: stale-колбэк не публикует успех, данные аккаунтов не смешиваются.

Рекомендовано (не блокирует): эталонная фикстура реального файла владельца (1673 модели, схема 2.0) до R2; перенос R5 после R6.

**Правка плана:** фактический путь блокировки шитов — `millio/UI/Main/RootTabView.swift:187` (в таблице выше указан сокращённо).

## Правила исполнения

- Guard phrase: без явного «Реализуй фазу N по плану» — только чтение.
- Каждая фаза = отдельная сессия + свежий контекст + коммит после гейта; **merge/push — только по явному разрешению владельца** (прецедент 2026-08-14).
- Сайдкар `plans/2026-08-22__recovery-rework.status.json` обновляется после каждой фазы.
- `ponytail` (full) активен на всех кодовых фазах.

## Stress-test

*Проведён 2026-08-22 (R0, Максим). 10 причин провала переработки. Код не менялся.*

| # | Риск | Вер-ть | Последствие | Митигация в план |
|---|------|--------|-------------|------------------|
| SR1 | **Потеря данных: restore/импорт на НЕпустой базе + провал rollback.** Snapshot-restore заменяет данные целиком (CORE_RULES). Если деструктивная фаза началась, а импорт упал в середине (порча файла, нехватка места, kill по памяти на 1673 моделях, откат SwiftData-контекста) — старых данных нет, новых тоже. S14 в R7 требует rollback, но в R3 нет ни требования «pre-restore safety snapshot», ни определения точки невозврата | Средняя | **Критическое** — необратимая потеря реальных данных владельца | В R3 (до кода): (а) обязательный **pre-restore safety-снимок** локальной базы (экспорт текущего состояния в файл до деструктивной фазы) — восстановить при любом сбое; (б) явно задать порядок: валидация+парсинг **полностью** до удаления, деструктив — последним и атомарным шагом; (в) тест `ImportThenRestoreTests` дополнить кейсом «kill в середине записи ⇒ старые данные целы»; (г) провал rollback — severity выше, чем провал restore, отдельный failure-code и лог |
| SR2 | **Гонка scope-generation: logout / смена аккаунта в середине restore.** Stale-колбэк дописывает данные бэкапа A в scope пользователя B, либо публикует `.restoreVerified` в чужой scope | Средняя | **Критическое** — смешение данных двух аккаунтов, приватность | В R1 `RecoveryDecisionStore.lastEvaluatedScopeGeneration` расширить до **сквозного токена операции**: снимок generation берётся в начале restore, перед КАЖДОЙ записью и перед публикацией события сверяется; несовпадение ⇒ отмена + `.restoreCancelledStaleScope`, без частичной записи. Тест S16 сделать блокирующим в R1 (а не только в R7) — сейчас он живёт в R7, то есть после всего кода |
| SR3 | **Миграция 3 флагов даёт неверное решение у существующего пользователя.** Проверено по коду: `autoRestoreAttemptsKey` (`millioApp.swift:1128`) — **глобальный** ключ без scope, а `RecoveryPromptStore` (`:1240,1250`) — **per-scope**. Слияние в один стор меняет семантику: глобальный счётчик попыток либо размажется на все scope, либо обнулится. Плюс частичное чтение: мигрировали 2 ключа из 3, приложение убито между записями | Высокая | Тяжёлое — у апдейтящегося пользователя либо навязчивый повторный prompt, либо **recovery не предлагается вовсе** (то есть основной баг «валидный бэкап не доходит до экрана» воспроизведётся у реального владельца) | В R1: (а) миграция — **атомарная**, один write одного версионированного словаря + флаг `migrationSchemaVersion`, не 3 отдельных `set`; (б) явно решить и записать в план, во что превращается глобальный `attemptsCount` (рекомендация: обнулить, но сохранить `userDeclined` per-scope — отказ важнее счётчика); (в) старые ключи **не удалять** в R1 (удаление — отдельным шагом в R5 после device-подтверждения); (г) тест «апдейт со всеми 8 комбинациями наличия 3 ключей» |
| SR4 | **Регресс шитов выписок.** `RootTabView.swift:187` (фактический путь `millio/UI/Main/RootTabView.swift`, в плане указан `UI/RootTabView.swift` — путь в плане неточен) блокирует шит выписки, пока `pendingIncomingBackupURL != nil`. Если recovery-путь потребляет URL, но не сбрасывает его на всех ветках (отказ, ошибка, таймаут, cold start без логина) — импорт банковских выписок **молча перестаёт открываться**, без ошибки и без связи с recovery | Высокая | Среднее, но диагностируется очень плохо (тихая поломка чужой фичи) | В R3: сброс `pendingIncomingBackupURL` — в `defer`/единой точке выхода recovery-потока, все ветки; grep-чек «нет ни одного `return` из recovery-потока без сброса»; тест «URL пришёл → пользователь отказался → шит выписки открывается»; исправить путь файла в R3 |
| SR5 | **Поломка 25 зелёных тест-файлов и работающих механизмов** (RecoveryDataPresence, financial-guard, receipt, legacy v2.0.0). Смена контракта событий (`.restoreCompleted` → `.restoreVerified`) и типа лукапа (`nil` → `BackupLookupOutcome`) — это правка публичных API, на которые завязаны тесты и продовые слушатели | Высокая (что тесты покраснеют) / Низкая (что механизм реально сломается) | Среднее — либо потеря дня на починку тестов, либо соблазн «подогнать тест под код» | Уже частично покрыто (регресс-набор + grep по обоим событиям в R2). Добавить: **запрет менять тест, доказывающий поведение, без явной строки в отчёте фазы «почему старое ожидание было неверным»**; `BackupEnvelopeTests` (legacy 2.0.0) и financial-guard объявить **read-only** — файлы не редактируются вообще, только запускаются |
| SR6 | **Реальный файл владельца станет невосстановимым.** 1673 модели, схема 2.0, magic `MBKP`, без шифрования. Ужесточение отбора кандидата в R2 (`size >= 1024` → `modelCount`) отсекает бэкапы, у которых `modelCount` нет в метаданных; ужесточение валидации в R3 (S13 «несовместимая схема») может отклонить схему 2.0 как «не текущую» | Средняя | **Критическое** — единственный бэкап владельца перестаёт открываться | (а) **До начала R2** прогнать реальный файл владельца через существующий парсер и зафиксировать эталон (modelCount, версия схемы, наличие полей) — фикстура-эталон в тестах; (б) правило: отсутствие `modelCount` ⇒ кандидат **не отбрасывается**, а понижается в приоритете; (в) «несовместимая схема» = только строго больше текущей или неизвестный magic, никогда не «меньше»; (г) после R3 и после R6 — повторный прогон того же файла, результат в отчёт гейта |
| SR7 | **Идемпотентность по scope-generation убивает recovery (over-fix D1).** «Решение уже принято для этого поколения» может залипнуть: пользователь отказался по ошибке, или лукап упал по сети и записал «решение принято», после чего recovery недоступен до logout | Средняя | Тяжёлое — тот же класс бага, что чиним, но замаскированный | План уже требует тест «отказ → перезапуск → recovery доступен из Профиля» (R1 Impact). Усилить: **сбой лукапа (`.failed`/`.timedOut`) не считается принятым решением** и не пишется в стор; ручной вход из Профиля **никогда** не блокируется стором (стор гасит только автоматический prompt) |
| SR8 | **CloudKit: офлайн, квота, троттлинг, аккаунт не залогинен.** R4 вводит `.failed/.timedOut`, но по коду таймаут CloudKit 3 s (см. `CLAUDE.md` → deep analysis). При медленной сети «нет бэкапа» превратится в «CloudKit не ответил» — честнее, но пользователь на холодном старте всё равно уходит в онбординг и может создать данные поверх | Высокая | Среднее — recovery откладывается, риск «данные создались до restore» | В R4: при `.failed/.timedOut` — не пускать в необратимый онбординг молча; баннер/повтор при возврате сети, и **повторная проверка recovery после восстановления связи**, пока база остаётся пустой. Явно проверить сценарий «нет iCloud-аккаунта на устройстве» (S9 покрывает только сеть) |
| SR9 | **UX-навязчивость и деструктивное подтверждение.** R3 «на пустой базе restore сразу» + R1 «явная ветка при `count == nil`» могут дать пользователю модалку на каждом старте или, наоборот, авто-перезапись без спроса. Конфликт с отклонённой альтернативой №3 (Challenge Log) | Средняя | Среднее — раздражение, в худшем случае неожиданная перезапись | Зафиксировать инвариант до кода: **любая перезапись непустой базы — только после явного подтверждения с датой/размером/modelCount**; `count == nil` трактуется как «непустая» (безопасная сторона); prompt показывается максимум 1 раз на поколение scope, дальше — только из Профиля |
| SR10 | **Порядок фаз и объём: 12 ч в одном заходе.** R3 зависит от R1/R2, R5 (удаление ~120 строк) — от «по факту» R4. Соблазн срезать: сделать R3 до готового R1, или удалить мёртвый код заранее. Плюс `millioApp.swift` правится в R1, R2 и R3 — три фазы в одном файле, конфликты и перезапись правок между сессиями | Высокая | Среднее — потеря времени, регрессии между фазами, «откатилось» | Правила уже есть (фаза = сессия + коммит после гейта). Добавить: (а) **коммит обязателен до старта следующей фазы**, старт фазы начинается с `git log --oneline -5` + `merge-base vs develop` (урок 6b из памяти); (б) R5 (удаление кода) переносится **после** R6, а не до — удалять только то, что доказано мёртвым на зелёном интеграционном гейте; (в) если R1 не прошёл гейт — R2/R3 не стартуют, стоп и решение владельца |

### Три главных риска

**SR1 (потеря данных при провале rollback)** — единственный риск с необратимым исходом: план описывает rollback как тест-сценарий S14, но не как требование к архитектуре восстановления, и нигде не задан pre-restore safety-снимок и точка невозврата. **SR3 (миграция флагов)** — самый вероятный из тяжёлых и проверен по коду: `autoRestoreAttemptsKey` глобальный, `RecoveryPromptStore` per-scope, слияние их в один стор без явного решения о семантике воспроизведёт у реального пользователя ровно тот баг, ради которого затевается переработка. **SR2 (гонка scope-generation)** — редкий, но с ценой «данные двух аккаунтов смешались»; его тест S16 сейчас стоит в R7, то есть проверяется в самом конце, когда весь код уже написан.

**Вердикт: можно начинать с условиями.** Условия, без которых R1 не стартует: (1) в R3 добавлено требование pre-restore safety-снимка и явной точки невозврата (SR1); (2) в R1 миграция атомарная, версионированная, старые ключи не удаляются, и в плане письменно зафиксировано, во что превращается глобальный `attemptsCount` (SR3); (3) тест S16 (смена scope в середине restore) поднят из R7 в блокирующий гейт R1 (SR2); (4) до старта R2 снят эталон реального файла владельца (1673 модели, схема 2.0) и заведён фикстурой (SR6); (5) R5 (удаление мёртвого кода) перенесён после R6 (SR10). Пункты 1–3 — обязательны; 4–5 — сильно рекомендованы.

## Changelog

| Date | Phase | Changes |
|------|-------|---------|
| 2026-08-23 | R5 | РЕАЛИЗОВАН на `feature/recovery-rework` (`21b3b21`). D12 закрыт: `RestoreView` и `BackupManagementView` больше не создают `CloudBackupStore()` напрямую — доступность облака спрашивается у DI-менеджера (`SwitchingBackupManager.isAvailable()` и так отвечает при выключенном автобэкапе, ради чего и был обход). Grep-чек `CloudBackupStore(` вне `Core/Backup` = 0. **D11 оказался неприменим:** `RecoveryCoordinator` откачен вместе с Phase 9, а у всех пяти новых файлов R1–R4 каждый публичный член имеет живого потребителя (проверено посимвольно, с учётом внутрифайловых вызовов) — мёртвого кода нет, удалять нечего. Ponytail-ревизия дифа R1–R4 нашла три дубля вместо: (1) `IncomingBackupFileRestore.message(for:)` — копия `RestoreErrorPresenter`, которая на generic-пути показывала технический английский `AppError.localizedDescription`, то есть тот самый D9, закрытый в R4 только для `RestoreView`; (2) путь восстановления в `BackupManagementView` мапил ошибку двумя inline-`catch` мимо презентера; (3) приватный `withTimeout` + `RestoreTimeoutError` в `RestoreView` — побайтовая копия глобального `millio/Core/Concurrency/WithTimeout.swift`. Все три схлопнуты, −34 строки, единый текст ошибки на всех трёх путях восстановления. Консистентность путей проверена: авто-restore, `RestoreView`, `BackupManagementView`, файл из Files — все идут в одну воронку `restoreDownloadedBackup` → `replaceRepositoryDataWithBackup` с verified-receipt (R2); launch-путь под `LaunchRecoveryGate` (R1). Гейт: 34 красных при фоне 34–37, новых нет; из 3 красных в backup/recovery-сюитах все 3 — cross-suite order-flake (в изоляции `RestoreDiagnosticsLocalizationTests` 9/9 и `BackupRestoreIntegrityTests` 9/9 зелёные) |
| 2026-08-23 | R4 | РЕАЛИЗОВАН на `feature/recovery-rework` (`8117c2d`, `cf7b2ae`, `6b6f70a`). D8: `BackupLookupOutcome` — ошибка CloudKit больше не приходит в UI как пустой список; таймаут стал исходом, а не английской строкой. Экран восстановления различает «копий нет» / «поиск не удался (причина)» / «iCloud не ответил», у каждого — кнопка «Повторить». D9: `RestoreFailureCode.message`, `AppError` в UI и 5 ключей экрана без перевода переведены через каталог (30 ключей × 7 языков); новый `RestoreErrorPresenter` — единственный источник текста ошибки. S10: guest-scope до логина = `skip(.guestScopeBeforeSignIn)` с причиной в логе (раньше гостю предлагали восстановить облачную копию в гостевой стор). +18 тестов. Гейт: 2392/37 при фоне 34–36, backup/recovery/router-сюиты зелёные |
| 2026-08-23 | R3 | РЕАЛИЗОВАН на `feature/recovery-rework` (`3a8a6e0`, `bb87d9c`, `c4ab1b7`, `7c32398`). D5: `BackupFileFormat` — один источник расширений, `Info.plist` объявляет ОБА (экспорт писал `.milliobackup`, объявлено было только `millio-backup` — система не связывала файл владельца с приложением). D3: `IncomingBackupFileRestoreModifier` подключён в корне сцены — единственный потребитель `pendingIncomingBackupURL`, работает на любом экране и при холодном старте, URL потребляется до первого `await` на всех ветках (шиты выписок `RootTabView:187` не залипают). D2: после `importVersion` файл уходит в тот же путь → подтверждение перезаписи, отказ = версия остаётся в списке. D4: кнопка «Восстановить из файла» в `RestoreView`. Новое в Core: `inspectBackupFile` + `restoreFromFile` (путь «файл → данные» больше не требует iCloud, `importVersion` его требовал). Условие владельца: safety-снимок и `rollback(to:)` из R2 переиспользованы, провал отката = `RestoreRollbackFailure` (severity `.critical`, снимок не удаляется, локализованная инструкция). Тестов +10, включая S14. **Отклонение от плана:** подтверждение перезаписи показывается ВСЕГДА, а не только на непустой базе (SR9: неизвестный счётчик = «непустая»; отдельный подсчёт моделей в UI-слое не заводился) |
| 2026-08-22 | — | План создан (spec + plan + сайдкар), код не писан |
| 2026-08-22 | R2 | РЕАЛИЗОВАН на `feature/recovery-rework`. Создан `RestoreReceipt`/`RestoreModelCensus`/`RestoreVerificationFailure` (`millio/Core/Backup/RestoreReceipt.swift`); успех restore публикуется только после пересчёта стора; пустой бэкап отсекается до деструктивной фазы; провал проверки = откат + локализованная ошибка (`backup.restore.verification.*`). Порог `size >= 1024` в авто-restore удалён (отбор по содержимому). Побочно найден и исправлен блокер: `CashbackImporter.importPriority` 20 → 40 (кешбэк импортировался до `Account` и ронял весь restore реального бэкапа в `backupCorrupted`). Эталон владельца: 1673 → 1673, verified. Гейт: backup-сюиты 67/67, полный прогон 2358/36 при фоне 35 (2 лишних — order-flake Dynamics, в изоляции зелёные) |
| 2026-08-22 | R1 | РЕАЛИЗОВАН на `feature/recovery-rework`. Доказан двойной вызов `presentRestoreFlowIfNeeded` (cold start `:328` + `onSessionChanged` от `restoreSession` `:339`). Добавлен `LaunchRecoveryGate` (идемпотентность по поколению scope + stale-guard), `LaunchRecoveryPolicy.localDataCount` → `Int?` с ветками `presentRestoreManualOnly`/`allowsAutomaticRestore`/`locksLaunchRecovery`. 11 новых тестов (вкл. блокирующий S16). Гейт: 2346 тестов, 35 красных = фон, новых нет. Миграция флагов (D10) сознательно НЕ делалась — риск SR3 без выигрыша для D1 |
