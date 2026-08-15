import Foundation
import Testing
@testable import millio

private final class StatementMerchantStoreSpy: CashflowStatementMerchantCategoryStore {
    var values: [String: String] = [:]
    var writes: [(String, String)] = []

    func categoryRaw(forStableMerchantKey key: String) -> String? { values[key] }
    func remember(categoryRaw: String, forStableMerchantKey key: String) {
        writes.append((key, categoryRaw))
        values[key] = categoryRaw
    }
}

struct CashflowStatementCategoryResolverTests {
    private let catalog = CashflowStatementCategoryCatalog(categories: [
        "other": .expense,
        "groceries": .expense,
        "cafe": .expense,
        "salary": .income,
        "custom:books": .expense
    ])

    @Test("Override beats learned and backend categories, including a valid custom category")
    func precedenceAndCustomOverride() {
        let store = StatementMerchantStoreSpy()
        store.values["coffee point"] = "groceries"
        let result = StatementCategoryResolver(store: store).resolve(.init(
            kind: .expense, reviewOverride: "custom:books", stableMerchant: "Coffee Point",
            backendSuggestion: .init(taxonomyVersion: 1, categoryId: "cafe", confidence: 0.99, source: "rule")
        ), catalog: catalog)
        #expect(result.categoryRaw == "custom:books")
        #expect(result.source == .reviewOverride)
        #expect(!result.needsAttention)
    }

    @Test("Learned mapping beats a valid backend suggestion")
    func learnedBeatsBackend() {
        let store = StatementMerchantStoreSpy()
        store.values["coffee point"] = "groceries"
        let result = StatementCategoryResolver(store: store).resolve(.init(
            kind: .expense, stableMerchant: "  Coffee-Point!  ",
            backendSuggestion: .init(taxonomyVersion: 1, categoryId: "cafe", confidence: 0.99, source: "rule")
        ), catalog: catalog)
        #expect(result.categoryRaw == "groceries")
        #expect(result.source == .learnedMerchant)
    }

    @Test("Wrong taxonomy, missing category, wrong kind and low confidence fail closed")
    func invalidSuggestionsFailClosed() {
        let resolver = StatementCategoryResolver(store: StatementMerchantStoreSpy())
        for suggestion in [
            CashflowStatementPreviewDTO.CategorySuggestion(taxonomyVersion: 2, categoryId: "cafe", confidence: 1, source: "rule"),
            .init(taxonomyVersion: 1, categoryId: "missing", confidence: 1, source: "rule"),
            .init(taxonomyVersion: 1, categoryId: "custom:books", confidence: 1, source: "rule"),
            .init(taxonomyVersion: 1, categoryId: "salary", confidence: 1, source: "rule"),
            .init(taxonomyVersion: 1, categoryId: "cafe", confidence: 0.49, source: "rule")
        ] {
            let result = resolver.resolve(.init(kind: .expense, backendSuggestion: suggestion), catalog: catalog)
            #expect(result.categoryRaw == "other")
            #expect(result.source == .fallback)
            #expect(result.needsAttention)
        }
    }

    @Test("Only a bounded sanitized merchant is eligible for learned identity")
    func ambiguousMerchantIsRejected() {
        #expect(CashflowStatementMerchantKey.sanitize(nil) == nil)
        #expect(CashflowStatementMerchantKey.sanitize("Store 123456789012") == nil)
        #expect(CashflowStatementMerchantKey.sanitize("merchant@example.com") == nil)
        #expect(CashflowStatementMerchantKey.sanitize("Coffee-Point!") == "coffee point")
    }

    @Test("Explicit corrections are learned only for successfully inserted fingerprints")
    func successfulLearning() {
        let store = StatementMerchantStoreSpy()
        let learner = CashflowStatementCategoryLearningCoordinator(store: store)
        let corrections = [
            CashflowStatementCategoryCorrection(fingerprint: "inserted", stableMerchant: "Coffee Point", categoryRaw: "cafe"),
            .init(fingerprint: "skipped", stableMerchant: "Book Shop", categoryRaw: "custom:books")
        ]
        learner.learn(corrections, after: .init(insertedFingerprints: ["inserted"], skippedFingerprints: ["skipped"]))
        #expect(store.writes.count == 1)
        #expect(store.writes.first?.0 == "coffee point")
        #expect(store.writes.first?.1 == "cafe")
    }

    @Test("Cancellation or failed apply cannot learn because no successful result exists")
    func cancellationDoesNotLearn() {
        let store = StatementMerchantStoreSpy()
        let learner = CashflowStatementCategoryLearningCoordinator(store: store)
        let corrections = [CashflowStatementCategoryCorrection(
            fingerprint: "pending", stableMerchant: "Coffee Point", categoryRaw: "cafe"
        )]
        learner.learn(corrections, after: nil)
        #expect(store.writes.isEmpty)
    }
}
