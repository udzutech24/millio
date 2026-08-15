import Foundation
import SwiftData

/// Маппинг легаси-счёта (Card/Credit/Investment) в параметры создания core-двойника (Track C, MVP).
///
/// Знаковый вклад в тотал берётся ТОЧНО как в `FinanceTotalsService.getAccountAmount` — это единый
/// источник правды; иначе «Общий баланс» после конвертации разойдётся (ключевой acceptance-тест).
/// `openingBalance` приведён к знаку движка нового ядра:
///  - cashLike (`.debitCard`) / manualAsset (`.manualAsset`) — движок возвращает баланс = +opening,
///    поэтому opening = знаковый вклад;
///  - loan (`.loan`) — движок C возвращает баланс = −opening, поэтому opening = магнитуда.
enum LegacyAccountConversion {

    struct Plan {
        let legacyUniqueID: String
        let name: String
        let currency: String
        let productType: AccountProductType
        let openingBalance: Decimal
        let metadata: AccountProductMetadata
        let initialMarketPurchase: InitialMarketPurchase?
        let includeInTotal: Bool
    }

    /// Карта → `.debitCard` (движок cashLike). Знаковый вклад = `netWorthAmount` (для кредитной
    /// карты это −долг, для дебетовой — доступный остаток, 0 при `includeInTotal == false`).
    static func plan(for card: Card) -> Plan {
        let snapshot = CardSnapshotFactory.make(from: card)
        let opening = card.cardType == .credit ? snapshot.availableAmount : snapshot.netWorthAmount
        let last4 = card.maskedNumber
        let creditLimit = card.creditLimit.map { Decimal($0) }
        return Plan(
            legacyUniqueID: card.cardUniqueID,
            name: card.name,
            currency: card.currency,
            productType: card.cardType == .credit ? .creditCard : .debitCard,
            openingBalance: Decimal(opening),
            metadata: .init(card: CardMeta(
                bank: card.bank == .other ? nil : card.bankRaw,
                last4: last4.isEmpty ? nil : last4,
                creditLimit: creditLimit,
                statementDay: nil,
                dueDay: nil,
                minPayment: nil,
                graceDays: nil,
                overdraftLimit: nil
            )),
            initialMarketPurchase: nil,
            includeInTotal: card.includeInTotal
        )
    }

    /// Кредит → `.loan` (движок C — обязательство). `getAccountAmount` вносит −`remainingAmount`
    /// ВСЕГДА (без учёта `includeInTotal` — легаси-конвенция), движок C даёт баланс = −opening,
    /// поэтому opening = магнитуда `remainingAmount`.
    static func plan(for credit: Credit) -> Plan {
        return Plan(
            legacyUniqueID: credit.creditUniqueID,
            name: credit.name,
            currency: credit.currency,
            productType: .loan,
            openingBalance: Decimal(credit.remainingAmount),
            metadata: .init(loan: LoanMeta(
                principal: Decimal(credit.amount),
                rate: Decimal(credit.interestRate),
                monthlyPayment: credit.monthlyPayment > 0 ? Decimal(credit.monthlyPayment) : nil,
                paymentDay: credit.paymentDayOfMonth,
                termEnd: credit.endDate,
                scheduleType: .annuity,
                insurance: nil
            )),
            initialMarketPurchase: nil,
            includeInTotal: credit.includeInTotal
        )
    }

    /// Инвестиция → `.manualAsset` (движок F замораживает значение одним opening-событием), КРОМЕ
    /// «кэш-подобной» (`isCashflowAccount`, пресет «Счёт» — плюс/other/не рыночная) — та мигрирует
    /// в `.bankAccount` (движок cashLike), чтобы попасть в `newCoreAccountsForCashflowPicker()` и
    /// остаться выбираемой целью income/expense в Cashflow (Фаза 5a плана 6b «Путь B» — без этого
    /// счёт после миграции пропадает из пикера, легаси-ветка `.investment` архивируется).
    ///
    /// Для остальных (рыночные/вклад/недвижимость/бизнес/долг вне `.debt`-ветки Credit) — осознанная
    /// девиация от «инвестиция → рыночный тип» брифинга: рыночный движок E считает баланс как
    /// quantity×price и ИГНОРИРУЕТ opening — двойник показал бы 0, ломая инвариант тотала; MVP
    /// запрещает реплей истории/котировок. `.deposit` потребовал бы meta/scheduler и рисковал бы
    /// будущим дрейфом от начислений. `.manualAsset` замораживает любое значение без meta и без
    /// дрейфа — единственный вариант, гарантирующий инвариант при MVP-ограничениях.
    /// Знаковый вклад = ±`amount` при `includeInTotal`, иначе 0 (как в `getAccountAmount`).
    static func plan(for investment: Investment, currency: String) -> Plan {
        let signed = investment.includeInTotal
            ? (investment.investmentType == .positive ? investment.amount : -investment.amount)
            : 0
        if investment.isCashflowAccount {
            return Plan(
                legacyUniqueID: investment.investmentUniqueID,
                name: investment.name,
                currency: currency,
                productType: .bankAccount,
                openingBalance: Decimal(signed),
                metadata: .init(),
                initialMarketPurchase: nil,
                includeInTotal: investment.includeInTotal
            )
        }
        if investment.isDeposit {
            let capitalization = AccountDepositCapitalization(rawValue: investment.depositCapitalizationRaw) ?? .none
            return Plan(
                legacyUniqueID: investment.investmentUniqueID,
                name: investment.name,
                currency: currency,
                productType: .deposit,
                openingBalance: Decimal(signed),
                metadata: .init(deposit: DepositMeta(
                    rate: Decimal(investment.depositInterestRate ?? 0),
                    capitalization: capitalization,
                    termEnd: investment.depositEndDate,
                    payoutDay: nil,
                    allowsTopUp: true,
                    allowsEarlyClose: true,
                    earlyClosePenalty: nil,
                    remindEnd: investment.depositNotifyDaysBefore != nil,
                    autoRollover: false
                )),
                initialMarketPurchase: nil,
                includeInTotal: investment.includeInTotal
            )
        }
        if investment.category == .debt {
            let direction: DebtDirection = investment.investmentType == .positive ? .owedToMe : .owedByMe
            return Plan(
                legacyUniqueID: investment.investmentUniqueID,
                name: investment.name,
                currency: currency,
                productType: direction == .owedToMe ? .receivable : .payable,
                openingBalance: Decimal(signed),
                metadata: .init(debt: DebtMeta(direction: direction, counterparty: nil, dueDate: nil, rate: nil)),
                initialMarketPurchase: nil,
                includeInTotal: investment.includeInTotal
            )
        }
        let marketProduct: AccountProductType? = switch investment.category {
        case .stocks: .marketStock
        case .crypto: .marketCrypto
        case .bonds: .marketBond
        case .metals: .marketMetal
        case .other where investment.marketSymbol != nil: .genericMarketInvestment
        default: nil
        }
        if let marketProduct,
           investment.investmentType == .positive,
           let symbol = investment.marketSymbol?.trimmingCharacters(in: .whitespacesAndNewlines),
           !symbol.isEmpty,
           let quantity = investment.marketQuantity,
           quantity > 0,
           investment.amount >= 0 {
            let unitPrice = Decimal(investment.amount) / Decimal(quantity)
            let assetClass: MarketAssetClass = switch marketProduct {
            case .marketCrypto: .crypto
            case .marketBond: .bond
            case .marketMetal: .metal
            default: .stock
            }
            return Plan(
                legacyUniqueID: investment.investmentUniqueID,
                name: investment.name,
                currency: currency,
                productType: marketProduct,
                openingBalance: 0,
                metadata: .init(market: MarketMeta(symbol: symbol.uppercased(), assetClass: assetClass)),
                initialMarketPurchase: .init(quantity: Decimal(quantity), unitPrice: unitPrice),
                includeInTotal: investment.includeInTotal
            )
        }
        if let marketProduct {
            // Preserve explicit market intent. Missing required evidence is rejected by the
            // catalog/factory; it must never silently turn a stock/crypto/bond/metal into a
            // manual asset and then hide the legacy source.
            let assetClass: MarketAssetClass = switch marketProduct {
            case .marketCrypto: .crypto
            case .marketBond: .bond
            case .marketMetal: .metal
            default: .stock
            }
            return Plan(
                legacyUniqueID: investment.investmentUniqueID,
                name: investment.name,
                currency: currency,
                productType: marketProduct,
                openingBalance: 0,
                metadata: .init(market: MarketMeta(
                    symbol: investment.marketSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    assetClass: assetClass
                )),
                initialMarketPurchase: nil,
                includeInTotal: investment.includeInTotal
            )
        }
        let manualProduct: AccountProductType = switch investment.category {
        case .house: .realEstate
        case .business: .business
        case .car: .vehicle
        default: .otherManualAsset
        }
        return Plan(
            legacyUniqueID: investment.investmentUniqueID,
            name: investment.name,
            currency: currency,
            productType: manualProduct,
            openingBalance: Decimal(signed),
            metadata: .init(manualAsset: ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)),
            initialMarketPurchase: nil,
            includeInTotal: investment.includeInTotal
        )
    }
}

/// Collects the only admissible evidence for classifying an already-created ambiguous core twin:
/// a structured legacy row still exists and the device-local registry maps that exact row to that
/// exact core UUID. Multiple rows targeting one UUID are ambiguous and deliberately produce no
/// evidence.
@MainActor
enum LegacyProductEvidenceCollector {
    static func collect(
        in context: ModelContext,
        registry: LegacyConversionRegistry? = nil
    ) -> [UUID: VerifiedLegacyProductEvidence] {
        let registry = registry ?? .shared
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let accountByID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var candidates: [UUID: [VerifiedLegacyProductEvidence]] = [:]

        func append<Row>(
            _ row: Row,
            identifier: (Row) -> String,
            productType: AccountProductType
        ) {
            let legacyID = identifier(row)
            guard let coreID = registry.coreAccountID(forLegacyUniqueID: legacyID),
                  let account = accountByID[coreID],
                  let evidence = VerifiedLegacyProductEvidence.verify(
                    row: row,
                    identifier: identifier,
                    productType: productType,
                    coreAccount: account,
                    registry: registry
                  ) else { return }
            candidates[coreID, default: []].append(evidence)
        }

        for card in (try? context.fetch(FetchDescriptor<Card>())) ?? [] {
            append(card, identifier: \.cardUniqueID, productType: LegacyAccountConversion.plan(for: card).productType)
        }
        for credit in (try? context.fetch(FetchDescriptor<Credit>())) ?? [] {
            append(credit, identifier: \.creditUniqueID, productType: LegacyAccountConversion.plan(for: credit).productType)
        }
        for investment in (try? context.fetch(FetchDescriptor<Investment>())) ?? [] {
            append(
                investment,
                identifier: \.investmentUniqueID,
                productType: LegacyAccountConversion.plan(
                    for: investment,
                    currency: investment.currency
                ).productType
            )
        }

        return candidates.reduce(into: [:]) { result, entry in
            guard entry.value.count == 1, let evidence = entry.value.first else { return }
            result[entry.key] = evidence
        }
    }
}
