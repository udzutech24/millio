//
//  DashboardWidgetConfig.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import Foundation

struct DashboardWidgetConfig: Identifiable, Codable, Equatable {
    let kind: DashboardWidgetKind
    var isVisible: Bool
    var order: Int

    var id: String { kind.rawValue }
}
