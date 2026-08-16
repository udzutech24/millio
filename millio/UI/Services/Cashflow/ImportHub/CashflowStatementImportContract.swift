import Foundation

enum CashflowStatementImportAvailability: Equatable {
    case available
    case unavailable(reason: String)
}

enum CashflowStatementImportState: Equatable {
    case idle
    case selectingFile
    case uploading
    case processing
    case needsReview(operationCount: Int)
    case unsupported
    case backendUnavailable
    case reconciliationFailed
    case monthMismatch
    case applying
    case completed(importedCount: Int)
    case failed(retryable: Bool)
}

struct CashflowStatementPreviewDTO: Decodable, Equatable {
    let schemaVersion: Int
    let status: String
    let statement: Statement
    let operations: [Operation]
    let reconciliation: Reconciliation
    let balances: BalanceEvidence?
    let warnings: [String]

    struct Statement: Decodable, Equatable {
        let bankId: String
        let templateVersion: String
        let format: String
        let accountScope: String
        let period: Period
    }

    struct Period: Decodable, Equatable { let from: String; let to: String }

    struct Operation: Decodable, Equatable, Identifiable {
        let fingerprint: String
        let operationDate: String
        let postingDate: String?
        let description: String
        let merchant: String?
        let mcc: String?
        let amount: String
        let currency: String
        let type: String
        let categorySuggestion: CategorySuggestion?
        let extractionConfidence: Double
        let reviewReasons: [String]
        let sourceReference: SourceReference

        var id: String { fingerprint }

        var validatedAmount: Decimal? {
            Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    struct CategorySuggestion: Decodable, Equatable {
        let taxonomyVersion: Int
        let categoryId: String
        let confidence: Double
        let source: String
    }

    struct SourceReference: Decodable, Equatable {
        let page: Int?
        let row: Int?
        let sequence: Int
    }

    struct Reconciliation: Decodable, Equatable {
        let balanced: Bool
        let declaredIncome: String?
        let declaredExpense: String?
        let computedIncome: String
        let computedExpense: String
        let difference: String
        let reasons: [String]
    }

    struct BalanceEvidence: Decodable, Equatable {
        let opening: BalancePoint?
        let closing: BalancePoint?
        let currency: String
        let source: String
        let confidence: Double
        let reasons: [String]
    }

    struct BalancePoint: Decodable, Equatable {
        let amount: String
        let asOf: String

        var validatedAmount: Decimal? {
            Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

protocol CashflowStatementImportClient {
    var availability: CashflowStatementImportAvailability { get }
    func preview(fileURL: URL) async throws -> CashflowStatementPreviewDTO
}

struct UnavailableCashflowStatementImportClient: CashflowStatementImportClient {
    let availability: CashflowStatementImportAvailability

    init(reason: String = "statement_backend_unavailable") {
        availability = .unavailable(reason: reason)
    }

    func preview(fileURL: URL) async throws -> CashflowStatementPreviewDTO {
        throw CashflowStatementImportError.backendUnavailable
    }
}

enum CashflowStatementImportError: Error, Equatable {
    case backendUnavailable
    case unsupported
    case invalidContract
}
