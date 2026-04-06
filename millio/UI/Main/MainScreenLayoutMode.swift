//
//  MainScreenLayoutMode.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import Foundation

/// Visual mode for the main screen.
/// `classic` keeps the calm linear navigation, `focus` prioritizes the most frequent actions.
enum MainScreenLayoutMode: String, CaseIterable, Codable {
    case classic
    case focus
}
