//
//  FinanceAccount.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Тип счета
enum FinanceAccountType: String, Codable, CaseIterable {
    case card = "card"
    case credit = "credit"
    case investment = "investment"
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .card: return AppLocalization.string("finances.account.type.card", locale: locale)
        case .credit: return AppLocalization.string("finances.account.type.credit", locale: locale)
        case .investment: return AppLocalization.string("finances.account.type.investment", locale: locale)
        }
    }
    
    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .credit: return "doc.text.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Связь между группой и счетом (Card, Credit или Investment)
@Model
final class FinanceAccount: Persistable {
    /// Тип счета
    var accountTypeRaw: String = "card"
    
    /// ID счета (cardUniqueID, creditUniqueID или investmentUniqueID)
    var accountID: String = ""
    
    /// Группа, к которой принадлежит счет
    var group: FinanceGroup?
    
    /// Дата создания
    var createdAt: Date = Date()
    
    /// Дата последнего обновления
    var updatedAt: Date = Date()

    /// Порядок внутри группы
    var order: Int = 0
    
    var accountType: FinanceAccountType {
        get { FinanceAccountType(rawValue: accountTypeRaw) ?? .card }
        set { accountTypeRaw = newValue.rawValue }
    }
    
    init(accountType: FinanceAccountType, accountID: String) {
        self.accountTypeRaw = accountType.rawValue
        self.accountID = accountID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Exportable
    
    var accountUniqueID: String {
        "\(accountTypeRaw)|\(accountID)|\(createdAt.timeIntervalSince1970)"
    }
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "FinanceAccount",
            "accountTypeRaw": accountTypeRaw,
            "accountID": accountID,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "order": order,
            "accountUniqueID": accountUniqueID
        ]
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["accountTypeRaw"] as? String != nil,
              dict["accountID"] as? String != nil,
              dict["createdAt"] as? TimeInterval != nil,
              dict["updatedAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "FinanceAccount" &&
        dict["accountTypeRaw"] as? String != nil &&
        dict["accountID"] as? String != nil
    }
}
