//
//  UserSubscription.swift
//  millio
//

import Foundation
import SwiftData

extension UserSubscription: Persistable {
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "UserSubscription",
            "subscriptionID": subscriptionID,
            "serviceName": serviceName,
            "amount": amount,
            "currencyCode": currencyCode,
            "billingCycleRaw": billingCycleRaw,
            "isActive": isActive,
            "iconEmoji": iconEmoji,
            "colorHex": colorHex,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let d = nextChargeDate { dict["nextChargeDate"] = d.timeIntervalSince1970 }
        if let n = note { dict["note"] = n }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Import handled by UserSubscriptionImporter (ModelTypeRegistry)
    }
}

enum SubscriptionBillingCycle: String, CaseIterable, Codable {
    case weekly
    case monthly
    case quarterly
    case yearly

    var localizedTitle: String {
        switch self {
        case .weekly:    return L("subscriptions.cycle.weekly", defaultValue: "Weekly")
        case .monthly:   return L("subscriptions.cycle.monthly", defaultValue: "Monthly")
        case .quarterly: return L("subscriptions.cycle.quarterly", defaultValue: "Quarterly")
        case .yearly:    return L("subscriptions.cycle.yearly", defaultValue: "Yearly")
        }
    }

    /// Approximate multiplier to convert to monthly amount
    var monthlyFactor: Double {
        switch self {
        case .weekly:    return 52.0 / 12.0
        case .monthly:   return 1.0
        case .quarterly: return 1.0 / 3.0
        case .yearly:    return 1.0 / 12.0
        }
    }

    /// Approximate multiplier to convert to yearly amount
    var yearlyFactor: Double {
        switch self {
        case .weekly:    return 52.0
        case .monthly:   return 12.0
        case .quarterly: return 4.0
        case .yearly:    return 1.0
        }
    }
}

@Model
final class UserSubscription {
    var subscriptionID: String = UUID().uuidString
    var serviceName: String = ""
    var amount: Double = 0
    var currencyCode: String = "RUB"
    var billingCycleRaw: String = SubscriptionBillingCycle.monthly.rawValue
    var nextChargeDate: Date?
    var iconEmoji: String = "💳"
    var colorHex: String = "6A5CFF"
    var isActive: Bool = true
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var billingCycle: SubscriptionBillingCycle {
        get { SubscriptionBillingCycle(rawValue: billingCycleRaw) ?? .monthly }
        set { billingCycleRaw = newValue.rawValue }
    }

    var monthlyAmount: Double {
        amount * billingCycle.monthlyFactor
    }

    var yearlyAmount: Double {
        amount * billingCycle.yearlyFactor
    }

    init(
        serviceName: String,
        amount: Double,
        currencyCode: String,
        billingCycle: SubscriptionBillingCycle = .monthly,
        nextChargeDate: Date? = nil,
        iconEmoji: String = "💳",
        colorHex: String = "6A5CFF",
        note: String? = nil
    ) {
        self.subscriptionID = UUID().uuidString
        self.serviceName = serviceName
        self.amount = amount
        self.currencyCode = currencyCode
        self.billingCycleRaw = billingCycle.rawValue
        self.nextChargeDate = nextChargeDate
        self.iconEmoji = iconEmoji
        self.colorHex = colorHex
        self.note = note
        self.isActive = true
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
