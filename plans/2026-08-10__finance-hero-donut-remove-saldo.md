# План: donut общего баланса без дублирующего сальдо

**Статус:** РЕАЛИЗОВАНО
**Режим:** S (`millio-bulletproof`), 3 production-файла + тесты.

## Запрос владельца

- В верхней зоне общего баланса добавить компактную donut-иконку по референсу.
- Убрать справа блок `САЛЬДО +98…`, потому что он повторяет общий баланс сверху.
- Сохранить суммы дебета/кредита и горизонтальную полосу их соотношения.

## Доказанное текущее состояние

- Общий баланс уже рендерится в `FinancesView.totalAmountSection`.
- `FinanceOverviewCardView.assetsLiabilitiesStackedBar` повторно рендерит
  `presentation.saldo` справа от дебета/кредита.
- `FinanceOverviewLedgerPresentation` уже содержит единственные корректные debit/credit totals;
  новый donut должен использовать их, а не заводить второй финансовый расчёт.

## Решение

1. Удалить правый VStack `САЛЬДО` из compact overview.
2. Добавить небольшой SwiftUI donut-компонент, сегменты которого строятся из долей
   `debit.total / (debit.total + credit.total)` и `credit.total / ...`.
3. Передать готовые доли/презентацию из `FinanceOverviewCardView` в верхний hero без повторного
   запроса данных. Donut — визуальный consumer существующего ledger presentation.
4. Разместить donut в правой части верхней зоны с адаптацией под узкий экран и Dynamic Type;
   кнопки видимости и настроек должны остаться доступными и не перекрывать сумму.
5. При отсутствии данных показывать нейтральное кольцо; при скрытых суммах donut сохранять можно,
   потому что он раскрывает относительную структуру. Если privacy-контракт требует скрывать и доли —
   тест зафиксирует скрытие целиком.

## Acceptance criteria

- [x] Общий баланс числом отображается ровно один раз.
- [x] Compact overview не содержит текста/числа `САЛЬДО`.
- [x] Donut находится в верхней зоне общего баланса и отражает тот же debit/credit ratio, что полоса.
- [x] Суммы дебета/кредита и горизонтальная полоса остаются.
- [x] Нулевой портфель не даёт NaN/бесконечность и показывает нейтральное кольцо.
- [x] Узкий экран, длинная сумма, Dynamic Type и скрытый баланс не ломают layout/privacy.
- [x] VoiceOver получает понятную подпись состава активов/обязательств.

## Фаза 1

- [x] Добавить unit-тест чистой политики сегментов donut: 0/0, только дебет, только кредит, смесь.
- [x] Реализовать компактный donut без новой зависимости.
- [x] Поднять готовое ledger presentation в hero минимальным callback-контрактом.
- [x] Удалить compact saldo-дубль, сохранить debit/credit legends и stacked bar.
- [x] Добавить source/layout regression guard (ViewInspector в проекте отсутствует).
- [x] Запустить релевантные Finance overview/model/localization tests, compile gate и `git diff --check`.
- [x] Проверить адаптивную структуру: сумма сохраняет flexible width, donut живёт под фиксированными controls.
- [x] Self-audit acceptance criteria и обновить план.

## Не делать

- Не добавлять декоративную статическую картинку: она не отражает данные.
- Не считать debit/credit заново в `FinancesView`.
- Не удалять горизонтальную полосу или кликабельные debit/credit legends.
- Не затрагивать текущие незакоммиченные credit-card/stock изменения.

## Журнал

- 2026-08-10: запрос подтверждён по трём скриншотам; найден точный saldo-дубль и выбран reuse
  существующего `FinanceOverviewLedgerPresentation`. Код не менялся из-за guard phrase.
- 2026-08-10: фаза 1 реализована. Donut получает готовую presentation через callback; compact saldo
  удалён; legends и stacked bar сохранены. Политика 0/0 и долей покрыта unit-тестами.
- 2026-08-10: RED подтверждён отсутствующим `balanceComposition`; GREEN —
  `FinanceOverviewLedgerStyleTests` 17/17, overview models и localization suites зелёные,
  structural test `compactOverviewKeepsSingleBalanceNumber` зелёный, `git diff --check` чистый.
