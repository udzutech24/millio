//
//  CashflowCategoryPinPrefs.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct CashflowCategoryPinPrefs {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pinnedRawValues(for kind: CashflowCategoryKind) -> Set<String> {
        let values = defaults.array(forKey: storageKey(for: kind)) as? [String] ?? []
        return Set(values)
    }

    func isPinned(categoryRaw: String, kind: CashflowCategoryKind) -> Bool {
        pinnedRawValues(for: kind).contains(categoryRaw)
    }

    func setPinned(_ isPinned: Bool, categoryRaw: String, kind: CashflowCategoryKind) {
        var values = pinnedRawValues(for: kind)
        if isPinned {
            values.insert(categoryRaw)
        } else {
            values.remove(categoryRaw)
        }
        defaults.set(Array(values).sorted(), forKey: storageKey(for: kind))
    }

    private func storageKey(for kind: CashflowCategoryKind) -> String {
        "cashflow.category_pins.\(kind.rawValue)"
    }
}
