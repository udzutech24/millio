import Foundation
import SwiftData

@MainActor
struct QuickSetupApplier {
    let modelContext: ModelContext
    let appState: AppState

    func apply(_ selection: QuickSetupSelection) throws {
        applyLanguageAndCurrencies(selection)
        try applyExpenseCategories(selection.selectedExpenseCategoryIDs)
        try applyProducts(selection.products, groups: selection.groups)
        applyBackupPreference(selection.backupPreference)

        SettingsManager.shared.quickSetupExpenseCategoryIDs = selection.selectedExpenseCategoryIDs
        SettingsManager.shared.isQuickSetupCompleted = true
        SettingsManager.shared.isQuickSetupBannerHidden = false
    }

    private func applyLanguageAndCurrencies(_ selection: QuickSetupSelection) {
        appState.selectedLanguage = selection.language
        appState.primaryCurrencyCode = selection.primaryCurrencyCode

        let normalizedFavorites = SettingsManager.normalizeFavoriteCurrencyCodes(
            selection.favoriteCurrencyCodes,
            primaryCode: selection.primaryCurrencyCode
        )
        SettingsManager.shared.favoriteCurrencyCodes = Array(normalizedFavorites.prefix(QuickSetupViewModel.maxFavoriteCurrencies))
    }

    private func applyExpenseCategories(_ selectedIDs: [String]) throws {
        let baseCategories = ExpenseCategory.allCases
        let locale = AppLocalization.currentAppLocale
        let presetsByID = Dictionary(uniqueKeysWithValues: QuickSetupExpenseCategoryPreset.all(for: locale).map { ($0.id, $0) })
        var selectedSystemRaws = Set<String>()
        var selectedCustomPresets: [QuickSetupExpenseCategoryPreset] = []

        for id in selectedIDs {
            guard let preset = presetsByID[id] else { continue }
            if let systemRaw = preset.systemRaw {
                selectedSystemRaws.insert(systemRaw)
            } else {
                selectedCustomPresets.append(preset)
            }
        }

        if selectedSystemRaws.isEmpty {
            selectedSystemRaws.insert(ExpenseCategory.other.rawValue)
        }
        selectedSystemRaws.insert(ExpenseCategory.other.rawValue)

        let descriptor = FetchDescriptor<CashflowSystemCategoryOverride>()
        let allOverrides = try modelContext.fetch(descriptor)
        let expenseOverrides = allOverrides.filter { $0.kind == .expense }

        for category in baseCategories {
            let raw = category.rawValue
            let shouldBeVisible = selectedSystemRaws.contains(raw)
            let existing = expenseOverrides.first { $0.categoryRaw == raw }

            if shouldBeVisible {
                guard let existing else { continue }
                if existing.isHidden {
                    existing.isHidden = false
                    existing.updatedAt = Date()
                }
            } else {
                if let existing {
                    existing.isHidden = true
                    existing.updatedAt = Date()
                } else {
                    let hidden = CashflowSystemCategoryOverride(
                        kind: .expense,
                        categoryRaw: raw,
                        name: category.displayName,
                        icon: category.icon,
                        isHidden: true
                    )
                    modelContext.insert(hidden)
                }
            }
        }

        let customDescriptor = FetchDescriptor<CashflowCustomCategory>()
        let existingCustom = try modelContext.fetch(customDescriptor).filter { $0.kind == .expense }
        let existingByNormalizedName = Dictionary(uniqueKeysWithValues: existingCustom.map { ($0.normalizedName, $0) })

        for preset in selectedCustomPresets {
            let normalized = CashflowCustomCategory.normalize(preset.displayName)
            if existingByNormalizedName[normalized] != nil {
                continue
            }
            let custom = CashflowCustomCategory(
                kind: .expense,
                name: preset.displayName,
                icon: preset.icon
            )
            modelContext.insert(custom)
        }

        try modelContext.save()
    }

    private func applyProducts(_ products: [QuickSetupProductDraft], groups: [QuickSetupGroupDraft]) throws {
        guard !products.isEmpty else { return }

        let groupsByDraftID = try ensureQuickSetupGroups(groups)
        var ungroupedGroup: FinanceGroup?
        var trackedTickerCount = try activeTrackedTickerCount()
        let locale = AppLocalization.currentAppLocale

        for draft in products {
            let targetGroup: FinanceGroup
            if let groupDraftID = draft.groupDraftID,
               let group = groupsByDraftID[groupDraftID] {
                targetGroup = group
            } else {
                let resolved = ungroupedGroup ?? FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
                ungroupedGroup = resolved
                targetGroup = resolved
            }
            switch draft.type {
            case .card:
                let card = Card(
                    name: draft.name,
                    cardNumber: "",
                    bank: .other,
                    cardType: .debit,
                    priority: .normal,
                    currency: draft.currencyCode,
                    balance: draft.amount,
                    includeInTotal: true
                )
                modelContext.insert(card)
                let link = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
                link.group = targetGroup
                modelContext.insert(link)

            case .realEstate:
                let investment = Investment(
                    name: draft.name,
                    investmentType: .positive,
                    category: .house,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: false
                )
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = targetGroup
                modelContext.insert(link)

            case .debt:
                let investment = Investment(
                    name: draft.name,
                    investmentType: .negative,
                    category: .debt,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: false
                )
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = targetGroup
                modelContext.insert(link)

            case .crypto:
                guard EntitlementPolicy.canAddQuickSetupTrackedProduct(
                    type: .crypto,
                    isPro: appState.isPro,
                    currentTrackedTickers: trackedTickerCount
                ) else {
                    throw QuickSetupApplyError.cryptoRequiresPro(locale: locale)
                }
                let investment = Investment(
                    name: draft.symbol ?? draft.name,
                    investmentType: .positive,
                    category: .crypto,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: true
                )
                applyMarketSnapshot(draft.marketSnapshot, to: investment)
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = targetGroup
                modelContext.insert(link)
                trackedTickerCount += 1

            case .credit:
                let amount = max(0, draft.amount)
                let defaultTermMonths = 24
                let monthlyPayment = max(0, amount / Double(defaultTermMonths))
                let credit = Credit(
                    name: draft.name,
                    amount: amount,
                    interestRate: 0,
                    monthlyPayment: monthlyPayment,
                    startDate: Date(),
                    termMonths: defaultTermMonths,
                    currency: draft.currencyCode,
                    bank: .other,
                    creditType: .consumer,
                    includeInTotal: true
                )
                modelContext.insert(credit)
                let link = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
                link.group = targetGroup
                modelContext.insert(link)

            case .ticker:
                guard EntitlementPolicy.canAddQuickSetupTrackedProduct(
                    type: .ticker,
                    isPro: appState.isPro,
                    currentTrackedTickers: trackedTickerCount
                ) else {
                    throw QuickSetupApplyError.quickSetupTrackedTickerLimitReached(
                        limit: EntitlementPolicy.freeQuickSetupTrackedTickerLimit,
                        locale: locale
                    )
                }
                let investment = Investment(
                    name: draft.symbol ?? draft.name,
                    investmentType: .positive,
                    category: .stocks,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: true
                )
                applyMarketSnapshot(draft.marketSnapshot, to: investment)
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = targetGroup
                modelContext.insert(link)
                trackedTickerCount += 1
            }
        }

        try modelContext.save()

        if products.contains(where: { $0.type == .card }) {
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
        }
        if products.contains(where: { $0.type == .credit }) {
            EventBus.shared.publish(FinanceEvent.creditsUpdated)
        }
    }

    private func applyBackupPreference(_ preference: QuickSetupBackupPreference) {
        SettingsManager.shared.isBackupEnabled = preference.isBackupEnabled
        SettingsManager.shared.isAutoBackupEnabled = preference.isBackupEnabled
        appState.isBackupEnabled = preference.isBackupEnabled
        appState.isAutoBackupEnabled = preference.isBackupEnabled

        if !preference.isBackupEnabled {
            appState.isICloudAvailable = false
            appState.lastBackupDate = nil
        }
    }

    private func ensureQuickSetupGroups(_ drafts: [QuickSetupGroupDraft]) throws -> [UUID: FinanceGroup] {
        let descriptor = FetchDescriptor<FinanceGroup>()
        var groups = try modelContext.fetch(descriptor)
        var nextOrder = (groups.map(\.order).max() ?? -1) + 1
        var result: [UUID: FinanceGroup] = [:]

        for draft in drafts {
            let normalizedDraftName = normalizeGroupName(draft.name)
            if let existing = groups.first(where: { normalizeGroupName($0.name) == normalizedDraftName }) {
                result[draft.id] = existing
                continue
            }

            let group = FinanceGroup(
                name: draft.name,
                colorHex: draft.colorHex,
                order: nextOrder,
                isFavorite: false,
                priority: .normal
            )
            nextOrder += 1
            modelContext.insert(group)
            groups.append(group)
            result[draft.id] = group
        }

        return result
    }

    private func activeTrackedTickerCount() throws -> Int {
        let descriptor = FetchDescriptor<Investment>()
        let investments = try modelContext.fetch(descriptor)
        return investments.reduce(into: 0) { partialResult, investment in
            guard investment.archivedAt == nil else { return }
            if investment.category == .stocks || investment.category == .crypto {
                partialResult += 1
            }
        }
    }

    private func applyMarketSnapshot(_ snapshot: QuickSetupProductMarketSnapshot?, to investment: Investment) {
        guard let snapshot else { return }

        if let identity = MarketAssetIdentityResolver.resolve(
            category: investment.category,
            symbol: snapshot.symbol,
            exchange: snapshot.exchange,
            instrumentName: investment.name,
            micCode: nil,
            instrumentType: investment.category == .crypto ? "Cryptocurrency" : "Common Stock",
            currency: snapshot.currencyCode,
            country: nil,
            providerName: snapshot.providerRaw
        ) {
            investment.assetID = identity.assetID
            AssetCatalogStore(modelContext: modelContext).syncIfSupported(identity: identity)
        }

        investment.marketSymbol = snapshot.symbol
        investment.marketExchange = snapshot.exchange
        investment.marketCurrency = snapshot.currencyCode
        investment.marketQuantity = snapshot.quantity
        investment.averagePurchaseUnitPrice = snapshot.purchaseUnitPrice
        investment.totalPurchaseCost = snapshot.purchaseUnitPrice * snapshot.quantity
        investment.lastKnownUnitPrice = snapshot.currentUnitPrice ?? snapshot.purchaseUnitPrice
        investment.lastKnownPriceUpdatedAt = snapshot.priceUpdatedAt
        investment.marketProviderRaw = snapshot.providerRaw
        investment.recalculateAmountFromPosition()
    }

    private func normalizeGroupName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum QuickSetupApplyError: LocalizedError {
    case trackedTickerLimitReached(limit: Int)
    case quickSetupTrackedTickerLimitReached(limit: Int, locale: Locale)
    case cryptoRequiresPro(locale: Locale)

    var errorDescription: String? {
        switch self {
        case .trackedTickerLimitReached(let limit):
            return String(
                format: String(localized: "monetization.ticker.limit.max_format"),
                limit
            )
        case .quickSetupTrackedTickerLimitReached(let limit, let locale):
            return QuickSetupLocalization.format(
                "quick_setup.error.tracked_ticker_limit_format",
                locale: locale,
                limit
            )
        case .cryptoRequiresPro(let locale):
            return QuickSetupLocalization.tr("quick_setup.error.crypto_requires_pro", locale: locale)
        }
    }
}
