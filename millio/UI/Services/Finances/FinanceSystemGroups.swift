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

    @MainActor
    static func ensureUngroupedGroup(in modelContext: ModelContext) -> FinanceGroup {
        let name = ungroupedName
        let descriptor = FetchDescriptor<FinanceGroup>()
        let groups = (try? modelContext.fetch(descriptor)) ?? []

        if let existing = groups.first(where: { $0.name == name }) {
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
}
