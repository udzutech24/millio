import SwiftUI
import SwiftData
import PhotosUI

/// Лимиты Free/PRO формы создания: счётчики продуктов и paywall-сообщения.
extension FinanceAddAccountView {
    // [Ф5c.7 Gate C] Не `private` — минимально доступная точка для characterization-тестов
    // (SwiftUI View как обычный struct, `@testable import` не видит `private`). Поведение не менялось.
    //
    // Дедуп twin-пар (легаси↔core) «по построению»: конвертированный легаси архивируется
    // (`archivedAt` выставлен мигратором) и поэтому исключён из `available*` (эти массивы уже не
    // включают архивные — см. `FinanceAccountService.loadAccounts`); core-двойник учтён через
    // `state.coreAccounts`, который заполняется `participates(on:)`-фильтром (`archivedAt`+
    // `includeInTotal`, `FinanceViewModel.loadCoreEntities`) — тот же принцип исключения архива,
    // что и у `available*`. Одна и та же учётная единица не может одновременно быть в обоих
    // множествах — сложение без пересечения.
    var currentTrackedTickerCount: Int {
        let legacyCount = viewModel.state.availableInvestments.reduce(into: 0) { partialResult, investment in
            if investment.category.isMarketTickerCategory {
                partialResult += 1
            }
        }
        // Паритет с легаси: считаются ТОЛЬКО акции/крипта (`isMarketTickerCategory`), не
        // облигации/металлы — те же 2 из 4 `MarketAssetClass`, что и `InvestmentCategory`.
        let coreCount = viewModel.state.accounts.filter { account in
            guard account.kind == .marketInvestment, let assetClass = account.marketMeta?.assetClass else {
                return false
            }
            return assetClass == .stock || assetClass == .crypto
        }.count
        return legacyCount + coreCount
    }

    var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
        + viewModel.state.accounts.count
    }

    var isCreatingNewTrackedTicker: Bool {
        guard selectedAccountType == .investment else { return false }
        guard selectedInvestmentCategory.isMarketTickerCategory else { return false }
        return true
    }

    func validateEntitlementsForSave() -> Bool {
        let canAddProduct = EntitlementPolicy.canAddFinanceProduct(
            isPro: appState.isPro,
            currentProducts: currentFinanceProductCount
        )
        guard canAddProduct else {
            paywallMessage = LocalizedTextResolver { locale in
                String(
                    format: AppLocalization.string("monetization.finance.products.limit.hard_format", locale: locale),
                    locale: locale,
                    EntitlementPolicy.freeFinanceProductLimit
                )
            }
            showPaywallAlert = true
            return false
        }

        if selectedAccountType == .investment,
           selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto,
           !canUseMarketCategory(selectedInvestmentCategory) {
            paywallMessage = marketCategoryPaywallMessage(for: selectedInvestmentCategory)
            showPaywallAlert = true
            return false
        }

        guard isCreatingNewTrackedTicker else { return true }

        let canAdd = EntitlementPolicy.canAddTrackedTicker(
            isPro: appState.isPro,
            currentTrackedTickers: currentTrackedTickerCount
        )
        guard canAdd else {
            paywallMessage = LocalizedTextResolver { locale in
                String(
                    format: AppLocalization.string("monetization.ticker.limit.hard_format", locale: locale),
                    locale: locale,
                    EntitlementPolicy.freeTrackedTickerLimit
                )
            }
            showPaywallAlert = true
            return false
        }
        return true
    }

    func canUseMarketCategory(_ category: InvestmentCategory) -> Bool {
        switch category {
        case .stocks:
            return EntitlementPolicy.canUseFinanceStocks(isPro: appState.isPro)
        case .crypto:
            return EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        default:
            return true
        }
    }

    func marketCategoryPaywallMessage(for category: InvestmentCategory) -> LocalizedTextResolver {
        switch category {
        case .stocks:
            return .key("monetization.finance.stocks.pro_only")
        case .crypto:
            return .key("monetization.finance.crypto.pro_only")
        default:
            return .key("monetization.finance.market_assets.pro_only")
        }
    }

    func handleProductOptionSelection(_ option: FinanceAddAccountProductOption) {
        let selection = option.selection(locale: localizationLocale)

        if selection.investmentCategory.isMarketTickerCategory,
           !canUseMarketCategory(selection.investmentCategory) {
            paywallMessage = marketCategoryPaywallMessage(for: selection.investmentCategory)
            showPaywallAlert = true
            return
        }

        if option != selectedProductOption {
            invalidateStatementDraft()
        }
        selectedAccountType = selection.accountType
        selectedInvestmentCategory = selection.investmentCategory
        selectedInvestmentPreset = selection.investmentPreset
        selectedProductTypeTitle = selection.title
        hasConfirmedProductSelection = true
        showProductPicker = false
        focusNameFieldIfNeeded()
    }
}
