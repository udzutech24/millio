# План: упрощение экрана ввода операций (Расходы / Доходы)

**Дата:** 2026-09-06 · **Владелец:** Алексей · **Исполнитель:** Александр · **Статус:** РЕАЛИЗОВАН — Ф1–Ф5 в ветке `feature/entry-screen-simplify`, ждём device-проверку владельца (мерж/пуш не делались)
**Макет:** https://claude.ai/code/artifact/308226c9-680b-4aca-98c9-77aa4fa34e46 (артборды «Расходы», «Доходы», «Меню …»)
**Ветка:** `feature/entry-screen-simplify` от `develop` (НЕ от `feature/planned-operations-applied-notice`)

## Цель

Экран `CashflowCategoryTransactionSheet` перегружен: 4 пилюли в шапке, карточка с кольцом и кнопкой «План», три иконки-кнопки, сортировка, фильтр истории All/Upcoming/Paid. Оставить на экране только ежедневное: сегменты · месяц · сумма с полоской плана · категории · последние операции. Всё редкое — в лист «…» снизу. Функциональность не теряется, меняется только доступ к ней.

## Что где сейчас (research)

Корень: `millio/UI/Services/Cashflow/UnifiedEntry/CashflowUnifiedEntryView.swift` (1539 строк).

| Элемент | Строки | Судьба |
|---|---|---|
| Крестик, стрелки месяца, «История операций», меню «…» | 363–433 | Крестик и «…» остаются, «История» уходит |
| Карточка «за месяц» + «План» + кольцо | 439–507 | Переделать: сумма на фоне + полоска, без рамок |
| Три иконки (recurring/bulk import, planned, search) | 549–645, `CashflowManagementEntry.swift` | В лист «…» |
| Меню сортировки | 688–701 | В лист «…» |
| Сетка категорий 2 колонки | 705–731, карточка 816–916 | 3 колонки, компактнее, + плитка «Новая» |
| «All categories» | 736–753 | Текстовая кнопка «Все» в заголовке секции |
| История с фильтром All/Upcoming/Paid | `CashflowUnifiedEntryHistorySection.swift:50–55` | Фильтр убрать, 3 строки, плановые помечать словом «план» |
| Long-press категории → overlay (pin/операции/edit/delete) | 286–319, 910–913 | Без изменений |

## Фазы

### ✅ [x] Ф1 — Лист «…» (bottom sheet) — РЕАЛИЗОВАН (`4359c04`)
- Новый `CashflowEntryMoreSheet.swift`: секции «Операции» (Найти · Плановые · Повторяющиеся или Импорт списком по типу) · «Месяц» (План на месяц) · «Категории» (Сортировка · Порядок и закрепление · Настройки экрана · Новая категория).
- Каждый пункт дёргает существующий стейт (`showPlannedManagement`, `showRecurringManagement`, `showBulkExpenseImportSheet`, `showBudgetSetupSheet`, `sortMode`, `showReorderSheet`, `showSettingsSheet`, `showCreateCategorySheet`, `isSearchExpanded`).
- Правило владельца: лист снизу, детент фиксированной высоты ([[feedback-bottom-sheet-under-thumb]]).
- Критерий: каждый из 9 пунктов открывает то же, что открывала старая кнопка. Старые кнопки ещё на месте.

### ✅ [x] Ф2 — Шапка и блок суммы — РЕАЛИЗОВАН (`b9028b4`)
- Убрать пилюли «История операций», три иконки, кнопку «План», кольцо.
- Месяц: текст со стрелками по центру. Сумма 44 pt на фоне, под ней полоска плана 6 pt с градиентом типа (`AppColors` income/expense), строка «N% от плана X · осталось Y». Нет плана → полоска скрыта, строка «Плана нет».
- Тап по блоку суммы → `showTransactionsHistory = true`.
- Критерий: экран без плана и с планом; сумма 0.

### ✅ [x] Ф3 — Категории и операции — РЕАЛИЗОВАН (`781b4cd`)
- `LazyVGrid` 3 колонки, плитка: иконка в круге 40 pt · имя · сумма. Последняя плитка «Новая» (пунктир) → `showCreateCategorySheet`.
- Заголовок секции «Категории» + текстовая «Все» → `showAllCategories`.
- История: убрать сегмент All/Upcoming/Paid, показывать 3 последних (paid + upcoming вперемешку по дате), у upcoming подпись «· план» и серый цвет суммы; «История» в заголовке → `onOpenPaidHistory`.
- Критерий: long-press и pin работают как раньше; 0 категорий и 0 операций не ломают верстку.

### ✅ [x] Ф4 — Чистка и локализация — РЕАЛИЗОВАН
- Удалить мёртвый код старых кнопок и `CashflowManagementEntry`, если он больше нигде не используется (grep).
- Строки ru/en/zh-Hans в `Localizable.xcstrings`; проверить `git diff` файла после сборки на устройство ([[feedback-xcodebuild-xcstrings-corruption]]).

### ✅ [x] Ф5 — Декомпозиция `CashflowUnifiedEntryView.swift` — РЕАЛИЗОВАН (`6ae1221`)
- Разнести на `…Header.swift` (шапка + месяц + сумма), `…CategoryGrid.swift` (сетка + плитка + overlay действий), `…MoreSheet.swift` (из Ф1), корень ≤400 строк.
- Чистый рефакторинг без изменения поведения: гейт = тот же набор тестов, device-проверка не нужна.

## Гейты
- Сборка `xcodebuild … -quiet 2>&1 | tail -20`, изолированный `-derivedDataPath`.
- `millioTests`: baseline ~2690–2720 зелёных / 18–23 красных ([[millio-flaky-tests-known]]) — регрессии нет, если красные те же.
- Device-проверка владельцем после Ф3 по чек-листу: 9 пунктов меню · план/без плана · long-press · «Все» · «История» · доходы и расходы · zh-Hans.
- Стресс-тест перед Ф4 (снос кода) — правило 7 CLAUDE.md.

## Оценка
Ф1 ≈ 1 ч · Ф2 ≈ 1 ч · Ф3 ≈ 1.5 ч · Ф4 ≈ 0.5 ч · Ф5 ≈ 1 ч. Три сессии: Ф1+Ф2 · Ф3+Ф4 · Ф5 ([[feedback-long-multiphase-plan-eta]]).

## Решения владельца (2026-09-06)
1. Плановые операции в «Последних» показывать — серым, с пометкой «план».
2. Сегмент «Перевод» не трогаем.
3. Ф5 декомпозиция — делать, отдельной сессией после Ф4.

## Журнал

- **2026-09-06, Ф1** (`4359c04`): `CashflowEntryMoreSheet.swift` — детент `.height(470)`, секции Операции / Месяц / Категории.
  Действие листа выполняется в `onDismiss` (`performPendingMoreAction`) — iOS не открывает sheet поверх закрывающегося.
  Секция «Операции» переиспользует `CashflowManagementEntry.entries(for:)`, сортировка — inline Menu без закрытия листа.
  Новых ключей 4 (`cashflow.entry.more.*`), сборка зелёная.
- **2026-09-06, Ф2** (`8ffb969`): убраны пилюля «История операций», три иконки, `searchToggleButton`, кнопка «План»,
  кольцо (`heroChartEntries`/`heroCardBackground`) и рамочная карточка. Новый блок: сумма `.millioAmountHero` (44 pt),
  полоска плана 6 pt (`kind.strokeGradient`), строка `cashflow.entry.plan.summary` / `cashflow.entry.plan.none`.
  Тап по блоку → `showTransactionsHistory`. Поле поиска осталось (`searchFieldSection`), иконка-переключатель — в листе «…».
  `CashflowManagementEntry` пока жив (используется листом) — снос старого кода остаётся на Ф4.
- **2026-09-06, Ф3**: сетка 3 колонки (`CashflowCategoryGridLayout.regularColumns = 3`, тесты сравнивают с самой константой —
  остались зелёными), компактная плитка (иконка в круге 40 pt · имя · сумма + полоска лимита 3 pt), пунктирная плитка «Новая».
  Заголовок «Категории» + текстовая «Все» (только когда сетка обрезана); большая кнопка «All categories» и меню сортировки убраны,
  `showReorderSheet` перевешен на общий список sheet'ов. История: сегмент All/Upcoming/Paid убран, 3 строки вперемешку по дате,
  у плановых подпись «дата · план» и серая сумма, заголовок «Операции» + текстовая «История». Новых ключей 3.
  Мёртвыми стали `categoryBudgetBadgeText`, `categoryBudgetLimitLabel`, `CashflowEntryHistoryFilter`, `pinPlacement` — сносим в Ф4.
- **2026-09-06, Ф4**: стресс-тест — `thoughts/research/2026-09-06-entry-simplify-stress-test.md`.
  Снесены `categoryBudgetBadgeText`, `categoryBudgetLimitLabel`, `monthlyBudgetUsageText`, `categoryStrokeStyle`,
  `CashflowEntryHistoryFilter` + `filteredAndSorted`, `PinPlacement` + `pinPlacement`, ключи `cashflow.category.show_all`
  и `cashflow.category.quick_select`. Тесты правились точечно: сняты 2 кейса про `filteredAndSorted` и 2 про `pinPlacement`,
  три кейса сетки переведены на 3 колонки (+ новый кейс «<280 pt → 2 колонки»), тест локализации заголовка переехал
  на `cashflow.entry.more.section.categories`.
  НЕ снесено осознанно (обосновано в стресс-тесте): `CashflowManagementEntry` (жив — его использует лист «…»),
  `CashflowEntryHistoryStatusPolicy` и `pinAffordanceStyle` (предсуществующий тестируемый код, кандидаты на Ф5),
  `CashflowBudgetLocalization.categoryBadgeText/categoryBudgetLimitLabel` и их ключи — чтобы вернуть бейдж лимита
  стоило 5 строк, если владельцу полоски 3 pt окажется мало.
  Гейт: сборка exit=0; целевые тесты 46/46 passed, 0 failed (`xcresulttool`, 7 классов Cashflow/UnifiedEntry).
- **2026-09-06, Ф5**: чистый рефакторинг, поведение/строки/ключи не менялись. 1450 → **421** строка в корне.
  Новые файлы (extension'ы того же типа, без новых структур и протаскивания биндингов):
  `CashflowUnifiedEntryHeader.swift` 262 · `CashflowUnifiedEntryCategoryGrid.swift` 549 · `CashflowUnifiedEntryDataLoading.swift` 198.
  Третий файл (месячный срез + бюджетные хаптики, ~200 строк) добавлен сверх плана: без него корень оставался 542 строки.
  Оверлей действий над категорией уехал из `body` в `categoryActionsOverlay`/`categoryDeletionSheet`/`categoryUndoOverlay`.
  Цена подхода: `private` в Swift — область файла, поэтому хранимое состояние экрана и общие хелперы стали internal;
  `Calendar.startOfMonth` из `private extension` стал internal (второго определения в проекте нет — коллизии не будет).
  Гейт: сборка exit=0, те же 7 классов тестов 46/46 passed.
