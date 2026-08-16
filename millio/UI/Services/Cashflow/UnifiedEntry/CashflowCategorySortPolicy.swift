import Foundation

enum CashflowCategorySortMode: String, CaseIterable, Identifiable {
    case activity
    case amount
    case manual
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return L("cashflow.category.sort.activity", defaultValue: "Activity")
        case .amount: return L("cashflow.category.sort.amount", defaultValue: "Amount")
        case .manual: return L("cashflow.category.sort.manual", defaultValue: "Manual")
        case .name: return L("cashflow.category.sort.name", defaultValue: "Name")
        }
    }
}

enum CashflowCategorySortPolicy {
    static func sorted(
        _ options: [CashflowCategoryOption],
        mode: CashflowCategorySortMode,
        pinned: Set<String>,
        totals: [String: Double],
        latestActivity: [String: Date]
    ) -> [CashflowCategoryOption] {
        let manualIndex = Dictionary(uniqueKeysWithValues: options.enumerated().map { ($0.element.rawValue, $0.offset) })
        return options.sorted { lhs, rhs in
            let lhsPinned = pinned.contains(lhs.rawValue)
            let rhsPinned = pinned.contains(rhs.rawValue)
            if lhsPinned != rhsPinned { return lhsPinned }

            switch mode {
            case .activity:
                let left = latestActivity[lhs.rawValue] ?? .distantPast
                let right = latestActivity[rhs.rawValue] ?? .distantPast
                if left != right { return left > right }
            case .amount:
                let left = totals[lhs.rawValue, default: 0]
                let right = totals[rhs.rawValue, default: 0]
                if left != right { return left > right }
            case .manual:
                break
            case .name:
                let result = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return manualIndex[lhs.rawValue, default: .max] < manualIndex[rhs.rawValue, default: .max]
        }
    }
}

enum CashflowCategorySortPreferences {
    static func key(for kind: CashflowCategoryKind) -> String {
        "cashflow_unified_category_sort_\(String(describing: kind))"
    }

    static func load(for kind: CashflowCategoryKind, defaults: UserDefaults = .standard) -> CashflowCategorySortMode {
        defaults.string(forKey: key(for: kind)).flatMap(CashflowCategorySortMode.init(rawValue:)) ?? .activity
    }

    static func save(_ mode: CashflowCategorySortMode, for kind: CashflowCategoryKind, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key(for: kind))
    }
}
