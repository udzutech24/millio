//
//  AppRefreshCoordinatorEnvironmentKey.swift
//  millio
//
//  Created by Codex on 15.03.2026.
//

import SwiftUI

private struct AppRefreshCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppRefreshCoordinator? = nil
}

extension EnvironmentValues {
    var appRefreshCoordinator: AppRefreshCoordinator? {
        get { self[AppRefreshCoordinatorEnvironmentKey.self] }
        set { self[AppRefreshCoordinatorEnvironmentKey.self] = newValue }
    }
}
