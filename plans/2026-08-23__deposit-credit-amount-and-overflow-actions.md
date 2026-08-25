# Plan: изменение суммы вклада/долга и overflow-действия

## Inputs

- Research: `thoughts/research/2026-08-23__deposit-credit-amount-and-overflow-actions.md`
- Spec: `specs/2026-08-23__deposit-credit-amount-and-overflow-actions.md`

## Decision

- Chosen approach: добавить отдельную atomic-команду корректировки суммы вклада в `DepositOperationCoordinator`; перевести primary/overflow action mapping в presentation model; отрисовать overflow как toolbar `Menu` в `AccountDetailView`.
- Rejected alternatives: общий `AccountsCoreService.adjustBalance` для вклада (ломает forecast); редактирование opening event (ломает audit trail); скрыть кнопки без доступа к действиям (делает важные сценарии недоступными).
- Rollback strategy: изменение аддитивно для событий и UI. Если выявится дефект, отключить новый action mapping; уже созданные `adjustment`-события остаются корректной историей и восстанавливают баланс через существующий engine.

## Phases

- [x] Phase 1 — доменная операция вклада: command, validation, atomic adjustment + forecast rebuild, unit-тесты на дельту/no-op/сохранность подтверждённого interest.
- [x] Phase 2 — primary actions и денежный маршрут: `Изменить сумму` с датой для вклада через готовый coordinator из фазы 1; toolbar `…` для вклада и кредитной карты; сохранение всех confirmation flows.
- [x] Phase 3 — условия и переход типа: выделенный app-native экран смены типа вместо menu-popover; новая форма условий вклада с днём начисления, штрафом по умолчанию `0 %`, крупным процентным вводом, крестиком в toolbar и нижней keyboard-safe CTA.
- [ ] Phase 4 — regression gates: unit tests, iPhone/Dynamic Type render, focused build и acceptance-criteria audit.

## Verification

- Unit tests: `DepositOperationCoordinatorTests`, `DepositPresentationTests`, `AccountProductTransitionPresentationTests` и mapper-тесты на `payoutDay`/default penalty; новый/расширенный тест routing-поведения `AccountDetailView` там, где проект поддерживает view-level tests.
- Integration/build checks: focused `xcodebuild test` для millioTests и build приложения без signing/upload.
- Acceptance criteria audit: проверить каждый пункт спеки, включая capability состояния, no-op, forecast и destructive confirmations.

## Status

`В РАБОТЕ`: фазы 1–3 реализованы 2026-08-23.

### Журнал

- **2026-08-25 (device feedback по фазе 3).** Две правки по репорту владельца с устройства:
  1. Сумма от ~8 цифр не была видна при вводе — `TextField` прокручивает текст, а не сжимает его.
     Введены ступени шрифта `MoneyFieldFontRamp` (30 → 24 → 20 → 16pt по числу цифр), колонка
     ставки ужата 116 → 96pt, зазор строки `AppSpacing.l` → `AppSpacing.m`. Ширины проверяются
     реальными метриками SF в `MoneyFieldFontRampTests` (бюджет 127pt = экран создания на 390pt).
  2. День выплаты процентов появился в форме СОЗДАНИЯ: селектор переехал в общий
     `DepositTermsInputCard`, `DepositFormData.payoutDay` пробрасывается через
     `AccountsCoreAdditionBridge.depositMeta(payoutDay:)`; бридж — единственный нормализатор
     (гасит день для `daily`/`customDays` и значения вне 1…31). Наборы полей создания и правки
     снова совпадают.
  - Побочно: цепочка из 15 `.onChange` в `InlineDepositCreateForm` заменена одним наблюдением
    собранного `currentData()` — она роняла type-checker `body` на 15-м поле.
  - ⚠️ Красное НЕ из этих правок: `ProductColumnSchemaTests` ждут `AppSchemaCurrent == V7`, тогда
    как ветка перешла на V10 в `3c7486f`; этот же сьют роняет тест-хост (`signal trap`) и
    каскадом красит остальной прогон. Требует отдельного фикса до фазы 4. Фаза 3 вынесла смену типа в самостоятельный экран с видимым списком вариантов, сохранила payout day в metadata и переработала редактирование условий вклада: `0 %` по умолчанию, крупный процентный ввод, крестик в toolbar и нижняя CTA. Focused `AccountProductTransitionPresentationTests` + `DepositPresentationTests`: 16 тестов, 0 failures. Следующий шаг требует явной команды: `Реализуй фазу 4 по плану`.
