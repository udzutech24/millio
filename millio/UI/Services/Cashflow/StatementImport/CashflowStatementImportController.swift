import Combine
import Foundation

@MainActor
final class CashflowStatementImportController: ObservableObject {
    @Published private(set) var state: CashflowStatementImportState = .idle
    @Published private(set) var preview: CashflowStatementPreviewDTO?
    @Published var includedFingerprints: Set<String> = []
    @Published var categoryByFingerprint: [String: String] = [:]
    @Published private(set) var categoryResolutionByFingerprint: [String: CashflowStatementCategoryResolution] = [:]
    @Published private(set) var localDuplicateFingerprints: Set<String> = []
    @Published private(set) var dispositionByFingerprint: [String: CashflowStatementReviewDisposition] = [:]

    private let client: any CashflowStatementImportClient
    private let selectedMonth: Date
    private let categoryCatalog: CashflowStatementCategoryCatalog
    private let merchantStore: any CashflowStatementMerchantCategoryStore
    private var explicitCorrections: [String: CashflowStatementCategoryCorrection] = [:]
    private var initialCategoryByFingerprint: [String: String] = [:]

    init(
        client: any CashflowStatementImportClient,
        selectedMonth: Date = .now,
        categoryCatalog: CashflowStatementCategoryCatalog = .system,
        merchantStore: any CashflowStatementMerchantCategoryStore = CashflowStatementMerchantCategoryPrefsAdapter()
    ) {
        self.client = client
        self.selectedMonth = CashflowMonthSelectionPolicy.canonicalMonth(selectedMonth)
        self.categoryCatalog = categoryCatalog
        self.merchantStore = merchantStore
    }

    func beginSelection() { state = .selectingFile }

    func preview(fileURL: URL) async {
        state = .uploading
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            state = .processing
            let value = try await client.preview(fileURL: fileURL)
            guard value.schemaVersion == 1 else { throw CashflowStatementImportError.invalidContract }
            preview = value
            localDuplicateFingerprints = []
            explicitCorrections = [:]
            dispositionByFingerprint = Dictionary(uniqueKeysWithValues: value.operations.map { operation in
                (operation.fingerprint, CashflowStatementReviewDispositionPolicy.initial(for: operation, isLocalDuplicate: false))
            })
            includedFingerprints = Set(value.operations.compactMap { operation in
                dispositionByFingerprint[operation.fingerprint]?.isIncluded == true ? operation.fingerprint : nil
            })
            let resolver = StatementCategoryResolver(store: merchantStore)
            categoryResolutionByFingerprint = Dictionary(uniqueKeysWithValues: value.operations.map { operation in
                let kind: CashflowCategoryKind = (operation.validatedAmount ?? 0) > 0 ? .income : .expense
                let resolution = resolver.resolve(.init(
                    kind: kind,
                    stableMerchant: operation.merchant,
                    backendSuggestion: operation.categorySuggestion
                ), catalog: categoryCatalog)
                return (operation.fingerprint, resolution)
            })
            categoryByFingerprint = categoryResolutionByFingerprint.mapValues(\.categoryRaw)
            initialCategoryByFingerprint = categoryByFingerprint
            if value.status == "unsupported" {
                state = .unsupported
            } else if CashflowStatementMonthPolicy.validate(
                periodFrom: value.statement.period.from,
                periodTo: value.statement.period.to,
                selectedMonth: selectedMonth
            ) != .matches {
                state = .monthMismatch
            } else if !value.reconciliation.balanced {
                state = .reconciliationFailed
            } else {
                state = .needsReview(operationCount: value.operations.count)
            }
        } catch CashflowStatementImportError.backendUnavailable {
            state = .backendUnavailable
        } catch CashflowStatementImportError.unsupported {
            state = .unsupported
        } catch {
            state = .failed(retryable: true)
        }
    }

    func markApplying() { state = .applying }
    func markCompleted(result: CashflowStatementApplyResult) {
        CashflowStatementCategoryLearningCoordinator(store: merchantStore)
            .learn(Array(explicitCorrections.values), after: result)
        state = .completed(importedCount: result.insertedFingerprints.count)
    }
    func markApplyFailure() { state = .failed(retryable: false) }

    func setCategory(_ categoryRaw: String, for operation: CashflowStatementPreviewDTO.Operation) {
        let kind: CashflowCategoryKind = (operation.validatedAmount ?? 0) > 0 ? .income : .expense
        let resolution = StatementCategoryResolver(store: merchantStore).resolve(.init(
            kind: kind,
            reviewOverride: categoryRaw,
            stableMerchant: operation.merchant,
            backendSuggestion: operation.categorySuggestion
        ), catalog: categoryCatalog)
        categoryByFingerprint[operation.fingerprint] = resolution.categoryRaw
        categoryResolutionByFingerprint[operation.fingerprint] = resolution
        guard resolution.source == .reviewOverride,
              initialCategoryByFingerprint[operation.fingerprint] != resolution.categoryRaw else {
            explicitCorrections.removeValue(forKey: operation.fingerprint)
            return
        }
        explicitCorrections[operation.fingerprint] = .init(
            fingerprint: operation.fingerprint,
            stableMerchant: operation.merchant,
            categoryRaw: resolution.categoryRaw
        )
    }

    func annotateLocalDuplicates(_ fingerprints: Set<String>) {
        guard let preview else { return }
        localDuplicateFingerprints = fingerprints.intersection(preview.operations.map(\.fingerprint))
        includedFingerprints.subtract(localDuplicateFingerprints)
        for fingerprint in localDuplicateFingerprints {
            dispositionByFingerprint[fingerprint] = .excludedDuplicate
        }
    }

    func isLocalDuplicate(_ operation: CashflowStatementPreviewDTO.Operation) -> Bool {
        localDuplicateFingerprints.contains(operation.fingerprint)
    }

    var reviewRows: [CashflowStatementReviewRow] {
        guard let preview else { return [] }
        return preview.operations.map { operation in
            .init(
                operation: operation,
                disposition: dispositionByFingerprint[operation.fingerprint]
                    ?? CashflowStatementReviewDispositionPolicy.initial(for: operation, isLocalDuplicate: isLocalDuplicate(operation)),
                categoryRaw: categoryByFingerprint[operation.fingerprint] ?? "other",
                needsAttention: categoryResolutionByFingerprint[operation.fingerprint]?.needsAttention ?? true
            )
        }
    }

    func setIncluded(_ included: Bool, for operation: CashflowStatementPreviewDTO.Operation) {
        guard CashflowStatementReviewDispositionPolicy.initial(
            for: operation, isLocalDuplicate: isLocalDuplicate(operation)
        ).isIncluded else { return }
        let kind: CashflowCategoryKind = (operation.validatedAmount ?? 0) > 0 ? .income : .expense
        dispositionByFingerprint[operation.fingerprint] = included ? .included(kind) : .excludedByUser
        if included { includedFingerprints.insert(operation.fingerprint) }
        else { includedFingerprints.remove(operation.fingerprint) }
    }

    func reclassifyExternalTransfer(
        _ operation: CashflowStatementPreviewDTO.Operation,
        as kind: CashflowCategoryKind,
        categoryRaw: String
    ) {
        guard CashflowStatementReviewDispositionPolicy.canReclassify(operation) else { return }
        dispositionByFingerprint[operation.fingerprint] = .included(kind)
        includedFingerprints.insert(operation.fingerprint)
        setCategory(categoryRaw, for: operation, forcedKind: kind)
    }

    func excludeAllTransfers() {
        guard let preview else { return }
        for operation in preview.operations where operation.type.hasPrefix("transfer_") {
            dispositionByFingerprint[operation.fingerprint] = operation.type == "transfer_internal"
                ? .excludedInternalTransfer : .excludedExternalTransfer
            includedFingerprints.remove(operation.fingerprint)
        }
    }

    func canInclude(_ operation: CashflowStatementPreviewDTO.Operation) -> Bool {
        dispositionByFingerprint[operation.fingerprint]?.isIncluded == true
    }

    private func setCategory(
        _ categoryRaw: String,
        for operation: CashflowStatementPreviewDTO.Operation,
        forcedKind: CashflowCategoryKind
    ) {
        let resolution = StatementCategoryResolver(store: merchantStore).resolve(.init(
            kind: forcedKind,
            reviewOverride: categoryRaw,
            stableMerchant: operation.merchant,
            backendSuggestion: operation.categorySuggestion
        ), catalog: categoryCatalog)
        categoryByFingerprint[operation.fingerprint] = resolution.categoryRaw
        categoryResolutionByFingerprint[operation.fingerprint] = resolution
        explicitCorrections[operation.fingerprint] = .init(
            fingerprint: operation.fingerprint,
            stableMerchant: operation.merchant,
            categoryRaw: resolution.categoryRaw
        )
    }
}
