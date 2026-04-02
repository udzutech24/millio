import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashflowBudgetLocalizationTests {
    @Test("Budget helper uses Simplified Chinese catalog copy for release-critical labels")
    @MainActor
    func simplifiedChineseBudgetCopyComesFromCatalog() {
        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            #expect(CashflowBudgetLocalization.setupTitle(for: .expense) == "预算限额")
            #expect(CashflowBudgetLocalization.planButtonTitle(for: .expense, hasBudget: false) == "添加限额")
            #expect(CashflowBudgetLocalization.categoryBadgeText(for: .warning) == "临近")
            #expect(CashflowBudgetLocalization.status(.exceeded) == "超支")
        }
    }

    @Test("Budget helper recomputes cached-looking labels after language switch")
    @MainActor
    func budgetStaticCopyHotReloadsWithLanguageChanges() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            LanguageManager.shared.setLanguage(.english)
            #expect(CashflowBudgetLocalization.save == "Save")
            #expect(CashflowBudgetLocalization.used == "Used")

            LanguageManager.shared.setLanguage(.simplifiedChinese)
            #expect(CashflowBudgetLocalization.save == "保存")
            #expect(CashflowBudgetLocalization.used == "已使用")
        }
    }
}
