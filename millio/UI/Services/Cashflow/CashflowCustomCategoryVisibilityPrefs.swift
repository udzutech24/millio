//
//  CashflowCustomCategoryVisibilityPrefs.swift
//  millio
//
//  Хранит скрытые кастомные категории кэшфлоу в UserDefaults.
//  Структура аналогична CashflowCategoryPinPrefs — без SwiftData-миграции.
//

import Foundation

struct CashflowCustomCategoryVisibilityPrefs {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hiddenRawValues(for kind: CashflowCategoryKind) -> Set<String> {
        let values = defaults.array(forKey: storageKey(for: kind)) as? [String] ?? []
        return Set(values)
    }

    func isHidden(categoryRaw: String, kind: CashflowCategoryKind) -> Bool {
        hiddenRawValues(for: kind).contains(categoryRaw)
    }

    func setHidden(_ isHidden: Bool, categoryRaw: String, kind: CashflowCategoryKind) {
        var values = hiddenRawValues(for: kind)
        if isHidden {
            values.insert(categoryRaw)
        } else {
            values.remove(categoryRaw)
        }
        defaults.set(Array(values).sorted(), forKey: storageKey(for: kind))
    }

    /// Переносит запись скрытости при переименовании/слиянии категории.
    func remap(categoryRaw sourceRaw: String, to targetRaw: String, kind: CashflowCategoryKind) {
        guard sourceRaw != targetRaw else { return }
        var values = hiddenRawValues(for: kind)
        if values.remove(sourceRaw) != nil {
            values.insert(targetRaw)
        }
        defaults.set(Array(values).sorted(), forKey: storageKey(for: kind))
    }

    /// Удаляет запись при полном удалении категории.
    func removeAll(categoryRaw: String, kind: CashflowCategoryKind) {
        var values = hiddenRawValues(for: kind)
        values.remove(categoryRaw)
        defaults.set(Array(values).sorted(), forKey: storageKey(for: kind))
    }

    private func storageKey(for kind: CashflowCategoryKind) -> String {
        "cashflow.custom_category_visibility.\(kind.rawValue)"
    }
}
