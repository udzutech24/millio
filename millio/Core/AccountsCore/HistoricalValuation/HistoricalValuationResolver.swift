import Foundation

enum HistoricalValuationContributionOrigin: String, Codable, CaseIterable, Hashable, Sendable {
    case core
    case compatibility
}

enum HistoricalValuationContributionInput: Hashable, Sendable {
    /// The caller owns replay and sign. The resolver owns only valuation evidence and conversion.
    case native(
        value: Decimal,
        currency: String,
        fxPolicy: HistoricalValuationCalendarPolicy
    )
    case market(
        quantity: Decimal,
        instrument: HistoricalMarketInstrument,
        quoteCurrency: String,
        pricePolicy: HistoricalValuationCalendarPolicy,
        fxPolicy: HistoricalValuationCalendarPolicy
    )
}

struct HistoricalValuationContributionRequest: Hashable, Sendable {
    let id: String
    let origin: HistoricalValuationContributionOrigin
    let valuationDate: Date
    let input: HistoricalValuationContributionInput
}

struct HistoricalValuationDependencyResolution: Codable, Hashable, Sendable {
    let dimension: HistoricalValuationMissingDimension
    let requestedDayKey: String
    let kind: HistoricalValuationResolutionKind
    let value: Decimal?
    let provenance: HistoricalValuationResolutionProvenance?
    let reasonCode: String?
}

struct HistoricalValuationContributionResolution: Sendable {
    let requestID: String
    let origin: HistoricalValuationContributionOrigin
    let value: Decimal?
    let quality: HistoricalValuationQuality
    let dependencies: [HistoricalValuationDependencyResolution]
    let unresolvedDimensions: Set<HistoricalValuationMissingDimension>
}

/// Pure, shared valuation policy for core and compatibility contributions. It receives already
/// replayed/signed native inputs, so it neither duplicates `AccountBalanceEngine` nor produces a
/// portfolio series. Evidence I/O is batched once per dependency kind before any account resolves.
/// The ordered result has exactly one element per request; opaque IDs are diagnostic metadata and
/// are not dictionary keys, because core/compatibility inputs may legitimately share an ID.
/// Phase 3 owns persisted-close immutability: before publication, recovered provider evidence may
/// produce a new result/input revision; this stateless resolver never pretends otherwise.
actor HistoricalValuationResolver {
    func resolve(
        requests: [HistoricalValuationContributionRequest],
        displayCurrency: String,
        timeContext: HistoricalValuationTimeContext,
        now: Date,
        evidenceProvider: any HistoricalValuationEvidenceProviding
    ) async -> [HistoricalValuationContributionResolution] {
        let display = HistoricalValuationCurrencyCode.normalized(displayCurrency)
        var fxPolicies: [HistoricalFXDependencyKey: HistoricalValuationCalendarPolicy] = [:]
        var marketPolicies: [HistoricalMarketDependencyKey: HistoricalValuationCalendarPolicy] = [:]
        var conflictingFX: Set<HistoricalFXDependencyKey> = []
        var conflictingMarket: Set<HistoricalMarketDependencyKey> = []

        for request in requests {
            let dayKey = timeContext.dayKey(for: request.valuationDate)
            switch request.input {
            case .native(let value, let currency, let policy):
                let source = HistoricalValuationCurrencyCode.normalized(currency)
                guard isValid(value), value != 0,
                      HistoricalValuationCurrencyCode.isSupported(source),
                      HistoricalValuationCurrencyCode.isSupported(display),
                      source != display else {
                    continue
                }
                register(
                    policy,
                    for: HistoricalFXDependencyKey(dayKey: dayKey, pair: .init(base: source, quote: display)),
                    in: &fxPolicies,
                    conflicts: &conflictingFX
                )

            case .market(let quantity, let instrument, let quoteCurrency, let pricePolicy, let fxPolicy):
                guard isValid(quantity), quantity != 0, !instrument.symbol.isEmpty else { continue }
                register(
                    pricePolicy,
                    for: HistoricalMarketDependencyKey(dayKey: dayKey, instrument: instrument),
                    in: &marketPolicies,
                    conflicts: &conflictingMarket
                )
                let quote = HistoricalValuationCurrencyCode.normalized(quoteCurrency)
                guard HistoricalValuationCurrencyCode.isSupported(quote),
                      HistoricalValuationCurrencyCode.isSupported(display),
                      quote != display else { continue }
                register(
                    fxPolicy,
                    for: HistoricalFXDependencyKey(dayKey: dayKey, pair: .init(base: quote, quote: display)),
                    in: &fxPolicies,
                    conflicts: &conflictingFX
                )
            }
        }

        let fxKeys = Set(fxPolicies.keys).subtracting(conflictingFX)
        let marketKeys = Set(marketPolicies.keys).subtracting(conflictingMarket)
        let fxLoad = await loadFX(fxKeys, from: evidenceProvider)
        let marketLoad = await loadMarket(marketKeys, from: evidenceProvider)

        return requests.map { request in
            resolveContribution(
                request,
                displayCurrency: display,
                timeContext: timeContext,
                now: now,
                fxPolicies: fxPolicies,
                marketPolicies: marketPolicies,
                conflictingFX: conflictingFX,
                conflictingMarket: conflictingMarket,
                fxLoad: fxLoad,
                marketLoad: marketLoad
            )
        }
    }

    private func resolveContribution(
        _ request: HistoricalValuationContributionRequest,
        displayCurrency: String,
        timeContext: HistoricalValuationTimeContext,
        now: Date,
        fxPolicies: [HistoricalFXDependencyKey: HistoricalValuationCalendarPolicy],
        marketPolicies: [HistoricalMarketDependencyKey: HistoricalValuationCalendarPolicy],
        conflictingFX: Set<HistoricalFXDependencyKey>,
        conflictingMarket: Set<HistoricalMarketDependencyKey>,
        fxLoad: EvidenceLoad<HistoricalFXDependencyKey>,
        marketLoad: EvidenceLoad<HistoricalMarketDependencyKey>
    ) -> HistoricalValuationContributionResolution {
        let dayKey = timeContext.dayKey(for: request.valuationDate)
        let isOpenDay = timeContext.isOpenDay(request.valuationDate, now: now)
        var dependencies: [HistoricalValuationDependencyResolution] = []
        var nativeValue: Decimal

        switch request.input {
        case .native(let value, let rawCurrency, _):
            guard isValid(value) else {
                return unavailableContribution(
                    request,
                    dimension: .nativeBalance,
                    dayKey: dayKey,
                    reason: "invalid_native_value"
                )
            }
            nativeValue = value
            if value == 0 {
                return resolvedContribution(request, value: 0, dependencies: [])
            }
            guard HistoricalValuationCurrencyCode.isSupported(displayCurrency) else {
                return unavailableContribution(request, dimension: .fxRate, dayKey: dayKey, reason: "invalid_display_currency")
            }
            let currency = HistoricalValuationCurrencyCode.normalized(rawCurrency)
            guard HistoricalValuationCurrencyCode.isSupported(currency) else {
                return unavailableContribution(request, dimension: .fxRate, dayKey: dayKey, reason: "invalid_account_currency")
            }
            let fx = resolveFX(
                dayKey: dayKey,
                base: currency,
                quote: displayCurrency,
                isOpenDay: isOpenDay,
                timeContext: timeContext,
                now: now,
                policies: fxPolicies,
                conflicts: conflictingFX,
                load: fxLoad
            )
            dependencies.append(fx)

        case .market(let quantity, let instrument, let rawQuoteCurrency, _, _):
            guard isValid(quantity) else {
                return unavailableContribution(request, dimension: .nativeBalance, dayKey: dayKey, reason: "invalid_market_quantity")
            }
            if quantity == 0 {
                return resolvedContribution(request, value: 0, dependencies: [])
            }
            guard !instrument.symbol.isEmpty else {
                return unavailableContribution(request, dimension: .marketPrice, dayKey: dayKey, reason: "invalid_market_instrument")
            }
            nativeValue = quantity
            let marketKey = HistoricalMarketDependencyKey(dayKey: dayKey, instrument: instrument)
            let price = resolveEvidence(
                dimension: .marketPrice,
                dayKey: dayKey,
                isOpenDay: isOpenDay,
                timeContext: timeContext,
                now: now,
                policy: marketPolicies[marketKey],
                hasConflict: conflictingMarket.contains(marketKey),
                bundle: marketLoad.values[marketKey],
                fetchFailure: marketLoad.failureReason
            )
            dependencies.append(price)

            guard HistoricalValuationCurrencyCode.isSupported(displayCurrency) else {
                dependencies.append(unavailable(.fxRate, dayKey, "invalid_display_currency"))
                return resolvedContribution(request, value: nil, dependencies: dependencies)
            }
            let quoteCurrency = HistoricalValuationCurrencyCode.normalized(rawQuoteCurrency)
            guard HistoricalValuationCurrencyCode.isSupported(quoteCurrency) else {
                dependencies.append(unavailable(.fxRate, dayKey, "invalid_quote_currency"))
                return resolvedContribution(request, value: nil, dependencies: dependencies)
            }
            let fx = resolveFX(
                dayKey: dayKey,
                base: quoteCurrency,
                quote: displayCurrency,
                isOpenDay: isOpenDay,
                timeContext: timeContext,
                now: now,
                policies: fxPolicies,
                conflicts: conflictingFX,
                load: fxLoad
            )
            dependencies.append(fx)
        }

        let allResolved = dependencies.allSatisfy { $0.value != nil && $0.kind != .unavailable }
        guard allResolved else {
            return resolvedContribution(request, value: nil, dependencies: dependencies)
        }
        let factors = [nativeValue] + dependencies.compactMap(\.value)
        guard let value = checkedProduct(factors) else {
            dependencies.append(unavailable(.nativeBalance, dayKey, "valuation_overflow"))
            return resolvedContribution(request, value: nil, dependencies: dependencies)
        }
        return resolvedContribution(
            request,
            value: value,
            dependencies: dependencies
        )
    }

    private func resolveFX(
        dayKey: String,
        base: String,
        quote: String,
        isOpenDay: Bool,
        timeContext: HistoricalValuationTimeContext,
        now: Date,
        policies: [HistoricalFXDependencyKey: HistoricalValuationCalendarPolicy],
        conflicts: Set<HistoricalFXDependencyKey>,
        load: EvidenceLoad<HistoricalFXDependencyKey>
    ) -> HistoricalValuationDependencyResolution {
        if base == quote {
            return .init(
                dimension: .fxRate,
                requestedDayKey: dayKey,
                kind: .nativeParity,
                value: 1,
                provenance: nil,
                reasonCode: nil
            )
        }
        let key = HistoricalFXDependencyKey(dayKey: dayKey, pair: .init(base: base, quote: quote))
        return resolveEvidence(
            dimension: .fxRate,
            dayKey: dayKey,
            isOpenDay: isOpenDay,
            timeContext: timeContext,
            now: now,
            policy: policies[key],
            hasConflict: conflicts.contains(key),
            bundle: load.values[key],
            fetchFailure: load.failureReason
        )
    }

    private func resolveEvidence(
        dimension: HistoricalValuationMissingDimension,
        dayKey: String,
        isOpenDay: Bool,
        timeContext: HistoricalValuationTimeContext,
        now: Date,
        policy: HistoricalValuationCalendarPolicy?,
        hasConflict: Bool,
        bundle: HistoricalValuationEvidenceBundle?,
        fetchFailure: String?
    ) -> HistoricalValuationDependencyResolution {
        guard !hasConflict else { return unavailable(dimension, dayKey, "conflicting_calendar_policy") }
        guard let policy else { return unavailable(dimension, dayKey, "calendar_policy_missing") }
        guard !policy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return unavailable(dimension, dayKey, "invalid_calendar_policy")
        }
        if let fetchFailure { return unavailable(dimension, dayKey, fetchFailure) }
        let bundle = bundle ?? .init()

        if !bundle.exact.isEmpty {
            guard let record = preferred(bundle.exact.filter { $0.dayKey == dayKey }) else {
                return unavailable(dimension, dayKey, "invalid_exact_day")
            }
            return validResolution(record, dimension: dimension, requestedDayKey: dayKey, kind: .exact, policy: policy)
        }

        if !bundle.previousClose.isEmpty {
            let eligible = bundle.previousClose.filter { policy.allowsPreviousClose(from: $0.dayKey, for: dayKey) }
            if let record = eligible.sorted(by: evidenceOrder).last {
                return validResolution(
                    record,
                    dimension: dimension,
                    requestedDayKey: dayKey,
                    kind: .previousClose,
                    policy: policy
                )
            }
        }

        if !isOpenDay, !bundle.frozenClose.isEmpty {
            let validDay = bundle.frozenClose.filter {
                $0.dayKey == dayKey && timeContext.dayKey(for: $0.observedAt) == dayKey
            }
            guard let record = preferred(validDay) else {
                return unavailable(dimension, dayKey, "invalid_frozen_close_day")
            }
            return validResolution(
                record,
                dimension: dimension,
                requestedDayKey: dayKey,
                kind: .frozenClose,
                policy: policy
            )
        }

        if !bundle.currentEstimate.isEmpty {
            guard isOpenDay else {
                return unavailable(dimension, dayKey, "current_estimate_closed_day")
            }
            guard let record = preferred(bundle.currentEstimate.filter {
                $0.dayKey == dayKey &&
                    timeContext.dayKey(for: $0.observedAt) == dayKey &&
                    $0.observedAt <= now
            }) else {
                return unavailable(dimension, dayKey, "invalid_current_estimate_day")
            }
            return validResolution(
                record,
                dimension: dimension,
                requestedDayKey: dayKey,
                kind: .currentEstimate,
                policy: policy
            )
        }

        if !bundle.previousClose.isEmpty {
            return unavailable(dimension, dayKey, "previous_close_ineligible")
        }
        return unavailable(dimension, dayKey, "evidence_unavailable")
    }

    private func validResolution(
        _ record: HistoricalValuationEvidenceRecord,
        dimension: HistoricalValuationMissingDimension,
        requestedDayKey: String,
        kind: HistoricalValuationResolutionKind,
        policy: HistoricalValuationCalendarPolicy
    ) -> HistoricalValuationDependencyResolution {
        guard !record.recordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return unavailable(dimension, requestedDayKey, "invalid_evidence_identity")
        }
        guard isValid(record.value), record.value > 0 else {
            let reason: String
            switch kind {
            case .exact: reason = "invalid_exact_value"
            case .previousClose: reason = "invalid_previous_close_value"
            case .frozenClose: reason = "invalid_frozen_close_value"
            case .currentEstimate: reason = "invalid_current_estimate_value"
            case .nativeParity, .unavailable: reason = "invalid_evidence_value"
            }
            return unavailable(dimension, requestedDayKey, reason)
        }
        return .init(
            dimension: dimension,
            requestedDayKey: requestedDayKey,
            kind: kind,
            value: record.value,
            provenance: .init(
                sourceID: record.sourceID,
                recordID: record.recordID,
                evidenceDayKey: record.dayKey,
                observedAt: record.observedAt,
                calendarPolicyID: policy.id
            ),
            reasonCode: nil
        )
    }

    private func resolvedContribution(
        _ request: HistoricalValuationContributionRequest,
        value: Decimal?,
        dependencies: [HistoricalValuationDependencyResolution]
    ) -> HistoricalValuationContributionResolution {
        let unresolved = Set(dependencies.filter { $0.value == nil }.map(\.dimension))
        return .init(
            requestID: request.id,
            origin: request.origin,
            value: unresolved.isEmpty ? value : nil,
            quality: quality(for: dependencies),
            dependencies: dependencies,
            unresolvedDimensions: unresolved
        )
    }

    private func unavailableContribution(
        _ request: HistoricalValuationContributionRequest,
        dimension: HistoricalValuationMissingDimension,
        dayKey: String,
        reason: String
    ) -> HistoricalValuationContributionResolution {
        resolvedContribution(
            request,
            value: nil,
            dependencies: [unavailable(dimension, dayKey, reason)]
        )
    }

    private func quality(
        for dependencies: [HistoricalValuationDependencyResolution]
    ) -> HistoricalValuationQuality {
        if dependencies.contains(where: { $0.kind == .unavailable }) { return .unavailable }
        var qualities: Set<HistoricalValuationQuality> = []
        for dependency in dependencies {
            switch dependency.kind {
            case .nativeParity, .exact:
                qualities.insert(.exact)
            case .previousClose, .frozenClose:
                qualities.insert(.fallback)
            case .currentEstimate:
                qualities.insert(.estimated)
            case .unavailable:
                qualities.insert(.unavailable)
            }
        }
        if qualities.isEmpty { return .exact }
        return qualities.count == 1 ? qualities.first! : .mixed
    }

    private func unavailable(
        _ dimension: HistoricalValuationMissingDimension,
        _ dayKey: String,
        _ reason: String
    ) -> HistoricalValuationDependencyResolution {
        .init(
            dimension: dimension,
            requestedDayKey: dayKey,
            kind: .unavailable,
            value: nil,
            provenance: nil,
            reasonCode: reason
        )
    }

    private func register<Key: Hashable>(
        _ policy: HistoricalValuationCalendarPolicy,
        for key: Key,
        in policies: inout [Key: HistoricalValuationCalendarPolicy],
        conflicts: inout Set<Key>
    ) {
        if let existing = policies[key], existing != policy {
            conflicts.insert(key)
        } else {
            policies[key] = policy
        }
    }

    private func preferred(
        _ records: [HistoricalValuationEvidenceRecord]
    ) -> HistoricalValuationEvidenceRecord? {
        records.sorted(by: evidenceOrder).last
    }

    private func evidenceOrder(
        _ lhs: HistoricalValuationEvidenceRecord,
        _ rhs: HistoricalValuationEvidenceRecord
    ) -> Bool {
        if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
        if lhs.observedAt != rhs.observedAt { return lhs.observedAt < rhs.observedAt }
        return lhs.recordID < rhs.recordID
    }

    private func isValid(_ value: Decimal) -> Bool {
        !value.isNaN
    }

    private func checkedProduct(_ factors: [Decimal]) -> Decimal? {
        var product: Decimal = 1
        for factor in factors {
            product *= factor
            guard isValid(product) else { return nil }
        }
        return product
    }

    private struct EvidenceLoad<Key: Hashable & Sendable>: Sendable {
        let values: [Key: HistoricalValuationEvidenceBundle]
        let failureReason: String?
    }

    private func loadFX(
        _ dependencies: Set<HistoricalFXDependencyKey>,
        from provider: any HistoricalValuationEvidenceProviding
    ) async -> EvidenceLoad<HistoricalFXDependencyKey> {
        guard !dependencies.isEmpty else { return .init(values: [:], failureReason: nil) }
        do {
            return .init(values: try await provider.fetchFXEvidence(for: dependencies), failureReason: nil)
        } catch {
            return .init(values: [:], failureReason: "fx_evidence_fetch_failed")
        }
    }

    private func loadMarket(
        _ dependencies: Set<HistoricalMarketDependencyKey>,
        from provider: any HistoricalValuationEvidenceProviding
    ) async -> EvidenceLoad<HistoricalMarketDependencyKey> {
        guard !dependencies.isEmpty else { return .init(values: [:], failureReason: nil) }
        do {
            return .init(values: try await provider.fetchMarketEvidence(for: dependencies), failureReason: nil)
        } catch {
            return .init(values: [:], failureReason: "market_evidence_fetch_failed")
        }
    }
}

enum HistoricalValuationEvidenceRevision {
    static func digest(_ results: [HistoricalValuationContributionResolution]) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        let tokens = results.flatMap { result in
            result.dependencies.map { dependency in
                [
                    result.requestID,
                    result.origin.rawValue,
                    dependency.dimension.rawValue,
                    dependency.requestedDayKey,
                    dependency.kind.rawValue,
                    dependency.provenance?.sourceID ?? "<none>",
                    dependency.provenance?.recordID ?? "<none>",
                    dependency.provenance?.evidenceDayKey ?? "<none>",
                    dependency.provenance.map {
                        String($0.observedAt.timeIntervalSinceReferenceDate.bitPattern)
                    } ?? "<none>",
                    dependency.provenance?.calendarPolicyID ?? "<none>",
                    dependency.reasonCode ?? "<none>",
                    dependency.value.map(String.init(describing:)) ?? "<nil>"
                ].joined(separator: "|")
            }
        }.sorted()
        for token in tokens {
            for byte in token.utf8 {
                value ^= UInt64(byte)
                value &*= 1_099_511_628_211
            }
            value ^= 0xFF
            value &*= 1_099_511_628_211
        }
        return value
    }
}
