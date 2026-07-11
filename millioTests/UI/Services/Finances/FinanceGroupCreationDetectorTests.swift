//
//  FinanceGroupCreationDetectorTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceGroupCreationDetectorTests {
    // [Ф5c.7 contract] `AccountGroup` не хранит `createdAt` — тай-брейкер на `order` (см. коммент
    // в `FinanceGroupCreationDetector`).
    @Test("Новая группа после создания корректно детектится по diff-у ID и самому большому order")
    func detectsMostRecentCreatedGroup() {
        let existing = AccountGroup(name: "Existing", colorHex: "#000000", order: 0)
        let createdOlder = AccountGroup(name: "Created 1", colorHex: "#111111", order: 1)
        let createdNewer = AccountGroup(name: "Created 2", colorHex: "#222222", order: 2)

        let previousIDs: Set<String> = [existing.groupUniqueID]
        let groups = [existing, createdOlder, createdNewer]

        let detected = FinanceGroupCreationDetector.detectCreatedGroup(previousGroupIDs: previousIDs, groups: groups)
        #expect(detected?.groupUniqueID == createdNewer.groupUniqueID)
    }

    @Test("Если новых групп нет — возвращается nil")
    func returnsNilWhenNoNewGroups() {
        let existing = AccountGroup(name: "Existing", colorHex: "#000000")
        let previousIDs: Set<String> = [existing.groupUniqueID]

        let detected = FinanceGroupCreationDetector.detectCreatedGroup(previousGroupIDs: previousIDs, groups: [existing])
        #expect(detected == nil)
    }
}
