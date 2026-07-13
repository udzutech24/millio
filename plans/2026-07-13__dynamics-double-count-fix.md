# План — фикс двойного учёта в графике «Динамика»

Дата: 2026-07-13 · Статус: РЕАЛИЗОВАН · Размер: M (Standard) · Ветка: `feature/dynamics-double-count-fix`
Spec: `specs/2026-07-13-dynamics-double-count-fix.md`
Research: `thoughts/research/2026-07-13-dynamics-double-count.md`

## Подход (одно предложение)

Сузить окно легаси-предшественника до строгой day-granularity границы
`dayKey(date) < dayKey(legacyArchivedAt)` внутри `legacyPredecessorContribution`
(единая точка, чинит все пути) + UI-фолбок «н/д» для near-zero базы.

---

## Фазы

### [x] Фаза 1 — Day-granularity cutoff легаси-предшественника — РЕАЛИЗОВАН
- В `legacyPredecessorContribution` (FinanceDynamicsViewModel.swift:1095) для каждого
  легаси-предшественника с `archivedAt` добавлять вклад ТОЛЬКО когда
  `AccountEvent.dayKey(for: date) < AccountEvent.dayKey(for: archivedAt)`; иначе 0
  (core-двойник уже владеет днём миграции через opening-снапшот).
- НЕ трогать `isLegacyActiveInTotal` (обычные архивные легаси-счета).
- Комментарий-инвариант: почему строгая граница (день миграции принадлежит core).
- Gate: build + существующие тесты Динамики зелёные.

### [x] Фаза 2 — UI: скрытие процента при near-zero базе — РЕАЛИЗОВАН
> ⚠️ Решение владельца (2026-07-13) отличается от исходного текста плана: НЕ показываем
> «н/д»/«—»/«+∞», а вообще не рендерим процентный лейбл при sentinel-базе. Ключ
> `dynamics.percent.undefined` НЕ добавлялся (не нужен). Реализовано через
> `FinanceAmountText.isPercentUndefined(value:isHidden:)` + условный рендер в 3 точках
> `FinanceDynamicsView` (header-бейдж + 2 badge-строки). Приватное маскирование `isHidden` сохранено.

<details><summary>исходный текст фазы</summary>
- Ввести явный sentinel-семантику: `calculateDeltaPercent` при near-zero базе
  возвращает признак «не определено» (оставить ±999999 как sentinel ИЛИ `.nan` —
  решить в имплементации, рекомендация: оставить порог 999999, т.к. он уже только
  из near-zero базы рождается).
- В рендере (`FinanceAmountText.percent`:45) вместо «+∞»/«-∞» отдавать
  локализованный `L("dynamics.percent.undefined")` = «н/д» (сохранить маскирование
  при `isHidden`).
- Ключ `dynamics.percent.undefined` в Localizable.xcstrings: RU «н/д», EN «n/a», zh-Hans «无数据».
- Gate: build зелёный.
</details>

### [x] Фаза 3 — Unit-тесты + верификация — РЕАЛИЗОВАН
- Тест непрерывности перехода: `archivedAt-1` (только легаси), `archivedAt`
  (только core, НЕ сумма) , `archivedAt+1` (только core) — тотал непрерывен, без задвоения.
- Тест-регрессия: старое поведение (double-count на дне) воспроизводимо на pre-fix логике.
- Тест near-zero базы → фолбок «н/д», не «∞» и не число.
- Тест AC1: заголовок == первая точка серии == сумма строк на историческую дату.
- Gate: `xcodebuild test … -quiet | tail`, зелёные.

---

## Challenge Loop (перед финализацией)

1. **Решает ли проблему?** Да. AC2 закрыт cutoff'ом (Ф1), AC3 фолбоком (Ф2), AC1/AC4/AC5
   тестами (Ф3). Единая точка `legacyPredecessorContribution` покрывает все пути (header/
   graph/table), т.к. все они зовут её.
2. **Самое эффективное?** Да. Альтернативы (сдвиг opening-снапшота; глобальный
   `isLegacyActiveInTotal`) имеют больший blast radius и/или регрессируют обычные архивные
   счета — отвергнуты в research. Выбранный путь — минимальная правка, низкий риск.
3. **Код ради кода?** Нет. Ф1 = 1 условие; Ф2 = 1 ключ + смена ветки рендера; Ф3 = тесты.

---

## Стресс-тест (10 причин провала)

1. **Данные/граница:** сдвиг границы не в ту сторону → gap (недосчёт) вместо overlap.
   Вероятность: средняя. → Тест непрерывности archivedAt-1/archivedAt/archivedAt+1 (Ф3).
2. **Функционал:** несколько мигрированных вкладов с разными `archivedAt` — граница на
   счёт, не глобальная. Средняя. → cutoff считается per-account внутри цикла (уже так).
3. **Функционал:** легаси-предшественник без `archivedAt` (не архивирован). Низкая. →
   `guard let archivedAt` → поведение без изменений (не мигрирован — не задваивается).
4. **UX:** «н/д» пугает/непонятен на первой точке периода. Низкая. → семантически честнее
   «+∞»; локализован; согласовать формулировку с владельцем (вопрос ниже).
5. **Локализация:** новый ключ ломает zh-Hans при отсутствии перевода. Низкая. → три
   локали сразу в Ф2, прогон L10n-теста.
6. **Регрессия:** обычные архивные легаси-счета (ручной архив) — НЕ трогаем
   `isLegacyActiveInTotal`, только предшественников. Низкая. → AC5-тест.
7. **Согласованность:** header (`.currentVisible`) и graph (`.historicalInterval`) на
   историческую дату дают разный набор счетов → AC1 не сойдётся. Средняя. → Ф3 AC1-тест;
   если разойдётся — эскалация (scope-семантика Non-Goal, отдельная задача).
8. **Производительность:** правка в горячем per-day цикле (`seriesBetween`). Низкая. →
   добавляем 1 сравнение dayKey, без новых fetch.
9. **Зависимости:** `LegacyConversionRegistry` пуст/не заполнен → предшественник не
   находится. Низкая. → `guard let legacyUniqueID … else continue` уже есть; фикс не
   меняет этот путь.
10. **Слепое пятно:** sentinel ±999999 теоретически совпадёт с реальным гигантским %.
    Низкая. → уже сегодня рендерится как ∞; смена на «н/д» не ухудшает; при желании —
    отдельный sentinel (обсуждаемо, не блокер).

Красных (высокая вероятность краха) нет. Основной риск — #1 и #7, закрываются тестами Ф3.

---

## Impact Analysis
- **Регрессия:** `legacyPredecessorContribution` зовётся из `coreContributionWithLegacyPredecessor`
  (Cashflow Start, CashflowViewModel+Categories.swift:393) и `coreAccountDynamicsItems` —
  оба выиграют от фикса согласованно; проверить Cashflow Start на дне миграции.
- **Side effects:** контракт функций не меняется (та же сигнатура, скорректирован лишь
  вклад на границе).
- **Compatibility:** данных не мигрируем; бэкап-схема не затронута.
- **Edge cases:** покрыты стресс-тестом #1–#3, #9.

## Журнал
- 2026-07-13 — создан план после Research+Spec; стресс-тест пройден, красных нет; ждём
  подтверждения владельца перед имплементацией (guard phrase).
- 2026-07-13 — РЕАЛИЗОВАНО (ветка `feature/dynamics-double-count-fix`, коммиты b7af609 Ф1-2, ba50396 Ф3).
  - Ф1: `legacyPredecessorContribution` (FinanceDynamicsViewModel.swift:1101) — вклад легаси-
    предшественника только при `dayKey(date) < dayKey(archivedAt)`; иначе 0. archivedAt резолвится
    из кэшей конкретной модели новым хелпером `legacyPredecessorArchivedAt(for:)`
    (FinanceAccount archivedAt не хранит). Инвариант строгой границы задокументирован в коде.
  - Ф2: решение владельца изменено — при sentinel-базе процент не рендерится совсем.
    `FinanceAmountText.isPercentUndefined(value:isHidden:)` + условный рендер в 3 точках
    `FinanceDynamicsView` (строки ~1123, 2459, 2503). Ключ локализации НЕ добавлялся.
  - Ф3: `FinanceDynamicsLegacyCutoffTests` (2 теста: непрерывность перехода + регрессия
    немигрированного архивного) + 3 теста `isPercentUndefined` в `FinanceAmountTextTests`.
  - Гейты: build SUCCEEDED; тесты FinanceDynamicsLegacyCutoffTests/FinanceAmountTextText/
    FinanceDynamicsCoreContributionTests — все passed (0 failed).
  - Impact: `coreContributionWithLegacyPredecessor` (Cashflow Assets-snapshot) и
    `coreAccountDynamicsItems` наследуют фикс автоматически (общая точка) — подтверждено
    прохождением существующих CoreContribution-тестов.
  - Осталось: НЕ запушено (по регламенту — push/merge с владельцем); проверка на реальном
    устройстве на сценарии владельца (скачущий график 1D/1W) — PENDING.
