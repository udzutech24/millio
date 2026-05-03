//
//  CashflowCategoryOrderPrefs.swift
//  millio
//

import Foundation

struct CashflowCategoryOrderPrefs {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Возвращает сохранённый пользовательский порядок (rawValues) или nil если порядок не задан.
    func customOrder(for kind: CashflowCategoryKind) -> [String]? {
        let values = defaults.array(forKey: storageKey(for: kind)) as? [String]
        return values?.isEmpty == false ? values : nil
    }

    func setOrder(_ rawValues: [String], for kind: CashflowCategoryKind) {
        defaults.set(rawValues, forKey: storageKey(for: kind))
    }

    func clearOrder(for kind: CashflowCategoryKind) {
        defaults.removeObject(forKey: storageKey(for: kind))
    }

    func remap(categoryRaw sourceRaw: String, to targetRaw: String, kind: CashflowCategoryKind) {
        guard sourceRaw != targetRaw, var order = customOrder(for: kind) else { return }
        if let idx = order.firstIndex(of: sourceRaw) {
            order[idx] = targetRaw
            setOrder(order, for: kind)
        }
    }

    private func storageKey(for kind: CashflowCategoryKind) -> String {
        "cashflow.category_order.\(kind.rawValue)"
    }
}
