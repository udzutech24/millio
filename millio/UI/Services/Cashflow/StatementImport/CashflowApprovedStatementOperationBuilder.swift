import Foundation

enum CashflowApprovedStatementOperationBuilderError: Error, Equatable {
    case invalidReviewedRows
}

@MainActor
enum CashflowApprovedStatementOperationBuilder {
    static func build(
        preview: CashflowStatementPreviewDTO,
        controller: CashflowStatementImportController,
        accountID: String?
    ) throws -> [CashflowApprovedStatementOperation] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false

        let operations = preview.operations.compactMap { operation -> CashflowApprovedStatementOperation? in
            guard controller.includedFingerprints.contains(operation.fingerprint),
                  let disposition = controller.dispositionByFingerprint[operation.fingerprint],
                  let kind = disposition.kind,
                  let date = formatter.date(from: operation.operationDate),
                  let amount = operation.validatedAmount else { return nil }
            return .init(
                fingerprint: operation.fingerprint,
                date: date,
                amount: amount,
                currency: operation.currency,
                type: kind == .income ? .income : .expense,
                categoryRaw: controller.categoryByFingerprint[operation.fingerprint] ?? "other",
                accountID: accountID,
                note: operation.description
            )
        }
        guard operations.count == controller.includedFingerprints.count else {
            throw CashflowApprovedStatementOperationBuilderError.invalidReviewedRows
        }
        return operations
    }
}
