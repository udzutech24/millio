//
//  AppState.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

@Observable
final class AppState {
    var lifecycle: AppLifecycleState = .launching
    var isICloudAvailable: Bool = false
    var lastBackupDate: Date?
    var selectedLanguage: Language = .system
    var isBackupEnabled: Bool = false
    
    init() {
        self.isBackupEnabled = SettingsManager.shared.isBackupEnabled
    }
}
