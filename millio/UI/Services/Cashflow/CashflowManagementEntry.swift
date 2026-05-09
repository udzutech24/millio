//
//  CashflowManagementEntry.swift
//  millio
//

import SwiftUI

struct CashflowManagementEntry: Identifiable, Equatable {
    let title: String
    let icon: String
    let destination: CashflowManagementDestination
    let lineLimit: Int

    var id: CashflowManagementDestination { destination }

    static func entries(for categoryKind: CashflowCategoryKind) -> [CashflowManagementEntry] {
        if categoryKind == .expense {
            return [
                CashflowManagementEntry(
                    title: String(
                        localized: "cashflow.bulk_expense.entry.title",
                        defaultValue: "Mass import",
                        comment: "Compact entry title for bulk expense import"
                    ),
                    icon: "square.stack.3d.down.right.fill",
                    destination: .bulkImport,
                    lineLimit: 2
                ),
                CashflowManagementEntry(
                    title: String(
                        localized: "cashflow.management.planner_expenses.title",
                        defaultValue: "Planned",
                        comment: "Management entry title for planned expenses"
                    ),
                    icon: "calendar.badge.plus",
                    destination: .planned,
                    lineLimit: 2
                )
            ]
        }

        return [
            CashflowManagementEntry(
                title: String(
                    localized: "cashflow.management.recurring.title",
                    defaultValue: "Recurring",
                    comment: "Management entry title for recurring cashflow items"
                ),
                icon: "repeat",
                destination: .recurring,
                lineLimit: 1
            ),
            CashflowManagementEntry(
                title: String(
                    localized: "cashflow.management.income_plan.title",
                    defaultValue: "Income plan",
                    comment: "Management entry title for planned income items"
                ),
                icon: "calendar.badge.plus",
                destination: .planned,
                lineLimit: 2
            )
        ]
    }
}

enum CashflowManagementDestination: Hashable {
    case bulkImport
    case recurring
    case planned
}
