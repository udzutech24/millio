//
//  AppLifecycleState.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

enum AppLifecycleState: Equatable {
    case launching
    case onboarding
    case ready
    case restoring
    case error(AppError)
}
