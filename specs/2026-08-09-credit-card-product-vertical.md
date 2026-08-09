# Spec: продуктовая вертикаль «Кредитная карта»

## Problem

Кредитная карта сейчас является generic cash account с лимитом. Raw balance означает доступный остаток, detail показывает его как баланс, а операции не имеют самостоятельной финансовой семантики. Это недостаточно и опасно для Cashflow/totals.

## Goal

Сделать credit card самостоятельным UX-продуктом поверх AccountsCore event sourcing без второй финансовой модели и без недоказанной schema mutation.

## Financial contract

- Canonical account value: signed net position; долг `< 0`, ноль `0`, переплата `> 0`. UI debt = `max(0, -value)`, overpayment = `max(0, value)`.
- Credit limit — positive metadata, никогда не входит в капитал. Available limit = `limit + min(value, 0)`; при переплате отдельно показывается overpayment, лимит не искусственно увеличивается. Utilization = `debt/limit`, не меньше 0; over-limit policy обязана быть явной.
- Purchase, fee, interest уменьшают canonical value; refund и repayment увеличивают. Adjustment допускается только как event с явным предупреждением/audit note.
- `includeInTotal=false` исключает карту из current/historical totals, не из списка.
- Purchase/fee/interest создают expense projection ровно один раз; refund корректирует исходный expense, не становится обычным income; repayment — transfer и не expense.
- Archived card read-only; ненулевой canonical value требует credit-card-specific warning, история сохраняется.

## Acceptance criteria

- [ ] Characterization tests фиксируют legacy available-balance contract и migration boundary.
- [ ] Creation требует name и positive limit, валидирует optional last4; advanced fields раскрываются постепенно; investment/manual controls отсутствуют.
- [ ] Persisted CardMeta round-trips all supported fields; unsupported percentage minimum/APR/reminders не имитируются.
- [ ] Specialized detail показывает debt/overpayment, available limit, utilization, payment/grace presentation, fees/interest, exclusion badge, actions/history and event-only step chart.
- [ ] Separate `CreditCardEditSheet`; Account + metadata update atomic, currency read-only.
- [ ] Typed purchase/refund/repayment/fee/interest commands валидируются до записи и имеют одну save boundary.
- [ ] Repayment accepts only active same-currency cash-like sources, checks funds and writes both legs atomically without Cashflow expense.
- [ ] Refund links to purchase where possible, cannot exceed refundable remainder, and adjusts Cashflow once.
- [ ] Pure calendar policy covers overdue/days remaining/month-end/short months/timezone and avoids promises about bank interest rules.
- [ ] Existing NotificationManager is reused if reminders are scheduled; typed options: none/1/3/7 days/day-of.
- [ ] Current/historical totals and list/detail/dashboard refresh immediately and consistently.
- [ ] Backup/migration/schema gates pass; schema changes only by additive version + fixture + rollback proof.
- [ ] RU/EN/zh-Hans typed titles exist; no dynamic keys/raw namespaces are visible.
- [ ] 375×812 and 390×844 render matrix passes normal/accessibility Dynamic Type, dark mode, Reduce Motion and VoiceOver labels for all required states/sheets.

## Scope

AccountsCore credit-card semantics, specialized creation/detail/edit, operations, Cashflow projection, totals/history, archival policy, presentation/calendar/reminders, localization/accessibility/render QA, backup/migration proof.

## Non-goals

- Bank-grade interest/grace calculator or scraping bank rules.
- Merchant field unless an existing persisted field is proven reusable.
- Generic abstraction for every financial product.
- Silent reinterpretation of existing persisted events.

## Constraints and risks

- Guard phrase: product code starts only after `Реализуй фазу N по плану`.
- Current user changes overlap save boundary, schema, detail and creation; preserve them.
- Schema remains unchanged through Phase 2. Any Phase 3+ schema proposal needs explicit evidence and migration design.
