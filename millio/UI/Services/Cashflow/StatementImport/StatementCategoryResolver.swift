import Foundation

protocol CashflowStatementMerchantCategoryStore: AnyObject {
    func categoryRaw(forStableMerchantKey key: String) -> String?
    func remember(categoryRaw: String, forStableMerchantKey key: String)
}

final class CashflowStatementMerchantCategoryPrefsAdapter: CashflowStatementMerchantCategoryStore {
    /// Statement learning schema. Increment when stable-key semantics change.
    static let schemaVersion = 1
    private let prefs: CashflowBulkExpenseMerchantCategoryPrefs

    init(prefs: CashflowBulkExpenseMerchantCategoryPrefs = .init()) { self.prefs = prefs }

    func categoryRaw(forStableMerchantKey key: String) -> String? {
        prefs.categoryRaw(for: key)
    }

    func remember(categoryRaw: String, forStableMerchantKey key: String) {
        prefs.remember(categoryRaw: categoryRaw, for: key)
    }
}

enum CashflowStatementMerchantKey {
    static func sanitize(_ merchant: String?) -> String? {
        guard let merchant else { return nil }
        let normalized = CashflowBulkExpenseMerchantCategoryPrefs.normalizeMerchantTitle(merchant)
        guard normalized.count >= 3, normalized.count <= 80,
              !merchant.contains("@"),
              merchant.range(of: #"\d{6,}"#, options: .regularExpression) == nil else { return nil }
        return normalized
    }
}

struct CashflowStatementCategoryCatalog {
    private let income: Set<String>
    private let expense: Set<String>
    private let systemIncome = Set(IncomeCategory.allCases.map(\.rawValue))
    private let systemExpense = Set(ExpenseCategory.allCases.map(\.rawValue))

    init(income: Set<String>, expense: Set<String>) {
        self.income = income
        self.expense = expense
    }

    init(categories: [String: CashflowCategoryKind]) {
        income = Set(categories.compactMap { $0.value == .income ? $0.key : nil })
        expense = Set(categories.compactMap { $0.value == .expense ? $0.key : nil })
    }

    static let system = CashflowStatementCategoryCatalog(
        income: Set(IncomeCategory.allCases.map(\.rawValue)),
        expense: Set(ExpenseCategory.allCases.map(\.rawValue))
    )

    func contains(_ raw: String, kind: CashflowCategoryKind) -> Bool {
        (kind == .income ? income : expense).contains(raw)
    }

    func containsSystem(_ raw: String, kind: CashflowCategoryKind) -> Bool {
        (kind == .income ? systemIncome : systemExpense).contains(raw)
    }
}

enum CashflowStatementCategoryResolutionSource: Equatable {
    case reviewOverride
    case learnedMerchant
    case backendSuggestion
    case fallback
}

struct CashflowStatementCategoryResolution: Equatable {
    let categoryRaw: String
    let source: CashflowStatementCategoryResolutionSource
    let confidence: Double?
    let needsAttention: Bool
}

struct CashflowStatementCategoryResolutionRequest {
    let kind: CashflowCategoryKind
    var reviewOverride: String? = nil
    var stableMerchant: String? = nil
    var backendSuggestion: CashflowStatementPreviewDTO.CategorySuggestion? = nil
}

struct StatementCategoryResolver {
    static let supportedTaxonomyVersion = 1
    static let minimumAutomaticConfidence = 0.8
    private let store: any CashflowStatementMerchantCategoryStore

    init(store: any CashflowStatementMerchantCategoryStore) { self.store = store }

    func resolve(
        _ request: CashflowStatementCategoryResolutionRequest,
        catalog: CashflowStatementCategoryCatalog
    ) -> CashflowStatementCategoryResolution {
        if let override = request.reviewOverride, catalog.contains(override, kind: request.kind) {
            return .init(categoryRaw: override, source: .reviewOverride, confidence: 1, needsAttention: false)
        }
        if let key = CashflowStatementMerchantKey.sanitize(request.stableMerchant),
           let learned = store.categoryRaw(forStableMerchantKey: key),
           catalog.contains(learned, kind: request.kind) {
            return .init(categoryRaw: learned, source: .learnedMerchant, confidence: 1, needsAttention: false)
        }
        if let suggestion = request.backendSuggestion,
           suggestion.taxonomyVersion == Self.supportedTaxonomyVersion,
           suggestion.confidence >= Self.minimumAutomaticConfidence,
           catalog.containsSystem(suggestion.categoryId, kind: request.kind) {
            return .init(categoryRaw: suggestion.categoryId, source: .backendSuggestion,
                         confidence: suggestion.confidence, needsAttention: false)
        }
        let fallback = catalog.contains("other", kind: request.kind) ? "other" : ""
        return .init(categoryRaw: fallback, source: .fallback,
                     confidence: request.backendSuggestion?.confidence, needsAttention: true)
    }
}

struct CashflowStatementCategoryCorrection: Equatable {
    let fingerprint: String
    let stableMerchant: String?
    let categoryRaw: String
}

struct CashflowStatementCategoryLearningCoordinator {
    private let store: any CashflowStatementMerchantCategoryStore
    init(store: any CashflowStatementMerchantCategoryStore) { self.store = store }

    func learn(_ corrections: [CashflowStatementCategoryCorrection], after result: CashflowStatementApplyResult?) {
        guard let result else { return }
        for correction in corrections where result.insertedFingerprints.contains(correction.fingerprint) {
            guard let key = CashflowStatementMerchantKey.sanitize(correction.stableMerchant) else { continue }
            store.remember(categoryRaw: correction.categoryRaw, forStableMerchantKey: key)
        }
    }
}
