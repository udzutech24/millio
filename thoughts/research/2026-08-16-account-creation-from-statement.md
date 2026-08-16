# Research: создание счёта из банковской выписки

- Date: 2026-08-16
- Scope: iOS create-flow для `.debitCard`/`.bankAccount`, существующий Statement Import, backend preview-contract и атомарная локальная запись. Без Open Banking и production deploy.
- Reproduction/evidence:
  - `CashflowImportHubView` уже принимает PDF/CSV/XLSX и передаёт файл существующему `CashflowStatementImportClient`.
  - Preview уже содержит банк, opaque `accountScope`, период, операции, категории, fingerprint-дубли и reconciliation доходов/расходов.
  - Preview v1 не содержит opening/closing balance и balance date. Адаптеры Alfa XLSX и T-Bank PDF сейчас сверяют только обороты.
  - `CashflowStatementApplyService` намеренно создаёт `CashflowTransaction` с `affectsCardBalance: false`; это правильная защита от двойного влияния.
  - `FinanceAddAccountView.createMoneyAccountOnNewCore` создаёт счёт через `AccountProductFactory`; фабрика уже имеет `graphEnricher`, который может добавить Cashflow-проекции в ту же изолированную транзакцию.
  - Core-счета уже атрибутируются в Cashflow через `account.id.uuidString`; вторая модель ссылки не нужна.
  - Реальная выгрузка T-Bank XLSX локально доказала 67 operation rows, transfer rows и bank-specific columns, но не содержит exact opening/closing balance. Значения и PII не сохранялись.
  - Main app уже имеет App Group `group.com.millio.app`, URL ingress и `.onOpenURL`, но Share Extension target нет. `CFBundleDocumentTypes` сейчас регистрирует только backup.
- Current architecture and constraints:
  - `AccountEvent` — единственный ledger баланса; `CashflowTransaction` — классификация/проекция.
  - Одна операция может влиять на баланс ровно один раз.
  - Текущий statement UX месячный. KISS-релиз должен принимать только выписку в пределах одного календарного месяца; multi-month требует отдельной спеки.
  - Закрытый месяц, несовпадающая валюта, несверенная выписка или недостоверный остаток не могут пройти «молча».
  - Банковские bytes передаются существующему backend preview API, но не хранятся и не логируются.
- Options considered:
  1. Создать счёт с нулевым opening balance и проиграть все операции как `AccountEvent`. Отклонено: без достоверного opening balance и полной трансфер-парности это создаёт неверную историю и двойной учёт.
  2. Сначала создать счёт, потом отдельно запустить обычный import. Отклонено как финальная архитектура: падение между двумя save оставит полурезультат.
  3. Сначала preview/review, затем одной атомарной операцией создать Account + closing-balance anchor + Cashflow projections с `affectsCardBalance=false`. Выбрано: переиспользует текущие контракты, даёт верный текущий остаток и атомарный rollback.
  4. Force-open main app from a Share Extension through responder-chain/private URL hacks. Отклонено: iOS не гарантирует это, поведение хрупкое и App Review-risky.
  5. Document ingress (`Open in Millio`) + secondary Share Extension inbox. Выбрано: direct-open идёт через public document contract, а extension даёт надёжный deferred fallback.
- Recommended option and why:
  - Добавить в preview v2 типизированный optional `balances`: opening, closing, `asOf`, currency, confidence/source/reasons.
  - Не выводить closing balance из оборотов, если нет хотя бы одного банком declared balance. При отсутствии closing balance пользователь явно вводит остаток на дату выписки.
  - Финальный create идёт через узкий `AccountStatementOnboardingCoordinator`, который использует `AccountProductFactory.graphEnricher` и общий statement staging helper.
  - Для idempotency новая persisted-модель не нужна: stable onboarding key записывается в `openingEvent.sourceTransactionID`, а payload identity проверяется по account ID, balance/date/currency и fingerprint set.
  - Оба external-file маршрута сходятся в один `IncomingStatementCoordinator`; extension не парсит, не знает auth и не пишет financial data.
- Risks and unknowns:
  - Не все поддержанные форматы гарантируют остаток; нужен явный manual fallback.
  - Выписка может быть не полной или не на текущую дату; UX должен показывать `остаток на <date>`, а не обещать live-синхронизацию.
  - Две одновременные final apply должны сходиться к одному account graph/fingerprint set.
  - Разные валюты в одной выписке не могут быть молча свёрнуты в один счёт.
  - External URLs могут быть security-scoped и исчезнуть после callback; ingress обязан bounded-copy файл в app-owned temporary/App Group storage до async preview.
  - Stress-test доказал, что `sourceTransactionID` не имеет storage-level uniqueness. Check-then-save в двух `ModelContext` может создать два graph; это blocker для Phase 2, а не теоретический edge case.
  - Local SwiftData save атомарен, но CloudKit может доставлять связанные records не как одну транзакцию; нужен явный incomplete-graph reconciliation contract.
  - Текущий backend path поддерживает PDF/CSV/XLSX, но не OFX. Регистрация OFX в iOS до parser support создаст ложное обещание и тупиковый UX.
  - External ingress без активного create draft не имеет target account. До preview можно скопировать/проверить файл, но persistence требует явного destination choice.
  - Existing global fingerprint dedupe не проверяет account attribution. Простой skip операции, ранее привязанной к другому счёту, оставит новый счёт с ложной историей.
- Relevant files/tests:
  - iOS: `FinanceAddAccountView.swift`, `AccountProductFactory.swift`, `CashflowStatementImportController.swift`, `CashflowStatementReviewView.swift`, `CashflowStatementApplyService.swift`, `CashflowSelectableAccount.swift`, `APIClientFactory.swift`.
  - Backend: `bank-statement.types.ts`, `bank-statement-contract.ts`, `alfa-bank-xlsx.adapter.ts`, `t-bank-movement-funds-pdf.adapter.ts` and their specs.
  - Tests: statement contract/controller/apply suites, `DebitCardOperationCoordinatorTests`, product-factory rollback tests and new onboarding coordinator tests.
