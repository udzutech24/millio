//
//  WidgetDeepLinkHandlerTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import SwiftUI
import Testing
@testable import millio

@MainActor
struct WidgetDeepLinkHandlerTests {
    @Test("AppWidgetDeepLinkHandler прокидывает pending-флаг расхода")
    func appDeepLinkExpenseSetsPendingFlag() {
        let appState = AppState()
        let url = CurrencyWidgetShared.deepLinkURL(for: .addExpense)!

        AppWidgetDeepLinkHandler.handle(url: url, appState: appState)

        #expect(appState.pendingOpenMainExpenseSheet)
        #expect(appState.pendingOpenMainIncomeSheet == false)
        #expect(appState.pendingOpenConverterService == false)
    }

    @Test("AppWidgetDeepLinkHandler прокидывает pending-флаг конвертера")
    func appDeepLinkConverterSetsPendingFlag() {
        let appState = AppState()
        let url = CurrencyWidgetShared.deepLinkURL(for: .openConverter)!

        AppWidgetDeepLinkHandler.handle(url: url, appState: appState)

        #expect(appState.pendingOpenConverterService)
    }

    @Test("MainWidgetDeepLinkHandler открывает нужные шиты и очищает флаги")
    func mainDeepLinkConsumerOpensSheetsAndClearsPendingFlags() {
        let appState = AppState()
        let router = AppRouter()
        var showExpenseSheet = false
        var showIncomeSheet = false

        appState.pendingOpenMainExpenseSheet = true
        appState.pendingOpenMainIncomeSheet = true

        MainWidgetDeepLinkHandler.consumePendingActions(
            appState: appState,
            router: router,
            showExpenseSheet: &showExpenseSheet,
            showIncomeSheet: &showIncomeSheet
        )

        #expect(showExpenseSheet)
        #expect(showIncomeSheet)
        #expect(appState.pendingOpenMainExpenseSheet == false)
        #expect(appState.pendingOpenMainIncomeSheet == false)
    }

    @Test("MainWidgetDeepLinkHandler открывает конвертер и очищает pending-флаг")
    func mainDeepLinkConsumerNavigatesToConverter() {
        let appState = AppState()
        let router = AppRouter()
        var showExpenseSheet = false
        var showIncomeSheet = false

        appState.pendingOpenConverterService = true

        MainWidgetDeepLinkHandler.consumePendingActions(
            appState: appState,
            router: router,
            showExpenseSheet: &showExpenseSheet,
            showIncomeSheet: &showIncomeSheet
        )

        #expect(appState.pendingOpenConverterService == false)
        #expect(router.navigationPath.isEmpty == false)
    }
}
