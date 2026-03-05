import Foundation

protocol FinanceBalanceAuditStoreProtocol {
    func daySnapshot(for day: FinanceBalanceDayKey) -> [String: FinanceBalanceSnapshotValue]
    func setValue(
        _ value: Double,
        for accountKey: String,
        day: FinanceBalanceDayKey,
        defaultCurrency: String,
        defaultTitle: String,
        defaultGroupName: String,
        accountTypeRaw: String,
        effectSign: Int,
        isUnknown: Bool
    )
    func deleteValue(for accountKey: String, day: FinanceBalanceDayKey)
    func setCurrency(_ currencyCode: String, for accountKey: String)
    func currency(for accountKey: String) -> String?
    func deleteAccountEverywhere(_ accountKey: String)
}

struct FinanceBalanceAuditStore: FinanceBalanceAuditStoreProtocol {
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "finance.balance.audit.snapshot.store") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func daySnapshot(for day: FinanceBalanceDayKey) -> [String: FinanceBalanceSnapshotValue] {
        loadPayload().days[day.rawValue] ?? [:]
    }

    func setValue(
        _ value: Double,
        for accountKey: String,
        day: FinanceBalanceDayKey,
        defaultCurrency: String,
        defaultTitle: String,
        defaultGroupName: String,
        accountTypeRaw: String,
        effectSign: Int,
        isUnknown: Bool
    ) {
        guard value.isFinite else { return }

        var payload = loadPayload()
        var dayMap = payload.days[day.rawValue] ?? [:]
        let existing = dayMap[accountKey]

        let currency = normalizedCurrency(
            payload.accountCurrency[accountKey]
                ?? existing?.currencyCode
                ?? defaultCurrency
        )

        dayMap[accountKey] = FinanceBalanceSnapshotValue(
            value: value,
            currencyCode: currency,
            title: existing?.title ?? defaultTitle,
            groupName: existing?.groupName ?? defaultGroupName,
            accountTypeRaw: existing?.accountTypeRaw ?? accountTypeRaw,
            effectSign: existing?.effectSign ?? effectSign,
            isUnknown: existing?.isUnknown ?? isUnknown
        )
        payload.days[day.rawValue] = dayMap
        payload.accountCurrency[accountKey] = currency
        savePayload(payload)
    }

    func deleteValue(for accountKey: String, day: FinanceBalanceDayKey) {
        var payload = loadPayload()
        var dayMap = payload.days[day.rawValue] ?? [:]
        dayMap.removeValue(forKey: accountKey)
        payload.days[day.rawValue] = dayMap
        savePayload(payload)
    }

    func setCurrency(_ currencyCode: String, for accountKey: String) {
        let normalized = normalizedCurrency(currencyCode)
        guard !normalized.isEmpty else { return }

        var payload = loadPayload()
        payload.accountCurrency[accountKey] = normalized
        for dayKey in payload.days.keys {
            guard var dayMap = payload.days[dayKey], var entry = dayMap[accountKey] else { continue }
            entry.currencyCode = normalized
            dayMap[accountKey] = entry
            payload.days[dayKey] = dayMap
        }
        savePayload(payload)
    }

    func currency(for accountKey: String) -> String? {
        loadPayload().accountCurrency[accountKey]
    }

    func deleteAccountEverywhere(_ accountKey: String) {
        var payload = loadPayload()
        payload.accountCurrency.removeValue(forKey: accountKey)
        for dayKey in payload.days.keys {
            guard var dayMap = payload.days[dayKey] else { continue }
            dayMap.removeValue(forKey: accountKey)
            payload.days[dayKey] = dayMap
        }
        savePayload(payload)
    }

    private func normalizedCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func loadPayload() -> FinanceBalanceSnapshotStorePayload {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(FinanceBalanceSnapshotStorePayload.self, from: data) else {
            return .empty
        }
        return decoded
    }

    private func savePayload(_ payload: FinanceBalanceSnapshotStorePayload) {
        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}
