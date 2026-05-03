//
//  UserSubscriptionsFeatureRegistration.swift
//  millio
//

import Foundation
import SwiftData

enum UserSubscriptionsFeatureRegistration {
    static func register() {
        ModelTypeRegistry.shared.register(UserSubscription.self, typeName: "UserSubscription")
        ModelTypeRegistry.shared.registerImporter(UserSubscriptionImporter.self)
    }
}

struct UserSubscriptionImporter: ModelImporter {
    static func importType() -> String { "UserSubscription" }
    static var importPriority: Int { 50 }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let subscriptionID = data["subscriptionID"] as? String,
              let serviceName = data["serviceName"] as? String,
              let amount = data["amount"] as? Double,
              let currencyCode = data["currencyCode"] as? String,
              let billingCycleRaw = data["billingCycleRaw"] as? String,
              let isActive = data["isActive"] as? Bool,
              let createdAt = data["createdAt"] as? TimeInterval,
              let updatedAt = data["updatedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let cycle = SubscriptionBillingCycle(rawValue: billingCycleRaw) ?? .monthly
        let nextChargeDate = (data["nextChargeDate"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) }

        let sub = UserSubscription(
            serviceName: serviceName,
            amount: amount,
            currencyCode: currencyCode,
            billingCycle: cycle,
            nextChargeDate: nextChargeDate,
            iconEmoji: (data["iconEmoji"] as? String) ?? "💳",
            colorHex: (data["colorHex"] as? String) ?? "6A5CFF",
            note: data["note"] as? String
        )
        sub.subscriptionID = subscriptionID
        sub.isActive = isActive
        sub.createdAt = Date(timeIntervalSince1970: createdAt)
        sub.updatedAt = Date(timeIntervalSince1970: updatedAt)
        context.insert(sub)
    }
}
