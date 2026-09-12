# План — карточка «Изучи millio» (первые шаги)

**Статус:** В РАБОТЕ
**Ветка:** `feature/first-steps-card` (от `origin/develop` @ cb54a8d)
**Спека:** [`../specs/2026-09-12__first-steps-card.md`](../specs/2026-09-12__first-steps-card.md)

## Решения по реализации

**Это не виджет дашборда, а встроенная карточка.** `DashboardWidgetStorage` не
мигрирует при новом case: у существующих пользователей сохранённый массив не
содержит новый виджет, и он не появится сам. Плюс карточка временная, её не надо
двигать и настраивать. Поэтому — прямая вставка в `normalModeContent` выше
`widgetsSection`, без case в `DashboardWidgetID`, без `AddWidgetSheet`.

**Подсветка — один общий модификатор**, потому что готового в коде нет
(проверено). Триггер — строка в `AppState`, чтобы работать через границу
навигации, как уже работают `pendingOpen*`.

**Новое поле `pendingOpenProfileBackup`** — экран резервной копии сейчас
открывается только статичным `NavigationLink` в профиле, программного входа нет.

## Ф1 — карточка и шаги `[x]`

Файлы:
- `millio/UI/Dashboard/Widgets/FirstStepsCard.swift` (новый) — `FirstStep`,
  `FirstStepsSnapshot`, массив шагов, вью карточки.
- `millio/UI/Dashboard/DashboardView.swift` — вставка выше `widgetsSection`,
  колбэк `onFirstStepAction: (FirstStep) -> Void`.
- `millio/UI/Root/RootTabView.swift` — проброс колбэка, реализация переходов
  через существующие `pendingOpenFinanceAddCard` и `pendingOpenMainExpenseSheet`.
- `millio/Localizable.xcstrings` — 8 ключей × ru/en/zh-Hans.

Гейт: сборка зелёная, карточка видна на чистом сторе, счётчик считает верно,
русских литералов в коде нет.

**Сделано 12.09.2026:** `FirstStepsCard.swift` (шаги + снимок + вью), вставка в
`DashboardView.normalModeContent`, `handleFirstStepAction` в `RootTabView`,
9 ключей `first_steps.*` (ru/en/zh-Hans). Сборка симулятора зелёная. `openBackup`
пока открывает профиль целиком — точечный вход в Ф2.

## Ф2 — подсветка и экран бэкапа `[ ]`

Файлы:
- `millio/UI/Design/HighlightEffect.swift` (новый) — `.highlightTarget("id")`,
  обводка + затухание за 2 с, снимает флаг сам.
- `millio/Core/AppState.swift` — `highlightTarget: String?`,
  `pendingOpenProfileBackup: Bool`.
- `millio/UI/Services/Finances/FinancesView.swift` — модификатор на кнопке «+».
- `millio/UI/Profile/ProfileView.swift` — программное открытие
  `BackupManagementView` по флагу.

Гейт: «Показать» у шагов 3 и 5 доводит до нужного экрана, подсветка гаснет сама
и не остаётся при повторном заходе.

## Ф3 — тест и самоаудит `[ ]`

- `millioTests/FirstStepsTests.swift` — прогресс и выполненность по снимку
  данных: пустой снимок = 2 из 5, снимок со счётом = 3 из 5, полный = карточка
  скрыта.
- Проход по acceptance criteria спеки, каждый отмечен.

Гейт: тест зелёный, регрессий в `millioTests` нет.

## Запреты для исполнителя

- `git merge`, `git push`, `git rebase` — запрещены. Только коммиты в свою ветку.
- Сборка на устройстве и Simulator.app — не трогать.
- `Font.system(size:)` и числа в padding — запрещены, только токены.
