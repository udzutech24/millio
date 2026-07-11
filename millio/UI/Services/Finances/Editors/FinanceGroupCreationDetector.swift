//
//  FinanceGroupCreationDetector.swift
//  millio
//

import Foundation

enum FinanceGroupCreationDetector {
    /// [Ф5c.7 contract] `AccountGroup` не хранит `createdAt` — тай-брейкер на `order` (новые группы
    /// получают `maxOrder+1` при создании в `FinanceGroupService.updateGroup`, монотонно растёт).
    static func detectCreatedGroup(previousGroupIDs: Set<String>, groups: [AccountGroup]) -> AccountGroup? {
        let createdGroups = groups.filter { previousGroupIDs.contains($0.groupUniqueID) == false }
        return createdGroups.max(by: { $0.order < $1.order })
    }
}

