//
//  DashboardWidgetKind.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import Foundation

enum DashboardWidgetKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case converter
    case quickActions
    case finances
    case services
    case cashflow

    var id: String { rawValue }
}
