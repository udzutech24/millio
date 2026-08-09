# 2026-08-08 — Phase 5 cache-first historical rates

## 1. Задача

Реализовать cache-first загрузку исторических курсов для legacy и core-счетов в Phase 5,
с ЦБ как основным источником RUB-пар.

## 2. Как решалась

- Проверены research/spec/plan Phase 5 и legacy/core read paths.
- Core compatibility totals переведены на общий SwiftData-backed `HistoricalRateStore`.
- Прогрев Dynamics расширен валютами core-счетов.
- Для RUB-пар provider order изменён на CBR → Frankfurter.
- Добавлены unit-регрессии на cache hit, CBR-first/fallback и core cache-first.

## 3. Решена ли

Частично. Код и test target компилируются. Focused tests не запустились: два разных
симулятора отклонили cloned test runner с `launchd job spawn failed`. Операционные gates
Phase 5 по-прежнему открыты.

## 4. Эффективно ли

Да: использован существующий store без новой абстракции и drive-by рефакторинга. Полный test gate
не заявлен без фактического запуска.

## 5. Было → Стало

| Область | Было | Стало |
|---|---|---|
| Core history | Прямой provider call | Общий cache-first store |
| Dynamics prefetch | Только legacy-валюты | Legacy + core currencies |
| RUB history | Frankfurter → CBR | CBR → Frankfurter |

## 6. Идеи по улучшению

- Агенты: 0 наблюдений.
- Токены/контекст: 0 наблюдений.
- Процесс: simulator lease/clone instability уже зафиксирована в
  `improvements/agents/2026-08-08-simulator-lease-coordination.md`; дубликат не создавался.
- Бизнес: 0 наблюдений.

## 7. Артефакты

- Коммиты не создавались.
- План актуализирован; Phase 5 остаётся в работе.

## 8. Коррекция после real-device evidence

Скриншоты доказали, что FX-фикс не закрыл дефект: экран «Счета» видел `Account`,
а Динамика собирала core scope через пустые legacy-`FinanceGroup`. Scope переведён на
прямой `Account` fetch; добавлен core-only тест без единой legacy-группы. Production и test targets
успешно прошли `build-for-testing`.

Добавлен non-PII лог `HistoricalPortfolio` для incomplete-серий: только counts, dimensions и
reason codes, без имё, ID и сумм. Xcode debug console не доступна из Codex-сессии; живой
запуск должен дать точный unresolved reason до следующего изменения алгоритма.
