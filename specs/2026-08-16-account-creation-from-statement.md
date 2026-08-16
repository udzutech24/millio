# Spec: создание счёта из банковской выписки

## Problem

Создание счёта и импорт выписки сейчас разнесены. Пользователь вручную вводит остаток, затем повторно ищет import-flow. Наивное применение и остатка, и операций к балансу задвоит деньги.

## Goal

При создании дебетовой карты или банковского счёта дать optional-маршрут `выписка → preview/review → подтверждение остатка → один атомарный create`, переиспользуя текущий statement pipeline.

## Financial contract

- Текущий остаток нового счёта равен подтверждённому closing balance на дату выписки.
- Импортированные `CashflowTransaction` привязаны к новому `Account`, влияют на cashflow-итоги, но не изменяют баланс.
- Closing balance не вычисляется из оборотов без bank-declared opening/closing anchor.
- Если в ыписке нет надёжного closing balance, пользователь явно вводит и подтверждает остаток; приложение не угадывает.
- Account graph и все одобренные Cashflow-проекции коммитятся или откатываются вместе.
- Fingerprint-идемпотентность и запрет закрытого месяца сохраняются.

## Acceptance criteria

- [x] **ASI-C1** В create-flow `.debitCard` и `.bankAccount` есть optional «Загрузить выписку»; остальные типы счетов его не видят.
- [x] **ASI-C2** Используются те же client/controller/category/disposition/review policies, что и в Cashflow import; второго parser/reviewer нет.
- [ ] **ASI-C3** Backend preview возвращает optional typed balance evidence с amount, currency, date, source/confidence/reasons; v1 client не падает на отсутствии полей.
- [x] **ASI-C4** При bank-declared closing balance UI показывает amount, currency и `на дату`, а при его отсутствии требует manual confirmation.
- [x] **ASI-C5** Валюта счёта, closing balance и каждой импортируемой операции совпадают; mixed-currency выписка блокирует create.
- [x] **ASI-C6** В v1 принимается только выписка в пределах одного календарного месяца; multi-month получает явное объяснение.
- [ ] **ASI-C7** Закрытый месяц, failed reconciliation, unsupported/corrupt/empty/oversized file и backend offline не создают счёт или операции.
- [x] **ASI-C8** Финальный review показывает account name/type, closing balance/date, included/excluded/reclassified counts, totals by currency и гарантию «операции не изменят уже учтённый остаток».
- [ ] **ASI-C9** Один final apply создаёт ровно один `Account`, один `.openingBalance` anchor на balance date и по одной `CashflowTransaction` на каждый одобренный fingerprint.
- [ ] **ASI-C10** Все импортированные транзакции имеют `cardID = account.id.uuidString`, `affectsCashflowTotals=true`, `affectsCardBalance=false`.
- [ ] **ASI-C11** Ошибка на любой staging/save-фазе оставляет ноль Account/AccountEvent/CashflowTransaction; refresh и category learning не публикуются.
- [ ] **ASI-C12** Stable onboarding key хранится в `openingEvent.sourceTransactionID`; повторный final apply/double tap с тем же payload возвращает исходный graph, а conflicting payload даёт typed error.
- [ ] **ASI-C13** Успешный commit один раз обновляет Finances/Cashflow/groups/totals; после создания видны остаток и импортированные расходы без relaunch.
- [x] **ASI-C14** Отмена на file picker/preview/review/final confirmation ничего не сохраняет; обычное ручное создание счёта не меняется.
- [ ] **ASI-C15** Ни bytes, ни account identifiers, ни raw bank descriptions, ни amounts не пишутся в logs/analytics; хранятся только текущие redacted transaction fields и opaque fingerprints/scope.
- [ ] **ASI-C16** RU/EN/zh-Hans, VoiceOver, Dynamic Type, Reduce Motion и 375/390-point layouts проходят для no-file/loading/error/manual-balance/review/success states.
- [ ] **ASI-C17** Только форматы, для которых есть активный backend adapter, регистрируются в `Open in Millio`: в v1 PDF/CSV/XLSX. OFX не рекламируется и не принимается до появления parser/contract tests.
- [ ] **ASI-C18** Secondary Share Extension accepts the same allowlist, bounded-copies one file into the App Group inbox and never parses, uploads, logs or writes financial models itself.
- [ ] **ASI-C19** Main-app activation drains at most one inbox item into review, preserves remaining items, deduplicates repeated shares and deletes a staged copy only after the defined safe handoff/cancel policy.
- [ ] **ASI-C20** Security-scoped URL access is balanced on every success/error/cancel path; symlinks, directories, zero/oversized files, filename traversal and extension/MIME disagreement fail closed.
- [ ] **ASI-C21** Share Extension does not use private API or pretend it can guarantee force-opening the containing app. UI names the actions honestly: `Open in Millio` (direct) and `Save to Millio` (deferred).
- [ ] **ASI-C22** Внешний файл не теряется и не попадает в неверный flow: при активном statement onboarding он прикрепляется к draft; без него preview открывает destination choice `создать новый счёт` / `импортировать в существующий Cashflow`. До явного выбора persistence нет.
- [ ] **ASI-C23** App lock, cold launch, store migration/recovery, guest-to-user scope switch, backup import modal и второй incoming URL не раскрывают preview до unlock/ready и не перетирают очередь; route привязан к тому data scope, в котором пользователь его подтвердил.
- [x] **ASI-C24** Ручной остаток всегда имеет явно выбранную дату `as of`; дата окончания выписки не подставляется как доказанная дата остатка.
- [ ] **ASI-C25** Повторный импорт проверяет не только fingerprint, но и его account attribution: транзакция, уже привязанная к другому счёту, требует явного conflict resolution и не перепривязывается молча.
- [ ] **ASI-C26** Onboarding idempotency доказана для двух concurrent coordinators и CloudKit merge. Если `sourceTransactionID` без storage uniqueness этого не гарантирует, фаза 2 обязана ввести детерминированные IDs/serialized writer или явную persisted uniqueness model с migration plan.
- [ ] **ASI-C27** Атомарность обещается только для local store commit. После частичного/out-of-order CloudKit merge проверяемый reconciliation либо восстанавливает целый graph, либо fail-closed скрывает неполный graph и показывает recovery state.
- [ ] **ASI-C28** App Group inbox и temporary copies имеют iOS file protection, исключены из device backup, не попадают в Spotlight и удаляются после durable handoff, явного discard или TTL; crash на любом шаге не удаляет единственную готовую копию.
- [ ] **ASI-C29** Client и backend имеют лимиты compressed/uncompressed size, row/page count, parsing time и memory; ZIP bomb, malformed shared strings, CSV formula-like cells, recursive containers и password-protected documents fail closed без PII в logs.
- [ ] **ASI-C30** Реальная multi-month T-Bank XLSX в v1 служит negative fixture: preview может определить период, но create/apply блокируются с явным сообщением; скрытого auto-split нет.

## Scope

- Optional statement CTA в create-flow дебетовой карты/банковского счёта.
- Additive balance evidence в backend/iOS preview contract для уже поддержанных bank adapters.
- Переиспользование statement review и атомарный onboarding coordinator.
- Unit/contract/integration/UI/accessibility tests и device acceptance.
- Public document ingress plus a minimal App Group Share Extension inbox, both converging on the existing statement coordinator.

## Non-goals

- Open Banking, автосинхронизация, банковские credentials/tokens.
- Multi-month выписки в v1.
- Импорт кредитного лимита/долга, вкладов, кредитов и инвестиций.
- Реконструкция полной AccountEvent-истории из выписки.
- Новые бани и форматы.

## Constraints and risks

- Backend schema меняется аддитивно; deploy и rollback — отдельная явно авторизованная фаза.
- Если balance evidence нет или confidence ниже порога, manual balance обязателен.
- Выписка — snapshot, а не live-связь; копирайт и UX не должны обещать автообновление.
