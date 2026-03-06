import Foundation
import Combine

@MainActor
final class QuickSetupViewModel: ObservableObject {
    @Published var currentStep: QuickSetupStep = .localeAndCurrencies
    @Published var selectedLanguage: Language
    @Published var primaryCurrencyCode: String
    @Published var favoriteCurrencyCodes: [String]
    @Published var selectedExpenseCategoryIDs: Set<String>
    @Published var productTypeForCreation: QuickSetupProductType = .card
    @Published var productNameInput: String = ""
    @Published var productSymbolInput: String = ""
    @Published var productAmountInput: String = ""
    @Published var products: [QuickSetupProductDraft] = []
    @Published var backupPreference: QuickSetupBackupPreference
    @Published private(set) var lastAddDraftError: String?

    private let isProUser: Bool

    static let maxFavoriteCurrencies = 4

    init(appState: AppState) {
        isProUser = appState.isPro
        selectedLanguage = appState.selectedLanguage
        primaryCurrencyCode = appState.primaryCurrencyCode
        favoriteCurrencyCodes = Array(SettingsManager.shared.favoriteCurrencyCodes.prefix(Self.maxFavoriteCurrencies))
        backupPreference = appState.isBackupEnabled ? .cloudBackup : .localOnly

        let storedCategories = SettingsManager.shared.quickSetupExpenseCategoryIDs
        if storedCategories.isEmpty {
            selectedExpenseCategoryIDs = Set(
                [
                    ExpenseCategory.groceries,
                    ExpenseCategory.transport,
                    ExpenseCategory.shopping,
                    ExpenseCategory.cafe,
                    ExpenseCategory.bills,
                    ExpenseCategory.health,
                    ExpenseCategory.education,
                    ExpenseCategory.other
                ].map(\.rawValue) + ["custom:travel", "custom:home"]
            )
        } else {
            selectedExpenseCategoryIDs = Set(storedCategories)
        }
    }

    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(QuickSetupStep.allCases.count)
    }

    var canContinue: Bool {
        switch currentStep {
        case .localeAndCurrencies:
            return !primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .expenseCategories:
            return !selectedExpenseCategoryIDs.isEmpty
        case .products:
            return true
        case .summary:
            return true
        }
    }

    var continueTitle: String {
        switch currentStep {
        case .summary:
            return "Завершить"
        default:
            return "Продолжить"
        }
    }

    func makeSelection() -> QuickSetupSelection {
        let normalizedPrimary = primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedFavorites = SettingsManager
            .normalizeFavoriteCurrencyCodes(favoriteCurrencyCodes, primaryCode: normalizedPrimary)

        return QuickSetupSelection(
            language: selectedLanguage,
            primaryCurrencyCode: normalizedPrimary,
            favoriteCurrencyCodes: Array(normalizedFavorites.prefix(Self.maxFavoriteCurrencies)),
            selectedExpenseCategoryIDs: Array(selectedExpenseCategoryIDs),
            products: products,
            backupPreference: backupPreference
        )
    }

    func goNextStep() {
        guard canContinue else { return }
        if let next = QuickSetupStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func goBackStep() {
        if let prev = QuickSetupStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    func toggleFavoriteCurrency(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        guard code != primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return }

        if let index = favoriteCurrencyCodes.firstIndex(of: code) {
            favoriteCurrencyCodes.remove(at: index)
            return
        }

        guard favoriteCurrencyCodes.count < Self.maxFavoriteCurrencies else { return }
        favoriteCurrencyCodes.insert(code, at: 0)
    }

    func toggleExpenseCategory(raw: String) {
        if selectedExpenseCategoryIDs.contains(raw) {
            selectedExpenseCategoryIDs.remove(raw)
        } else {
            selectedExpenseCategoryIDs.insert(raw)
        }
    }

    func selectProductType(_ type: QuickSetupProductType) {
        productTypeForCreation = type
        if type != .ticker && type != .crypto {
            productSymbolInput = ""
        }
    }

    @discardableResult
    func addDraftProduct() -> Bool {
        lastAddDraftError = nil
        let trimmedName = productNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = productSymbolInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let resolvedName: String
        let symbol: String?

        if productTypeForCreation == .ticker || productTypeForCreation == .crypto {
            if productTypeForCreation == .ticker, trimmedSymbol.isEmpty {
                lastAddDraftError = String(localized: "quick_setup.error.enter_ticker")
                return false
            }
            let currentTickerDraftCount = products.reduce(into: 0) { partialResult, item in
                if item.type == .ticker || item.type == .crypto {
                    partialResult += 1
                }
            }
            if !EntitlementPolicy.canAddTrackedTicker(
                isPro: isProUser,
                currentTrackedTickers: currentTickerDraftCount
            ) {
                lastAddDraftError = String(
                    format: String(localized: "monetization.ticker.limit.short_format"),
                    EntitlementPolicy.freeTrackedTickerLimit
                )
                return false
            }
            let resolvedSymbol = trimmedSymbol.isEmpty ? "BTC" : trimmedSymbol
            resolvedName = trimmedName.isEmpty ? resolvedSymbol : trimmedName
            symbol = resolvedSymbol
        } else {
            guard !trimmedName.isEmpty else {
                lastAddDraftError = String(localized: "quick_setup.error.enter_name")
                return false
            }
            resolvedName = trimmedName
            symbol = nil
        }

        let normalizedCurrency = primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let amount = max(0, Double(productAmountInput.replacingOccurrences(of: ",", with: ".")) ?? 0)

        products.append(
            QuickSetupProductDraft(
                type: productTypeForCreation,
                name: resolvedName,
                amount: amount,
                currencyCode: normalizedCurrency.isEmpty ? SettingsManager.defaultPrimaryCurrencyCode : normalizedCurrency,
                symbol: symbol,
                visualIcon: productTypeForCreation.icon
            )
        )

        productNameInput = ""
        productSymbolInput = ""
        productAmountInput = ""
        return true
    }

    func removeProduct(id: UUID) {
        products.removeAll { $0.id == id }
    }
}
