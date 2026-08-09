import Foundation
import SwiftData

struct InitialMarketPurchase: Equatable {
    let quantity: Decimal
    let unitPrice: Decimal
}

/// Validated application command. It carries persisted IDs, not live SwiftData objects, so the
/// complete graph can be built in an isolated context and committed exactly once.
struct CreateProductCommand {
    let accountID: UUID
    let productType: AccountProductType
    let name: String
    let currency: String
    let openingBalance: Decimal
    let includeInTotal: Bool
    let order: Int
    let groupID: UUID?
    let metadata: AccountProductMetadata
    let note: String?
    let date: Date
    let initialMarketPurchase: InitialMarketPurchase?
    let calendar: Calendar

    init(
        accountID: UUID = UUID(),
        productType: AccountProductType,
        name: String,
        currency: String,
        openingBalance: Decimal,
        includeInTotal: Bool = true,
        order: Int = 0,
        groupID: UUID? = nil,
        metadata: AccountProductMetadata = .init(),
        note: String? = nil,
        date: Date = Date(),
        initialMarketPurchase: InitialMarketPurchase? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.accountID = accountID
        self.productType = productType
        self.name = name
        self.currency = currency
        self.openingBalance = openingBalance
        self.includeInTotal = includeInTotal
        self.order = order
        self.groupID = groupID
        self.metadata = metadata
        self.note = note
        self.date = date
        self.initialMarketPurchase = initialMarketPurchase
        self.calendar = calendar
    }
}

enum ProductCreationStage: String, CaseIterable {
    case validation
    case account
    case openingEvent
    case marketPurchase
    case depositSchedule
    case save
}

enum AccountProductFactoryError: Error, Equatable {
    case emptyName
    case invalidCurrency
    case missingGroup(UUID)
    case missingMarketPurchase
    case unexpectedMarketPurchase
    case invalidMarketPurchase
    case injectedFailure(ProductCreationStage)
}

struct BuiltProductGraph {
    let account: Account
    let openingEvent: AccountEvent
    let marketPurchase: AccountEvent?
    let depositInterestEvents: [AccountEvent]
}

/// Builds a complete product graph without saving. Persistence ownership belongs to the outer
/// coordinator (or an explicit bulk writer such as the DEBUG seeder).
@MainActor
enum AccountProductGraphBuilder {
    typealias StageHook = (ProductCreationStage) throws -> Void

    static func build(
        _ command: CreateProductCommand,
        in context: ModelContext,
        stageHook: StageHook = { _ in }
    ) throws -> BuiltProductGraph {
        try stageHook(.validation)
        let normalizedName = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw AccountProductFactoryError.emptyName }
        let normalizedCurrency = command.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency.count == 3 else { throw AccountProductFactoryError.invalidCurrency }

        let definition = ProductDefinitionCatalog.definition(for: command.productType)
        guard let kind = definition.canonicalKind else {
            throw ProductCatalogValidationError.unknownLegacyCannotBeCreated
        }
        try ProductDefinitionCatalog.validateNewProduct(command.productType, kind: kind, metadata: command.metadata)

        let group: AccountGroup?
        if let groupID = command.groupID {
            let descriptor = FetchDescriptor<AccountGroup>(predicate: #Predicate<AccountGroup> { $0.id == groupID })
            guard let persistedGroup = try context.fetch(descriptor).first else {
                throw AccountProductFactoryError.missingGroup(groupID)
            }
            group = persistedGroup
        } else {
            group = nil
        }

        switch definition.openingStrategy {
        case .openingBalanceAndMarketBuy:
            guard let purchase = command.initialMarketPurchase else {
                throw AccountProductFactoryError.missingMarketPurchase
            }
            guard purchase.quantity > 0, purchase.unitPrice >= 0 else {
                throw AccountProductFactoryError.invalidMarketPurchase
            }
        case .openingBalance, .openingBalanceAndDepositSchedule:
            guard command.initialMarketPurchase == nil else {
                throw AccountProductFactoryError.unexpectedMarketPurchase
            }
        }

        try stageHook(.account)
        let account = Account(
            id: command.accountID,
            name: normalizedName,
            kind: kind,
            productType: command.productType,
            currency: normalizedCurrency,
            createdAt: command.date,
            includeInTotal: command.includeInTotal,
            order: command.order
        )
        account.group = group
        account.cardMeta = command.metadata.card
        account.depositMeta = command.metadata.deposit
        account.loanMeta = command.metadata.loan
        account.debtMeta = command.metadata.debt
        account.marketMeta = command.metadata.market
        account.manualAssetMeta = command.metadata.manualAsset
        account.note = command.note
        HistoricalValuationRevisionTracker.bump(
            [.accountSet, .financial, .events],
            on: account
        )
        context.insert(account)

        try stageHook(.openingEvent)
        let opening = AccountEvent(
            account: account,
            date: command.date,
            type: .openingBalance,
            amount: command.openingBalance
        )
        context.insert(opening)

        var purchaseEvent: AccountEvent?
        if let purchase = command.initialMarketPurchase {
            try stageHook(.marketPurchase)
            let event = AccountEvent(
                account: account,
                date: command.date,
                type: .buy,
                quantity: purchase.quantity,
                unitPrice: purchase.unitPrice
            )
            context.insert(event)
            purchaseEvent = event
        }

        var interestEvents: [AccountEvent] = []
        if definition.openingStrategy == .openingBalanceAndDepositSchedule,
           let meta = command.metadata.deposit {
            try stageHook(.depositSchedule)
            let drafts = DepositInterestScheduler.buildInitialSchedule(
                accountID: account.id,
                meta: meta,
                openingBalance: command.openingBalance,
                openingDate: command.date,
                calendar: command.calendar
            )
            interestEvents = drafts.map { draft in
                let event = AccountEvent(
                    account: account,
                    date: draft.date,
                    type: .interest,
                    amount: draft.amount,
                    sourceTransactionID: draft.sourceTransactionID
                )
                context.insert(event)
                return event
            }
        }

        return BuiltProductGraph(
            account: account,
            openingEvent: opening,
            marketPurchase: purchaseEvent,
            depositInterestEvents: interestEvents
        )
    }
}

/// Atomic application boundary for interactive writers. A disposable context makes failure
/// cleanup structural: the caller's context never owns the failed graph, so a later unrelated
/// save cannot resurrect it.
@MainActor
final class AccountProductFactory {
    typealias StageHook = AccountProductGraphBuilder.StageHook
    typealias GraphEnricher = (BuiltProductGraph, ModelContext) throws -> Void

    private let container: ModelContainer
    private let saveBoundary: AccountsCoreSaveBoundary

    init(
        modelContext: ModelContext,
        saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }
    ) {
        self.container = modelContext.container
        self.saveBoundary = AccountsCoreSaveBoundary(saveOperation: saveOperation)
    }

    @discardableResult
    func create(
        _ command: CreateProductCommand,
        graphEnricher: GraphEnricher = { _, _ in },
        stageHook: StageHook = { _ in }
    ) throws -> UUID {
        let transactionContext = ModelContext(container)
        transactionContext.autosaveEnabled = false

        do {
            let graph = try AccountProductGraphBuilder.build(command, in: transactionContext, stageHook: stageHook)
            try graphEnricher(graph, transactionContext)
            try stageHook(.save)
            try saveBoundary.commit(transactionContext, operation: .createProduct)
        } catch {
            transactionContext.rollback()
            throw error
        }

        // After commit the result is deliberately non-throwing. A failed caller-context refresh
        // must never turn a successful durable write into a retryable error (and duplicate rows).
        return command.accountID
    }
}
