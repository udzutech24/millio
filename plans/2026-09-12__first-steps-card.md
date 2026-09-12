# План — карточка «Изучи millio» (первые шаги)

**Статус:** РЕАЛИЗОВАН
**Ветка:** `feature/first-steps-card` (от `origin/develop` @ cb54a8d)
**Спека:** [`../specs/2026-09-12__first-steps-card.md`](../specs/2026-09-12__first-steps-card.md)

## Решения по реализации

**Это не виджет дашборда, а встроенная карточка.** ⚠️ Отменено в Ф4 решением
владельца 12.09.2026: карточка должна двигаться и удаляться как остальные
виджеты. Миграция сохранённого массива решается разовой инъекцией в `load()`.

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

## Ф2 — подсветка и экран бэкапа `[x]`

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

**Сделано 12.09.2026:** `HighlightEffect.swift` (`.highlightTarget(_:)`, обводка
brandPrimary + затухание за 2 с, сама снимает флаг), поля `highlightTarget` и
`pendingOpenProfileBackup` в `AppState`, подсветка кнопки «+» в `FinancesView`,
программный вход в `BackupManagementView` через
`navigationDestination(isPresented:)` в `ProfileView`. Колбэк карточки отдаёт
шаг целиком — `highlightID` берётся из массива шагов, не из `RootTabView`.
Шаг «резервная копия» подсветки не имеет: переход ведёт прямо на экран.

## Ф3 — тест и самоаудит `[x]`

- `millioTests/FirstStepsTests.swift` — прогресс и выполненность по снимку
  данных: пустой снимок = 2 из 5, снимок со счётом = 3 из 5, полный = карточка
  скрыта.
- Проход по acceptance criteria спеки, каждый отмечен.

Гейт: тест зелёный, регрессий в `millioTests` нет.

**Сделано 12.09.2026:** `millioTests/FirstStepsTests.swift` — три теста прогресса
по снимку, все зелёные. Полный прогон `millioTests`: 2770 passed, 23 failed.
Из них 12 красные и на `origin/develop` (проверено отдельным прогоном тех же
классов на baseline), остальные 8 — флак: на повторном прогоне той же ветки все
восемь зелёные. Регрессий от фичи нет.

Требуют проверки владельцем на живом приложении: карточка на чистой установке
после QuickSetup (AC1), закрытие шага без перезапуска (AC2), подсветка «+» в
Финансах (AC3), вход в экран резервной копии (AC4), исчезновение после
последнего шага (AC5), необратимость крестика после перезапуска (AC6).

## Запреты для исполнителя

- `git merge`, `git push`, `git rebase` — запрещены. Только коммиты в свою ветку.
- Сборка на устройстве и Simulator.app — не трогать.
- `Font.system(size:)` и числа в padding — запрещены, только токены.

## Ф4 — карточка как виджет + сворачивание `[x]`

Решение владельца 12.09.2026: карточка не должна занимать экран и не должна быть
вшита намертво.

Файлы:
- `millio/UI/Dashboard/DashboardWidgetID.swift` — case `firstSteps` (первым в
  `defaultWidgets`) + разовая инъекция в `load()` по флагу
  `dashboard.firstSteps.injected`: у существующего пользователя в сохранённом
  массиве нового виджета нет, сам он не появится. Флаг ставится один раз
  навсегда — удалённый виджет не вернётся.
- `millio/UI/Dashboard/DashboardView.swift` — case в `widgetView(_:)`, снятие
  жёсткой вставки из `normalModeContent` (Ф1), удаление виджета из
  `activeWidgets` тем же путём, что и в edit mode.
- `millio/UI/Dashboard/Widgets/FirstStepsCard.swift` — сворачивание
  (`@AppStorage("firstSteps.collapsed")`), шеврон, нажатие на шапку; флаг
  `firstSteps.dismissed` из Ф1 убран совсем — крестик и завершение чек-листа
  удаляют виджет.

Гейт: сборка зелёная, токены, ноль русских литералов; пользователь, прошедший
чек-лист до обновления, карточку не видит.

**Сделано 12.09.2026:** case `firstSteps` + инъекция в `load()`, case в
`widgetView`, `removeFirstStepsWidget()` в `DashboardView`, сворачивание с
шевроном в карточке, флаг `firstSteps.dismissed` удалён. Новых ключей
локализации не понадобилось — имя виджета берёт `first_steps.title`. Сборка
зелёная, `FirstStepsTests` зелёные (логика подсчёта не менялась).
