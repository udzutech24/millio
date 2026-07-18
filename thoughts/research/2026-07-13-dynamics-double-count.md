# Research — двойной учёт мигрированного вклада в графике «Динамика»

Дата: 2026-07-13
Автор: Александр (iOS)
Статус: Stage 1 (Research) завершён
Режим Bulletproof: Standard (M, правки в 3+ файлах)

## Проблема (подтверждена чтением кода)

График «Динамика» на Дашборде даёт разные тоталы на одну дату в зависимости от
периода/пути расчёта; на дне миграции 6b (~12.07.2026) сумма мигрированного вклада
учитывается дважды; на домиграционной нулевой базе 1W показывает «+∞%».

## Root cause — точность до одного календарного дня

Граница «легаси → core» перекрывается ровно на день миграции (`archivedAt` легаси-
предшественника == день opening-снапшота core-двойника).

**Легаси-предшественник** (`legacyPredecessorContribution` → `calculateBalanceAtDate` →
`isLegacyActiveInTotal`, FinanceDynamicsViewModel.swift:1095, :2401):
- предикат `date > archivedAt → false`, т.е. легаси включается для `date <= archivedAt`
  (**инклюзивно на дне миграции**).

**Core-двойник** (`AccountsTotalsService.total`/`balance`, :60/:92; `Account.participates`, :63):
- у core-двойника `archivedAt == nil` → `participates(on:)` всегда `true`;
- opening-снапшот `dayKey == день миграции`, предикат `dayKey <= dayKey` →
  на дне миграции и позже `balance` возвращает core-баланс (**core тоже включён на дне миграции**).

Итог по дням:
| день относительно миграции | легаси | core | результат |
|---|---|---|---|
| до (`date < archivedAt`) | включён | 0 (нет снапшота ≤ date, реплей=0) | ок |
| **день миграции (`date == archivedAt`)** | **включён** | **включён (снапшот)** | **ДВОЙНОЙ УЧЁТ** |
| после (`date > archivedAt`) | исключён | включён | ок |

Перекрытие — ровно 1 календарный день.

## Расхождение заголовок vs график/таблица

- заголовок: `.currentVisible` scope (:807, :840…);
- график/таблица: `.historicalInterval` scope (:810, :1083, :1491…).
Оба ядровой вклад берут через `coreContributionWithLegacyPredecessor` (:1147) и
`coreAccountDynamicsItems` (:1169) — оба зовут ту же `legacyPredecessorContribution`.
→ Единая правка граничной логики в `legacyPredecessorContribution` чинит все пути
сразу. Разница `currentVisible`/`historicalInterval` для чисто-легаси счетов —
преднамеренная (видимые vs вся история), проверить, что на заданную историческую
дату набор счетов совпадает.

## «+∞%»

`calculateDeltaPercent` (:2422) при `|startBalance| < 0.01` возвращает sentinel
±999999. Рендер `FinanceAmountText.percent` (:45) при `|value| >= 999999` печатает
«+∞»/«-∞». Sentinel рождается ТОЛЬКО из near-zero базы → это «процент не определён»,
а не «очень большой процент». Часть «+∞» на 1W уходит после фикса двойного учёта
(база на домиграционном дне станет корректной), но UI-фолбек для near-zero базы
всё равно нужен как явный инвариант.

## Как решают эту задачу (WebSearch)

Стандарт миграции time-series/бухгалтерии: **cutoff partitioning** — запись живёт
ровно в одной системе (live ИЛИ archive), без перекрытия, с единой точкой отсечения;
для mid-period переносов явно фиксируется, какая система «владеет» датой cutover,
чтобы не задвоить и не потерять. Валидация — тоталы обеих систем должны совпадать
«до копейки» на границе.

Проекция на нас: единый cutoff = день миграции (`archivedAt`). Легаси владеет днями
**строго до** миграции; core владеет днём миграции и далее (его opening-снапшот несёт
перенесённый баланс = финальный баланс легаси → непрерывно, без разрыва).

## Вывод — лучшее решение

**Сузить окно легаси-предшественника до `dayKey(date) < dayKey(legacyArchivedAt)`**
(day-granularity, строгая граница), scoped ТОЛЬКО к мигрированным предшественникам
внутри `legacyPredecessorContribution` — НЕ трогая глобальный `isLegacyActiveInTotal`
(он же обслуживает обычные архивные легаси-счета; их поведение менять нельзя).
Плюс UI-фолбек «н/д» для near-zero базы вместо «∞».

Почему это лучшее: KISS, одна точка отсечения, чинит все пути сразу, не трогает
AccountsCore/снапшоты (низкий риск), не задевает не-мигрированные архивные счета.

Отвергнутые альтернативы:
1. Сдвиг opening-снапшота core на `archivedAt+1` — трогает генерацию снапшотов и весь
   `AccountsTotalsService`, широкий blast radius, риск для тоталов всех экранов.
2. Глобальная смена `isLegacyActiveInTotal` на `date < archivedAt` — регрессия для
   обычных архивных легаси-счетов (пропадут на день раньше).

## Ключевые file:line
- FinanceDynamicsViewModel.swift: `legacyPredecessorContribution` :1095; `isLegacyActiveInTotal` :2401;
  `calculateDeltaPercent` :2422; `coreContributionWithLegacyPredecessor` :1147;
  `coreAccountDynamicsItems` :1169; scope paths :807/:810/:1083/:1491.
- AccountsTotalsService.swift: `total` :60; `balance` :92 (snapshot `dayKey <= dayKey` :102).
- Account.swift: `participates` :63.
- FinanceAmountText.swift: sentinel-рендер :45.
