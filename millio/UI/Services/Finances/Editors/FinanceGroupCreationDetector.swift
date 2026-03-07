//
//  FinanceGroupCreationDetector.swift
//  millio
//

import Foundation

enum FinanceGroupCreationDetector {
    static func detectCreatedGroup(previousGroupIDs: Set<String>, groups: [FinanceGroup]) -> FinanceGroup? {
        let createdGroups = groups.filter { previousGroupIDs.contains($0.groupUniqueID) == false }
        return createdGroups.max(by: { $0.createdAt < $1.createdAt })
    }
}

