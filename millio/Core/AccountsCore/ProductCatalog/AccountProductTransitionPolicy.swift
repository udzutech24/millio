import Foundation

enum AccountProductTransitionBlockedReason: String, CaseIterable, Equatable, Sendable {
    case sameProduct = "same_product"
    case unknownLegacy = "unknown_legacy"
    case invalidSourceIdentity = "invalid_source_identity"
    case invalidTargetMetadata = "invalid_target_metadata"
    case nonPristineDeposit = "non_pristine_deposit"
    case cashflowLinkedDeposit = "cashflow_linked_deposit"
    case creditReplayEngine = "credit_replay_engine"
    case loanReplayEngine = "loan_replay_engine"
    case debtDirection = "debt_direction"
    case marketQuoteIdentity = "market_quote_identity"
    case crossReplayEngine = "cross_replay_engine"
    case unsupportedConversion = "unsupported_conversion"
}

enum AccountProductTransitionKind: Equatable, Sendable {
    case inPlaceCorrection
    case replacementConversion
    case blocked(AccountProductTransitionBlockedReason)
}

struct AccountProductEventSummary: Equatable, Sendable {
    let eventCount: Int
    let openingBalanceCount: Int
    let hasGeneratedOrConfirmedInterest: Bool
    let hasCashflowLink: Bool
    let hasMarketActivity: Bool

    static func make(events: [AccountEvent]) -> Self {
        .init(
            eventCount: events.count,
            openingBalanceCount: events.filter { $0.type == .openingBalance }.count,
            hasGeneratedOrConfirmedInterest: events.contains { $0.type == .interest },
            hasCashflowLink: events.contains {
                guard let source = $0.sourceTransactionID else { return false }
                return source.hasPrefix("cashflow:") || source.hasPrefix("deposit-cashflow:")
            },
            hasMarketActivity: events.contains { [.buy, .sell, .dividend].contains($0.type) }
        )
    }

    var isPristine: Bool { eventCount == 1 && openingBalanceCount == 1 }
}

/// Exhaustive, write-free classifier. Every product pair is routed through semantic families;
/// callers never infer safety from a convenient `kind` comparison alone.
enum AccountProductTransitionPolicy {
    static func classify(
        source: AccountProductType,
        sourceKind: AccountKind,
        sourceMetadata: AccountProductMetadata,
        target: AccountProductType,
        targetMetadata: AccountProductMetadata,
        events: AccountProductEventSummary
    ) -> AccountProductTransitionKind {
        guard source != target else { return .blocked(.sameProduct) }
        guard source != .unknownLegacy, target != .unknownLegacy else { return .blocked(.unknownLegacy) }
        guard (try? ProductDefinitionCatalog.validateStoredIdentity(
            source, kindRaw: sourceKind.rawValue, metadata: sourceMetadata, migrationReason: nil
        )) != nil else { return .blocked(.invalidSourceIdentity) }
        guard let targetKind = ProductDefinitionCatalog.definition(for: target).canonicalKind,
              (try? ProductDefinitionCatalog.validateNewProduct(
                target, kind: targetKind, metadata: targetMetadata
              )) != nil else { return .blocked(.invalidTargetMetadata) }

        if cashLike.contains(source), cashLike.contains(target) { return .inPlaceCorrection }
        if manual.contains(source), manual.contains(target) { return .inPlaceCorrection }

        if market.contains(source), market.contains(target) {
            guard sourceMetadata.market?.symbol == targetMetadata.market?.symbol,
                  sourceMetadata.market?.assetClass == targetMetadata.market?.assetClass else {
                return .blocked(.marketQuoteIdentity)
            }
            return .inPlaceCorrection
        }

        if (source == .deposit && cashLike.contains(target))
            || (cashLike.contains(source) && target == .deposit) {
            guard !events.hasCashflowLink else { return .blocked(.cashflowLinkedDeposit) }
            return events.isPristine && !events.hasGeneratedOrConfirmedInterest
                ? .inPlaceCorrection : .replacementConversion
        }

        if source == .creditCard || target == .creditCard { return .blocked(.creditReplayEngine) }
        if source == .loan || target == .loan { return .blocked(.loanReplayEngine) }
        if debt.contains(source) || debt.contains(target) { return .blocked(.debtDirection) }
        if market.contains(source) || market.contains(target) { return .blocked(.crossReplayEngine) }
        if manual.contains(source) || manual.contains(target) { return .blocked(.crossReplayEngine) }
        return .blocked(.unsupportedConversion)
    }

    private static let cashLike: Set<AccountProductType> = [.cash, .debitCard, .bankAccount]
    private static let manual: Set<AccountProductType> = [.realEstate, .business, .vehicle, .otherManualAsset]
    private static let market: Set<AccountProductType> = [.marketStock, .marketCrypto, .marketBond, .marketMetal, .genericMarketInvestment]
    private static let debt: Set<AccountProductType> = [.receivable, .payable]
}
