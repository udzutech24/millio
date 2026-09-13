import Foundation
import SwiftData

/// Тот же кортеж, что несёт `FinanceAddAccountView.investmentData` — вынесен алиасом только
/// затем, чтобы не повторять десяток полей в трёх сигнатурах ниже; второй тип не создаёт.
typealias AccountCreationInvestmentDraft = (
    name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double,
    currency: String, includeInTotal: Bool, isFavorite: Bool,
    marketData: InvestmentMarketData?, createCashflowTransaction: Bool
)

/// Тот же кортеж, что несёт `FinanceAddAccountView.creditData`.
typealias AccountCreationCreditDraft = (
    name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double,
    currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode,
    paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?,
    reminderTime: Date?, includeInTotal: Bool
)

/// Финальный шаг любого пути создания счёта нового ядра: построить команду → создать счёт
/// фабрикой → записать оформление (избранное/иконка/цвет). Вынесено из
/// `FinanceAddAccountView+CoreCreate.swift` в статические функции без `@State`/`View`.
///
/// Причина: `@State.wrappedValue` использует `nonmutating set`, который пишет через `_location` —
/// ссылку, устанавливаемую SwiftUI только при монтировании view в живой граф рендера. Экземпляр,
/// созданный напрямую (как в unit-тесте), такой `_location` не получает, и запись в `@State`
/// молча теряется (подтверждено экспериментом при фиксе Бага 2, см. `AccountAppearancePersister`).
/// Поэтому реальный путь создания раньше нельзя было покрыть тестом — только оторванный от него
/// `AccountAppearancePersister`. Экран остаётся тонкой обёрткой: берёт значения из своих `@State`,
/// зовёт функции ниже, публикует `EventBus` и закрывает форму сам — тест зовёт ИХ, и откат правки
/// в любой из четырёх функций (или в `CoreCreate.swift`, если он перестанет их вызывать) ломает тест.
@MainActor
enum AccountCreationCoordinator {

    private static func resolvedName(_ accountName: String, fallback: String) -> String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    // MARK: - Денежный счёт («Карта»/«Счёт»)

    /// `nil` — форма ещё не готова (нет `cardData`/`investmentData` для выбранного `kind`), это не
    /// ошибка: экран в норме не должен был позволить дойти сюда без данных, но защитный `guard`
    /// молчит так же, как молчал до рефакторинга.
    static func finalizeMoneyAccount(
        kind: AccountKind,
        selectedProductOption: FinanceAddAccountProductOption,
        accountName: String,
        selectedProductTypeTitle: String,
        cardData: InlineCardDraft?,
        investmentData: AccountCreationInvestmentDraft?,
        groupID: UUID?,
        draftIconName: String?,
        draftIconColor: String?,
        modelContext: ModelContext
    ) throws -> UUID? {
        let resolved = resolvedName(accountName, fallback: selectedProductTypeTitle)

        let currency: String
        let openingBalance: Decimal
        var cardMeta: CardMeta?
        // includeInTotal/isFavorite/note выбираем ПО KIND, а не цепочкой `cardData?.x ??
        // investmentData?.x`: та цепочка брала значение из брошенной формы, если экран не успел
        // сбросить её `@State` при смене типа/пресета (Баг 2, третий заход после ревью) — например
        // «Карта» → «Счёт» с ещё не обнулённым `cardData` тихо переносила её избранное/заметку
        // на новый денежный счёт, у которого своя форма (`investmentData`).
        let includeInTotal: Bool
        let favorite: Bool
        let note: String?

        switch kind {
        case .debitCard:
            guard let cardData else { return nil }
            currency = cardData.currency
            openingBalance = Decimal(cardData.balance)
            cardMeta = CardMeta(
                bank: cardData.bank == .other ? nil : cardData.bank.rawValue,
                last4: cardData.cardNumber.isEmpty ? nil : cardData.cardNumber,
                creditLimit: cardData.cardType == .credit ? cardData.creditLimit.map { Decimal($0) } : nil
            )
            includeInTotal = cardData.includeInTotal
            favorite = cardData.isFavorite
            note = cardData.note
        default: // .bankAccount, .cash — обе формы денежные и без реквизитов карты
            guard let investmentData else { return nil }
            currency = investmentData.currency
            openingBalance = Decimal(investmentData.amount)
            includeInTotal = investmentData.includeInTotal
            favorite = investmentData.isFavorite
            note = nil // у формы «Счёт»/«Наличные» заметки нет — не путаем со старой картой
        }

        let factory = AccountProductFactory(modelContext: modelContext)
        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: selectedProductOption,
            name: resolved,
            currency: currency,
            amount: openingBalance,
            includeInTotal: includeInTotal,
            groupID: groupID,
            cardType: cardData?.cardType,
            bank: cardData?.bank,
            cardLast4: cardData?.cardNumber,
            creditLimit: cardMeta?.creditLimit,
            statementDay: cardData?.statementDay,
            dueDay: cardData?.dueDay,
            minPayment: cardData?.minPayment.map { Decimal($0) },
            graceDays: cardData?.graceDays,
            note: note
        ))
        _ = try factory.create(command)
        AccountAppearancePersister.persistIfNeeded(
            context: modelContext,
            accountID: command.accountID,
            isFavorite: favorite,
            iconName: draftIconName,
            tintHex: draftIconColor
        )
        return command.accountID
    }

    // MARK: - Обязательство («Кредит»/«Долг»)

    static func finalizeObligationAccount(
        kind: AccountKind,
        accountName: String,
        selectedProductTypeTitle: String,
        creditData: AccountCreationCreditDraft?,
        investmentData: AccountCreationInvestmentDraft?,
        loanTermsDraft: LoanTermsDraft?,
        groupID: UUID?,
        draftIconName: String?,
        draftIconColor: String?,
        modelContext: ModelContext
    ) throws -> UUID? {
        let resolved = resolvedName(accountName, fallback: selectedProductTypeTitle)
        let factory = AccountProductFactory(modelContext: modelContext)

        switch kind {
        case .loan:
            guard let creditData else { return nil }
            let meta = AccountsCoreAdditionBridge.loanMeta(
                principal: Decimal(creditData.amount),
                monthlyPayment: creditData.monthlyPayment > 0 ? Decimal(creditData.monthlyPayment) : nil,
                paymentDay: creditData.paymentDayOfMonth,
                termEnd: creditData.endDate
            )
            // openingBalance — ТЕКУЩИЙ остаток долга (remainingAmount), не первоначальная сумма
            // (principal хранится отдельно в loanMeta для отображения) — движок C сам сделает знак
            // минус. Баг 1: форма обязана прислать remainingAmount, равный principal, пока
            // пользователь не тронул поле вручную (`RemainingAmountAutoSync`) — здесь читаем то,
            // что реально прислала форма, а не пересчитываем.
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: .credit,
                name: resolved,
                currency: creditData.currency,
                amount: Decimal(creditData.remainingAmount),
                includeInTotal: creditData.includeInTotal,
                groupID: groupID,
                loanMeta: meta
            ))
            // Договор пишем через graphEnricher — в том же transaction-контексте, что и счёт:
            // иначе при сбое сохранения остался бы счёт без условий (или наоборот).
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
            AccountAppearancePersister.persistIfNeeded(
                context: modelContext, accountID: command.accountID,
                isFavorite: creditData.isFavorite, iconName: draftIconName, tintHex: draftIconColor
            )
            return command.accountID
        case .debt:
            guard let investmentData else { return nil }
            let direction: DebtDirection = investmentData.investmentType == .positive ? .owedToMe : .owedByMe
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: .debt,
                name: resolved,
                currency: investmentData.currency,
                amount: Decimal(investmentData.amount),
                includeInTotal: investmentData.includeInTotal,
                groupID: groupID,
                debtDirection: direction
            ))
            _ = try factory.create(command)
            AccountAppearancePersister.persistIfNeeded(
                context: modelContext, accountID: command.accountID,
                isFavorite: investmentData.isFavorite, iconName: draftIconName, tintHex: draftIconColor
            )
            return command.accountID
        default:
            return nil
        }
    }

    // MARK: - Рыночный/ручной актив

    static func finalizeAssetAccount(
        kind: AccountKind,
        selectedProductOption: FinanceAddAccountProductOption,
        accountName: String,
        selectedProductTypeTitle: String,
        investmentData: AccountCreationInvestmentDraft?,
        groupID: UUID?,
        realEstatePropertyType: RealEstatePropertyType,
        realEstatePhotoData: [Data],
        draftIconName: String?,
        draftIconColor: String?,
        modelContext: ModelContext
    ) throws -> UUID? {
        guard let investmentData else { return nil }
        let resolved = resolvedName(accountName, fallback: selectedProductTypeTitle)
        let factory = AccountProductFactory(modelContext: modelContext)

        switch kind {
        case .marketInvestment:
            guard let marketData = investmentData.marketData,
                  let symbol = marketData.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !symbol.isEmpty,
                  let quantity = marketData.quantity else { return nil }
            // Цена ПОКУПКИ — приоритет `purchaseUnitPrice` (пользователь ввёл вручную), иначе
            // последняя известная рыночная цена на момент выбора тикера.
            let unitPrice = Decimal(marketData.purchaseUnitPrice ?? marketData.unitPrice ?? 0)
            let currency = (marketData.currency?.isEmpty == false) ? marketData.currency! : investmentData.currency
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: selectedProductOption,
                name: resolved,
                currency: currency,
                amount: Decimal(investmentData.amount),
                includeInTotal: investmentData.includeInTotal,
                groupID: groupID,
                marketSymbol: symbol,
                marketQuantity: Decimal(quantity),
                marketUnitPrice: unitPrice
            ))
            _ = try factory.create(command)
            AccountAppearancePersister.persistIfNeeded(
                context: modelContext, accountID: command.accountID,
                isFavorite: investmentData.isFavorite, iconName: draftIconName, tintHex: draftIconColor
            )
            return command.accountID
        case .manualAsset:
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: selectedProductOption,
                name: resolved,
                currency: investmentData.currency,
                amount: Decimal(investmentData.amount),
                includeInTotal: investmentData.includeInTotal,
                groupID: groupID,
                marketSymbol: nil
            ))
            if selectedProductOption == .house {
                _ = try factory.create(command, graphEnricher: { graph, transactionContext in
                    transactionContext.insert(RealEstateProfile(
                        accountID: graph.account.id,
                        propertyType: realEstatePropertyType
                    ))
                    for (index, data) in realEstatePhotoData.enumerated() {
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
            AccountAppearancePersister.persistIfNeeded(
                context: modelContext, accountID: command.accountID,
                isFavorite: investmentData.isFavorite, iconName: draftIconName, tintHex: draftIconColor
            )
            return command.accountID
        default:
            return nil
        }
    }

    // MARK: - Вклад/накопительный счёт

    /// Создаёт счёт + сразу генерирует БУДУЩИЕ interest-события по расписанию капитализации
    /// (`DepositInterestScheduler`) — карточка счёта открывается уже с прогнозом «в месяц»/«за
    /// срок», без отдельного шага «посчитать». У вклада нет тумблера «избранное» в форме —
    /// `isFavorite` в `AccountAppearancePersister` всегда `false`.
    static func finalizeDepositAccount(
        accountName: String,
        selectedProductTypeTitle: String,
        depositData: DepositFormData?,
        groupID: UUID?,
        draftIconName: String?,
        draftIconColor: String?,
        modelContext: ModelContext
    ) throws -> UUID? {
        guard let depositData else { return nil }
        let resolved = resolvedName(accountName, fallback: selectedProductTypeTitle)
        let factory = AccountProductFactory(modelContext: modelContext)

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

        let command = try FinanceProductCreationCommandResolver.resolve(.init(
            option: .deposit,
            name: resolved,
            currency: depositData.currency,
            amount: Decimal(depositData.amount),
            groupID: groupID,
            depositMeta: meta,
            note: depositData.comment.isEmpty ? nil : depositData.comment
        ))
        _ = try factory.create(command)
        AccountAppearancePersister.persistIfNeeded(
            context: modelContext,
            accountID: command.accountID,
            isFavorite: false,
            iconName: draftIconName,
            tintHex: draftIconColor
        )
        if meta.remindEnd, let maturity = meta.termEnd {
            Task { @MainActor in
                _ = await NotificationManager.shared.scheduleAccountDepositMaturityReminder(
                    accountID: command.accountID, accountName: resolved, maturityDate: maturity
                )
            }
        }
        return command.accountID
    }
}
