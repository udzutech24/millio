import Foundation

enum CashflowMenuDestination: String, CaseIterable, Hashable, Identifiable {
    case currency

    var id: Self { self }

    var localizationKey: String {
        "cashflow.menu.currency"
    }

    var systemImage: String {
        "dollarsign.circle"
    }
}

enum CashflowMenuSectionKind: Hashable {
    case display
}

struct CashflowMenuSection: Equatable {
    let kind: CashflowMenuSectionKind
    let destinations: [CashflowMenuDestination]
}

enum CashflowMenuPresentation {
    static let sections: [CashflowMenuSection] = [
        .init(kind: .display, destinations: [.currency])
    ]
}
