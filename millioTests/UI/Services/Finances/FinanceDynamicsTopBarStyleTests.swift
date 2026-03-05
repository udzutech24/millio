import Testing
@testable import millio

struct FinanceDynamicsTopBarStyleTests {
    @Test("Левая кнопка показывает явный редактор в обычном режиме")
    func editorButtonUsesEditorSymbolWhenNotEditing() {
        #expect(FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: false) == "square.and.pencil")
    }

    @Test("Левая кнопка переключается на сохранение во время inline-редактирования")
    func editorButtonUsesSaveSymbolWhenEditing() {
        #expect(FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: true) == "checkmark")
    }
}
