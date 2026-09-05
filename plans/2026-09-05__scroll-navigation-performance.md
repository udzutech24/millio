# Производительность: тормоза при скролле и переходах (iPhone 17 Pro)

Диагноз: millio-audit, 2026-09-05. Ветка для работы — новая от `develop`: `perf/scroll-navigation`.
Принцип: минимальные точечные правки, без рефакторинга архитектуры. Каждая фаза — отдельный коммит + гейт.

## [x] Ф0. Замер «до» — РЕАЛИЗОВАН (коммит `70e6a96`)
Instruments на устройстве владельца недоступен — заменён воспроизводимым замером в тестах:
`millioTests/Performance/AccountBalancePerformanceTests.swift`. Фикстура: 62 счёта, 6 групп,
каждый 5-й без группы, 30–200 событий на счёт, 3 валюты, вклады, события редоминации.

Цифры «до» (iPhone 17 Pro, симулятор 26.5; бюджет кадра 60 fps = 16.7 мс):

| Сценарий | Среднее | stddev | В кадрах |
|---|---|---|---|
| один вызов `newCoreBalanceToday` | 2.30 мс | — | 0.14 |
| проход списка из 62 счетов | 154.0 мс | 2.4 мс | 9 |
| проход body экрана «Счета» | 452.7 мс | 21.1 мс | 27 |

Проход body втрое дороже голого списка: `sortedAccounts` → `displayCurrencyBalances` делает
второй полный круг реплеев поверх того, что уже считают строки.

Грабли для следующих фаз: метрики `measure {}` новый `xcresulttool` наружу не отдаёт, а `print`
из раннера в симуляторе не форвардится в лог `xcodebuild` — цифры печатаются через
`XCTContext.runActivity` и читаются командой `xcresulttool get test-results activities`.

## [x] Ф1. Кэш баланса счёта — РЕАЛИЗОВАН (коммит `a549072`)
- Новый `millio/UI/Services/Finances/AccountBalanceCache.swift`; пересчёт в `loadCoreEntities()`,
  чтение из `newCoreBalanceToday`, аварийный реплей вынесен в `replayBalanceToday`.
- Валидность кэша привязана к отпечатку ревизий счёта (`membership`/`financial`/`events`), а не к
  сигналу «обновись». Их бампит каждый писатель ленты — список аудируется в
  `HistoricalValuationWriterInventory`. Промах деградирует в прежнее поведение, не в неверную цифру.
- Кэш намеренно НЕ внутри `@Published state`: строки читают его из тела View, а запись в `state`
  оттуда — мутация во время отрисовки.

| Сценарий | До | После | Раз |
|---|---|---|---|
| один вызов `newCoreBalanceToday` | 2.30 мс | 0.0023 мс | ×980 |
| проход списка из 62 счетов | 154.0 мс | 0.148 мс | ×1040 |
| проход body экрана «Счета» | 452.7 мс | 1.521 мс | ×298 |

Тесты: `millioTests/UI/Services/Finances/AccountBalanceCacheTests.swift` — 6 штук (инвариант
«кэш == реплей», промах по устаревшему отпечатку, смена суток, путь создания события, путь
`adjustBalance`, правка `creditLimit`). Гейт `millioTests`: было 27 красных / 2640 зелёных,
стало 24 / 2649. Новых красных нет.

**Отступление от плана (осознанное).** Живой fetch в `ungroupedAccounts()` / `isGroupEmpty` НЕ
заменён срезом `state`. Комментарий `[R8]` в коде и память проекта («кэш-срез vs живые данные»,
всплывало трижды) прямо фиксируют: срез уже делал секцию пустой после restore. После кэша на весь
этот путь приходится ~1.5 мс из 16.7 мс бюджета — менять рабочее поведение ради этого нечем
обосновать (prove the bug is real). Вместо замены убран чистый дубль: `groupsListView`
(`FinancesView.swift:935`) гонял `isGroupEmpty` — а с ним fetch легаси-группы — дважды на каждую
группу; теперь одно разбиение вместо двух фильтров.

**Хвост для Ф4.** Замер не покрывает легаси-хвост владельца: в фикстуре нет записей
`FinanceGroup`/`Card`, поэтому `legacyAccountsMatchingGroupName` (fetch на группу на каждый проход
body) возвращает пусто и стоит около нуля. На устройстве владельца этот путь дороже — проверять
на device-прогоне.

## Ф2. Табы: TabView вместо ZStack+opacity
- `RootTabView.swift:213-229`: 4 экрана всегда в дереве. Заменить на `TabView(selection:)` — SwiftUI сам не рендерит неактивные.
- Проверить, что ничего не опиралось на «экран жив в фоне» (таймеры, onAppear-логика Dynamics, сохранение позиции скролла). Если Dynamics строит Charts в `opacity(0)` — это уйдёт само.
- Разбить `@Published var state = FinanceState()` (`FinanceViewModel.swift:235`) — НЕ делать в этой фазе (архитектурно, дорого). Вместо этого убрать частые мутации (тост, `lastRefreshedAt`) в отдельный `@Published`/локальный `@State`.
- `FinancesView.swift:547` `@Query _allCards` + `cardBalanceHash` (`:551`) — убрать, если данные уже есть в state; иначе предикат/лимит.

## Ф3. Форматтеры и layout в hot-path
- `NumberFormatter()` на каждый вызов: `FinanceRows.swift:472`, `NewCoreAccountRow.swift:86`, `FinanceAmountText.swift:25`, `CashflowView.swift:30` (27 мест), `TotalBalanceWidget.swift:27,51`.
- Фикс: статический кэш `[currency+locale: NumberFormatter]` в существующем `AmountInputFormatter`/общем helper (правило: денежный ввод — только через него); один `sed`-проход по call-sites.
- `TotalBalanceWidget.swift:153` Timer 1/60 → `TimelineView(.animation)` или `withAnimation` на значении; один вызов вместо 39 перерисовок.
- `AccountRowView.swift:23-87` `OverflowFadeText`: 2 GeometryReader на каждый текст → `.lineLimit(1)` + `.truncationMode` или `ViewThatFits`; fade оставить только если владелец настаивает визуально.

## Ф4. Замер «после» + device-проверка
- Повторить Ф0, таблица до/после в `progress/`. Цель: 0 hitches при скролле «Счета», переключение таба < 1 кадра задержки.
- Билд на устройство владельца, ручная проверка 4 сценариев. Проверить `git diff Localizable.xcstrings` перед мержем (грабли device-сборки).
- Мерж в develop — только по «да» владельца. Push — по запросу.

## Не делаем (осознанно)
- Разбивку `FinanceState` на несколько VM, переход на `@Observable` — отдельная задача после релиза.
- Виртуализацию Dynamics-графиков — сначала смотрим, что даст Ф2.
