//
//  BudgetCategoryLimit.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation
import SwiftData

@Model
final class BudgetCategoryLimit: Persistable {
    var categoryLimitID: String = UUID().uuidString
    var budgetID: String = ""
    var categoryKindRaw: String = CashflowCategoryKind.expense.rawValue
    var categoryRawValue: String = ""
    var limitAmount: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var categoryKind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: categoryKindRaw) ?? .expense }
        set { categoryKindRaw = newValue.rawValue }
    }

    init(
        budgetID: String,
        categoryKind: CashflowCategoryKind,
        categoryRawValue: String,
        limitAmount: Double
    ) {
        self.categoryLimitID = UUID().uuidString
        self.budgetID = budgetID
        self.categoryKindRaw = categoryKind.rawValue
        self.categoryRawValue = categoryRawValue
        self.limitAmount = max(0, limitAmount)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "BudgetCategoryLimit",
            "categoryLimitID": categoryLimitID,
            "budgetID": budgetID,
            "categoryKindRaw": categoryKindRaw,
            "categoryRawValue": categoryRawValue,
            "limitAmount": limitAmount,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["categoryLimitID"] as? String != nil,
              dict["budgetID"] as? String != nil,
              dict["categoryKindRaw"] as? String != nil,
              dict["categoryRawValue"] as? String != nil,
              dict["limitAmount"] as? Double != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}
