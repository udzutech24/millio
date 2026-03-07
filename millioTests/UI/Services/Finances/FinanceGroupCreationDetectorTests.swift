//
//  FinanceGroupCreationDetectorTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceGroupCreationDetectorTests {
    @Test("Новая группа после создания корректно детектится по diff-у ID и самой свежей createdAt")
    func detectsMostRecentCreatedGroup() {
        let existing = FinanceGroup(name: "Existing", colorHex: "#000000")
        existing.createdAt = Date(timeIntervalSince1970: 10)

        let createdOlder = FinanceGroup(name: "Created 1", colorHex: "#111111")
        createdOlder.createdAt = Date(timeIntervalSince1970: 20)

        let createdNewer = FinanceGroup(name: "Created 2", colorHex: "#222222")
        createdNewer.createdAt = Date(timeIntervalSince1970: 30)

        let previousIDs: Set<String> = [existing.groupUniqueID]
        let groups = [existing, createdOlder, createdNewer]

        let detected = FinanceGroupCreationDetector.detectCreatedGroup(previousGroupIDs: previousIDs, groups: groups)
        #expect(detected?.groupUniqueID == createdNewer.groupUniqueID)
    }

    @Test("Если новых групп нет — возвращается nil")
    func returnsNilWhenNoNewGroups() {
        let existing = FinanceGroup(name: "Existing", colorHex: "#000000")
        let previousIDs: Set<String> = [existing.groupUniqueID]

        let detected = FinanceGroupCreationDetector.detectCreatedGroup(previousGroupIDs: previousIDs, groups: [existing])
        #expect(detected == nil)
    }
}

