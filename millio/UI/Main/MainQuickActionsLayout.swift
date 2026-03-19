//
//  MainQuickActionsLayout.swift
//  millio
//
//  Created by Codex on 19.03.2026.
//

import Foundation

/// Визуальный порядок быстрых действий на главном экране.
enum MainQuickActionKind: Equatable, Hashable {
    case expense
    case income
}

enum MainQuickActionsLayout {
    /// Доход идет первым, расход вторым. Это влияет только на расположение кнопок,
    /// но не меняет обработчики самих действий.
    static let buttonOrder: [MainQuickActionKind] = [
        .income,
        .expense
    ]
}
