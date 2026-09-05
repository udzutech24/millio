//
//  FinanceGroupExpansionResetTests.swift
//  millioTests
//
//  Created by Александр on 05.09.2026.
//

import Foundation
import Testing
@testable import millio

/// Инварианты сворачивания групп при тапе по активной вкладке «Счета».
///
/// Поведение целиком собрано из свойств SwiftUI, поэтому проверяется цепочкой звеньев,
/// а не прогоном экрана: тап по активной вкладке → `resetTabToRoot` бампит `resetToken`
/// → меняется `.id` поддерева вкладки → SwiftUI пересоздаёт `FinancesMainTabView`
/// → его `@State` со списком раскрытых групп рождается пустым.
/// Сломай любое звено — фича молча исчезнет, поэтому каждое зафиксировано отдельно.
struct FinanceGroupExpansionResetTests {

    // MARK: - Звено 1: состояние раскрытия локально для экрана

    @Test("Раскрытые группы живут в @State экрана, а не в общем FinanceState")
    func expansionStateIsLocalToFinancesScreen() throws {
        let view = try source("millio/UI/Services/Finances/FinancesView.swift")

        #expect(view.contains("@State private var expandedGroupIDs: Set<String> = []"))
        // Пробрасывается вниз биндингом — иначе строки групп снова начнут ходить в VM.
        #expect(view.contains("expandedGroupIDs: $expandedGroupIDs"))
    }

    @Test("Строка группы мутирует биндинг экрана, а не состояние FinanceViewModel")
    func groupRowMutatesBindingNotViewModel() throws {
        let rows = try source("millio/UI/Services/Finances/Rows/FinanceRows.swift")

        #expect(rows.contains("@Binding var expandedGroupIDs: Set<String>"))
        #expect(rows.contains("expandedGroupIDs.contains(groupID)"))
    }

    // MARK: - Звено 2: второго источника правды не осталось

    @Test("FinanceViewModel больше не хранит и не переключает раскрытие групп")
    func financeViewModelNoLongerOwnsExpansion() throws {
        let viewModel = try source("millio/UI/Services/Finances/FinanceViewModel.swift")

        // Оба следа сразу: поле состояния и action. Пока их нет — тап по группе
        // не мутирует @Published state, значит Дашборд и Динамика не перерисовываются.
        #expect(viewModel.contains("expandedGroupIDs") == false)
        #expect(viewModel.contains("toggleGroupExpanded") == false)
    }

    @Test("Ни один экран вне «Счетов» не читает раскрытие групп из FinanceState")
    func noScreenOutsideFinancesReadsExpansionFromState() throws {
        for relativePath in [
            "millio/UI/Services/Finances/FinanceDynamicsView.swift",
            "millio/UI/Services/Finances/Components/FinanceOverviewCardView.swift",
            "millio/UI/Main/RootTabView.swift"
        ] {
            let file = try source(relativePath)
            #expect(file.contains("state.expandedGroupIDs") == false, "\(relativePath)")
        }
    }

    // MARK: - Звено 3: сброс вкладки пересоздаёт поддерево «Счетов»

    @Test("Тап по активной вкладке «Счета» бампит resetToken, меняющий .id поддерева")
    func reselectingFinancesTabBumpsResetToken() throws {
        let rootTab = try source("millio/UI/Main/RootTabView.swift")

        // `.id` на поддереве вкладки — то самое, что заставляет SwiftUI пересоздать
        // FinancesMainTabView и обнулить его @State (а заодно сбросить скролл списка).
        #expect(rootTab.contains(".id(resetToken(for: .finances))"))
        #expect(rootTab.contains("tabResetTokens[tab] = resetToken(for: tab) + 1"))
        #expect(rootTab.contains("onReselectTab: { tab in resetTabToRoot(tab) }"))
    }

    @Test("Сброс вызывается на любом тапе по активной вкладке, даже на корне раздела")
    func reselectFiresEvenWhenAlreadyAtRoot() throws {
        let tabBar = try source("millio/UI/Main/RootTabBar.swift")

        // Если обернуть вызов условием «есть глубокая навигация», группы на корне
        // перестанут сворачиваться — владелец просил «один тап делает всё сразу».
        let condensed = tabBar.filter { !$0.isWhitespace }
        #expect(condensed.contains("ifisActive{onReselectTab?(tab)"))
    }

    // MARK: - Звено 4: скролл-контейнер внутри пересоздаваемого поддерева

    @Test("Список счетов скроллится внутри FinancesMainTabView — сброс обнуляет позицию")
    func accountsListScrollLivesInsideRecreatedSubtree() throws {
        let view = try source("millio/UI/Services/Finances/FinancesView.swift")
        let rootTab = try source("millio/UI/Main/RootTabView.swift")

        // ScrollView экрана не вынесен наружу — иначе пересоздание поддерева
        // не сбросило бы позицию списка и «скролл наверх» пришлось бы делать руками.
        #expect(view.contains("ScrollView {"))
        #expect(rootTab.contains("ScrollView {") == false)
    }

    // MARK: - Helpers

    private func source(_ relativePath: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        throw NSError(
            domain: "FinanceGroupExpansionResetTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Не найден \(relativePath) от \(#filePath)"]
        )
    }
}
