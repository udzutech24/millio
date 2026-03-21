//
//  BudgetPlan.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation
import SwiftData

enum BudgetPeriodType: String, Codable, CaseIterable {
    case month
    case quarter
    case year
    case custom
}

struct BudgetPeriodDescriptor: Equatable {
    let type: BudgetPeriodType
    let startDate: Date
    let endDate: Date
    let anchorYear: Int
    let anchorMonth: Int
}

@Model
final class BudgetPlan: Persistable {
    var budgetID: String = UUID().uuidString
    var categoryKindRaw: String = CashflowCategoryKind.expense.rawValue
    var periodTypeRaw: String = BudgetPeriodType.month.rawValue
    var anchorYear: Int = 0
    var anchorMonth: Int = 0
    var customStartDate: Date?
    var customEndDate: Date?
    var currencyCode: String = "RUB"
    var totalLimitAmount: Double = 0
    var isCategoryBudgetingEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var periodType: BudgetPeriodType {
        get { BudgetPeriodType(rawValue: periodTypeRaw) ?? .month }
        set { periodTypeRaw = newValue.rawValue }
    }

    var categoryKind: CashflowCategoryKind {
        get { CashflowCategoryKind(rawValue: categoryKindRaw) ?? .expense }
        set { categoryKindRaw = newValue.rawValue }
    }

    init(
        categoryKind: CashflowCategoryKind,
        descriptor: BudgetPeriodDescriptor,
        currencyCode: String,
        totalLimitAmount: Double,
        isCategoryBudgetingEnabled: Bool = false
    ) {
        self.budgetID = UUID().uuidString
        self.categoryKindRaw = categoryKind.rawValue
        self.periodTypeRaw = descriptor.type.rawValue
        self.anchorYear = descriptor.anchorYear
        self.anchorMonth = descriptor.anchorMonth
        if descriptor.type == .custom {
            self.customStartDate = descriptor.startDate
            self.customEndDate = descriptor.endDate
        }
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.totalLimitAmount = max(0, totalLimitAmount)
        self.isCategoryBudgetingEnabled = isCategoryBudgetingEnabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func matches(
        _ descriptor: BudgetPeriodDescriptor,
        categoryKind: CashflowCategoryKind,
        calendar: Calendar = .current
    ) -> Bool {
        guard self.categoryKind == categoryKind else { return false }
        guard periodType == descriptor.type else { return false }
        switch descriptor.type {
        case .month, .quarter, .year:
            return anchorYear == descriptor.anchorYear && anchorMonth == descriptor.anchorMonth
        case .custom:
            guard let customStartDate, let customEndDate else { return false }
            return calendar.isDate(customStartDate, inSameDayAs: descriptor.startDate)
                && calendar.isDate(customEndDate, inSameDayAs: descriptor.endDate)
        }
    }

    func apply(
        categoryKind: CashflowCategoryKind,
        descriptor: BudgetPeriodDescriptor,
        currencyCode: String,
        totalLimitAmount: Double,
        isCategoryBudgetingEnabled: Bool = false
    ) {
        self.categoryKind = categoryKind
        periodType = descriptor.type
        anchorYear = descriptor.anchorYear
        anchorMonth = descriptor.anchorMonth
        if descriptor.type == .custom {
            customStartDate = descriptor.startDate
            customEndDate = descriptor.endDate
        } else {
            customStartDate = nil
            customEndDate = nil
        }
        self.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.totalLimitAmount = max(0, totalLimitAmount)
        self.isCategoryBudgetingEnabled = isCategoryBudgetingEnabled
        updatedAt = Date()
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "BudgetPlan",
            "budgetID": budgetID,
            "categoryKindRaw": categoryKindRaw,
            "periodTypeRaw": periodTypeRaw,
            "anchorYear": anchorYear,
            "anchorMonth": anchorMonth,
            "customStartDate": customStartDate?.timeIntervalSince1970 as Any,
            "customEndDate": customEndDate?.timeIntervalSince1970 as Any,
            "currencyCode": currencyCode,
            "totalLimitAmount": totalLimitAmount,
            "isCategoryBudgetingEnabled": isCategoryBudgetingEnabled,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["budgetID"] as? String != nil,
              dict["periodTypeRaw"] as? String != nil,
              dict["anchorYear"] as? Int != nil,
              dict["anchorMonth"] as? Int != nil,
              dict["currencyCode"] as? String != nil,
              dict["totalLimitAmount"] as? Double != nil,
              dict["isCategoryBudgetingEnabled"] as? Bool != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
    }
}
