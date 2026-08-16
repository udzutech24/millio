import Foundation
import Testing
@testable import millio

/// Regression coverage for the unified upcoming planner + Cashflow month workspace
/// localization audit (2026-08-14): both helpers used to hand-roll a ru/en/zh switch
/// that silently fell back to English for German/Spanish — both are release-ready,
/// user-selectable languages (`LocalizationSupport.releaseReadySelectableLanguages`).
@Suite(.serialized)
struct CashflowUpcomingLocalizationTests {
    @Test("Upcoming planner labels are translated for every release-ready language, not just ru/en/zh")
    @MainActor
    func upcomingLocalizationCoversReleaseReadyLanguages() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            LanguageManager.shared.setLanguage(.german)
            #expect(CashflowUpcomingLocalization.navigationTitle == "Anstehend")
            #expect(CashflowUpcomingLocalization.empty == "Keine anstehenden Transaktionen")
            #expect(CashflowUpcomingLocalization.recurring == "Monatliche Transaktion")

            LanguageManager.shared.setLanguage(.spanish)
            #expect(CashflowUpcomingLocalization.navigationTitle == "Próximos")
            #expect(CashflowUpcomingLocalization.empty == "No hay transacciones próximas")
            #expect(CashflowUpcomingLocalization.recurring == "Transacción mensual")
        }
    }

    @Test("Upcoming planner section title matches the scheduled planner's 'upcoming' terminology in Chinese")
    @MainActor
    func upcomingSectionTitleIsTerminologicallyConsistentInChinese() {
        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            // cashflow.scheduled.overview.empty already establishes "即将到来" for "upcoming";
            // the compact card / full planner navigation title must reuse the same term.
            #expect(CashflowUpcomingLocalization.navigationTitle == "即将到来")
        }
    }

    @Test("Month workspace labels are translated for German and Spanish")
    @MainActor
    func monthWorkspaceLocalizationCoversReleaseReadyLanguages() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            LanguageManager.shared.setLanguage(.german)
            #expect(CashflowMonthWorkspaceLocalization.closeMonth == "Monat schließen")
            #expect(CashflowMonthWorkspaceLocalization.statement == "Kontoauszug")

            LanguageManager.shared.setLanguage(.spanish)
            #expect(CashflowMonthWorkspaceLocalization.closeMonth == "Cerrar mes")
            #expect(CashflowMonthWorkspaceLocalization.statement == "Extracto bancario")
        }
    }

    @Test("Month workspace transaction count interpolates the real count and uses correct plural forms")
    @MainActor
    func transactionCountInterpolatesAndPluralizes() {
        AppLanguageTestSupport.withLanguage(.english) {
            // Regression: the original implementation returned the literal string "(count)
            // transactions" without ever interpolating the actual `count` argument.
            #expect(CashflowMonthWorkspaceLocalization.transactionCount(1) == "1 transaction")
            #expect(CashflowMonthWorkspaceLocalization.transactionCount(3) == "3 transactions")
        }

        AppLanguageTestSupport.withLanguage(.russian) {
            // Russian has distinct one/few/many plural forms (1 операция / 3 операции / 5 операций).
            #expect(CashflowMonthWorkspaceLocalization.transactionCount(1) == "1 операция")
            #expect(CashflowMonthWorkspaceLocalization.transactionCount(3) == "3 операции")
            #expect(CashflowMonthWorkspaceLocalization.transactionCount(5) == "5 операций")
        }
    }

    @Test("Statement review has localized copy in every selectable non-system language")
    @MainActor
    func statementReviewCoversSelectableLanguages() {
        let expected: [(Language, String, String)] = [
            (.english, "Review Statement", "Import 3 transactions"),
            (.russian, "Проверка выписки", "Импортировать 3 операции"),
            (.simplifiedChinese, "审核对账单", "导入 3 笔交易"),
            (.german, "Kontoauszug prüfen", "3 Transaktionen importieren"),
            (.spanish, "Revisar extracto", "Importar 3 transacciones"),
        ]

        for (language, title, importCount) in expected {
            AppLanguageTestSupport.withLanguage(language) {
                #expect(CashflowStatementReviewLocalization.title == title)
                #expect(CashflowStatementReviewLocalization.importCount(3) == importCount)
                #expect(CashflowStatementReviewLocalization.confirmImportCount(3).contains("3"))
            }
        }
    }

    @Test("Statement review operation count uses Russian plural categories")
    @MainActor
    func statementReviewRussianPluralization() {
        AppLanguageTestSupport.withLanguage(.russian) {
            #expect(CashflowStatementReviewLocalization.operationCount(1) == "1 операция")
            #expect(CashflowStatementReviewLocalization.operationCount(3) == "3 операции")
            #expect(CashflowStatementReviewLocalization.operationCount(5) == "5 операций")
        }
    }
}
