import Foundation
import SwiftData

/// Единая точка расчёта тоталов/графика по счетам нового ядра — заменяет три расходящихся пути
/// старого мира (AC2: Accounts-тотал == Analytics-тотал == график). НЕ трогает старый
/// `FinanceTotalsService` (интеграция сумм old+new — задача Фазы 1a-ui).
@MainActor
final class AccountsTotalsService {
    private let modelContext: ModelContext
    private let rebuilder: AccountSnapshotRebuilder
    private let rateService: CurrencyRateServiceProtocol
    private let historicalRateStore: HistoricalRateStore
    /// Опционален (Фаза 4): без него рыночные счета считаются по последней известной цене buy/sell
    /// из событий (fallback внутри `AccountBalanceEngine.marketBalance`) — тесты, не подключающие
    /// живые котировки, продолжают работать без изменений (обратная совместимость с Фазой 1a).
    private let marketPriceService: AccountMarketPriceService?
    private let historicalDataAccess: HistoricalValuationDataAccess
    private let historicalEvidenceProvider: (any HistoricalValuationEvidenceProviding)?
    private let scopeReadiness: @MainActor () -> HistoricalScopeReadiness

    init(
        modelContext: ModelContext,
        rebuilder: AccountSnapshotRebuilder,
        rateService: CurrencyRateServiceProtocol,
        marketPriceService: AccountMarketPriceService? = nil,
        historicalDataAccess: HistoricalValuationDataAccess? = nil,
        historicalEvidenceProvider: (any HistoricalValuationEvidenceProviding)? = nil,
        scopeReadiness: @escaping @MainActor () -> HistoricalScopeReadiness = { .ready }
    ) {
        self.modelContext = modelContext
        self.rebuilder = rebuilder
        self.rateService = rateService
        self.historicalRateStore = HistoricalRateStore(
            modelContext: modelContext,
            currencyService: rateService
        )
        self.marketPriceService = marketPriceService
        self.historicalEvidenceProvider = historicalEvidenceProvider
        self.historicalDataAccess = historicalDataAccess ?? .live(
            modelContext: modelContext,
            rebuilder: rebuilder,
            marketPriceService: marketPriceService
        )
        self.scopeReadiness = scopeReadiness
    }

    // MARK: - Structured Phase 1V boundary

    func availableHistoricalAccountIDs() -> Set<UUID>? {
        do { return Set(try modelContext.fetch(FetchDescriptor<Account>()).map(\.id)) }
        catch { return nil }
    }

    /// Typed historical boundary used by the future portfolio producer. It intentionally performs
    /// direct event replay: existing snapshots have only a lexical day key, with no checkpoint
    /// timestamp/frozen timezone/evidence revision, so they cannot safely prove historical identity.
    /// Cache operations are still checked and surfaced; they are never allowed to replace source data.
    func historicalValuation(
        at date: Date,
        in currency: String,
        scopeID: String,
        accountIDs: Set<UUID>? = nil,
        timeContext: HistoricalValuationTimeContext,
        clock: any HistoricalValuationClock,
        schemaVersion: Int = HistoricalPortfolioValuation.storageSchemaVersion,
        valuationPolicyVersion: Int = 1
    ) async -> HistoricalValuationResult {
        await historicalValuationBatch(
            at: date,
            in: currency,
            scopeID: scopeID,
            accountIDs: accountIDs,
            timeContext: timeContext,
            clock: clock,
            schemaVersion: schemaVersion,
            valuationPolicyVersion: valuationPolicyVersion
        ).portfolio
    }

    /// Resolves the portfolio and its account slices from the same fetched accounts, events and
    /// evidence snapshot. This is the structured batching boundary used by chart consumers.
    func historicalValuationBatch(
        at date: Date,
        in currency: String,
        scopeID: String,
        accountIDs: Set<UUID>? = nil,
        timeContext: HistoricalValuationTimeContext,
        clock: any HistoricalValuationClock,
        schemaVersion: Int = HistoricalPortfolioValuation.storageSchemaVersion,
        valuationPolicyVersion: Int = 1
    ) async -> HistoricalPortfolioValuationBatch {
        let generatedAt = clock.now
        let readinessAtStart = HistoricalValuationReadinessCoordinator.shared.snapshot(
            scopeID: scopeID
        )
        let finality: HistoricalValuationFinality = timeContext.isOpenDay(date, now: generatedAt) ? .open : .closed
        let displayCurrency = HistoricalValuationCurrencyCode.normalized(currency)
        let emptyRevision = HistoricalValuationInputRevision(accountSet: 0, financial: 0, events: 0, evidence: 0)

        func key(_ revision: HistoricalValuationInputRevision) -> HistoricalValuationKey {
            .init(
                schemaVersion: schemaVersion,
                scopeID: scopeID,
                dayKey: timeContext.dayKey(for: date),
                timeZoneID: timeContext.timeZoneID,
                displayCurrency: displayCurrency,
                valuationPolicyVersion: valuationPolicyVersion,
                inputRevision: revision
            )
        }

        func failedScope(
            readiness: HistoricalScopeReadiness,
            dimension: HistoricalValuationMissingDimension,
            reason: String
        ) -> HistoricalValuationResult {
            HistoricalValuationResult(
                key: key(emptyRevision),
                diagnosticPartialTotal: 0,
                finality: finality,
                quality: .unavailable,
                publication: .unpublished,
                scopeReadiness: readiness,
                readinessToken: readinessAtStart.token,
                expectedContributionCount: 0,
                resolvedContributionCount: 0,
                unresolved: [.init(opaqueAccountID: "scope", dimension: dimension, reasonCode: reason)],
                resolutions: [],
                generatedAt: generatedAt
            )
        }

        let injectedInitialReadiness = scopeReadiness()
        let initialReadiness = readinessAtStart.readiness == .ready
            ? injectedInitialReadiness
            : readinessAtStart.readiness
        guard initialReadiness == .ready else {
            return .init(portfolio: failedScope(
                readiness: initialReadiness,
                dimension: .scopeReadiness,
                reason: initialReadiness.reasonCode ?? "scope_not_ready"
            ), accountContributions: [])
        }
        guard HistoricalValuationCurrencyCode.isSupported(displayCurrency) else {
            return .init(
                portfolio: failedScope(readiness: .ready, dimension: .fxRate, reason: "invalid_display_currency"),
                accountContributions: []
            )
        }

        let allAccounts: [Account]
        do {
            allAccounts = try historicalDataAccess.fetchAccounts()
        } catch {
            return .init(portfolio: failedScope(
                readiness: .failed(reasonCode: "account_fetch_failed"),
                dimension: .accountData,
                reason: "account_fetch_failed"
            ), accountContributions: [])
        }

        let accounts = allAccounts.filter {
            (accountIDs == nil || accountIDs?.contains($0.id) == true)
                && $0.createdAt <= date
                && $0.participates(on: date)
        }
        let priceProvider: MarketPriceProviding?
        do {
            priceProvider = try historicalDataAccess.makeMarketPriceProvider(accounts)
        } catch {
            let failures = accounts.isEmpty
                ? [HistoricalValuationUnresolvedContribution(
                    opaqueAccountID: "scope", dimension: .cache, reasonCode: "price_cache_fetch_failed"
                )]
                : accounts.map {
                    HistoricalValuationUnresolvedContribution(
                        opaqueAccountID: $0.id.uuidString,
                        dimension: .cache,
                        reasonCode: "price_cache_fetch_failed"
                    )
                }
            return .init(portfolio: HistoricalValuationResult(
                key: key(emptyRevision),
                diagnosticPartialTotal: 0,
                finality: finality,
                quality: .unavailable,
                publication: .unpublished,
                scopeReadiness: .ready,
                readinessToken: readinessAtStart.token,
                expectedContributionCount: accounts.count,
                resolvedContributionCount: 0,
                unresolved: failures,
                resolutions: [],
                generatedAt: generatedAt
            ), accountContributions: accounts.map { account in
                .init(
                    opaqueAccountID: account.id.uuidString,
                    value: nil,
                    state: .incomplete,
                    quality: .unavailable,
                    unresolved: failures.filter { $0.opaqueAccountID == account.id.uuidString }
                )
            })
        }

        var unresolved: [HistoricalValuationUnresolvedContribution] = []
        var eventsByAccountID: [UUID: [AccountEvent]] = [:]
        var requests: [HistoricalValuationContributionRequest] = []
        // Both CBR and the global fiat provider publish business-day closes. This versioned policy
        // permits Friday's persisted close on a weekend, but rejects an ordinary weekday miss.
        let historicalFXPolicy = HistoricalValuationCalendarPolicy.fiat(
            id: "historical-fiat-business-days-v1"
        )

        for account in accounts {
            let opaqueID = account.id.uuidString
            let events: [AccountEvent]
            do {
                events = try historicalDataAccess.fetchEvents(account)
                eventsByAccountID[account.id] = events
            } catch {
                unresolved.append(.init(
                    opaqueAccountID: opaqueID,
                    dimension: .events,
                    reasonCode: "event_fetch_failed"
                ))
                continue
            }

            do {
                try await historicalDataAccess.rebuildSnapshots(account, date, priceProvider)
            } catch {
                unresolved.append(.init(
                    opaqueAccountID: opaqueID,
                    dimension: .nativeBalance,
                    reasonCode: "snapshot_rebuild_failed"
                ))
                continue
            }

            do {
                if let snapshot = try historicalDataAccess.fetchLatestSnapshot(account, timeContext.dayKey(for: date)),
                   !timeContext.isValid(dayKey: snapshot.dayKey) {
                    unresolved.append(.init(
                        opaqueAccountID: opaqueID,
                        dimension: .cache,
                        reasonCode: "snapshot_cache_corrupted"
                    ))
                    continue
                }
            } catch {
                unresolved.append(.init(
                    opaqueAccountID: opaqueID,
                    dimension: .cache,
                    reasonCode: "snapshot_fetch_failed"
                ))
                continue
            }

            let input: HistoricalValuationContributionInput
            if account.kind == .marketInvestment {
                let quantity = AccountBalanceEngine.marketQuantityAt(events: events, on: date)
                let meta = account.marketMeta
                let instrument = HistoricalMarketInstrument(
                    symbol: meta?.symbol ?? "",
                    assetClass: meta?.assetClass ?? .stock
                )
                let pricePolicy: HistoricalValuationCalendarPolicy = meta?.assetClass == .crypto
                    ? .crypto24x7(id: "local-crypto-24x7-v1")
                    : .exchange(
                        id: "historical-market-business-days-v1"
                    )
                input = .market(
                    quantity: quantity,
                    instrument: instrument,
                    quoteCurrency: account.currency,
                    pricePolicy: pricePolicy,
                    fxPolicy: historicalFXPolicy
                )
            } else {
                let rawBalance = AccountBalanceEngine.balanceAt(
                    events: events,
                    kind: account.kind,
                    on: date
                )
                let contribution = AccountTotalsContribution.signedValue(
                    rawBalance: rawBalance,
                    kind: account.kind,
                    creditLimit: account.cardMeta?.creditLimit
                )
                input = .native(value: contribution, currency: account.currency, fxPolicy: historicalFXPolicy)
            }
            requests.append(.init(id: opaqueID, origin: .core, valuationDate: date, input: input))
        }

        let evidenceProvider: any HistoricalValuationEvidenceProviding
        if let historicalEvidenceProvider {
            evidenceProvider = historicalEvidenceProvider
        } else {
            evidenceProvider = HistoricalValuationLocalEvidenceSnapshot.make(
                modelContext: modelContext,
                timeContext: timeContext,
                now: generatedAt
            )
        }
        let contributionResults = await HistoricalValuationResolver().resolve(
            requests: requests,
            displayCurrency: displayCurrency,
            timeContext: timeContext,
            now: generatedAt,
            evidenceProvider: evidenceProvider
        )

        var partialTotal: Decimal = 0
        var resolvedCount = 0
        var resolutions: [HistoricalValuationResolutionSummary] = []
        var contributionQualities: Set<HistoricalValuationQuality> = []
        for result in contributionResults {
            contributionQualities.insert(result.quality)
            if let value = result.value {
                let next = partialTotal + value
                if next.isNaN {
                    unresolved.append(.init(
                        opaqueAccountID: result.requestID,
                        dimension: .nativeBalance,
                        reasonCode: "valuation_overflow"
                    ))
                } else {
                    partialTotal = next
                    resolvedCount += 1
                }
            } else {
                for dependency in result.dependencies where dependency.value == nil {
                    unresolved.append(.init(
                        opaqueAccountID: result.requestID,
                        dimension: dependency.dimension,
                        reasonCode: dependency.reasonCode ?? "evidence_unavailable"
                    ))
                }
            }
            for dependency in result.dependencies {
                let provenance = dependency.provenance
                resolutions.append(.init(
                    opaqueAccountID: result.requestID,
                    dimension: dependency.dimension,
                    kind: dependency.kind.rawValue,
                    sourceID: provenance?.sourceID,
                    recordID: provenance?.recordID,
                    evidenceDayKey: provenance?.evidenceDayKey,
                    observedAt: provenance?.observedAt,
                    calendarPolicyID: provenance?.calendarPolicyID
                ))
            }
            if result.dependencies.isEmpty, result.value == 0 {
                resolutions.append(.init(opaqueAccountID: result.requestID, kind: "provenZero"))
            }
        }

        let revision = HistoricalValuationRevisionBuilder.build(
            accounts: accounts,
            eventsByAccountID: eventsByAccountID,
            evidenceRevision: HistoricalValuationEvidenceRevision.digest(contributionResults)
        )
        let injectedFinalReadiness = scopeReadiness()
        let readinessAtEnd = HistoricalValuationReadinessCoordinator.shared.snapshot(
            scopeID: scopeID
        )
        let finalReadiness: HistoricalScopeReadiness
        if readinessAtEnd.token != readinessAtStart.token {
            finalReadiness = .failed(reasonCode: "scope_changed_during_read")
        } else if readinessAtEnd.readiness != .ready {
            finalReadiness = readinessAtEnd.readiness
        } else {
            finalReadiness = injectedFinalReadiness
        }
        if finalReadiness != .ready {
            unresolved.append(.init(
                opaqueAccountID: "scope",
                dimension: .scopeReadiness,
                reasonCode: finalReadiness.reasonCode ?? "scope_changed_during_read"
            ))
        }

        let quality: HistoricalValuationQuality
        if !unresolved.isEmpty {
            quality = .unavailable
        } else if contributionQualities.count > 1 || contributionQualities.contains(.mixed) {
            quality = .mixed
        } else {
            quality = contributionQualities.first ?? .exact
        }

        let portfolio = HistoricalValuationResult(
            key: key(revision),
            diagnosticPartialTotal: partialTotal,
            finality: finality,
            quality: quality,
            publication: .unpublished,
            scopeReadiness: finalReadiness,
            readinessToken: readinessAtStart.token,
            expectedContributionCount: accounts.count,
            resolvedContributionCount: resolvedCount,
            unresolved: unresolved,
            resolutions: resolutions,
            generatedAt: generatedAt
        )
        let resultsByID = Dictionary(
            contributionResults.map { ($0.requestID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let accountContributions = accounts
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { account -> HistoricalPortfolioAccountContribution in
                let opaqueID = account.id.uuidString
                let result = resultsByID[opaqueID]
                let accountUnresolved = unresolved.filter { $0.opaqueAccountID == opaqueID }
                let value = accountUnresolved.isEmpty ? result?.value : nil
                return .init(
                    opaqueAccountID: opaqueID,
                    value: value,
                    state: value == nil ? .incomplete : .complete,
                    quality: value == nil ? .unavailable : (result?.quality ?? .unavailable),
                    unresolved: accountUnresolved,
                    resolutions: resolutions.filter { $0.opaqueAccountID == opaqueID }
                )
            }
        return .init(portfolio: portfolio, accountContributions: accountContributions)
    }

    /// Быстрая проверка «есть ли хоть один счёт нового ядра» — дешёвый COUNT без загрузки объектов.
    /// Все дорогие пути (`totalAt`/`seriesBetween`) выходят рано, пока новых счетов ещё нет
    /// (Т2 в плане: не платим за реплей там, где платить не за что — критично для сосуществования
    /// со старым миром в Фазе 1a-ui, где у подавляющего большинства ViewModel'ов новых счетов нет).
    private func hasAnyAccounts() -> Bool {
        ((try? modelContext.fetchCount(FetchDescriptor<Account>())) ?? 0) > 0
    }

    /// Transition/rollback reader retained until the Phase 4 consumer cutover. It deliberately
    /// preserves the pre-2V best-effort semantics (including silent omission) and must not feed
    /// published portfolio history. New structured consumers use `historicalValuation` above,
    /// whose evidence and failure policy is owned exclusively by `HistoricalValuationResolver`.
    ///
    /// Σ по счетам нового ядра: `balanceAt(счёт, date)` в валюте счёта × курс(валюта счёта → currency,
    /// НА ДАТУ `date`). Для сегодня — текущий курс, для прошлого — исторический (AC13).
    func totalAt(_ date: Date, in currency: String, participatingOnly: Bool = true) async -> Decimal {
        guard hasAnyAccounts(), let accounts = try? modelContext.fetch(FetchDescriptor<Account>()) else { return 0 }

        // Провайдер цен строится ОДИН РАЗ на весь вызов (не на каждый счёт) — одна выборка кэша на
        // все символы портфеля вместо N (Т2: не платим за реплей там, где можно один раз прочитать кэш).
        let priceProvider = marketPriceProvider(for: accounts)

        var total: Decimal = 0
        for account in accounts {
            if participatingOnly, !account.participates(on: date) { continue }
            guard let balance = try? await balance(for: account, on: date, priceProvider: priceProvider) else { continue }
            guard balance != 0 else { continue } // 0 × курс = 0 — не запрашиваем курс впустую
            guard let rate = await rate(from: account.currency, to: currency, on: date) else { continue }
            total += balance * Decimal(rate)
        }
        return total
    }

    /// Σ по ЗАДАННОМУ подмножеству счетов нового ядра на дату — та же механика, что `totalAt`, но по
    /// готовому списку (per-group сумма: Фаза 1.5 слияния групп, чтобы группа из core-счетов давала
    /// верную сумму/дельту на экранах «Счета»/«Динамика»). `participatingOnly` фильтрует архивные.
    func total(for accounts: [Account], on date: Date, in currency: String, participatingOnly: Bool = true) async -> Decimal {
        guard !accounts.isEmpty else { return 0 }
        let priceProvider = marketPriceProvider(for: accounts)
        var total: Decimal = 0
        for account in accounts {
            if participatingOnly, !account.participates(on: date) { continue }
            guard let balance = try? await balance(for: account, on: date, priceProvider: priceProvider) else { continue }
            guard balance != 0 else { continue }
            guard let rate = await rate(from: account.currency, to: currency, on: date) else { continue }
            total += balance * Decimal(rate)
        }
        return total
    }

    /// Точки для графика: одна точка на календарный день между `start` и `end` включительно,
    /// каждая — курсом СВОЕЙ даты (AC13), не сегодняшним.
    func seriesBetween(start: Date, end: Date, currency: String) async -> [(Date, Decimal)] {
        guard start <= end, hasAnyAccounts() else { return [] }
        var result: [(Date, Decimal)] = []
        var cursor = start
        let calendar = Calendar(identifier: .gregorian)
        while cursor <= end {
            let value = await totalAt(cursor, in: currency)
            result.append((cursor, value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - Баланс счёта на дату (кэш с fallback на реплей)

    private func balance(for account: Account, on date: Date, priceProvider: MarketPriceProviding?) async throws -> Decimal {
        // Досчитываем недостающий хвост кэша (быстрый no-op на тёплом кэше — Т2).
        try await rebuilder.rebuild(accountID: account.persistentModelID, upTo: date, priceProvider: priceProvider)

        // Phase 1V: persisted checkpoints contain only a lexical dayKey. They do not record the
        // effective checkpoint timestamp, frozen timezone or market-price evidence revision.
        // Therefore even a lexically earlier day can be a later instant after a timezone change,
        // and a market checkpoint embeds the wrong price for a later query day. Until the additive
        // checkpoint schema can prove those dimensions, snapshots are rebuildable diagnostics only;
        // both the structured and compatibility readers use authoritative timestamp replay.
        let rawBalance = AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: account.kind,
            on: date,
            priceProvider: priceProvider,
            marketMeta: account.marketMeta
        )

        return AccountTotalsContribution.signedValue(
            rawBalance: rawBalance,
            kind: account.kind,
            creditLimit: account.cardMeta?.creditLimit
        )
    }

    // MARK: - Провайдер цен (Фаза 4)

    /// Собирает `MarketPriceProviding` ОДИН РАЗ на список счетов — единственная выборка кэша цен
    /// на все символы, а не по одной на каждый рыночный счёт (Т2). `nil`, если сервис не подключён
    /// (совместимость с вызовами Фазы 1a/тестами) или в выборке нет рыночных счетов.
    private func marketPriceProvider(for accounts: [Account]) -> MarketPriceProviding? {
        guard let marketPriceService else { return nil }
        let symbols = accounts.compactMap { $0.kind == .marketInvestment ? $0.marketMeta?.symbol : nil }
        guard !symbols.isEmpty else { return nil }
        return marketPriceService.makeSnapshotProvider(symbols: symbols)
    }

    // MARK: - Курс на дату

    private func rate(from: String, to: String, on date: Date) async -> Double? {
        if from.uppercased() == to.uppercased() { return 1 }
        if Calendar.current.isDateInToday(date) {
            if let liveRate = await rateService.getRate(from: from, to: to) {
                return liveRate
            }
            // `getRate` не смог обновиться (офлайн/cold-start/провайдер недоступен) — берём
            // последний прогретый курс тем же способом, что уже используют CurrencyRatesWidget и
            // RateSourcePickerViewModel. Без этого `total(for:)` тихо пропускает счёт через
            // `guard let rate = ... else { continue }`, и виджет активов/обязательств рисует
            // "нет данных", хотя список счетов и общий баланс показывают реальные суммы.
            return rateService.getCachedRate(from: from, to: to)
        }
        // Compatibility core reads share the same persistent cache-first path as legacy reads.
        // Structured Phase 5 reads consume the rows written here through the immutable evidence
        // snapshot, so neither account world can silently diverge on provider availability.
        return await historicalRateStore.getRate(on: date, from: from, to: to).rate
    }
}
