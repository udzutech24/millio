import Foundation
import SwiftData

/// Production compatibility-domain replay for the remaining `FinanceAccount` graph.
///
/// The structured portfolio producer owns completeness and composition. This service owns only the
/// old Card/Credit/Investment replay semantics and exposes every requested legacy row as an explicit
/// contribution. A missing row/model is incomplete; it is never silently interpreted as zero.
@MainActor
final class LegacyHistoricalValuator: HistoricalPortfolioExternalCoverageProviding {
    private struct StructuredResolutionContext {
        let timeContext: HistoricalValuationTimeContext
        let evidence: HistoricalValuationLocalEvidenceSnapshot
        let now: Date
    }

    private struct Evaluation {
        let value: Double?
        let quality: HistoricalValuationQuality
        let unresolved: [HistoricalValuationUnresolvedContribution]
    }

    private let modelContext: ModelContext
    private let currencyService: CurrencyRateServiceProtocol
    private let historicalRateStore: HistoricalRateStore
    private let onEstimatedConversion: (() -> Void)?

    private var accountsByOpaqueID: [String: FinanceAccount] = [:]
    private var accountsByModelID: [String: FinanceAccount] = [:]
    private var verifiedMappedCoreIDsByLegacyModelID: [String: UUID] = [:]
    private var cardsByID: [String: Card] = [:]
    private var creditsByID: [String: Credit] = [:]
    private var investmentsByID: [String: Investment] = [:]
    private var transactionsByCardID: [String: [CashflowTransaction]] = [:]
    private var transactionsByCreditID: [String: [CashflowTransaction]] = [:]
    private var transactionsByInvestmentID: [String: [CashflowTransaction]] = [:]
    private var initialBalances: [String: Double] = [:]
    private var balances: [String: Double] = [:]
    private var structuredResolutionContext: StructuredResolutionContext?
    private var structuredResolutionFailure: HistoricalValuationUnresolvedContribution?
    private var structuredResolutionSummaries: [HistoricalValuationResolutionSummary] = []
    private var structuredResolutionAccountID: String?

    init(
        modelContext: ModelContext,
        currencyService: CurrencyRateServiceProtocol? = nil,
        onEstimatedConversion: (() -> Void)? = nil
    ) {
        let resolvedCurrencyService = currencyService ?? CurrencyRateService.shared
        self.modelContext = modelContext
        self.currencyService = resolvedCurrencyService
        self.historicalRateStore = HistoricalRateStore(
            modelContext: modelContext,
            currencyService: resolvedCurrencyService
        )
        self.onEstimatedConversion = onEstimatedConversion
        reload()
    }

    /// Refreshes the immutable inputs used by subsequent point evaluations and invalidates replay
    /// caches. Callers which keep the valuator alive across store mutations must call this first.
    func reload() {
        let accounts = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        accountsByOpaqueID = Dictionary(
            accounts.map { ($0.accountUniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        accountsByModelID = Dictionary(
            accounts.map { ($0.accountID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let coreIDs = Set(((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).map(\.id))
        verifiedMappedCoreIDsByLegacyModelID = Dictionary(
            accounts.compactMap { account in
                guard let coreID = LegacyConversionRegistry.shared.coreAccountID(
                    forLegacyUniqueID: account.accountID
                ), coreIDs.contains(coreID) else {
                    return nil
                }
                return (account.accountID, coreID)
            },
            uniquingKeysWith: { first, _ in first }
        )
        cardsByID = Dictionary(
            ((try? modelContext.fetch(FetchDescriptor<Card>())) ?? []).map { ($0.cardUniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        creditsByID = Dictionary(
            ((try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []).map { ($0.creditUniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        investmentsByID = Dictionary(
            ((try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []).map { ($0.investmentUniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        transactionsByCardID.removeAll()
        transactionsByCreditID.removeAll()
        transactionsByInvestmentID.removeAll()
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .forward)]
        )
        for transaction in (try? modelContext.fetch(descriptor)) ?? [] {
            if let cardID = transaction.cardID {
                transactionsByCardID[cardID, default: []].append(transaction)
            }
            if let toCardID = transaction.toCardID {
                transactionsByCardID[toCardID, default: []].append(transaction)
            }
            if let creditID = transaction.creditID {
                transactionsByCreditID[creditID, default: []].append(transaction)
            }
            if let investmentID = transaction.investmentID {
                transactionsByInvestmentID[investmentID, default: []].append(transaction)
            }
        }
        initialBalances.removeAll()
        balances.removeAll()
    }

    func balance(
        accounts: [FinanceAccount],
        at date: Date,
        displayCurrency: String,
        debtAsNegative: Bool = false,
        includeInitialBeforeCreation: Bool = false
    ) async -> Double {
        let sortedIDs = accounts.map(\.accountUniqueID).sorted()
        let cacheKey = [
            sortedIDs.joined(separator: "|"),
            String(date.timeIntervalSince1970),
            normalizedCurrency(displayCurrency),
            debtAsNegative ? "net" : "raw",
            includeInitialBeforeCreation ? "init" : "strict"
        ].joined(separator: "#")
        if let cached = balances[cacheKey] { return cached }

        var total = 0.0
        for account in accounts {
            let result = await evaluate(
                account: account,
                opaqueAccountID: account.accountUniqueID,
                at: date,
                displayCurrency: displayCurrency,
                debtAsNegative: debtAsNegative,
                includeInitialBeforeCreation: includeInitialBeforeCreation
            )
            if let value = result.value { total += value }
        }
        if balances.count < 1_000 { balances[cacheKey] = total }
        return total
    }

    /// Freezes rate/market evidence once for the whole series query. Rebuilding this snapshot for
    /// every sampled day was pure repeated I/O and could also mix evidence observed mid-query.
    func prepare(
        for query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext,
        now: Date
    ) {
        structuredResolutionContext = .init(
            timeContext: timeContext,
            evidence: HistoricalValuationLocalEvidenceSnapshot.make(
                modelContext: modelContext,
                timeContext: timeContext,
                now: now
            ),
            now: now
        )
    }

    func finishQuery() {
        structuredResolutionContext = nil
        structuredResolutionFailure = nil
    }

    func contributions(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> [HistoricalPortfolioAccountContribution]? {
        // Standalone callers retain fail-closed compatibility, while the producer prepares one
        // immutable snapshot per query and reuses it for every point.
        let ownsPreparedContext = structuredResolutionContext == nil
        if ownsPreparedContext {
            prepare(for: query, timeContext: timeContext, now: Date())
        }
        defer {
            if ownsPreparedContext { finishQuery() }
        }
        var output: [HistoricalPortfolioAccountContribution] = []
        output.reserveCapacity(query.unresolvedExternalAccountIDs.count)
        for opaqueID in query.unresolvedExternalAccountIDs.sorted() {
            guard let account = accountsByOpaqueID[opaqueID] ?? accountsByModelID[opaqueID] else {
                continue
            }
            structuredResolutionFailure = nil
            structuredResolutionSummaries = []
            structuredResolutionAccountID = opaqueID
            if verifiedMappedCoreIDsByLegacyModelID[account.accountID] != nil, archivedAt(for: account) == nil {
                structuredResolutionFailure = .init(
                    opaqueAccountID: opaqueID,
                    dimension: .migrationBoundary,
                    reasonCode: "verified_predecessor_boundary_missing"
                )
            }
            let evaluation = await evaluate(
                account: account,
                opaqueAccountID: opaqueID,
                at: date,
                displayCurrency: query.displayCurrency,
                debtAsNegative: true,
                includeInitialBeforeCreation: false
            )
            let strictUnresolved = structuredResolutionFailure.map {
                HistoricalValuationUnresolvedContribution(
                    opaqueAccountID: opaqueID,
                    dimension: $0.dimension,
                    reasonCode: $0.reasonCode
                )
            }
            let unresolved = evaluation.unresolved + [strictUnresolved].compactMap { $0 }
            let value = unresolved.isEmpty ? evaluation.value : nil
            let resolutions: [HistoricalValuationResolutionSummary]
            if value == 0 {
                resolutions = [.init(opaqueAccountID: opaqueID, kind: "provenZero")]
            } else if value != nil, structuredResolutionSummaries.isEmpty {
                resolutions = [.init(
                    opaqueAccountID: opaqueID,
                    dimension: .fxRate,
                    kind: HistoricalValuationResolutionKind.nativeParity.rawValue
                )]
            } else {
                resolutions = structuredResolutionSummaries
            }
            output.append(.init(
                opaqueAccountID: opaqueID,
                value: value.map { Decimal($0) },
                state: value == nil ? .incomplete : .complete,
                quality: value == nil ? .unavailable : evaluation.quality,
                unresolved: unresolved,
                resolutions: resolutions
            ))
        }
        return output
    }

    /// A verified migrated predecessor stops being a separate logical contribution on the core
    /// boundary day. Before that day it supplies the pre-core window under the requested opaque ID.
    func nonParticipatingAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<String> {
        Set(query.unresolvedExternalAccountIDs.filter { opaqueID in
            guard let account = accountsByOpaqueID[opaqueID] ?? accountsByModelID[opaqueID],
                  let coreID = verifiedMappedCoreIDsByLegacyModelID[account.accountID] else {
                return false
            }
            if case .accountIDs(let scopedCoreIDs) = query.accountScope,
               !scopedCoreIDs.contains(coreID) {
                return true
            }
            guard let archivedAt = archivedAt(for: account) else { return false }
            return timeContext.dayKey(for: date) >= timeContext.dayKey(for: archivedAt)
        })
    }

    /// Before the verified boundary the compatibility predecessor replaces its core successor.
    /// On and after the boundary `nonParticipatingAccountIDs` removes the predecessor instead.
    func replacedCoreAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<UUID> {
        var replaced: Set<UUID> = []
        for opaqueID in query.unresolvedExternalAccountIDs {
            guard let account = accountsByOpaqueID[opaqueID] ?? accountsByModelID[opaqueID],
                  let coreID = verifiedMappedCoreIDsByLegacyModelID[account.accountID],
                  let archivedAt = archivedAt(for: account),
                  timeContext.dayKey(for: date) < timeContext.dayKey(for: archivedAt) else {
                continue
            }
            if case .accountIDs(let scopedCoreIDs) = query.accountScope,
               !scopedCoreIDs.contains(coreID) {
                continue
            }
            replaced.insert(coreID)
        }
        return replaced
    }

    private func evaluate(
        account: FinanceAccount,
        opaqueAccountID: String,
        at date: Date,
        displayCurrency: String,
        debtAsNegative: Bool,
        includeInitialBeforeCreation: Bool
    ) async -> Evaluation {
        switch account.accountType {
        case .card:
            guard let card = cardsByID[account.accountID] else {
                return missingModel(opaqueAccountID: opaqueAccountID, reasonCode: "legacy_card_missing")
            }
            guard Self.isActive(includeInTotal: card.includeInTotal, archivedAt: card.archivedAt, at: date) else {
                return .init(value: 0, quality: .exact, unresolved: [])
            }

            let transactions = transactionsByCardID[account.accountID] ?? []
            let effectiveCreationDate = transactions.map(\.transactionDate).min()
                .map { min(card.createdAt, $0) } ?? card.createdAt
            let initialBalance = await initialCardBalance(card, currency: card.currency)
            var balance: Double
            if date < effectiveCreationDate {
                guard includeInitialBeforeCreation else {
                    return .init(value: 0, quality: .exact, unresolved: [])
                }
                balance = initialBalance
            } else {
                balance = initialBalance
                for transaction in transactions
                    .filter({ $0.transactionDate >= effectiveCreationDate && $0.transactionDate <= date })
                    .sorted(by: { $0.transactionDate < $1.transactionDate }) {
                    switch transaction.transactionType {
                    case .income:
                        if transaction.affectsCardBalance, transaction.cardID == account.accountID {
                            balance += await transactionAmount(transaction, to: card.currency).value
                        }
                    case .expense:
                        if transaction.affectsCardBalance, transaction.cardID == account.accountID {
                            balance = max(0, balance - (await transactionAmount(transaction, to: card.currency).value))
                        }
                    case .transfer:
                        let amount = await transactionAmount(transaction, to: card.currency).value
                        if transaction.cardID == account.accountID {
                            balance = max(0, balance - amount)
                        } else if transaction.toCardID == account.accountID {
                            balance += amount
                        }
                    case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                        if transaction.cardID == account.accountID {
                            balance += await transactionAmount(transaction, to: card.currency).value
                        }
                    }
                }
            }

            var accountBalance: Double
            if card.cardType == .credit, let limit = card.creditLimit {
                accountBalance = max(0, limit - balance)
            } else {
                accountBalance = balance
            }
            let lastTrackedChange = transactions.map(\.transactionDate).max() ?? card.createdAt
            let liveEffectiveDate = max(lastTrackedChange, card.updatedAt)
            if date.addingTimeInterval(1) >= liveEffectiveDate {
                let actual = if card.cardType == .credit, let limit = card.creditLimit {
                    max(0, limit - card.balance)
                } else {
                    card.balance
                }
                if abs(actual - accountBalance) > 0.01 { accountBalance = actual }
            }
            let converted = await convert(accountBalance, from: card.currency, to: displayCurrency, at: date)
            return .init(
                value: Self.signed(converted.value, isLiability: card.cardType == .credit, debtAsNegative: debtAsNegative),
                quality: converted.quality,
                unresolved: []
            )

        case .credit:
            guard let credit = creditsByID[account.accountID] else {
                return missingModel(opaqueAccountID: opaqueAccountID, reasonCode: "legacy_credit_missing")
            }
            guard Self.isActive(includeInTotal: credit.includeInTotal, archivedAt: credit.archivedAt, at: date) else {
                return .init(value: 0, quality: .exact, unresolved: [])
            }
            let transactions = transactionsByCreditID[credit.creditUniqueID] ?? []
            let effectiveCreationDate = transactions.map(\.transactionDate).min()
                .map { min(credit.createdAt, $0) } ?? credit.createdAt
            let native: Double
            if date < effectiveCreationDate {
                guard includeInitialBeforeCreation else {
                    return .init(value: 0, quality: .exact, unresolved: [])
                }
                native = credit.initialRemainingAmount
            } else {
                native = await creditRemainingAmount(credit, at: date, currency: credit.currency)
            }
            let converted = await convert(native, from: credit.currency, to: displayCurrency, at: date)
            return .init(
                value: Self.signed(converted.value, isLiability: true, debtAsNegative: debtAsNegative),
                quality: converted.quality,
                unresolved: []
            )

        case .investment:
            guard let investment = investmentsByID[account.accountID] else {
                return missingModel(opaqueAccountID: opaqueAccountID, reasonCode: "legacy_investment_missing")
            }
            guard Self.isActive(
                includeInTotal: investment.includeInTotal,
                archivedAt: investment.archivedAt,
                at: date
            ) else {
                return .init(value: 0, quality: .exact, unresolved: [])
            }
            let currency = investmentCurrency(investment)
            let transactions = transactionsByInvestmentID[investment.investmentUniqueID] ?? []
            var baseAmount = baselineAmount(investment)
            if !investment.hasInitialAmount {
                var totalDelta = 0.0
                for transaction in transactions where
                    transaction.transactionType == .balanceAdjustment &&
                    transaction.investmentID == investment.investmentUniqueID {
                    totalDelta += await transactionAmount(transaction, to: currency).value
                }
                baseAmount = investment.amount - totalDelta
            }

            let sign = investment.investmentType == .positive ? 1.0 : -1.0
            var native = sign * baseAmount
            if date < investment.createdAt {
                guard includeInitialBeforeCreation else {
                    return .init(value: 0, quality: .exact, unresolved: [])
                }
            } else {
                let adjustments = transactions.filter {
                    $0.transactionType == .balanceAdjustment &&
                    $0.investmentID == investment.investmentUniqueID &&
                    $0.transactionDate <= date
                }.sorted(by: { $0.transactionDate < $1.transactionDate })
                if investment.isMarketPriced {
                    native = await marketInvestmentBalance(
                        investment,
                        currency: currency,
                        baseAmount: baseAmount,
                        allTransactions: transactions,
                        relevantTransactions: adjustments,
                        fallback: native,
                        at: date
                    )
                } else {
                    for transaction in adjustments {
                        native += await transactionAmount(transaction, to: currency).value
                    }
                }
                let actual = investment.investmentType == .positive ? investment.amount : -investment.amount
                let lastTrackedChange = adjustments.map(\.transactionDate).max() ?? investment.createdAt
                if date.addingTimeInterval(1) >= max(lastTrackedChange, investment.updatedAt),
                   abs(actual - native) > 0.01 {
                    native = actual
                }
            }
            let converted = await convert(native, from: currency, to: displayCurrency, at: date)
            return .init(value: converted.value, quality: converted.quality, unresolved: [])
        }
    }

    private func initialCardBalance(_ card: Card, currency: String) async -> Double {
        if card.hasInitialBalance { return card.initialBalance }
        if let cached = initialBalances[card.cardUniqueID] { return cached }
        var adjustments = 0.0
        for transaction in transactionsByCardID[card.cardUniqueID] ?? [] where
            (transaction.transactionType == .balanceAdjustment ||
             transaction.transactionType == .cardBalanceAdjustment ||
             transaction.transactionType == .creditDebtAdjustment) &&
            transaction.cardID == card.cardUniqueID {
            adjustments += await transactionAmount(transaction, to: currency).value
        }
        let result = card.balance - adjustments
        initialBalances[card.cardUniqueID] = result
        return result
    }

    func creditRemainingAmount(_ credit: Credit, at date: Date, currency: String) async -> Double {
        let transactions = transactionsByCreditID[credit.creditUniqueID] ?? []
        var baseAmount: Double
        if credit.hasInitialRemainingAmount {
            baseAmount = credit.initialRemainingAmount
        } else {
            var adjustments = 0.0
            for transaction in transactions where
                (transaction.transactionType == .balanceAdjustment ||
                 transaction.transactionType == .creditDebtAdjustment) &&
                transaction.creditID == credit.creditUniqueID {
                adjustments += await transactionAmount(transaction, to: currency).value
            }
            baseAmount = credit.remainingAmount - adjustments
        }
        let relevant = transactions.filter {
            ($0.transactionType == .balanceAdjustment || $0.transactionType == .creditDebtAdjustment) &&
            $0.creditID == credit.creditUniqueID && $0.transactionDate <= date
        }.sorted(by: { $0.transactionDate < $1.transactionDate })
        var remaining = baseAmount
        for transaction in relevant {
            remaining = max(0, remaining - (await transactionAmount(transaction, to: currency).value))
        }
        let lastTrackedChange = relevant.map(\.transactionDate).max() ?? credit.createdAt
        if date >= max(lastTrackedChange, credit.updatedAt), abs(credit.remainingAmount - remaining) > 0.01 {
            remaining = max(0, credit.remainingAmount)
        }
        return remaining
    }

    func convertedAmount(_ value: Double, from: String, to: String, at date: Date? = nil) async -> Double {
        await convert(value, from: from, to: to, at: date).value
    }

    private func marketInvestmentBalance(
        _ investment: Investment,
        currency: String,
        baseAmount: Double,
        allTransactions: [CashflowTransaction],
        relevantTransactions: [CashflowTransaction],
        fallback: Double,
        at date: Date
    ) async -> Double {
        let allAdjustments = allTransactions.filter {
            $0.transactionType == .balanceAdjustment &&
            $0.investmentID == investment.investmentUniqueID
        }.sorted(by: { $0.transactionDate < $1.transactionDate })
        guard !allAdjustments.isEmpty else { return fallback }
        let sign = investment.investmentType == .positive ? 1.0 : -1.0
        if let first = allAdjustments.first,
           date < first.transactionDate,
           let amountBefore = first.assetAmountBefore {
            return sign * amountBefore
        }
        var unsigned = baseAmount
        for transaction in relevantTransactions {
            if let amountAfter = transaction.assetAmountAfter {
                unsigned = amountAfter
            } else {
                unsigned += await transactionAmount(transaction, to: currency).value
            }
        }
        return sign * unsigned
    }

    private func transactionAmount(
        _ transaction: CashflowTransaction,
        to targetCurrency: String
    ) async -> (value: Double, quality: HistoricalValuationQuality) {
        let target = normalizedCurrency(targetCurrency)
        let source = normalizedCurrency(transaction.currency)
        if source == target { return (transaction.amount, .exact) }
        if let rate = transaction.exchangeRate,
           rate > 0,
           let frozenCurrency = transaction.exchangeRateCurrency,
           normalizedCurrency(frozenCurrency) == target {
            return (transaction.amount * rate, .exact)
        }
        return await convert(
            transaction.amount,
            from: transaction.currency,
            to: targetCurrency,
            at: transaction.transactionDate
        )
    }

    private func convert(
        _ value: Double,
        from: String,
        to: String,
        at date: Date?
    ) async -> (value: Double, quality: HistoricalValuationQuality) {
        let source = normalizedCurrency(from)
        let target = normalizedCurrency(to)
        guard source != target else { return (value, .exact) }

        if let structuredResolutionContext {
            let request = HistoricalValuationContributionRequest(
                id: "legacy-fx",
                origin: .compatibility,
                valuationDate: date ?? structuredResolutionContext.now,
                input: .native(
                    value: Decimal(value),
                    currency: source,
                    fxPolicy: .fiat(id: "legacy-fiat-v1")
                )
            )
            let resolutions = await HistoricalValuationResolver().resolve(
                requests: [request],
                displayCurrency: target,
                timeContext: structuredResolutionContext.timeContext,
                now: structuredResolutionContext.now,
                evidenceProvider: structuredResolutionContext.evidence
            )
            if let resolution = resolutions.first, let resolved = resolution.value {
                structuredResolutionSummaries.append(contentsOf: resolution.dependencies.map { dependency in
                    let provenance = dependency.provenance
                    return HistoricalValuationResolutionSummary(
                        opaqueAccountID: structuredResolutionAccountID ?? request.id,
                        dimension: dependency.dimension,
                        kind: dependency.kind.rawValue,
                        sourceID: provenance?.sourceID,
                        recordID: provenance?.recordID,
                        evidenceDayKey: provenance?.evidenceDayKey,
                        observedAt: provenance?.observedAt,
                        calendarPolicyID: provenance?.calendarPolicyID
                    )
                })
                return (NSDecimalNumber(decimal: resolved).doubleValue, resolution.quality)
            }
            if structuredResolutionFailure == nil {
                let reason = resolutions.first?.dependencies
                    .first(where: { $0.value == nil })?.reasonCode ?? "legacy_fx_unavailable"
                structuredResolutionFailure = .init(
                    opaqueAccountID: request.id,
                    dimension: .fxRate,
                    reasonCode: reason
                )
            }
            // Internal placeholder only: `contributions` discards the whole account evaluation when
            // this marker is set, so a wrong-currency native amount never enters a structured total.
            return (value, .unavailable)
        }

        if let date {
            let result = await historicalRateStore.getRate(on: date, from: source, to: target)
            if let rate = result.rate {
                switch result.resolution {
                case .exact:
                    return (value * rate, .exact)
                case .previous:
                    onEstimatedConversion?()
                    return (value * rate, .fallback)
                case .current:
                    onEstimatedConversion?()
                    return (value * rate, .estimated)
                case .unavailable:
                    break
                }
            }
        }
        if let converted = await currencyService.convert(amount: value, from: source, to: target) {
            onEstimatedConversion?()
            return (converted, .estimated)
        }
        // Compatibility semantics: the old replay returned the native amount when every FX source
        // failed. It remains explicit as estimated legacy coverage and is observable in shadow mode.
        onEstimatedConversion?()
        return (value, .estimated)
    }

    private func baselineAmount(_ investment: Investment) -> Double {
        let endOfCreationDay = Calendar.current.date(
            bySettingHour: 23, minute: 59, second: 59, of: investment.createdAt
        ) ?? investment.createdAt
        if investment.hasInitialAmount {
            if abs(investment.initialAmount) >= 0.01 { return investment.initialAmount }
            if investment.isMarketPriced,
               investment.updatedAt <= endOfCreationDay,
               abs(investment.amount) >= 0.01 { return investment.amount }
            if investment.isMarketPriced, let cost = investment.totalPurchaseCost, cost > 0 { return cost }
            return investment.initialAmount
        }
        if investment.isMarketPriced,
           investment.updatedAt <= endOfCreationDay,
           abs(investment.amount) >= 0.01 { return investment.amount }
        if investment.isMarketPriced, let cost = investment.totalPurchaseCost, cost > 0 { return cost }
        return investment.amount
    }

    private func investmentCurrency(_ investment: Investment) -> String {
        let stored = investment.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !stored.isEmpty { return stored }
        let market = investment.marketCurrency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return market.isEmpty ? "USD" : market
    }

    private func normalizedCurrency(_ currency: String) -> String {
        let value = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { return "USD" }
        if ["USDT", "USDC", "BUSD", "TUSD", "FDUSD", "DAI"].contains(value) { return "USD" }
        if value.contains("/") { return normalizedCurrency(String(value.split(separator: "/").last!)) }
        if value.contains("-") { return normalizedCurrency(String(value.split(separator: "-").last!)) }
        return value
    }

    private func missingModel(opaqueAccountID: String, reasonCode: String) -> Evaluation {
        .init(
            value: nil,
            quality: .unavailable,
            unresolved: [.init(
                opaqueAccountID: opaqueAccountID,
                dimension: .accountData,
                reasonCode: reasonCode
            )]
        )
    }

    private func archivedAt(for account: FinanceAccount) -> Date? {
        switch account.accountType {
        case .card: cardsByID[account.accountID]?.archivedAt
        case .credit: creditsByID[account.accountID]?.archivedAt
        case .investment: investmentsByID[account.accountID]?.archivedAt
        }
    }

    private static func isActive(includeInTotal: Bool, archivedAt: Date?, at date: Date) -> Bool {
        guard includeInTotal else { return false }
        guard let archivedAt else { return true }
        return date <= archivedAt
    }

    private static func signed(_ amount: Double, isLiability: Bool, debtAsNegative: Bool) -> Double {
        debtAsNegative && isLiability ? -abs(amount) : amount
    }
}
