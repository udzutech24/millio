//
//  ModelContainerEnvironmentKey.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

private struct ModelContainerEnvironmentKey: EnvironmentKey {
    static let defaultValue: ModelContainer? = nil
}

extension EnvironmentValues {
    var modelContainer: ModelContainer? {
        get { self[ModelContainerEnvironmentKey.self] }
        set { self[ModelContainerEnvironmentKey.self] = newValue }
    }
}
