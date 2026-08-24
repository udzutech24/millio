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
- [ ] Phase 2 — primary actions и денежный маршрут: `Изменить сумму` с датой для вклада через готовый coordinator из фазы 1; toolbar `…` для вклада и кредитной карты; сохранение всех confirmation flows.
- [ ] Phase 3 — условия и переход типа: выделенный app-native экран смены типа вместо menu-popover; новая форма условий вклада с днём начисления, штрафом по умолчанию `0 %`, крупным процентным вводом, крестиком в toolbar и нижней keyboard-safe CTA.
- [ ] Phase 4 — regression gates: unit tests, iPhone/Dynamic Type render, focused build и acceptance-criteria audit.

## Verification

- Unit tests: `DepositOperationCoordinatorTests`, `DepositPresentationTests`, `AccountProductTransitionPresentationTests` и mapper-тесты на `payoutDay`/default penalty; новый/расширенный тест routing-поведения `AccountDetailView` там, где проект поддерживает view-level tests.
- Integration/build checks: focused `xcodebuild test` для millioTests и build приложения без signing/upload.
- Acceptance criteria audit: проверить каждый пункт спеки, включая capability состояния, no-op, forecast и destructive confirmations.

## Status

`В РАБОТЕ`: фаза 1 реализована 2026-08-23. Добавлены `DepositBalanceAdjustmentCommand` и atomic `DepositOperationCoordinator.adjustBalance`: положительная/отрицательная дельта события, no-op без записи, защита от отрицательного баланса, идемпотентный retry и откат на каждом mutation stage. Проверка: `xcodebuild test ... -only-testing:millioTests/DepositOperationCoordinatorTests` — 14 тестов / 27 test runs, 0 failures. По обратной связи 2026-08-23 добавлены фазы 3–4: переход типа/условия требуют самостоятельного UI, payout day и default penalty 0%. Следующий шаг требует явной команды: `Реализуй фазу 2 по плану`.
