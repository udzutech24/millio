# План: уведомление о применённых плановых операциях

Статус: **В РАБОТЕ** — Ф0, Ф1, Ф1b, Ф2 реализованы и гейты сверены; Ф3 в работе (WIP на устройстве).
Прогресс: 4 из 7 фаз. Обновлён: 05.09.2026.
Спека: [`specs/2026-09-05-planned-operations-applied-notice.md`](../specs/2026-09-05-planned-operations-applied-notice.md).
Размер: **L** (10+ файлов, затрагивается Core). Ветка: `feature/planned-operations-applied-notice`.
Стресс-тест: пройден 2026-09-05, план переписан по находкам (журнал внизу).

Область V1 — **только информирование**. Балансовая арифметика не меняется ни в одной фазе.
Кнопка отката вынесена в отдельную задачу.

## Что выяснил стресс-тест (правки уже внесены в фазы)

| Находка | Где | Как учтено |
|---|---|---|
| Запись в журнал «после apply» произошла бы ДО `modelContext.save()` — при броске сохранения журнал соврёт | apply `:397-398` vs save `:409`; recurring `:338` vs save `:349` | буфер, коммит журнала только после успешного save (Ф1) |
| В `CashflowScheduledService` нет ни имени счёта, ни отображаемого title | резолверы живут в VM: `CashflowViewModel.swift:154`, `:101-106` | прокидываем колбэки по образцу `cardProvider` (Ф1) |
| Мост вкладов отдаёт только `insertedCount`, деталей нет | `DepositCashflowProjector.swift:10-13`, данные строк `:53-66`, мост `:140` | отдельная фаза Ф1b, правится Core-файл |
| `AppState.activeScopeKey` ненадёжен — дефолт guest, на холодном старте не присваивается | `AppState.swift:86`, `millioApp.swift:654` (guard `:609`), VM создаётся с `defaults: .standard` (`CashflowViewModel.swift:195`, `RootTabView.swift:444`) | ключ строим от `activeDataScope.storeConfigurationName` (`millioApp.swift:311`), прокидываем явно (Ф0) |
| `didBecomeActive` уже занят: биометрия с системным промптом, затем лист выписки | `millioApp.swift:207-226`, гейт `:272-290`, экран блокировки `:141-142` | встраиваемся в тот же гейт, второй путь не заводим (Ф2) |
| Очереди листов нет — 7 листов на одном view, взаимоисключение вручную | `RootTabView.swift:132-169`, `:188-203` | новый флаг + правка этого биндинга (Ф2) |
| Потолок журнала исказил бы счётчик («50», а применилось 300) | `generateRecurringTransactionsIfNeeded` `:252-300` не ограничен назад | агрегат (счёт + суммы) хранится отдельно от списка деталей (Ф0) |
| Суммирование разных валют в одну цифру | записи несут `currencyCode` | группировка по валютам, без конвертации (Ф3) |
| Metal-шейдер и `.sensoryFeedback` — первые в проекте | ни одного `.metal`/`colorEffect`/`ShaderLibrary` в репо | Ф4 расширена: `.metal` в таргет + `ShaderLibrary.default`; haptics по образцу `LaunchSplashHapticsPlan.swift:23` |

**Найден существующий денежный баг (не наш, но делает сводку лживой)** — см. «Предшественник».

---

## Фаза 0 — журнал непоказанных применений `[x]` РЕАЛИЗОВАН

Новый файл `millio/UI/Services/Cashflow/AppliedPlannedNoticeStore.swift`
(в плане значился `millio/Core/Cashflow/` — папки такой нет, а оба будущих потребителя,
`CashflowScheduledService` и `AccountsCoreDepositCashflowBridge`, лежат в
`UI/Services/Cashflow/`; заводить `Core/Cashflow/` ради одного файла — папка ради папки).

- `struct AppliedPlannedEntry: Codable, Identifiable` — `id`, `title`, `accountName`,
  `amount: Decimal`, `currencyCode`, `appliedAt: Date`,
  `kind: .scheduled | .recurring | .depositInterest`.
- `struct AppliedPlannedDigest: Codable` — **агрегат отдельно от деталей**: `totalCount`,
  `totalsByCurrency: [String: Decimal]` (нетто), `incomeCount`/`expenseCount`, `details: [Entry]`
  с потолком 50. Потолок обрезает только `details`, счётчик и суммы остаются точными.
- API: `append(_:)`, `takeDigest() -> AppliedPlannedDigest?` (читает и очищает), `hasPending`.
- Хранилище: UserDefaults, ключ `cashflow.appliedPlannedNotice.v1.<storeConfigurationName>`.
  **Строку scope брать ровно ту же, что `GroupsMigrator.swift:46,60-66`** — из
  `activeDataScope.storeConfigurationName` (`millioApp.swift:311`), прокинутую в сервис явно.
  НЕ использовать `AppState.activeScopeKey` (`AppState.swift:86` — дефолт guest).
  **Никаких новых `@Model`** — схема перечислена явно (`AppSchemaVersions.swift:8,32,58,150`),
  автогенерации нет, но и повода её трогать тоже.

**Гейт Ф0:** ✅ пройден — `millioTests/UI/Services/Cashflow/AppliedPlannedNoticeStoreTests.swift`,
4 теста зелёные (append→takeDigest возвращает данные и повторный вызов пуст, в т.ч. у нового
экземпляра стора; два scope в одних UserDefaults изолированы; 300 append → `totalCount` 300,
`details` 50, сумма 3165 не обрезана; `totalsByCurrency` считает нетто по каждой валюте отдельно).

Как решён потолок: агрегат накапливается в самой хранимой записи (`accumulate`), в `details`
запись попадает только пока не выбран `detailsCap = 50` — в UserDefaults никогда не лежит больше
50 деталей, а счётчик и суммы точны при любом объёме. Отбрасываются поздние записи: список
остаётся хронологически связным с начала, «и ещё N» (`truncatedCount`) замыкает его в конце.
Направление операции задаётся знаком `amount` (доход > 0, расход < 0) — отдельного поля нет,
чтобы знак и нетто-итог не могли разойтись.

## Фаза 1 — запись в журнал из cashflow-путей `[x]` РЕАЛИЗОВАН — подтв. 05.09: 8409b31, гейт сверен Денисом (5 тестов)

Только буферизация и `append`, ни строки существующей арифметики.

- Разовые к дате (`CashflowScheduledService.swift:358-416`) и повторяющиеся (`:252-355`):
  собирать записи в локальный буфер, **коммитить в журнал только после успешного
  `modelContext.save()`** (`:409` / `:349`). Бросок сохранения → буфер выбрасывается.
- Имя счёта и title сервису недоступны — прокинуть два колбэка в его инициализатор по образцу
  `cardProvider` (`CashflowViewModel.swift:154`) и `incomeCategoryDisplayNameResolver` (`:101-106`).

**Гейт Ф1:** существующие тесты Cashflow зелёные (доказательство — цифры до/после,
`xcodebuild … -quiet 2>&1 | tail -20`); новые тесты — «успешное применение кладёт ровно одну
запись нужного вида» и «провал save не оставляет записей».

## Фаза 1b — проценты по вкладу `[x]` РЕАЛИЗОВАН

- `DepositCashflowProjectionReport` несёт `inserted: [InsertedRow]` (сумма, валюта, дата,
  `accountID`, имя счёта); `insertedCount` стал вычисляемым `inserted.count` — вызывающие не
  тронуты, смысл прежний.
- Мост (`AccountsCoreDepositCashflowBridge`) получил опциональный `appliedNoticeStore` и пишет
  записи `kind = .depositInterest` ТОЛЬКО после успешного `modelContext.save()`, до
  `publishCommitted()`. Стор прокинут из VM тем же `dataScopeIdentifier`, что у Ф0/Ф1.
- `appliedAt` = дата начисления, а не `now()`: один прогон материализует все накопившиеся
  периоды сразу, «применено сейчас» слило бы полгода в один момент.
- Title берётся из уже локализованного (RU/EN/zh-Hans/de/es) ключа
  `cashflow.upcoming.source.deposit_interest` — новых строк не заводили.
- Арифметика не тронута: баланс двигает `AccountEvent`, запись информационная.

**Гейт Ф1b:** ✅ пройден — `millioTests/UI/Services/Cashflow/DepositInterestAppliedNoticeTests.swift`,
4 теста зелёные (детали отчёта + равенство `insertedCount` числу реально вставленных строк;
пустой прогон = 0; записи `.depositInterest` с именем счёта, валютой и положительной суммой,
повторный прогон журнал не пополняет; мост без стора работает как прежде).
Полный прогон `millioTests`: **2725 passed / 21 failed** против baseline 2719/23; оба красных
из Cashflow-кластера перепрогнаны изолированно и зелёные (флак параллельного прогона).

## Фаза 2 — триггер показа `[x]` РЕАЛИЗОВАН

- Решение «показывать / ждать / показывать нечего» вынесено в чистую функцию
  `AppliedPlannedNoticePresentation.decide(hasPendingNotice:readiness:)`
  (`millio/UI/Services/Cashflow/AppliedPlannedNoticePresentation.swift`) по образцу
  `LaunchSplashHapticsPlan`. `makeItem(store:readiness:)` — единственный способ превратить журнал
  в лист: при `.wait`/`.nothing` журнал НЕ очищается.
- Единственная точка показа — `millioApp.presentAppliedPlannedNoticeIfReady()` рядом с гейтом
  выписки: те же `isAppLocked` / `lifecycle` / `isRestoreInProgress` / `isSwitchingScope` /
  `isReconciling`, плюс `hasPendingStatement` (выписка приоритетнее). Вызывается из
  `didBecomeActive`, `onChange(lifecycle)`, `onChange(isAppLocked)`, при закрытии листа выписки
  и по `appState.appliedPlannedNoticeRequestToken`.
- Триггер «сразу после цикла применения»: VM дёргает `notifyAppliedPlannedNoticeIfPending()` на
  завершении всех трёх путей (scheduled/recurring через `onTransactionsMutated`, проценты — через
  `scheduleSync`), проверка `hasPending` внутри; `RootTabView` бампит токен. Прямого показа из
  Cashflow-слоя нет — он не видит ни блокировки, ни очереди листов.
- Взаимоисключение листов: новый `appliedPlannedNoticeBinding` в `RootTabView` в том же ручном
  механизме, что и биндинг выписки. Чтобы биндинги не заблокировали друг друга насмерть,
  приоритет разведён в одном месте — гейт выписки отдаёт `.modalBusy`, пока сводка на экране.
- **Скриншот-режим и UI-тесты исключены** (`runtimeEnvironment.isAnyTesting`): при сидировании
  данных лист перекрывал съёмку — 4 `ScreenshotTests` покраснели, после гарда 8/8 зелёные.
- Лист Ф2 — заглушка (`AppliedPlannedNoticeStubSheet`, только цифры, без текста): настоящий UI в Ф3.

**Гейт Ф2:** ✅ пройден — `millioTests/UI/Services/Cashflow/AppliedPlannedNoticePresentationTests.swift`,
9 тестов зелёных: (а) применение при активном приложении → `.show` со сводкой;
(б) показ ровно один раз, второй и третий заход пусты; (в) `isAppLocked` → `.wait`, журнал цел,
после снятия блокировки показывается; (г) при листе выписки → `.wait`, после закрытия → показ;
плюс `isAlreadyPresenting`/пустой журнал → `.nothing`, неготовый стор и modal-busy → `.wait`,
и VM просит показ только когда в журнале есть непоказанное.
Полный прогон: **2696 passed / 27 failed (2729)** против baseline той же командой на HEAD
(`c76e298`) — **2692 / 22 (2720)**. Все расхождения перепроверены изолированно: кластер
`LegacyMigrationOrdering` + `FinanceDynamicsCoreContribution` даёт ровно те же 8 красных и на
чистом HEAD (14/8 обе стороны), `testPercentChangeWithZeroDenominator` красный на HEAD в изоляции,
остальные — известный флак параллельного прогона. Новых регрессий нет.

## Фаза 3 — UI листа снизу `[~]` В РАБОТЕ — подтв. 05.09: 4c5bb63 + 2e742f7 (WIP). Лист заменил заглушку, строки заведены в Localizable.xcstrings. НЕ пройден гейт (снимок при Dynamic Type XXXL и 50 строках); эта версия собрана и установлена на iPhone 17 Pro Max для теста владельцем.

- Заголовок: «Пока вас не было: N операций». Суммы — **по валютам отдельной строкой каждая,
  без конвертации**; доход и расход не сливать в одно число.
- Раскрытие в список (название · счёт · сумма); при обрезке — строка «и ещё N».
- Проценты по вкладу помечены как информационные.
- Детенты `.medium` / `.large`, содержимое в скролле, без фиксированной высоты (Dynamic Type XXXL).
- Токены обязательны: `AppTypography`, `AppSpacing`, `AppAnimation`.

**Гейт Ф3:** снимок в симуляторе при Dynamic Type XXXL и 50 строках без обрезки;
проверка на устройстве владельцем.

## Фаза 4 — «ультракод»-эффект `[ ]`

Первый шейдер в проекте — заводим инфраструктуру:

- `.metal`-файл в таргете + `ShaderLibrary.default`, дизеринг-градиент через `.colorEffect`.
- Хаптика — по образцу тестируемого плана `LaunchSplashHapticsPlan.swift:23`
  (`.sensoryFeedback` в проекте ещё не используется, сейчас генераторы).
- Reduce Motion через `@Environment(\.accessibilityReduceMotion)` (образцы:
  `LaunchingView.swift:13`, `CashflowUnifiedEntryContainer.swift:39,88`) — при включённом
  обычное появление без эффекта и без вибрации.
- Применяется только здесь.

**Гейт Ф4:** device-проверка владельцем (эффект + вибрация), отдельно прогон с Reduce Motion.

## Фаза 5 — локализация и self-audit `[ ]`

- Строки в `Localizable.xcstrings`: RU / EN / zh-Hans, плюрализация числа операций.
- ⚠️ После device-сборки проверить `git diff` по `Localizable.xcstrings` — Xcode портит файл.
- Self-audit по критериям готовности спеки построчно.

**Гейт Ф5:** полный прогон тестов, l10n-тесты зелёные.

---

## Предшественник — ✅ СДЕЛАН 2026-09-05

Ветка `feature/scheduled-apply-checkpoint-fix`, коммит `ca12eee` (не смержен, не запушен).
Стресс-тест нашёл два существующих денежных дефекта в применении — оба закрыты:

1. ~~**`dueAutoApplyCheckpointKey` НЕ per-scope.** Гостевая сессия двигает чекпойнт владельца →
   его плановые операции могут не примениться никогда.~~ Ключ стал
   `cashflow_due_auto_apply_checkpoint_v1.<scope>` (`CashflowScheduledService.swift:51-59`),
   scope берётся из конфигурации открытого стора (`CashflowViewModel.swift:59-66`), старое
   значение мигрирует один раз (`:453-467`).
2. ~~**Чекпойнт уезжает вперёд даже при провале применения**~~ — теперь двигается только при
   нулевом числе провалов (`:407-411`, `:436-444`).

Тесты: 4 новых зелёных (`millioTests/UI/Services/Cashflow/CashflowScheduledCheckpointTests.swift`).
Осталось решить владельцу: мержить ветку в develop до старта Ф0 или после.

Плюс уже известное: `min(storedCheckpoint, referenceNow)` (`:364-366`) откатывает чекпойнт назад
при сдвиге часов или восстановлении бэкапа → повторное применение и дубли.

## Журнал

- 2026-09-05 — план создан, прогнан стресс-тест (`Максим` + `millio-audit`), переписан:
  размер M→L, добавлена Ф1b, ужесточены Ф0/Ф1/Ф2, найден предшественник.
- 2026-09-05 — Ф0 реализована в `feature/planned-operations-applied-notice`: стор + 4 теста,
  существующий код не тронут. Отклонение от плана — папка `UI/Services/Cashflow/` вместо
  `Core/Cashflow/` (обоснование в теле фазы). Для Ф1 держать в уме: API — только `append(_:)`,
  батчевого варианта нет намеренно; буфер Ф1 отдаёт записи по одной после успешного `save()`.
- 2026-09-05 — Ф1b реализована: отчёт проектора несёт детали строк, мост пишет проценты в журнал.
  Для Ф2 держать в уме: `appliedAt` у процентов — дата начисления, у scheduled/recurring — момент
  применения; сортировать список по `appliedAt` без этой оговорки нельзя.
- 2026-09-05 — Ф2 реализована: чистая функция решения + единственная точка показа в `millioApp`,
  очередь с листом выписки разведена в гейте (биндинги RootTabView иначе блокируют друг друга).
  Для Ф3 держать в уме: заглушка `AppliedPlannedNoticeStubSheet` подлежит замене целиком, лист
  показывается только вне тестовых/скриншотных режимов, а `AppliedPlannedNoticeItem` уже несёт
  digest — новых полей в AppState для UI не нужно.
