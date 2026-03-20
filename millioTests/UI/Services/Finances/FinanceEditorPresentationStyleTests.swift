import Testing
@testable import millio

struct FinanceEditorPresentationStyleTests {
    @Test("Модальная подача редактора сама поднимает NavigationStack и крестик закрытия")
    func modalPresentationKeepsModalChrome() {
        #expect(FinanceEditorPresentationStyle.modal.wrapsInNavigationStack)
        #expect(FinanceEditorPresentationStyle.modal.showsDismissButton)
        #expect(FinanceEditorPresentationStyle.modal.showsOpenCurrentGroupAction)
    }

    @Test("Push-переход переиспользует текущий стек и не дублирует модальные контролы")
    func pushedPresentationUsesInlineNavigation() {
        #expect(!FinanceEditorPresentationStyle.pushed.wrapsInNavigationStack)
        #expect(!FinanceEditorPresentationStyle.pushed.showsDismissButton)
        #expect(!FinanceEditorPresentationStyle.pushed.showsOpenCurrentGroupAction)
    }
}
