import SwiftUI
import SwiftData

/// Роутинг листов карточки счёта и операции, которые они запускают.
extension AccountDetailView {
    // MARK: - Sheets

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .income:
            AccountEventEntrySheet(
                title: incomeActionTitle,
                onSave: { amount, date, note in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .income, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordEvent(account: account, type: incomeSheetEventType, amount: amount, date: date, note: note)
                        }
                    }
                }
            )
        case .expense:
            // ВАЖНО: amount передаётся МАГНИТУДОЙ (положительным числом) — движок сам применяет
            // знак по типу события (cashLikeSignMap(.expense) == -1). Ранее здесь стояло `-amount`,
            // что давало ДВОЙНОЕ отрицание и увеличивало баланс вместо уменьшения (найдено при
            // разборе Фазы 2 — см. регрессионный тест engineA_expenseSignConventionMatchesRecordEvent).
            AccountEventEntrySheet(
                title: expenseActionTitle,
                onSave: { amount, date, note in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .expense, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordEvent(account: account, type: expenseSheetEventType, amount: amount, date: date, note: note)
                        }
                    }
                }
            )
        case .adjustBalance:
            let isCreditCard = account.productType == .creditCard
            let creditLimit = account.cardMeta?.creditLimit ?? 0
            let debt = max(0, creditLimit - balanceToday)
            // Наличные: та же корректировка, но на языке пользователя это «сверка» — он не
            // «меняет баланс», а пересчитывает кошелёк, и разница записывается за него.
            let isCash = account.kind == .cash
            AccountAdjustBalanceSheet(
                currentBalance: isCreditCard ? debt : balanceToday,
                titleOverride: isCreditCard
                    ? L("accounts_core.detail.action.adjust_debt")
                    : (isCash ? L("accounts_core.detail.cash.reconcile.title") : nil),
                hint: isCash ? L("accounts_core.detail.cash.reconcile.hint") : nil,
                onSave: { newValue in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).adjust(
                                account: account, to: newValue,
                                operationID: "debit-detail:\(UUID().uuidString)",
                                reason: "manual_balance_correction"
                            )
                        } else {
                            try service.adjustBalance(
                                account: account,
                                to: isCreditCard
                                    ? CreditCardFinancialContract.rawAvailableBalance(debt: newValue, creditLimit: creditLimit)
                                    : newValue
                            )
                        }
                    }
                }
            )
        case .loanTerms:
            LoanTermsEditSheet(
                account: account,
                modelContext: modelContext,
                contract: loanContract,
                onSaved: {
                    // Договор перечитываем сразу: `loanContract` грузится один раз в `.task`,
                    // и без перечитывания экран показывал бы старые условия до переоткрытия.
                    loanContract = try? LoanContractStore(context: modelContext).contract(for: account.id)
                    refreshToken = UUID()
                }
            )
        case .loanPayment:
            if let loanPresentation {
                LoanPaymentConfirmSheet(
                    presentation: loanPresentation,
                    onConfirm: { recordLoanPayment(loanPresentation) },
                    // Явный `self`: параметр `sheet` этой функции затеняет одноимённый `@State`.
                    onDismiss: { self.sheet = nil }
                )
            }
        case .loanPrepayment:
            if let terms = LoanTermsResolver.terms(for: account, contract: loanContract) {
                LoanPrepaymentSheet(
                    terms: terms,
                    outstandingPrincipal: loanOutstandingPrincipal,
                    paymentsMade: loanContract?.paymentsMade ?? 0,
                    currency: account.currency,
                    onConfirm: { entry in recordLoanExtraPayment(entry) }
                )
            }
        case .editDetails:
            if account.kind == .deposit, let meta = account.depositMeta, let presentation = depositPresentation {
                // Коммит 2: «Реквизиты счёта» вклада — слияние генерик-формы и правки условий в
                // один экран тёмного языка приложения. Другие типы продолжают открывать прежние
                // экраны ниже — их поведение этой веткой не затронуто.
                DepositAccountDetailsSheet(
                    account: account,
                    modelContext: modelContext,
                    meta: meta,
                    canEarlyClose: presentation.actions.contains(.earlyClose),
                    onSave: { edit in
                        performDeposit {
                            try service.updateAccount(
                                account,
                                name: edit.name,
                                group: edit.group,
                                note: edit.note,
                                includeInTotal: edit.includeInTotal
                            )
                            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
                            if let newOpeningDate = edit.openingDate {
                                // Коммит 3: дата открытия менялась — атомарно применяет И новую
                                // дату, И новые условия (`edit.meta` уже включает обе правки),
                                // поэтому обычный `coordinator.editTerms` здесь НЕ вызывается —
                                // он читал бы старую дату из `account.createdAt` и продублировал
                                // бы перестройку графика поверх уже пересчитанной.
                                let confirmedAlready = DepositOpeningDateRecalculation.hasConfirmedInterest(
                                    events: account.events ?? []
                                )
                                if confirmedAlready {
                                    // Сюда мы попадаем ТОЛЬКО после явного подтверждения в самом
                                    // листе (`DepositAccountDetailsSheet.handleDoneTapped`) —
                                    // единственный путь, ломающий инвариант «прошлое неприкосновенно».
                                    _ = try DepositOpeningDateRecalculation.recalculateConfirmed(
                                        account: account, newOpeningDate: newOpeningDate,
                                        meta: edit.meta, service: service, context: modelContext
                                    )
                                } else {
                                    _ = try DepositOpeningDateRecalculation.applySilently(
                                        account: account, newOpeningDate: newOpeningDate,
                                        meta: edit.meta, service: service, context: modelContext
                                    )
                                }
                                synchronizeDepositReminder(meta: edit.meta)
                                return DepositOperationResult(operationID: nil, eventIDs: [], wasAlreadyPersisted: false)
                            }
                            let coordinator = DepositOperationCoordinator(modelContext: modelContext)
                            let result = try coordinator.editTerms(
                                depositID: account.id,
                                command: DepositTermsEditCommand(meta: edit.meta)
                            )
                            synchronizeDepositReminder(meta: edit.meta)
                            return result
                        }
                    },
                    onProductTransitionCommitted: productTransitionCommitted,
                    onRequestEarlyClose: { confirmation = .depositEarlyClose },
                    onRequestDelete: { requestArchiveConfirmation() }
                )
            } else if account.productType == .creditCard {
                CreditCardEditSheet(account: account, modelContext: modelContext, onSave: { command, settings in
                    performEdit {
                        try CreditCardEditorService(modelContext: modelContext).update(account: account, command: command)
                        CreditCardPaymentSettingsStore().save(settings, accountID: account.id)
                        Task { await NotificationManager.shared.scheduleCreditCardPaymentReminder(
                            accountID: account.id, cardName: account.name,
                            settings: settings, graceDays: account.cardMeta?.graceDays
                        ) }
                    }
                })
            } else if account.productType == .realEstate {
                RealEstateEditSheet(
                    account: account,
                    modelContext: modelContext,
                    onSave: { name, group, note, includeInTotal, propertyType, reminderMonths, linkedLoanID, photos in
                        performEdit {
                            try RealEstateEditorService(modelContext: modelContext).update(
                                account: account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal,
                                propertyType: propertyType,
                                reminderMonths: reminderMonths,
                                linkedLoanID: linkedLoanID,
                                photos: photos
                            )
                        }
                    }
                )
            } else if account.productType == .marketStock, let stockSnapshot {
                StockPositionEditSheet(
                    account: account,
                    modelContext: modelContext,
                    snapshot: stockSnapshot,
                    onSave: { name, group, note, includeInTotal, quantity, averageCost in
                        performEdit {
                            try service.correctStockPosition(
                                account: account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal,
                                targetQuantity: quantity,
                                targetAverageCost: averageCost
                            )
                        }
                    }
                )
            } else {
                AccountEditDetailsSheet(
                    account: account,
                    modelContext: modelContext,
                    onSave: { name, group, note, includeInTotal, _, _, _ in
                        performEdit {
                            try service.updateAccount(
                                account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal
                            )
                        }
                    },
                    onProductTransitionCommitted: productTransitionCommitted
                )
            }
        case .transfer:
            AccountTransferSheet(
                source: account,
                modelContext: modelContext,
                onSave: { destination, amount in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).transfer(
                                from: account, to: destination,
                                operationID: "debit-detail:\(UUID().uuidString)", amount: amount
                            )
                        } else {
                            try service.transfer(from: account, to: destination, amountInSourceCurrency: amount)
                        }
                    }
                }
            )
        case .earlyClose:
            if let snapshot = depositPresentation?.snapshot {
                DepositCloseSheet(
                    source: account,
                    modelContext: modelContext,
                    preview: DepositDetailPresentation.earlyClosePreview(
                        snapshot: snapshot,
                        penaltyShare: account.depositMeta?.earlyClosePenalty
                    ),
                    isMaturity: false,
                    onSave: { destination in
                        performDepositAndDismiss {
                            let result = try DepositOperationCoordinator(modelContext: modelContext).earlyClose(
                                depositID: account.id,
                                command: DepositTransferCommand(
                                    operationID: "deposit-early-close:\(UUID().uuidString)",
                                    destinationAccountID: destination.id
                                )
                            )
                            NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
                            return result
                        }
                    }
                )
            }
        case .depositTopUp:
            DepositTopUpSheet(deposit: account, modelContext: modelContext) { source, amount in
                performDeposit {
                    try DepositOperationCoordinator(modelContext: modelContext).topUp(
                        depositID: account.id,
                        command: DepositTopUpCommand(
                            operationID: "deposit-top-up:\(UUID().uuidString)",
                            sourceAccountID: source.id,
                            amount: amount
                        )
                    )
                }
            }
        case .depositAdjustBalance:
            if let currentBalance = depositPresentation?.snapshot.currentBalance.value {
                DepositBalanceAdjustmentSheet(currentBalance: currentBalance, currency: account.currency) { amount, date, note in
                    performDeposit {
                        try DepositOperationCoordinator(modelContext: modelContext).adjustBalance(
                            depositID: account.id,
                            command: DepositBalanceAdjustmentCommand(
                                operationID: "deposit-balance-adjustment:\(UUID().uuidString)",
                                newBalance: amount,
                                date: date,
                                note: note
                            )
                        )
                    }
                }
            }
        case .depositTerms:
            if let meta = account.depositMeta, let snapshot = depositPresentation?.snapshot {
                DepositTermsEditSheet(
                    meta: meta,
                    snapshot: snapshot,
                    openingDate: account.createdAt,
                    currentNote: account.note
                ) { edit in
                    performDeposit {
                        // Заметка пишется ПЕРВОЙ и именно `updateAccount`: она живёт в контексте
                        // экрана, а координатор работает в своём. Если писать её после операций
                        // координатора, экранный `account` будет уже устаревшим снимком строки и
                        // сохранение заметки могло бы затереть только что записанную мету.
                        if edit.note != account.note {
                            try service.updateAccount(
                                account,
                                name: account.name,
                                group: account.group,
                                note: edit.note,
                                includeInTotal: account.includeInTotal
                            )
                            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
                        }
                        let coordinator = DepositOperationCoordinator(modelContext: modelContext)
                        // Порядок важен: сначала новые условия, потом коррекция суммы. Обе операции
                        // перестраивают будущий график, и вторая должна считать его уже по новой мете.
                        let result = try coordinator.editTerms(
                            depositID: account.id,
                            command: DepositTermsEditCommand(meta: edit.meta)
                        )
                        if let newBalance = edit.newBalance {
                            _ = try coordinator.adjustBalance(
                                depositID: account.id,
                                command: DepositBalanceAdjustmentCommand(
                                    operationID: "deposit-balance-adjustment:\(UUID().uuidString)",
                                    newBalance: newBalance,
                                    date: Date()
                                )
                            )
                        }
                        synchronizeDepositReminder(meta: edit.meta)
                        return result
                    }
                }
            }
        case .depositMaturity:
            if depositPresentation?.snapshot != nil {
                DepositCloseSheet(source: account, modelContext: modelContext, preview: nil, isMaturity: true) { destination in
                    performDepositAndDismiss {
                        let result = try DepositOperationCoordinator(modelContext: modelContext).mature(
                            depositID: account.id,
                            command: DepositTransferCommand(
                                operationID: "deposit-maturity:\(UUID().uuidString)",
                                destinationAccountID: destination.id
                            )
                        )
                        NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
                        return result
                    }
                }
            }
        case .buy:
            AccountBuySellSheet(
                title: L("accounts_core.detail.market.action.buy"),
                currentQuantity: currentQuantity,
                initialUnitPrice: currentUnitPrice > 0 ? currentUnitPrice : nil,
                currency: account.currency,
                showsSellWarning: false,
                onSave: { quantity, unitPrice, fee, date, note in
                    perform { try service.buy(account: account, quantity: quantity, unitPrice: unitPrice, fee: fee, date: date, note: note) }
                }
            )
        case .sell:
            AccountBuySellSheet(
                title: L("accounts_core.detail.market.action.sell"),
                currentQuantity: currentQuantity,
                initialUnitPrice: currentUnitPrice > 0 ? currentUnitPrice : nil,
                currency: account.currency,
                showsSellWarning: true,
                onSave: { quantity, unitPrice, fee, date, note in
                    perform { try service.sell(account: account, quantity: quantity, unitPrice: unitPrice, fee: fee, date: date, note: note) }
                }
            )
        case .dividend:
            AccountEventEntrySheet(
                title: L("accounts_core.detail.market.action.dividend"),
                onSave: { amount, date, note in
                    perform { try service.recordMarketCashEvent(account: account, type: .dividend, amount: amount, date: date, note: note) }
                }
            )
        case .fee:
            AccountEventEntrySheet(
                title: isDebitProduct ? L("debit_card.action.fee") : L("accounts_core.detail.market.action.fee"),
                onSave: { amount, date, note in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .fee, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordMarketCashEvent(account: account, type: .fee, amount: amount, date: date, note: note)
                        }
                    }
                }
            )
        case .refund:
            DebitCardRefundSheet(
                expenses: sortedEvents.filter { $0.type == .expense && $0.sourceTransactionID != nil },
                currency: account.currency
            ) { originalOperationID, amount, date, note in
                perform {
                    _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                        account: account,
                        command: .init(
                            operationID: "debit-detail:\(UUID().uuidString)",
                            kind: .refund(originalOperationID: originalOperationID),
                            amount: amount, date: date, note: note
                        )
                    )
                }
            }
        case .revalue:
            AccountAdjustBalanceSheet(
                currentBalance: balanceToday,
                titleOverride: L("accounts_core.detail.manual_asset.action.revalue"),
                onSave: { newValue in
                    perform { try service.revalue(account: account, newValue: newValue) }
                }
            )
        }
    }

    /// Досрочное закрытие вклада — отдельно от generic `perform` (успех архивирует счёт и закрывает
    /// карточку, а не просто закрывает sheet — счёт больше не открыть, он ушёл в архив).
    func performEarlyClose(transferTo destination: Account) {
        do {
            try service.earlyCloseDeposit(account, transferTo: destination)
            sheet = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleLoanAction(_ action: LoanDetailAction) {
        switch action {
        case .payment: sheet = .loanPayment
        case .terms: sheet = .loanTerms
        case .schedule: showLoanSchedule = true
        case .prepayment: sheet = .loanPrepayment
        }
    }

    /// Плановый платёж: долг уменьшает только тело, проценты копятся в договоре (спека Р6).
    /// Обе записи — одна транзакция внутри `LoanPaymentRecorder`.
    func recordLoanPayment(_ presentation: LoanDetailPresentation) {
        guard let principalPart = presentation.nextPaymentPrincipal,
              let interestPart = presentation.nextPaymentInterest,
              let date = presentation.nextPaymentDate else { return }
        perform {
            try LoanPaymentRecorder(modelContext: modelContext).recordScheduledPayment(
                account: account,
                principalPart: principalPart,
                interestPart: interestPart,
                date: date
            )
            loanContract = try? LoanContractStore(context: modelContext).contract(for: account.id)
        }
    }

    /// Досрочное погашение и недоплата (Ф6): что уходит в тело, что в проценты и расходуется ли
    /// период — решено ядром (`LoanPrepaymentPlanner`), экран только записывает готовое.
    ///
    /// Дата — сегодняшняя, а не дата планового платежа: событие с будущей датой не попало бы в
    /// баланс «на сегодня», и долг на экране не изменился бы до наступления этой даты.
    func recordLoanExtraPayment(_ entry: LoanExtraPaymentEntry) {
        perform {
            try LoanPaymentRecorder(modelContext: modelContext).record(entry, on: account)
            loanContract = try? LoanContractStore(context: modelContext).contract(for: account.id)
        }
    }

    /// Пункты «···» кредита. «Внести платёж» сюда не дублируем — кнопка уже на экране
    /// (`LoanDetailSection`), в меню только то, чего на экране нет.
    var loanActionSheetItems: [AccountActionItem] {
        var items: [AccountActionItem] = [
            .init(
                title: L("accounts_core.detail.loan.action.terms"),
                icon: "doc.text",
                action: { sheet = .loanTerms }
            )
        ]
        // «Изменить баланс» кредиту намеренно не даём: поле суммы отбрасывает минус
        // (`AmountInputFormatter.sanitize`), и сохранение перевернуло бы знак долга — счёт-
        // обязательство ушёл бы в net worth активом. Ремонт остатка — отдельная задача.
        if account.archivedAt == nil && account.deletedAt == nil {
            items.append(.init(
                title: L("accounts_core.detail.action.edit_details"),
                icon: "square.and.pencil",
                action: { sheet = .editDetails }
            ))
        }
        items.append(.init(
            title: L("accounts_core.detail.action.delete_account"),
            icon: "trash",
            isDestructive: true,
            action: { requestArchiveConfirmation() }
        ))
        return items
    }

    /// Правка реквизитов вклада (имя, группа, учёт в тотале) — те же условия, что и у actionsRow
    /// остальных типов счетов: архивный/удалённый счёт не редактируется.
    var canEditDepositDetails: Bool {
        account.archivedAt == nil && account.deletedAt == nil
    }

    /// Пункты bottom-sheet меню вклада (Коммит 1, `AccountActionsSheet`). «Реквизиты счёта» и
    /// «Изменить условия» слиты в один пункт — экран `.editDetails` для вклада сам показывает
    /// условия (Коммит 2). «Пополнить» сюда не добавляем — кнопка уже есть на экране
    /// (`DepositDetailSection.actions`).
    func depositActionSheetItems(_ presentation: DepositDetailPresentation) -> [AccountActionItem] {
        var items: [AccountActionItem] = []
        if canEditDepositDetails {
            items.append(.init(
                title: L("accounts_core.detail.action.edit_details"),
                icon: "square.and.pencil",
                action: { sheet = .editDetails }
            ))
        }
        if presentation.actions.contains(.earlyClose) {
            items.append(.init(
                title: L("accounts_core.detail.deposit.action.early_close"),
                // Реальное последствие из кода (`earlyClosePreview`), не выдуманная формулировка:
                // штраф — доля от УЖЕ начисленных процентов, будущие начисления просто теряются.
                subtitle: L("accounts_core.detail.deposit.early_close_confirm.message"),
                icon: "xmark.circle",
                action: { confirmation = .depositEarlyClose }
            ))
        }
        if presentation.actions.contains(.archive) {
            items.append(.init(
                title: L("accounts_core.detail.action.delete_account"),
                icon: "trash",
                isDestructive: true,
                action: { requestArchiveConfirmation() }
            ))
        }
        return items
    }

    func performDeposit(_ operation: () throws -> DepositOperationResult) {
        do {
            _ = try operation()
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performDepositAndDismiss(_ operation: () throws -> DepositOperationResult) {
        do {
            _ = try operation()
            sheet = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Правка «карточки» счёта (имя/группа/заметка) — как `perform`, но при успехе публикует
    /// `investmentsUpdated`: смена имени/группы должна обновить список и группировку на экране «Счета»
    /// (этот экран не держит ссылку на `FinanceViewModel` — тот же канал, что использует `archiveAccount`).
    func performEdit(_ operation: () throws -> Void) {
        do {
            try operation()
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Product transitions commit in an isolated context. Closing this stale detail instance makes
    /// the accounts list refetch the committed product (and is also required for replacement flows).
    func productTransitionCommitted() {
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        sheet = nil
        dismiss()
    }

    func archiveAccount() {
        do {
            if isDebitProduct {
                try DebitCardOperationCoordinator(modelContext: modelContext).archive(account)
            } else {
                try service.archiveAccount(account)
            }
            if account.kind == .deposit {
                NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
            }
            // Track D1: этот экран не хранит ссылку на FinanceViewModel — без события список
            // счетов и «Общий баланс» на экране Счетов не пересчитываются до перезапуска приложения
            // (FinanceViewModel.state.totalAmount обновляется только явным calculateTotalAmount(),
            // а сюда его никто не позвал бы). investmentsUpdated — уже существующий канал,
            // подписка есть в FinanceViewModel.subscribeToFinanceEvents().
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeDepositReminder(meta: DepositMeta) {
        guard meta.remindEnd, let maturity = meta.termEnd else {
            NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
            return
        }
        Task { @MainActor in
            _ = await NotificationManager.shared.scheduleAccountDepositMaturityReminder(
                accountID: account.id, accountName: account.name, maturityDate: maturity
            )
        }
    }
}
