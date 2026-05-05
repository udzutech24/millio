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


}
