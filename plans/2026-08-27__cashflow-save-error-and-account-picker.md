# Задача: сбой сохранения транзакции + редизайн выбора счёта

**Дата:** 2026-08-27
**Статус:** В РАБОТЕ (диагноз подтверждён кодом, дизайн согласован владельцем
2026-08-27; реализация не начата)
**Источник:** скрины владельца 2026-08-27 09:50 и 19:47, реальное устройство.

## 1. 🐛 «Не удалось сохранить транзакцию» — ДИАГНОЗ ПОДТВЕРЖДЁН

Репро владельца: Cashflow → Новый расход → категория «Кв Светлогорск»,
сумма 53 500 RUB, дата 26.08, частота «Не повторять», заметка «Перевел Ане»
→ галочка → алерт «Транзакция не сохранена. Проверьте выбранный счёт, дату
и доступный баланс».

### Root cause (аудит 2026-08-27, millio-audit)

Пикер счёта показывает core-счета (`Account`) наравне с легаси-картами (`Card`),
складывая **два разных типа ID в одно строковое поле `cardID`**. Проверка
достаточности средств при сохранении резолвит счёт **только через легаси `Card`**.
Core-UUID не находится → «card not found» → `canPersistTransaction` = false → алерт.

**Цепочка:**
- `CashflowTransactionEditorView.swift:1490` (`saveTransaction`, `cardID: selectedCardID`)
- → `CashflowTransactionEditorView.swift:1560` (`persistTransaction`)
- → `CashflowViewModel.swift:750`
- → `CashflowPersistenceService.swift:292` (`canPersistTransaction`)
- → `CashflowPersistenceService.swift:436-446` (expense-ветка, `isAmountAvailable`)
- → `CashflowPersistenceService.swift:225-227` (`cardProvider(fromCardID)` → `nil`)
- → `CashflowTransactionEditorView.swift:1568` (`showSaveErrorAlert = true`)

**Ключевые места:**
- `CashflowViewModel+Categories.swift:467-474` — `card(for:)` фетчит только
  `FetchDescriptor<Card>()`, матчит по `cardUniqueID`, никогда не смотрит в core `Account`.
- `CashflowSelectableAccount.swift:70-72` — core `Account` мапится как
  `.card(cardID: $0.id.uuidString)`, то есть `selectedCardID` может быть core-UUID.
- `CashflowTransactionEditorView.swift:1733` — автоподстановка
  `selectedCardID = selectableAccounts.first?.cardID` может незаметно выбрать core-счёт.

**Почему защита мертва:** `isAmountAvailable`/`canPersistTransaction` написаны под
легаси `Card` и не обновлены после интеграции core-счетов в пикер. Гэп между
«показываем core-счета» и «проверяем баланс только по легаси» — структурный.

**Уточнение исходной гипотезы:** дело НЕ в том, что `FinanceAccount` указывают на
легаси. Дело в двух типах ID в одном поле. Аудит данных
(`thoughts/research/2026-08-27-full-data-audit.md:39-48`) подтверждает 62 пары
«core ↔ легаси по имени» — владелец не отличает их на глаз, отсюда «то сохраняется,
то нет».

**Не подтверждено фактически:** дамп `scratchpad/backup-2026-08-27.json` на момент
аудита недоступен — конкретный ID из репро не проверен, вывод сделан по коду.
Исключены: ветка `.transfer` (репро — расход), гонка двойного тапа
(`isPersistingTransaction`, `CashflowViewModel.swift:743`).

### Файлы фикса
`CashflowPersistenceService.swift:101,218-245,427-464`,
`CashflowViewModel+Categories.swift:467-474`,
`CashflowSelectableAccount.swift:46-72`,
`CashflowViewModel+AccountsCore.swift:12-24`,
`CashflowTransactionEditorView.swift:1490-1580,1709-1734`.

## 2. 🎨 Редизайн выбора счёта — ВАРИАНТ СОГЛАСОВАН

Владелец (2026-08-27, скрины формы «Добавить доход»): «UI выбора карт нужно
сделать в стиле приложения», нужны избранные счета, видимые остатки,
основательная переработка.

### Решения владельца

| Развилка | Выбрано |
|---|---|
| Формат | **Bottom sheet со списком.** Секция «Избранные» сверху, ниже все счета. Строка = иконка + название + остаток. Без поля поиска. |
| Иконки | **Монограмма без правки схемы.** Легаси-карты — своя иконка и цвет; core-счета — буква-монограмма с цветом по имени. Миграция схемы НЕ делается. |
| Остатки | **Доступно к трате.** Дебетовая — остаток, кредитка — доступный лимит. |

### Что уже есть (переиспользовать, не писать заново)
- `CashflowSelectableAccount.swift:8-43` — в DTO **уже есть `isFavorite` и
  `prioritySortOrder`**; сейчас избранное рисуется лишь префиксом «★» в тексте
  (`pickerTitle`, строки 21-23).
- `NewCoreAccountRow.swift:5-64` — готовая строка счёта с иконкой и балансом
  (экран «Счета»).
- `AccountIconBadgeView.swift:5-50` — бейдж иконки: монограмма / SF Symbol /
  fallback + цвет + error-состояние. Монограмму умеет из коробки.
- UI-токены: `millio/UI/Design/` — `AppAnimation`, `AppColors`, `AppSpacing`,
  `AppTypography`, `MoneyFieldFontRamp`.

### Технические ограничения
- У core `Account` (`Core/AccountsCore/Account.swift:7-91`) и `CardMeta`
  (`AccountMeta.swift:9-17`) **нет полей** `isFavorite`, иконки, цвета. Есть
  `order: Int` (Account.swift:33). У легаси `Card` (`Card.swift:108-183`) всё есть:
  `isFavorite:157`, `customIconName`/`customIconColor`/`resolvedIconName:176-183`,
  `priority`→`sortOrder:36-60`, `cardColor:154`, `balance:133`.
- **Баланс core-счёта не хранится** — считается `AccountBalanceEngine.balanceAt(...)`
  по событиям. В форме Cashflow баланс core-счетов сейчас не показывается вообще
  (`cardBalanceSnapshot` возвращает nil, `CashflowViewModel+Categories.swift:457-474`).
  Показ остатков в списке потребует дёрнуть движок — учесть стоимость при 60+ счетах.
- Требования проекта: Dark Mode only, токены обязательны, денежный ввод — только
  `AmountInputFormatter`.
- Дублирующий `Menu` для transfer-селектора «куда» —
  `CashflowTransactionEditorView.swift:~1220` — переводить на тот же компонент.

### Точки рендера
`compactAccountSelector` — `CashflowTransactionEditorView.swift:822-839` (~18 строк).

## 3. ⚠️ Стресс-тест (2026-08-27) — ключевые выводы

**Наиболее вероятный класс регрессии — тихая порча атрибуции:** транзакция уходит
на счёт-двойник или на изменившийся дефолтный счёт БЕЗ ошибки и без алерта. Хуже
текущего бага, потому что не виден.

**Топ-риски:**
1. Соблазн «вернуть `true` при core-ID» в `isAmountAvailable`
   (`CashflowPersistenceService.swift:222-244`) = навсегда отключить проверку
   овердрафта для 62 счетов. Решать явно, с комментарием и тестом.
2. `CashflowTransactionEditorView.swift:1733` — новая сортировка меняет
   `selectableAccounts.first`, дефолтный счёт молча уезжает. Правило автоподстановки
   НЕ менять в одном PR с сортировкой; порядок зафиксировать тестом.
3. `id`-коллизия в `ForEach`: `id` = `"card:\(cardID)"` для обоих миров
   (`CashflowSelectableAccount.swift:26-31`). Разделить `Kind` на `.legacyCard`/
   `.coreAccount` с разными префиксами — это и есть честный «единый резолвер».
4. Transfer-путь: `CashflowPersistenceService.swift:280` —
   `cardProvider(toCardID)?.currency` → nil для core → конвертация по фолбэку,
   **тихая порча сумм перевода**. Резолвер валюты чинить вместе с балансом.
5. Ревёрт при редактировании: `applyAccountBalanceEffect:527` резолвит только `Card`.
6. Расчёт 60+ балансов движком синхронно в `body` = фриз шита. Async-прогон при
   открытии, кэш в `@State`, скелетон вместо нуля.
7. Показывать прочерк, а не «0 ₽», при отсутствии баланса (память
   `millio-stale-slice-vs-live-data`).
8. Пикер — отдельным файлом-компонентом; во View 2532 строк оставить 3 строки.

**Обязательно покрыть тестом:** расход на core-счёт сохраняется · расход на
легаси-счёт всё ещё блокируется при нехватке · create→edit→баланс сошёлся ·
перевод core→core с разными валютами · отсутствие дублей `id` при 62 парах ·
сортировка и дефолтный счёт.

## Решения владельца по итогам стресс-теста (2026-08-27)

- **Работу разбить на два шага** (ponytail-угол стресс-теста).
- **Двойники — отдельная задача.** Пикер их проблему на себя не берёт: показываем
  оба как есть. Сведение легаси-счетов в core и чистка данных — отдельным планом.

## Порядок

1. [x] Диагноз бага сохранения (millio-audit, без кода) — 2026-08-27.
2. [x] Согласование варианта редизайна с владельцем — 2026-08-27.
3. [x] Стресс-тест перед реализацией — 2026-08-27, выводы выше.
4. [x] **Шаг 1 — минимальный фикс сохранения.** РЕАЛИЗОВАН 2026-08-27, ветка
   `feature/cashflow-core-account-save-fix`, коммит `b987341` (не мержено, не пушено).
   `CashflowPersistenceService.isAmountAvailable` при `cardProvider == nil` резолвит
   счёт как core (`AccountsCoreCashflowBridge.resolveNewCoreAccount`) и считает
   доступные средства реплеем событий (`AccountBalanceEngine.balanceAt`), исключая
   события редактируемой транзакции по `sourceTransactionID` — та же семантика, что у
   `DebitCardOperationCoordinator.commitStagedCashflow:165`, поэтому предварительная
   проверка не расходится с валидатором `DebitCardContract.validate:74-77`.
   Овердрафт НЕ разрешён (антипаттерн №1 стресс-теста не применён).
   Подтверждено кодом: легаси-применение баланса (`applyAccountBalanceEffect:526-531`)
   для core-ID и в apply, и в revert — no-op, так как `cardProvider` возвращает nil;
   единственный писатель для core — `bridge.sync`.
   Тесты: `millioTests/UI/Services/Cashflow/CashflowCoreAccountPersistenceTests.swift`
   (4/4 зелёные; 2 из них красные при откате фикса — баг воспроизведён).
5. [ ] Проверка Шага 1 на реальном устройстве владельцем.
   ⚠️ Если целевой core-счёт реально пуст (баланс 0 из-за счёта-двойника), алерт
   остаётся — и он корректен. Это упирается в отложенную задачу о 62 парах.
6. [x] **Шаг 2 — редизайн пикера.** РЕАЛИЗОВАН 2026-08-27, ветка
   `feature/cashflow-account-picker-redesign` (от ветки Шага 1), коммит `ccae672`
   (не мержено, не пушено).
   - `CashflowSelectableAccount.Kind` разведён на `.legacyCard`/`.coreAccount` с разными
     префиксами `id` (`card:` / `core:`) — риск 3 закрыт; поле `cardID` осталось общим.
   - Новый компонент `millio/UI/Services/Cashflow/AccountPicker/CashflowAccountPickerSheet.swift`:
     секция «Избранные» сверху, строка = иконка + название + «доступно к трате»,
     без поиска. Легаси-карты — своя иконка/цвет, core-счета — монограмма по имени
     (`CashflowAccountPickerDetails.swift`), схема SwiftData не менялась.
   - Балансы считаются вне `body` (`CashflowViewModel+AccountPicker.swift`, async +
     `Task.yield` каждые 10 счетов), на время загрузки — скелетон, при отсутствии
     данных — прочерк, а не «0 ₽» (риски 6 и 7).
   - Оба transfer-селектора («откуда»/«куда») переведены на тот же компонент;
     `Menu` в `transferCardPickerRow` убран.
   - `CashflowPersistenceService.destinationCurrency(for:)` резолвит валюту получателя
     и для core-счёта (риск 4): раньше `nil` молча отключал проверку курса.
   - Сортировка резолвера и правило автоподстановки НЕ менялись (риск 2), зафиксировано
     тестом `sectionsDoNotChangeDefaultAccount`.
   - Тесты: `millioTests/UI/Services/Cashflow/CashflowAccountPickerTests.swift` (7/7)
     + 4 теста Шага 1. Полный прогон `millioTests`: 16 красных — тот же список, что и
     на базовом коммите `0983102` (сверено прогоном в отдельном worktree), новых нет.
7. [ ] Проверка Шага 2 на реальном устройстве владельцем.

## Отложено отдельными задачами
- **Сведение 62 пар счетов-двойников** (core ↔ легаси с одинаковыми именами) и
  чистка данных — решение владельца 2026-08-27.
- Миграция схемы core `Account` под иконки/цвета/избранное — см.
  `millio-schema-frozen-types-trap`.

## Связанное
- `thoughts/research/2026-08-27-full-data-audit.md` — аудит данных.
- Память: `millio-schema-frozen-types-trap` — почему миграция схемы core-модели
  отложена.
