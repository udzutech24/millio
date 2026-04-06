//
//  MainLocalization.swift
//  millio
//
//  Created by Codex on 04.03.2026.
//

import Foundation

enum MainLocalization {
    static let historyAccessibility = "main.history.accessibility"
    static let quickActionHistory = "main.quick_action.history"

    static let quickActionExpense = "main.quick_action.expense"
    static let quickActionIncome = "main.quick_action.income"
    static let quickSetupBannerTitle = "main.quick_setup.banner.title"
    static let quickSetupBannerSubtitle = "main.quick_setup.banner.subtitle"
    static let quickSetupBannerOpen = "main.quick_setup.banner.open"
    static let focusEyebrow = "main.focus.eyebrow"
    static let focusTitle = "main.focus.title"
    static let focusSubtitle = "main.focus.subtitle"
    static let dashboardEditTitle = "main.dashboard.edit.title"
    static let dashboardEditSubtitle = "main.dashboard.edit.subtitle"
    static let dashboardEditClose = "main.dashboard.edit.close"
    static let dashboardEditWidgetsSection = "main.dashboard.edit.widgets.section"
    static let dashboardEditOpen = "main.dashboard.edit.open"
    static let dashboardWidgetQuickActionsTitle = "main.dashboard.widget.quick_actions.title"
    static let dashboardWidgetQuickActionsSubtitle = "main.dashboard.widget.quick_actions.subtitle"
    static let dashboardWidgetFinancesTitle = "main.dashboard.widget.finances.title"
    static let dashboardWidgetFinancesSubtitle = "main.dashboard.widget.finances.subtitle"
    static let dashboardWidgetFinancesAddProduct = "main.dashboard.widget.finances.add_product"
    static let dashboardWidgetFinancesOpen = "main.dashboard.widget.finances.open"
    static let dashboardWidgetFinancesEmpty = "main.dashboard.widget.finances.empty"
    static let dashboardWidgetFinancesProductsCount = "main.dashboard.widget.finances.products_count"
    static let dashboardWidgetFinancesSegmentCards = "main.dashboard.widget.finances.segment.cards"
    static let dashboardWidgetFinancesSegmentInvestments = "main.dashboard.widget.finances.segment.investments"
    static let dashboardWidgetFinancesSegmentLiabilities = "main.dashboard.widget.finances.segment.liabilities"
    static let dashboardWidgetConverterTitle = "main.dashboard.widget.converter.title"
    static let dashboardWidgetConverterSubtitle = "main.dashboard.widget.converter.subtitle"
    static let dashboardWidgetServicesTitle = "main.dashboard.widget.services.title"
    static let dashboardWidgetServicesSubtitle = "main.dashboard.widget.services.subtitle"
    static let servicesSectionTitle = "main.services.section.title"
    static let servicesReorderHint = "main.services.reorder_hint"
    static let layoutClassic = "main.layout.classic"
    static let layoutFocus = "main.layout.focus"
    static let layoutSwitchAccessibility = "main.layout.switch.accessibility"

    static let serviceFinances = "main.service.finances"
    static let serviceCourses = "main.service.courses"
    static let serviceCashback = "main.service.cashback"
    static let serviceCashflow = "main.service.cashflow"

    static func text(_ key: String) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: AppLocalization.currentAppLocale, arguments: arguments)
    }

    static func dashboardWidgetTitle(for kind: DashboardWidgetKind) -> String {
        switch kind {
        case .converter:
            return text(dashboardWidgetConverterTitle)
        case .quickActions:
            return text(dashboardWidgetQuickActionsTitle)
        case .finances:
            return text(dashboardWidgetFinancesTitle)
        case .services:
            return text(dashboardWidgetServicesTitle)
        case .cashflow:
            return String(
                localized: "main.dashboard.widget.cashflow.title",
                defaultValue: "Cashflow pulse",
                comment: "Title for the compact cashflow widget on the dashboard"
            )
        }
    }

    static func dashboardWidgetSubtitle(for kind: DashboardWidgetKind) -> String {
        switch kind {
        case .converter:
            return text(dashboardWidgetConverterSubtitle)
        case .quickActions:
            return text(dashboardWidgetQuickActionsSubtitle)
        case .finances:
            return text(dashboardWidgetFinancesSubtitle)
        case .services:
            return text(dashboardWidgetServicesSubtitle)
        case .cashflow:
            return String(
                localized: "main.dashboard.widget.cashflow.subtitle",
                defaultValue: "Monthly income and expense dynamics in one glance.",
                comment: "Subtitle for the compact cashflow widget on the dashboard"
            )
        }
    }
}
