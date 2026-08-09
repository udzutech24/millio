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

        // `applyProducts` может создавать core-счета (`AccountsCoreAdditionBridge`), но сам сервис
        // не публикует события — экран (онбординг ИЛИ повторный запуск из настроек) не держит
        // ссылку на `FinanceViewModel`. Тот же канал, что `AccountDetailView.archiveAccount()`.
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)
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
        // Defense-in-depth: два CashflowCustomCategory с одинаковым normalizedName (например, после
        // импорта старого бэкапа с дублями — см. DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch)
        // валят Dictionary(uniqueKeysWithValues:) с Fatal error: Duplicate values for key прямо на
        // онбординге. uniquingKeysWith берёт запись с более поздним updatedAt — краш недопустим здесь.
        let existingByNormalizedName = Dictionary(
            existingCustom.map { ($0.normalizedName, $0) },
            uniquingKeysWith: { current, candidate in candidate.updatedAt >= current.updatedAt ? candidate : current }
        )

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
    /// записи `AccountProductGraphBuilder`, легаси `Card`/`Credit`/`Investment`/`FinanceAccount` для НОВЫХ
    /// счетов больше не создаются (это был последний живой обходной путь легаси-создания, найденный
    /// аудитом Фазы 6a: онбординг создавал легаси-продукты в обход `AccountsCoreAdditionBridge`,
    /// которым уже пользуется основной экран добавления счёта).
    private func applyProducts(_ products: [QuickSetupProductDraft], groups: [QuickSetupGroupDraft]) throws {
        guard !products.isEmpty else { return }

        // The whole onboarding product batch commits in one disposable context. A later invalid
        // draft or failed save cannot leave earlier accounts/buys in the caller's context.
        let transactionContext = ModelContext(modelContext.container)
        transactionContext.autosaveEnabled = false
        do {
            let groupsByDraftID = try ensureQuickSetupGroups(groups, in: transactionContext)
            var ungroupedGroup: FinanceGroup?
            var trackedTickerCount = try activeTrackedTickerCount(in: transactionContext)
            let locale = AppLocalization.currentAppLocale

            for draft in products {
                let targetGroup: FinanceGroup
                if let groupDraftID = draft.groupDraftID,
                   let group = groupsByDraftID[groupDraftID] {
                    targetGroup = group
                } else {
                    let resolved = ungroupedGroup
                        ?? FinanceSystemGroups.ensureUngroupedGroup(in: transactionContext)
                    ungroupedGroup = resolved
                    targetGroup = resolved
                }
                let accountGroup = AccountsCoreAdditionBridge.resolveAccountGroup(
                    matching: targetGroup,
                    in: transactionContext
                )
                let command = try makeProductCommand(
                    for: draft,
                    groupID: accountGroup?.id,
                    trackedTickerCount: &trackedTickerCount,
                    locale: locale
                )
                _ = try AccountProductGraphBuilder.build(command, in: transactionContext)
            }
            try transactionContext.save()
        } catch {
            transactionContext.rollback()
            throw error
        }
    }

    private func makeProductCommand(
        for draft: QuickSetupProductDraft,
        groupID: UUID?,
        trackedTickerCount: inout Int,
        locale: Locale
    ) throws -> CreateProductCommand {
        switch draft.type {
        case .card:
            return CreateProductCommand(
                productType: .debitCard, name: draft.name, currency: draft.currencyCode,
                openingBalance: Decimal(draft.amount), groupID: groupID
            )
        case .realEstate:
            return CreateProductCommand(
                productType: .realEstate, name: draft.name, currency: draft.currencyCode,
                openingBalance: Decimal(draft.amount), groupID: groupID,
                metadata: .init(manualAsset: AccountsCoreAdditionBridge.manualAssetMeta())
            )
        case .debt:
            return CreateProductCommand(
                productType: .payable, name: draft.name, currency: draft.currencyCode,
                openingBalance: -Decimal(draft.amount), groupID: groupID,
                metadata: .init(debt: AccountsCoreAdditionBridge.debtMeta(direction: .owedByMe))
            )
        case .credit:
            let amount = max(0, draft.amount)
            let monthlyPayment = amount / 24
            return CreateProductCommand(
                productType: .loan, name: draft.name, currency: draft.currencyCode,
                openingBalance: Decimal(amount), groupID: groupID,
                metadata: .init(loan: AccountsCoreAdditionBridge.loanMeta(
                    principal: Decimal(amount),
                    monthlyPayment: monthlyPayment > 0 ? Decimal(monthlyPayment) : nil,
                    paymentDay: nil,
                    termEnd: nil
                ))
            )
        case .crypto, .ticker:
            if draft.type == .crypto {
                guard EntitlementPolicy.canAddQuickSetupTrackedProduct(
                    type: .crypto, isPro: appState.isPro,
                    currentTrackedTickers: trackedTickerCount
                ) else { throw QuickSetupApplyError.cryptoRequiresPro(locale: locale) }
            } else {
                guard EntitlementPolicy.canAddQuickSetupTrackedProduct(
                    type: .ticker, isPro: appState.isPro,
                    currentTrackedTickers: trackedTickerCount
                ) else {
                    throw QuickSetupApplyError.quickSetupTrackedTickerLimitReached(
                        limit: EntitlementPolicy.freeQuickSetupTrackedTickerLimit,
                        locale: locale
                    )
                }
            }
            guard let snapshot = draft.marketSnapshot else {
                throw QuickSetupApplyError.missingMarketEvidence(locale: locale)
            }
            trackedTickerCount += 1
            let category: InvestmentCategory = draft.type == .crypto ? .crypto : .stocks
            return CreateProductCommand(
                productType: draft.type == .crypto ? .marketCrypto : .marketStock,
                name: draft.name,
                currency: snapshot.currencyCode,
                openingBalance: 0,
                groupID: groupID,
                metadata: .init(market: AccountsCoreAdditionBridge.marketMeta(
                    symbol: snapshot.symbol,
                    category: category
                )),
                initialMarketPurchase: .init(
                    quantity: Decimal(snapshot.quantity),
                    unitPrice: Decimal(snapshot.purchaseUnitPrice)
                )
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

    private func ensureQuickSetupGroups(
        _ drafts: [QuickSetupGroupDraft],
        in context: ModelContext
    ) throws -> [UUID: FinanceGroup] {
        let descriptor = FetchDescriptor<FinanceGroup>()
        var groups = try context.fetch(descriptor)
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
            context.insert(group)
            groups.append(group)
            result[draft.id] = group
        }

        return result
    }

    /// Счётчик отслеживаемых тикеров нового ядра (Фаза 6a) — на старте онбординга стор всегда
    /// пуст, поэтому практический результат не меняется, но считаем честно на случай повторного
    /// запуска онбординга/будущей миграции существующих данных.
    private func activeTrackedTickerCount(in context: ModelContext) throws -> Int {
        let descriptor = FetchDescriptor<Account>()
        let accounts = try context.fetch(descriptor)
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
    case missingMarketEvidence(locale: Locale)

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
        case .missingMarketEvidence(let locale):
            return QuickSetupLocalization.tr("quick_setup.error.enter_ticker", locale: locale)
        }
    }
}
