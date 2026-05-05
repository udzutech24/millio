//
//  MainLocalization.swift
//  millio
//
//  Created by Codex on 04.03.2026.
//

import Foundation

enum MainLocalization {
    static let historyAccessibility = "main.history.accessibility"

    static let quickActionExpense = "main.quick_action.expense"
    static let quickActionIncome = "main.quick_action.income"
    static let quickSetupBannerTitle = "main.quick_setup.banner.title"
    static let quickSetupBannerSubtitle = "main.quick_setup.banner.subtitle"
    static let quickSetupBannerOpen = "main.quick_setup.banner.open"

    static let serviceFinances = "main.service.finances"
    static let serviceCourses = "main.service.courses"
    static let serviceCashback = "main.service.cashback"
    static let serviceCashflow = "main.service.cashflow"

    static let tabDashboard = "main.tab.dashboard"
    static let tabFinances = "main.tab.finances"
    static let tabDynamics = "main.tab.dynamics"

    static let dashboardPlaceholderTitle = "main.dashboard.placeholder.title"
    static let dashboardPlaceholderSubtitle = "main.dashboard.placeholder.subtitle"

    static func text(_ key: String) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
    }
}
