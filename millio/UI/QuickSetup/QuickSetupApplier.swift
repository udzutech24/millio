import Foundation
import SwiftData

@MainActor
struct QuickSetupApplier {
    let modelContext: ModelContext
    let appState: AppState

    func apply(_ selection: QuickSetupSelection) throws {
        applyLanguageAndCurrencies(selection)
        try applyExpenseCategories(selection.selectedExpenseCategoryIDs)
        try applyProducts(selection.products)

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
        let presetsByID = Dictionary(uniqueKeysWithValues: QuickSetupExpenseCategoryPreset.all.map { ($0.id, $0) })
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

    private func applyProducts(_ products: [QuickSetupProductDraft]) throws {
        guard !products.isEmpty else { return }

        let group = try ensureUngroupedGroup()

        for draft in products {
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
                link.group = group
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
                link.group = group
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
                link.group = group
                modelContext.insert(link)

            case .crypto:
                let investment = Investment(
                    name: draft.name,
                    investmentType: .positive,
                    category: .crypto,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: true
                )
                investment.marketSymbol = (draft.symbol ?? draft.name).uppercased()
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = group
                modelContext.insert(link)

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
                link.group = group
                modelContext.insert(link)

            case .ticker:
                let investment = Investment(
                    name: draft.name,
                    investmentType: .positive,
                    category: .stocks,
                    amount: draft.amount,
                    currency: draft.currencyCode,
                    includeInTotal: true,
                    priority: .normal,
                    isFavorite: true
                )
                investment.marketSymbol = (draft.symbol ?? draft.name).uppercased()
                modelContext.insert(investment)
                let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
                link.group = group
                modelContext.insert(link)
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

    private func ensureUngroupedGroup() throws -> FinanceGroup {
        let name = String(localized: "finances.group.ungrouped")
        let descriptor = FetchDescriptor<FinanceGroup>()
        let groups = try modelContext.fetch(descriptor)

        if let existing = groups.first(where: { $0.name == name }) {
            return existing
        }

        let maxOrder = groups.map(\.order).max() ?? -1
        let group = FinanceGroup(
            name: name,
            colorHex: "#3C4B5E",
            order: maxOrder + 1,
            isFavorite: false,
            priority: .low
        )
        modelContext.insert(group)
        return group
    }
}
