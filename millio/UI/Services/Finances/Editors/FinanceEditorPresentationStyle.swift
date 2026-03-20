//
//  FinanceEditorPresentationStyle.swift
//  millio
//

import Foundation

enum FinanceEditorPresentationStyle {
    case modal
    case pushed

    var wrapsInNavigationStack: Bool {
        self == .modal
    }

    var showsDismissButton: Bool {
        self == .modal
    }

    var showsOpenCurrentGroupAction: Bool {
        self == .modal
    }
}
