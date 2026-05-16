//
//  FinanceSystemGroups.swift
//  millio
//
//  Created by Codex on 08.03.2026.
//

import Foundation
import SwiftData

/// Системные группы финансов.
///
/// Важно: бизнес-логика должна опираться на устойчивую сущность (группу), а не на `nil`-связи.
/// `FinanceAccount.group == nil` считается невалидным состоянием и подлежит нормализации.
enum FinanceSystemGroups {
    static var ungroupedName: String { L("finances.group.ungrouped") }
    static let ungroupedColorHex: String = "#3C4B5E"

    /// Все известные переводы ключа «finances.group.ungrouped» по всем языкам.
    /// Нужны для поиска системной группы независимо от языка, в котором она была создана.
    static var allKnownUngroupedNames: Set<String> {
        var names: Set<String> = [ungroupedName]
        for language in Language.allCases {
            guard let locale = language.locale,
                  let bundle = AppLocalization.localizedBundle(for: locale, bundle: .main) else { continue }
            let name = String(localized: "finances.group.ungrouped", bundle: bundle)
            names.insert(name)
        }
        return names
    }

    @MainActor
    static func ensureUngroupedGroup(in modelContext: ModelContext) -> FinanceGroup {
        let name = ungroupedName
        let knownNames = allKnownUngroupedNames
        let descriptor = FetchDescriptor<FinanceGroup>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []

        if let existing = groups.first(where: { knownNames.contains($0.name) }) {
            if existing.name != name {
                existing.name = name
            }
            return existing
        }

        let maxOrder = groups.map(\.order).max() ?? -1
        let group = FinanceGroup(
            name: name,
            colorHex: ungroupedColorHex,
            order: maxOrder + 1
        )
        modelContext.insert(group)
        return group
    }

    /// Переименовывает существующую системную группу под текущий язык.
    /// Вызывать при старте ViewModel и при смене языка.
    @MainActor
    static func normalizeUngroupedGroupName(in modelContext: ModelContext) {
        let name = ungroupedName
        let knownNames = allKnownUngroupedNames
        let descriptor = FetchDescriptor<FinanceGroup>()
        guard let groups = try? modelContext.fetch(descriptor),
              let existing = groups.first(where: { knownNames.contains($0.name) }),
              existing.name != name else { return }
        existing.name = name
    }
}
