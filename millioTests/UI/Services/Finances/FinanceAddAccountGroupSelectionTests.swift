//
//  FinanceAddAccountGroupSelectionTests.swift
//  millioTests
//
//  Created by Codex on 14.02.2026.
//

import Testing
@testable import millio

@Suite
struct FinanceAddAccountGroupSelectionTests {

    @Test("Предпочитает явно выбранную группу")
    func testResolveSelectedGroupPrefersSelectedID() {
        let primary = FinanceGroup(name: "Основная", colorHex: "#FF0000")
        let secondary = FinanceGroup(name: "Дополнительная", colorHex: "#00FF00")

        let resolved = FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: secondary.groupUniqueID,
            preselectedGroupID: primary.groupUniqueID,
            groups: [primary, secondary]
        )

        #expect(resolved?.groupUniqueID == secondary.groupUniqueID)
    }

    @Test("Падает назад на предвыбранную группу, если выбранная недоступна")
    func testResolveSelectedGroupFallsBackToPreselected() {
        let primary = FinanceGroup(name: "Основная", colorHex: "#FF0000")
        let resolved = FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: "missing",
            preselectedGroupID: primary.groupUniqueID,
            groups: [primary]
        )

        #expect(resolved?.groupUniqueID == primary.groupUniqueID)
    }

    @Test("Возвращает nil, если нет выбранной и предвыбранной группы")
    func testResolveSelectedGroupReturnsNilWithoutExplicitSelection() {
        let primary = FinanceGroup(name: "Основная", colorHex: "#FF0000")
        let secondary = FinanceGroup(name: "Дополнительная", colorHex: "#00FF00")

        let resolved = FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: nil,
            preselectedGroupID: nil,
            groups: [primary, secondary]
        )

        #expect(resolved == nil)
    }

    @Test("Возвращает nil, когда групп нет")
    func testResolveSelectedGroupWithNoGroups() {
        let resolved = FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: "any",
            preselectedGroupID: "any",
            groups: []
        )

        #expect(resolved == nil)
    }
}
