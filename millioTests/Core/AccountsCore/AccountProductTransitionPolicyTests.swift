import Foundation
import Testing
@testable import millio

@Suite("Account product transition policy")
struct AccountProductTransitionPolicyTests {
    @Test func matrixClassifiesEveryPair() {
        for source in AccountProductType.allCases {
            for target in AccountProductType.allCases {
                let result = AccountProductTransitionPolicy.classify(
                    source: source,
                    sourceKind: ProductDefinitionCatalog.definition(for: source).canonicalKind ?? .cash,
                    sourceMetadata: metadata(for: source), target: target,
                    targetMetadata: metadata(for: target), events: .init(
                        eventCount: 1, openingBalanceCount: 1,
                        hasGeneratedOrConfirmedInterest: false, hasCashflowLink: false,
                        hasMarketActivity: false
                    )
                )
                switch result {
                case .inPlaceCorrection, .replacementConversion, .blocked: break
                }
            }
        }
    }

    @Test func cashAndManualFamiliesCorrectInPlace() {
        #expect(classify(.cash, .bankAccount) == .inPlaceCorrection)
        #expect(classify(.realEstate, .vehicle) == .inPlaceCorrection)
    }

    @Test func nonPristineDepositRequiresReplacement() {
        let result = AccountProductTransitionPolicy.classify(
            source: .deposit, sourceKind: .deposit, sourceMetadata: metadata(for: .deposit),
            target: .bankAccount, targetMetadata: metadata(for: .bankAccount),
            events: .init(eventCount: 2, openingBalanceCount: 1,
                          hasGeneratedOrConfirmedInterest: true, hasCashflowLink: false,
                          hasMarketActivity: false)
        )
        #expect(result == .replacementConversion)
    }

    @Test func dangerousReplayEnginesAreBlocked() {
        #expect(classify(.creditCard, .debitCard) == .blocked(.creditReplayEngine))
        #expect(classify(.loan, .cash) == .blocked(.loanReplayEngine))
        #expect(classify(.receivable, .payable) == .blocked(.debtDirection))
        #expect(classify(.marketStock, .cash) == .blocked(.crossReplayEngine))
    }

    private func classify(_ source: AccountProductType, _ target: AccountProductType) -> AccountProductTransitionKind {
        AccountProductTransitionPolicy.classify(
            source: source,
            sourceKind: ProductDefinitionCatalog.definition(for: source).canonicalKind ?? .cash,
            sourceMetadata: metadata(for: source), target: target,
            targetMetadata: metadata(for: target), events: .init(
                eventCount: 1, openingBalanceCount: 1,
                hasGeneratedOrConfirmedInterest: false, hasCashflowLink: false,
                hasMarketActivity: false
            )
        )
    }

    private func metadata(for type: AccountProductType) -> AccountProductMetadata {
        switch type {
        case .debitCard, .bankAccount: return .init(card: .init())
        case .creditCard: return .init(card: .init(creditLimit: 1000))
        case .deposit: return .init(deposit: .init(rate: 10, capitalization: .monthly, termEnd: Date.distantFuture, payoutDay: nil, allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: 0, remindEnd: false, autoRollover: false))
        case .loan: return .init(loan: .init(principal: 1000, rate: 10, monthlyPayment: 100, paymentDay: 1, termEnd: nil, scheduleType: .annuity, insurance: nil))
        case .receivable: return .init(debt: .init(direction: .owedToMe))
        case .payable: return .init(debt: .init(direction: .owedByMe))
        case .marketStock: return .init(market: .init(symbol: "AAA", assetClass: .stock))
        case .marketCrypto: return .init(market: .init(symbol: "AAA", assetClass: .crypto))
        case .marketBond: return .init(market: .init(symbol: "AAA", assetClass: .bond))
        case .marketMetal: return .init(market: .init(symbol: "AAA", assetClass: .metal))
        case .genericMarketInvestment: return .init(market: .init(symbol: "AAA", assetClass: .stock))
        case .cash, .realEstate, .business, .vehicle, .otherManualAsset, .unknownLegacy: return .init()
        }
    }
}
