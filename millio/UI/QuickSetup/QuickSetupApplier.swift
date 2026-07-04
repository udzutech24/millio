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

    /// Применяет продукты онбординга на НОВОМ ядре event-sourcing (Фаза 6a) — единственная точка
    /// записи `AccountsCoreService`, легаси `Card`/`Credit`/`Investment`/`FinanceAccount` для НОВЫХ
    /// счетов больше не создаются (это был последний живой обходной путь легаси-создания, найденный
    /// аудитом Фазы 6a: онбординг создавал легаси-продукты в обход `AccountsCoreAdditionBridge`,
    /// которым уже пользуется основной экран добавления счёта).
    private func applyProducts(_ products: [QuickSetupProductDraft], groups: [QuickSetupGroupDraft]) throws {
        guard !products.isEmpty else { return }

        let groupsByDraftID = try ensureQuickSetupGroups(groups)
        var ungroupedGroup: FinanceGroup?
        var trackedTickerCount = try activeTrackedTickerCount()
        let locale = AppLocalization.currentAppLocale
        let service = AccountsCoreService(modelContext: modelContext)

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
            let accountGroup = AccountsCoreAdditionBridge.resolveAccountGroup(matching: targetGroup, in: modelContext)

            switch draft.type {
            case .card:
                // Онбординг не собирает банк — всегда `.other`, тот же путь, что и обычная форма
                // добавления карты (см. `AccountsCoreAdditionBridge.cardKind`).
                try service.createAccount(
                    name: draft.name,
                    kind: AccountsCoreAdditionBridge.cardKind(bank: .other),
                    currency: draft.currencyCode,
                    openingBalance: Decimal(draft.amount),
                    group: accountGroup
                )

            case .realEstate:
                try service.createAccount(
                    name: draft.name,
                    kind: .manualAsset,
                    currency: draft.currencyCode,
                    openingBalance: Decimal(draft.amount),
                    group: accountGroup,
                    manualAssetMeta: AccountsCoreAdditionBridge.manualAssetMeta()
                )

            case .debt:
                // Онбординг знает только «я должен» (старая форма тоже не собирала направление
                // отдельно для этого пресета) — знак минус движок C сам не проставляет для `.debt`,
                // это делает вызывающий код (см. `createObligationAccountOnNewCore`).
                try service.createAccount(
                    name: draft.name,
                    kind: .debt,
                    currency: draft.currencyCode,
                    openingBalance: -Decimal(draft.amount),
                    group: accountGroup,
                    debtMeta: AccountsCoreAdditionBridge.debtMeta(direction: .owedByMe)
                )

            case .crypto:
                guard EntitlementPolicy.canAddQuickSetupTrackedProduct(
                    type: .crypto,
                    isPro: appState.isPro,
                    currentTrackedTickers: trackedTickerCount
                ) else {
                    throw QuickSetupApplyError.cryptoRequiresPro(locale: locale)
                }
                try createMarketOrManualAsset(service: service, draft: draft, category: .crypto, group: accountGroup)
                trackedTickerCount += 1

            case .credit:
                let amount = max(0, draft.amount)
                let defaultTermMonths = 24
                let monthlyPayment = max(0, amount / Double(defaultTermMonths))
                // Онбординг не собирает ставку/дату платежа — тот же пробел, что и у основной формы
                // «Кредит» (см. `AccountsCoreAdditionBridge.loanMeta`). openingBalance = ТЕКУЩИЙ остаток
                // (в упрощённой форме онбординга это то же число, что и principal).
                let meta = AccountsCoreAdditionBridge.loanMeta(
                    principal: Decimal(amount),
                    monthlyPayment: monthlyPayment > 0 ? Decimal(monthlyPayment) : nil,
                    paymentDay: nil,
                    termEnd: nil
                )
                try service.createAccount(
                    name: draft.name,
                    kind: .loan,
                    currency: draft.currencyCode,
                    openingBalance: Decimal(amount),
                    group: accountGroup,
                    loanMeta: meta
                )

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
                try createMarketOrManualAsset(service: service, draft: draft, category: .stocks, group: accountGroup)
                trackedTickerCount += 1
            }
        }
    }

    /// Акции/крипта с известным тикером (`marketSnapshot` собран поиском в форме онбординга) —
    /// рыночный счёт нового ядра с сразу примененной покупкой. Без снапшота (защитный путь, поиск
    /// формы этого не допускает, но пробел старого кода не воспроизводим) — ручной актив на сумму
    /// черновика, тот же выбор, что у пресета «Инвестиция» без тикера (Фаза 4).
    private func createMarketOrManualAsset(
        service: AccountsCoreService,
        draft: QuickSetupProductDraft,
        category: InvestmentCategory,
        group: AccountGroup?
    ) throws {
        if let snapshot = draft.marketSnapshot {
            let meta = AccountsCoreAdditionBridge.marketMeta(symbol: snapshot.symbol, category: category)
            let account = try service.createAccount(
                name: draft.name,
                kind: .marketInvestment,
                currency: snapshot.currencyCode,
                openingBalance: 0, // движок E игнорирует opening — баланс считает только buy/sell
                group: group,
                marketMeta: meta
            )
            try service.buy(
                account: account,
                quantity: Decimal(snapshot.quantity),
                unitPrice: Decimal(snapshot.purchaseUnitPrice)
            )
        } else {
            try service.createAccount(
                name: draft.name,
                kind: .manualAsset,
                currency: draft.currencyCode,
                openingBalance: Decimal(draft.amount),
                group: group,
                manualAssetMeta: AccountsCoreAdditionBridge.manualAssetMeta()
            )
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

    /// Счётчик отслеживаемых тикеров нового ядра (Фаза 6a) — на старте онбординга стор всегда
    /// пуст, поэтому практический результат не меняется, но считаем честно на случай повторного
    /// запуска онбординга/будущей миграции существующих данных.
    private func activeTrackedTickerCount() throws -> Int {
        let descriptor = FetchDescriptor<Account>()
        let accounts = try modelContext.fetch(descriptor)
        return accounts.reduce(into: 0) { partialResult, account in
            guard account.archivedAt == nil, account.kind == .marketInvestment else { return }
            partialResult += 1
        }
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
                format: L("monetization.ticker.limit.max_format"),
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
