//
//  FinanceFeatureRegistration.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Регистрация фичи финансов для backup/restore
enum FinanceFeatureRegistration {
    static func register() {
        ModelTypeRegistry.shared.register(FinanceGroup.self, typeName: "FinanceGroup")
        ModelTypeRegistry.shared.registerImporter(FinanceGroupImporter.self)
        
        ModelTypeRegistry.shared.register(FinanceAccount.self, typeName: "FinanceAccount")
        ModelTypeRegistry.shared.registerImporter(FinanceAccountImporter.self)
    }
}

// MARK: - Finance Group Importer

struct FinanceGroupImporter: ModelImporter {
    static func importType() -> String {
        "FinanceGroup"
    }
    
    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let name = dict["name"] as? String,
              let colorHex = dict["colorHex"] as? String,
              let createdAt = dict["createdAt"] as? TimeInterval,
              let updatedAt = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        let order = dict["order"] as? Int ?? 0
        
        // Проверяем, не существует ли уже группа с таким именем
        let groupDescriptor = FetchDescriptor<FinanceGroup>(
            predicate: #Predicate<FinanceGroup> { group in
                group.name == name
            }
        )
        
        if let existingGroup = try? context.fetch(groupDescriptor).first {
            // Обновляем существующую группу
            existingGroup.colorHex = colorHex
            existingGroup.order = order
            existingGroup.updatedAt = Date(timeIntervalSince1970: updatedAt)
            return
        }
        
        // Создаем новую группу
        let group = FinanceGroup(name: name, colorHex: colorHex, order: order)
        group.createdAt = Date(timeIntervalSince1970: createdAt)
        group.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        context.insert(group)
    }
}

// MARK: - Finance Account Importer

struct FinanceAccountImporter: ModelImporter {
    static func importType() -> String {
        "FinanceAccount"
    }
    
    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let accountTypeRaw = dict["accountTypeRaw"] as? String,
              let accountID = dict["accountID"] as? String,
              let createdAt = dict["createdAt"] as? TimeInterval,
              let updatedAt = dict["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        
        // Проверяем, не существует ли уже такой счет
        let accountDescriptor = FetchDescriptor<FinanceAccount>(
            predicate: #Predicate<FinanceAccount> { account in
                account.accountTypeRaw == accountTypeRaw && account.accountID == accountID
            }
        )
        
        if let existingAccount = try? context.fetch(accountDescriptor).first {
            // Обновляем существующий счет
            existingAccount.updatedAt = Date(timeIntervalSince1970: updatedAt)
            return
        }
        
        // Создаем новый счет
        let account = FinanceAccount(
            accountType: FinanceAccountType(rawValue: accountTypeRaw) ?? .card,
            accountID: accountID
        )
        account.createdAt = Date(timeIntervalSince1970: createdAt)
        account.updatedAt = Date(timeIntervalSince1970: updatedAt)
        
        // Связь с группой будет установлена в DataRepository после импорта
        context.insert(account)
    }
}
