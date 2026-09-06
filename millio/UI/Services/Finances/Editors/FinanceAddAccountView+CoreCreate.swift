import SwiftUI
import SwiftData
import PhotosUI

/// Создание счёта в новом ядре: резолверы `AccountKind` по пресету и команды создания.
extension FinanceAddAccountView {
    /// kind нового ядра для текущего выбора пресета «Карта»/«Счёт» — `nil` для остальных
    /// пресетов (вклад/инвестиции/… — свои резолверы). Форма теперь только для СОЗДАНИЯ:
    /// EDIT-путь легаси снесён (6b Ф5c.3), поэтому `isEditingLegacy: false`. Защитный гуард
    /// `isEditingLegacy` в мосте сохранён (гард-тест `AllPresetsOnNewCoreTests`, анамнез Фазы 6a).
    var newCoreMoneyKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.moneyKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            bank: cardData?.bank ?? .other,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Кредит»/«Долг» (Фаза 2) — `nil` для остальных пресетов
    /// и для режима редактирования (та же причина и фикс Фазы 6a, см. `newCoreMoneyKindForCurrentSelection`).
    var newCoreObligationKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.obligationKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресета «Вклад»/«Накопительный счёт» (Фаза 3) — `nil` для остальных
    /// пресетов и для режима редактирования (правка depositMeta — через `AccountDetailView`, не эту форму).
    var newCoreDepositKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.depositKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Акции»/«Крипта»/«Недвижимость»/«Бизнес»/«Другое»/«Инвестиция»
    /// (Фаза 4) — `nil` для остальных пресетов (карта/счёт/вклад/кредит/долг — уже обработаны выше)
    /// и для режима редактирования. «Долг» сюда НЕ попадает — обработан `newCoreObligationKindForCurrentSelection`.
    var newCoreAssetKindForCurrentSelection: AccountKind? {
        let hasTicker = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return AccountsCoreAdditionBridge.assetKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            investmentPreset: selectedInvestmentPreset,
            hasTicker: hasTicker,
            isEditingLegacy: false
        )
    }

    /// Создание вклада/накопительного счёта на новом ядре (Фаза 3): создаёт счёт + сразу генерирует
    /// БУДУЩИЕ interest-события по расписанию капитализации (`DepositInterestScheduler`) — карточка
    /// счёта открывается уже с прогнозом «в месяц»/«за срок», без отдельного шага «посчитать».
    func createDepositAccountOnNewCore() {
        guard let depositData else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        let meta = AccountsCoreAdditionBridge.depositMeta(
            rate: Decimal(depositData.rate),
            capitalization: depositData.capitalization,
            termEnd: depositData.termEnd,
            payoutDay: depositData.payoutDay,
            allowsTopUp: depositData.allowsTopUp,
            allowsEarlyClose: depositData.allowsEarlyClose,
            earlyClosePenaltyShare: Decimal(depositData.earlyClosePenaltyPercent / 100),
            remindEnd: depositData.remindEnd,
            autoRollover: depositData.autoRollover,
            isTaxable: depositData.isTaxable
        )

        do {
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: .deposit,
                name: resolvedName,
                currency: depositData.currency,
                amount: Decimal(depositData.amount),
                groupID: group?.id,
                depositMeta: meta,
                note: depositData.comment.isEmpty ? nil : depositData.comment
            ))
            _ = try factory.create(command)
            if meta.remindEnd, let maturity = meta.termEnd {
                Task { @MainActor in
                    _ = await NotificationManager.shared.scheduleAccountDepositMaturityReminder(
                        accountID: command.accountID, accountName: resolvedName, maturityDate: maturity
                    )
                }
            }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать вклад нового ядра: \(error)")
        }
    }

    /// Создание денежного счёта («Карта»/«Счёт») на новом ядре event-sourcing (Фаза 1a-ui).
    /// Никогда не создаёт старый `Card`/`Investment` — единственная точка записи: `AccountsCoreService`.
    func createMoneyAccountOnNewCore(kind: AccountKind) {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName

        let currency: String
        let openingBalance: Decimal
        var cardMeta: CardMeta?

        switch kind {
        case .cash, .debitCard:
            guard let cardData else { return }
            currency = cardData.currency
            openingBalance = Decimal(cardData.balance)
            cardMeta = CardMeta(
                bank: cardData.bank == .other ? nil : cardData.bank.rawValue,
                last4: cardData.cardNumber.isEmpty ? nil : cardData.cardNumber,
                creditLimit: cardData.cardType == .credit ? cardData.creditLimit.map { Decimal($0) } : nil
            )
        default: // .bankAccount
            guard let investmentData else { return }
            currency = investmentData.currency
            openingBalance = Decimal(investmentData.amount)
        }

        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)
        do {
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: selectedProductOption,
                name: resolvedName,
                currency: currency,
                amount: openingBalance,
                includeInTotal: cardData?.includeInTotal ?? investmentData?.includeInTotal ?? true,
                groupID: group?.id,
                cardType: cardData?.cardType,
                bank: cardData?.bank,
                cardLast4: cardData?.cardNumber,
                creditLimit: cardMeta?.creditLimit,
                statementDay: cardData?.statementDay,
                dueDay: cardData?.dueDay,
                minPayment: cardData?.minPayment.map { Decimal($0) },
                graceDays: cardData?.graceDays,
                note: cardData?.note
            ))
            _ = try factory.create(command)
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать денежный счёт нового ядра: \(error)")
        }
    }

    func moneyCreateCommand(kind: AccountKind, accountID: UUID = UUID()) throws -> CreateProductCommand {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let currency: String
        let openingBalance: Decimal
        var cardMeta: CardMeta?

        switch kind {
        case .cash, .debitCard:
            guard let cardData else { throw AccountStatementOnboardingError.unsupportedProduct }
            currency = cardData.currency
            openingBalance = Decimal(cardData.balance)
            cardMeta = CardMeta(
                bank: cardData.bank == .other ? nil : cardData.bank.rawValue,
                last4: cardData.cardNumber.isEmpty ? nil : cardData.cardNumber,
                creditLimit: cardData.cardType == .credit ? cardData.creditLimit.map { Decimal($0) } : nil
            )
        default:
            guard let investmentData else { throw AccountStatementOnboardingError.unsupportedProduct }
            currency = investmentData.currency
            openingBalance = Decimal(investmentData.amount)
        }

        let resolved = try FinanceProductCreationCommandResolver.resolve(.init(
            option: selectedProductOption,
            name: resolvedName,
            currency: currency,
            amount: openingBalance,
            includeInTotal: cardData?.includeInTotal ?? investmentData?.includeInTotal ?? true,
            groupID: targetGroup?.id,
            cardType: cardData?.cardType,
            bank: cardData?.bank,
            cardLast4: cardData?.cardNumber,
            creditLimit: cardMeta?.creditLimit,
            statementDay: cardData?.statementDay,
            dueDay: cardData?.dueDay,
            minPayment: cardData?.minPayment.map { Decimal($0) },
            graceDays: cardData?.graceDays,
            note: cardData?.note
        ))
        return CreateProductCommand(
            accountID: accountID,
            productType: resolved.productType,
            name: resolved.name,
            currency: resolved.currency,
            openingBalance: resolved.openingBalance,
            includeInTotal: resolved.includeInTotal,
            order: resolved.order,
            groupID: resolved.groupID,
            metadata: resolved.metadata,
            note: resolved.note,
            date: resolved.date,
            initialMarketPurchase: resolved.initialMarketPurchase,
            calendar: resolved.calendar
        )
    }

    /// Создание обязательства («Кредит»/«Долг») на новом ядре event-sourcing (Фаза 2).
    /// Никогда не создаёт старый `Credit`/`Investment(debt)` — единственная точка записи: `AccountsCoreService`.
    func createObligationAccountOnNewCore(kind: AccountKind) {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        do {
            switch kind {
            case .loan:
                guard let creditData else { return }
                let meta = AccountsCoreAdditionBridge.loanMeta(
                    principal: Decimal(creditData.amount),
                    monthlyPayment: creditData.monthlyPayment > 0 ? Decimal(creditData.monthlyPayment) : nil,
                    paymentDay: creditData.paymentDayOfMonth,
                    termEnd: creditData.endDate
                )
                // openingBalance — ТЕКУЩИЙ остаток долга (remainingAmount), не первоначальная сумма
                // (principal хранится отдельно в loanMeta для отображения) — движок C сам сделает знак минус.
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: .credit,
                    name: resolvedName,
                    currency: creditData.currency,
                    amount: Decimal(creditData.remainingAmount),
                    includeInTotal: creditData.includeInTotal,
                    groupID: group?.id,
                    loanMeta: meta
                ))
                // Договор пишем через `graphEnricher` — в том же transaction-контексте, что и
                // счёт: иначе при сбое сохранения остался бы счёт без условий (или наоборот).
                _ = try factory.create(command, graphEnricher: { _, transactionContext in
                    guard let terms = loanTermsDraft?.terms else { return }
                    try LoanContractStore(context: transactionContext)
                        .upsert(accountID: command.accountID) { contract in
                            contract.principal = terms.principal
                            contract.annualRatePercent = terms.annualRatePercent
                            contract.termPeriods = terms.termPeriods
                            contract.firstPaymentDate = terms.firstPaymentDate
                            contract.scheduleType = terms.scheduleType
                            contract.frequency = terms.frequency
                            contract.paymentOverride = terms.paymentOverride
                        }
                })
            case .debt:
                guard let investmentData else { return }
                let direction: DebtDirection = investmentData.investmentType == .positive ? .owedToMe : .owedByMe
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: .debt,
                    name: resolvedName,
                    currency: investmentData.currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    debtDirection: direction
                ))
                _ = try factory.create(command)
            default:
                return
            }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать обязательство нового ядра: \(error)")
        }
    }

    /// Создание рыночного/ручного актива на новом ядре event-sourcing (Фаза 4). Никогда не создаёт
    /// старый `Investment` — единственная точка записи: `AccountsCoreService`.
    func createAssetAccountOnNewCore(kind: AccountKind) {
        guard let investmentData else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        do {
            switch kind {
            case .marketInvestment:
                guard let marketData = investmentData.marketData,
                      let symbol = marketData.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !symbol.isEmpty,
                      let quantity = marketData.quantity else { return }
                // Цена ПОКУПКИ — приоритет `purchaseUnitPrice` (пользователь ввёл вручную), иначе
                // последняя известная рыночная цена на момент выбора тикера (брифинг Фазы 4, задача 1).
                let unitPrice = Decimal(marketData.purchaseUnitPrice ?? marketData.unitPrice ?? 0)
                let currency = (marketData.currency?.isEmpty == false) ? marketData.currency! : investmentData.currency
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: selectedProductOption,
                    name: resolvedName,
                    currency: currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    marketSymbol: symbol,
                    marketQuantity: Decimal(quantity),
                    marketUnitPrice: unitPrice
                ))
                _ = try factory.create(command)
            case .manualAsset:
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: selectedProductOption,
                    name: resolvedName,
                    currency: investmentData.currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    marketSymbol: nil
                ))
                if selectedProductOption == .house {
                    let propertyType = realEstatePropertyType
                    let photoData = realEstatePhotoData
                    _ = try factory.create(command, graphEnricher: { graph, transactionContext in
                        transactionContext.insert(RealEstateProfile(
                            accountID: graph.account.id,
                            propertyType: propertyType
                        ))
                        for (index, data) in photoData.enumerated() {
                            transactionContext.insert(AccountAttachment(
                                accountID: graph.account.id,
                                order: index,
                                isCover: index == 0,
                                mediaData: data
                            ))
                        }
                    })
                } else {
                    _ = try factory.create(command)
                }
            default:
                return
            }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать актив нового ядра: \(error)")
        }
    }

    func addAccount() {
        guard validateEntitlementsForSave() else { return }

        if let newCoreKind = newCoreMoneyKindForCurrentSelection {
            createMoneyAccountOnNewCore(kind: newCoreKind)
            return
        }

        if newCoreDepositKindForCurrentSelection != nil {
            createDepositAccountOnNewCore()
            return
        }

        if let newCoreObligationKind = newCoreObligationKindForCurrentSelection {
            createObligationAccountOnNewCore(kind: newCoreObligationKind)
            return
        }

        if let newCoreAssetKind = newCoreAssetKindForCurrentSelection {
            createAssetAccountOnNewCore(kind: newCoreAssetKind)
            return
        }

        // Все 11 create-пресетов резолвятся в один core-kind выше (гард-тест
        // `AllPresetsOnNewCoreTests`) — легаси-writer'ы (Card/Credit/Investment) недостижимы
        // после сноса EDIT-пути (6b Ф5c.3). Сюда управление в норме не доходит.
    }
}
